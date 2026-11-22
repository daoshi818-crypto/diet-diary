import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:opennutritracker/core/domain/entity/recipe_ingredient_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/presentation/widgets/app_modal_sheet.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/energy_display.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/data/ai_food_analysis_api.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/ai_food_draft.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/nutrition_label_draft.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/run_ai_endpoint_probe_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/search_products_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_screen.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/features/add_meal/presentation/log_tray.dart';
import 'package:opennutritracker/features/add_meal/presentation/screens/bulk_add_screen.dart';
import 'package:opennutritracker/features/add_meal/util/meal_photo_encoder.dart';
import 'package:opennutritracker/features/edit_meal/presentation/bloc/edit_meal_bloc.dart';
import 'package:opennutritracker/features/recipes/presentation/screens/recipe_builder_screen.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/ai_assist_dialog.dart';
import 'package:opennutritracker/generated/l10n.dart';

class AiFoodAnalysisScreen extends StatefulWidget {
  final Future<List<AiFoodDraft>> Function(String, MealPhoto?, AiSelection)?
  reader;
  final Future<List<MealEntity>> Function(String)? search;
  final Future<MealPhoto?> Function(ImageSource, AiSelection?)? photoPicker;
  final Future<void> Function(MealEntity)? onSaveCustom;

  const AiFoodAnalysisScreen({
    super.key,
    this.reader,
    this.search,
    this.photoPicker,
    this.onSaveCustom,
  });

  @override
  State<AiFoodAnalysisScreen> createState() => _AiFoodAnalysisScreenState();
}

class _AiFoodAnalysisScreenState extends State<AiFoodAnalysisScreen> {
  final _text = TextEditingController();
  final _rows = <_FoodRow>[];
  late BulkAddScreenArguments _args;
  bool _initialized = false;
  bool _busy = false;
  bool _adding = false;
  bool _photoMode = false;
  Uint8List? _image;
  MealPhoto? _photo;
  String? _error;
  AiAssistSummary? _summary;
  String? _model;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _args =
        ModalRoute.of(context)!.settings.arguments as BulkAddScreenArguments;
    _text.text = _args.initialText ?? '';
    _photoMode = _args.startWithPhoto;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _refreshConfiguration();
      if (!mounted) return;
      if (_photoMode) {
        await _pickPhoto();
      } else if (_text.text.trim().isNotEmpty) {
        await _analyze();
      }
    });
  }

  @override
  void dispose() {
    _text.dispose();
    for (final row in _rows) {
      row.amount.dispose();
    }
    super.dispose();
  }

  Future<void> _refreshConfiguration() async {
    final storage = locator<AiCredentialStorage>();
    final summary = await storage.readSummary();
    final model = await storage.readModel();
    if (mounted) {
      setState(() {
        _summary = summary;
        _model = model;
      });
    }
  }

  Future<void> _configure() async {
    await AiAssistDialog.show(
      context,
      locator<AiCredentialStorage>(),
      probeRunner: locator.isRegistered<AiEndpointProbeRunner>()
          ? locator<AiEndpointProbeRunner>()
          : null,
    );
    await _refreshConfiguration();
    if (mounted) setState(() => _error = null);
  }

  Future<void> _pickPhoto() async {
    if (_busy) return;
    final s = S.of(context);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AppModalSheet(
        identifier: 'ai-food-photo-source',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.aiFoodPhotoTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Semantics(
              identifier: 'ai-food-camera',
              child: ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text(s.mealImageTakePhoto),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
            ),
            Semantics(
              identifier: 'ai-food-gallery',
              child: ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(s.labelScanGallery),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    setState(() => _busy = true);
    MealPhoto? photo;
    try {
      final selection = await locator<AiCredentialStorage>().readSelection();
      if (widget.photoPicker != null) {
        photo = await widget.photoPicker!(source, selection);
      } else {
        final picked = await ImagePicker().pickImage(source: source);
        if (picked == null) return;
        photo = await MealPhotoEncoder.encodeAndDiscardSource(
          picked.path,
          format: MealPhotoFormat.forProvider(
            selection?.provider ?? AiProvider.ownServer,
          ),
        );
        if (photo == null) throw const FormatException('Unreadable photo');
      }
      if (!mounted || photo == null) return;
      setState(() {
        _image = photo!.bytes;
        _photo = photo;
        _photoMode = true;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = s.labelScanReadError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted && photo != null) await _analyze(photo: photo);
  }

  Future<void> _analyze({MealPhoto? photo}) async {
    photo ??= _photo;
    if (_busy || (photo == null && _text.text.trim().isEmpty)) return;
    final selection = await locator<AiCredentialStorage>().readSelection();
    if (!mounted) return;
    if (selection == null) {
      await _refreshConfiguration();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final drafts = widget.reader != null
          ? await widget.reader!(_text.text.trim(), photo, selection)
          : await AiFoodAnalysisApi(locator<http.Client>()).analyze(
              selection: selection,
              text: _text.text.trim(),
              photo: photo,
            );
      final rows = <_FoodRow>[];
      for (final draft in drafts) {
        List<MealEntity> matches = const [];
        try {
          matches = widget.search != null
              ? await widget.search!(draft.meal.name!)
              : (await locator<SearchProductsUseCase>().searchFDCFoodByString(
                  draft.meal.name!,
                  forResolution: true,
                )).meals;
        } catch (_) {
          /* The estimate remains reviewable offline. */
        }
        matches = matches
            .where(
              (m) =>
                  m.isLiquid == draft.meal.isLiquid &&
                  m.nutriments.energyKcal100 != null &&
                  m.nutriments.proteins100 != null &&
                  m.nutriments.fat100 != null &&
                  m.nutriments.carbohydrates100 != null,
            )
            .toList();
        final exact = matches
            .where(
              (m) =>
                  m.name?.trim() == draft.meal.name?.trim() &&
                  (m.brands ?? '') == (draft.meal.brands ?? '') &&
                  m.nutriments.energyKcal100 != null &&
                  m.nutriments.proteins100 != null &&
                  m.nutriments.fat100 != null &&
                  m.nutriments.carbohydrates100 != null,
            )
            .firstOrNull;
        rows.add(_FoodRow(draft, exact, matches));
      }
      if (!mounted) {
        for (final row in rows) {
          row.amount.dispose();
        }
        return;
      }
      for (final row in _rows) {
        row.amount.dispose();
      }
      setState(() {
        _rows
          ..clear()
          ..addAll(rows);
        if (_rows.isEmpty) _error = S.of(context).aiFoodEmpty;
      });
    } on MealInterpreterException catch (e) {
      if (!mounted) return;
      final s = S.of(context);
      setState(
        () => _error = switch (e.failure) {
          MealInterpreterFailure.auth => s.labelScanAuthError,
          MealInterpreterFailure.billing => s.labelScanBillingError,
          MealInterpreterFailure.unsupported =>
            photo == null ? s.aiFoodModelUnsupported : s.labelScanVisionError,
          MealInterpreterFailure.insecureDestination =>
            s.aiAssistModelsInsecureLabel,
          _ => s.aiFoodRequestFailed,
        },
      );
    } catch (_) {
      if (mounted) setState(() => _error = S.of(context).aiFoodRequestFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<LogTrayItem>? _items() {
    if (_rows.isEmpty || _rows.any((r) => r.quantity == null)) {
      setState(() => _error = S.of(context).aiFoodAmountError);
      return null;
    }
    return [
      for (final row in _rows)
        LogTrayItem(
          meal: row.meal,
          amount: row.quantity!,
          unit: row.unit,
          amountLabel: '${row.amount.text} ${row.unit}',
        ),
    ];
  }

  Future<void> _add() async {
    if (_adding || _busy) return;
    final items = _items();
    if (items == null) return;
    final tray = _args.logTray;
    if (tray != null) {
      tray.addAll(items);
      Navigator.pop(context);
    } else {
      setState(() => _adding = true);
      await Navigator.pushNamed(
        context,
        NavigationOptions.addMealRoute,
        arguments: AddMealScreenArguments(
          AddMealExtension.fromIntakeTypeEntity(_args.intakeTypeEntity),
          _args.day,
          initialItems: items,
        ),
      );
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _openIngredientMatches() async {
    if (_text.text.trim().isEmpty) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        settings: RouteSettings(
          arguments: BulkAddScreenArguments(
            _args.intakeTypeEntity,
            _args.day,
            _args.usesImperialUnits,
            initialText: _text.text.trim(),
            logTray: _args.logTray,
            databaseMatchOnly: true,
          ),
        ),
        builder: (_) => const BulkAddScreen(),
      ),
    );
  }

  Future<void> _saveRecipe() async {
    final items = _items();
    if (items == null) return;
    await Navigator.pushNamed(
      context,
      NavigationOptions.recipeBuilderRoute,
      arguments: RecipeBuilderArguments(
        initialIngredients: [
          for (final item in items)
            RecipeIngredientEntity(
              snapshotMeal: item.meal,
              amount: item.amount,
              unit: item.unit,
              convertedAmountG: item.amount,
            ),
        ],
      ),
    );
  }

  Future<void> _saveCustom(_FoodRow row) async {
    if (row.saving || row.saved) return;
    setState(() => row.saving = true);
    final bloc = widget.onSaveCustom == null ? locator<EditMealBloc>() : null;
    try {
      final meal = row.meal.source == MealSourceEntity.custom
          ? row.meal
          : NutritionLabelDraft(
              name: row.meal.name ?? '',
              brand: row.meal.brands ?? '',
              basisQuantity: 100,
              basisUnit: row.unit,
              energy: row.meal.nutriments.energyKcal100,
              protein: row.meal.nutriments.proteins100,
              fat: row.meal.nutriments.fat100,
              carbs: row.meal.nutriments.carbohydrates100,
            ).toMeal();
      if (widget.onSaveCustom != null) {
        await widget.onSaveCustom!(meal);
      } else {
        await bloc!.saveCustomMeal(meal);
      }
      if (mounted) {
        setState(() => row.saved = true);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(S.of(context).labelScanSaved)));
      }
    } catch (_) {
      if (mounted) setState(() => _error = S.of(context).labelScanSaveError);
    } finally {
      await bloc?.close();
      if (mounted) setState(() => row.saving = false);
    }
  }

  Future<void> _chooseMatch(_FoodRow row) async {
    final selected = await showModalBottomSheet<MealEntity>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AppModalSheet(
        identifier: 'ai-food-match',
        child: Semantics(
          identifier: 'ai-food-match-list',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                identifier: 'ai-food-match-estimate',
                child: ListTile(
                  title: Text(S.of(context).aiFoodEstimate),
                  subtitle: Text(row.draft.meal.name!),
                  onTap: () => Navigator.pop(context, row.draft.meal),
                ),
              ),
              for (final match in row.matches)
                Semantics(
                  identifier: 'ai-food-match-${row.matches.indexOf(match)}',
                  child: ListTile(
                    title: Text(match.name ?? ''),
                    subtitle: Text(
                      '${match.brands ?? ''} · '
                      '${EnergyDisplay.formatWithUnit(context, match.nutriments.energyKcal100 ?? 0)} / 100 ${match.mealUnit ?? 'g'}',
                    ),
                    onTap: () => Navigator.pop(context, match),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      row.meal = selected;
      row.isEstimate = identical(selected, row.draft.meal);
      row.edited = false;
      row.saved = false;
    });
  }

  Future<void> _edit(_FoodRow row) async {
    final result = await showModalBottomSheet<MealEntity>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NutritionEditor(meal: row.meal),
    );
    if (result != null && mounted) {
      setState(() {
        row.meal = result;
        row.edited = true;
        row.isEstimate = false;
        row.saved = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_photoMode ? s.aiFoodPhotoTitle : s.aiFoodTextTitle),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _summary?.enabled == true
                        ? '${s.aiFoodConnected} · ${_summary?.endpoint == null ? _summary?.provider?.name ?? '' : AiCredentialStorage.displayHost(_summary!.endpoint!)}${_model == null ? '' : ' · $_model'}'
                        : _summary?.configured == true
                        ? s.aiFoodPaused
                        : s.labelScanConfigureFirst,
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Semantics(
                      identifier: 'ai-food-configure',
                      child: TextButton.icon(
                        onPressed: _busy ? null : _configure,
                        icon: const Icon(Icons.settings_outlined),
                        label: Text(s.labelScanAiSettings),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_image != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.memory(
                        _image!,
                        height: 180,
                        fit: BoxFit.contain,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Semantics(
                        identifier: 'ai-food-remove-photo',
                        child: TextButton.icon(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                  _image = null;
                                  _photo = null;
                                  _photoMode = false;
                                }),
                          icon: const Icon(Icons.close_rounded),
                          label: Text(s.mealImageRemove),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Semantics(
              identifier: 'ai-food-description',
              child: TextField(
                controller: _text,
                minLines: 3,
                maxLines: null,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: s.aiFoodDescriptionLabel,
                  hintText: s.aiFoodDescriptionHint,
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Semantics(
                  identifier: 'ai-food-match-ingredients',
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _openIngredientMatches,
                    icon: const Icon(Icons.manage_search_rounded),
                    label: Text(s.aiFoodMatchIngredients),
                  ),
                ),
                Semantics(
                  identifier: 'ai-food-analyze',
                  child: FilledButton.icon(
                    onPressed: _busy || _summary?.enabled != true
                        ? null
                        : () => _analyze(),
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: Text(s.aiFoodAnalyze),
                  ),
                ),
                Semantics(
                  identifier: 'ai-food-pick-photo',
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _pickPhoto,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: Text(s.aiFoodPhotoTitle),
                  ),
                ),
              ],
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(s.aiFoodAnalyzing),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            if (_rows.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(s.aiFoodReviewHint),
              const SizedBox(height: 12),
              Semantics(
                identifier: 'ai-food-results',
                child: Column(
                  children: [
                    for (var i = 0; i < _rows.length; i++)
                      _resultCard(_rows[i], i),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Semantics(
                identifier: 'ai-food-save-recipe',
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _saveRecipe,
                  icon: const Icon(Icons.menu_book_outlined),
                  label: Text(s.saveAsMealLabel),
                ),
              ),
              const SizedBox(height: 8),
              Semantics(
                identifier: 'ai-food-add',
                child: FilledButton.icon(
                  onPressed: _busy || _adding ? null : _add,
                  icon: const Icon(Icons.playlist_add_rounded),
                  label: Text(s.aiFoodAddReviewed),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _resultCard(_FoodRow row, int index) {
    final s = S.of(context);
    final n = row.meal.nutriments;
    final factor = (row.quantity ?? 0) / 100;
    String g(double? v) => v == null ? '—' : (v * factor).toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              row.meal.name ?? '',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              row.edited
                  ? s.aiFoodCorrected
                  : row.isEstimate
                  ? s.aiFoodEstimate
                  : s.aiFoodDatabase,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 12),
            Semantics(
              identifier: 'ai-food-amount-$index',
              child: TextField(
                controller: row.amount,
                enabled: !_busy,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  labelText: s.loggingConfirmAmount,
                  suffixText: row.unit,
                  helperText: row.draft.amountEstimated
                      ? s.aiFoodWeightEstimated
                      : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              EnergyDisplay.formatWithUnit(
                context,
                (n.energyKcal100 ?? 0) * factor,
              ),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              '${s.proteinLabel} ${g(n.proteins100)} g · '
              '${s.fatLabel} ${g(n.fat100)} g · ${s.carbsLabel} ${g(n.carbohydrates100)} g',
            ),
            if (row.isEstimate && row.draft.notes.isNotEmpty)
              Text(
                row.draft.notes,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            Wrap(
              spacing: 4,
              children: [
                Semantics(
                  identifier: 'ai-food-edit-$index',
                  child: TextButton(
                    onPressed: _busy || row.saving ? null : () => _edit(row),
                    child: Text(s.aiFoodEditNutrition),
                  ),
                ),
                if (row.matches.isNotEmpty)
                  Semantics(
                    identifier: 'ai-food-replace-$index',
                    child: TextButton(
                      onPressed: _busy || row.saving
                          ? null
                          : () => _chooseMatch(row),
                      child: Text(s.aiFoodChooseMatch),
                    ),
                  ),
                Semantics(
                  identifier: 'ai-food-custom-$index',
                  child: TextButton(
                    onPressed: _busy || row.saved || row.saving
                        ? null
                        : () => _saveCustom(row),
                    child: Text(row.saved ? s.aiFoodSaved : s.aiFoodSaveCustom),
                  ),
                ),
                Semantics(
                  identifier: 'ai-food-remove-$index',
                  child: IconButton(
                    tooltip: s.dialogDeleteLabel,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _busy || row.saving
                        ? null
                        : () => setState(() {
                            _rows.remove(row);
                            row.amount.dispose();
                          }),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FoodRow {
  final AiFoodDraft draft;
  MealEntity meal;
  final List<MealEntity> matches;
  final TextEditingController amount;
  bool saved = false;
  bool edited = false;
  bool isEstimate;
  bool saving = false;
  _FoodRow(this.draft, MealEntity? match, this.matches)
    : isEstimate = match == null,
      meal = match ?? draft.meal,
      amount = TextEditingController(
        text: draft.amount.toString().replaceFirst(RegExp(r'\.0$'), ''),
      );
  String get unit => meal.isLiquid ? 'ml' : 'g';
  double? get quantity {
    final v = double.tryParse(amount.text.replaceAll(',', '.'));
    return v != null && v.isFinite && v > 0 && v <= 10000 ? v : null;
  }
}

class _NutritionEditor extends StatefulWidget {
  final MealEntity meal;
  const _NutritionEditor({required this.meal});
  @override
  State<_NutritionEditor> createState() => _NutritionEditorState();
}

class _NutritionEditorState extends State<_NutritionEditor> {
  late final List<TextEditingController> fields;
  final form = GlobalKey<FormState>();
  @override
  void initState() {
    super.initState();
    final n = widget.meal.nutriments;
    fields = [
      widget.meal.name ?? '',
      '${n.energyKcal100 ?? ''}',
      '${n.proteins100 ?? ''}',
      '${n.fat100 ?? ''}',
      '${n.carbohydrates100 ?? ''}',
    ].map((v) => TextEditingController(text: v)).toList();
  }

  @override
  void dispose() {
    for (final field in fields) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final labels = [
      s.recipeNameLabel,
      s.kcalLabel,
      s.proteinLabel,
      s.fatLabel,
      s.carbsLabel,
    ];

    return AppModalSheet(
      identifier: 'ai-food-edit',
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.aiFoodEditNutrition,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(s.aiFoodPerHundred),
            for (var i = 0; i < fields.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  identifier: 'ai-food-edit-field-$i',
                  child: TextFormField(
                    controller: fields[i],
                    decoration: InputDecoration(labelText: labels[i]),
                    keyboardType: i == 0
                        ? TextInputType.text
                        : const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      if (i == 0) {
                        return (v ?? '').trim().isEmpty
                            ? s.aiFoodAmountError
                            : null;
                      }
                      final n = double.tryParse((v ?? '').replaceAll(',', '.'));
                      return n == null ||
                              !n.isFinite ||
                              n < 0 ||
                              n > (i == 1 ? 1000 : 100)
                          ? s.labelScanValuesError
                          : null;
                    },
                  ),
                ),
              ),
            const SizedBox(height: 20),
            Semantics(
              identifier: 'ai-food-edit-save',
              child: FilledButton(
                onPressed: () {
                  if (!form.currentState!.validate()) return;
                  double v(int i) =>
                      double.parse(fields[i].text.replaceAll(',', '.'));
                  final draft = NutritionLabelDraft(
                    name: fields[0].text.trim(),
                    brand: widget.meal.brands ?? '',
                    basisQuantity: 100,
                    basisUnit: widget.meal.isLiquid ? 'ml' : 'g',
                    energy: v(1),
                    protein: v(2),
                    fat: v(3),
                    carbs: v(4),
                  );
                  if (draft.canSave) Navigator.pop(context, draft.toMeal());
                },
                child: Text(s.buttonSaveLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
