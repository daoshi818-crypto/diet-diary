import 'package:opennutritracker/core/presentation/widgets/app_modal_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/data/nutrition_label_api.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/nutrition_label_draft.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/run_ai_endpoint_probe_usecase.dart';
import 'package:opennutritracker/features/add_meal/util/meal_photo_encoder.dart';
import 'package:opennutritracker/features/edit_meal/presentation/bloc/edit_meal_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/ai_assist_dialog.dart';
import 'package:opennutritracker/generated/l10n.dart';

class NutritionLabelScreen extends StatefulWidget {
  final NutritionLabelDraft? initialDraft;
  final Future<void> Function(MealEntity)? onSave;
  final Future<NutritionLabelDraft> Function(MealPhoto, AiSelection)? reader;

  const NutritionLabelScreen({
    super.key,
    this.initialDraft,
    this.onSave,
    this.reader,
  });

  @override
  State<NutritionLabelScreen> createState() => _NutritionLabelScreenState();
}

class _NutritionLabelScreenState extends State<NutritionLabelScreen> {
  final _form = GlobalKey<FormState>();
  final _fields = {
    for (final key in [
      'name',
      'brand',
      'basis',
      'energy',
      'protein',
      'fat',
      'carbs',
      'fiber',
      'sodium',
    ])
      key: TextEditingController(),
  };
  String _unit = 'g';
  String _energyUnit = 'kcal';
  String _notes = '';
  String? _error;
  Uint8List? _image;
  bool _reading = false;
  bool _saving = false;
  bool _hasDraft = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialDraft case final draft?) _apply(draft);
  }

  void _apply(NutritionLabelDraft draft) {
    String n(double? value) =>
        value == null ? '' : value.toString().replaceFirst(RegExp(r'\.0$'), '');
    _fields['name']!.text = draft.name;
    _fields['brand']!.text = draft.brand;
    _fields['basis']!.text = n(draft.basisQuantity);
    _fields['energy']!.text = n(draft.energy);
    _fields['protein']!.text = n(draft.protein);
    _fields['fat']!.text = n(draft.fat);
    _fields['carbs']!.text = n(draft.carbs);
    _fields['fiber']!.text = n(draft.fiber);
    _fields['sodium']!.text = n(draft.sodiumMg);
    _unit = draft.basisUnit;
    _energyUnit = draft.energyUnit;
    _notes = draft.notes;
    _hasDraft = true;
  }

  double? _number(String key) =>
      double.tryParse(_fields[key]!.text.replaceAll(',', '.'));

  NutritionLabelDraft get _draft => NutritionLabelDraft(
    name: _fields['name']!.text.trim(),
    brand: _fields['brand']!.text.trim(),
    basisQuantity: _number('basis'),
    basisUnit: _unit,
    energy: _number('energy'),
    energyUnit: _energyUnit,
    protein: _number('protein'),
    fat: _number('fat'),
    carbs: _number('carbs'),
    fiber: _number('fiber'),
    sodiumMg: _number('sodium'),
  );

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _configure() async {
    await AiAssistDialog.show(
      context,
      locator<AiCredentialStorage>(),
      probeRunner: locator<AiEndpointProbeRunner>(),
    );
    if (mounted) setState(() => _error = null);
  }

  Future<void> _pick() async {
    if (_reading || _saving) return;
    final selection = await locator<AiCredentialStorage>().readSelection();
    if (!mounted) return;
    if (selection == null) {
      setState(() => _error = S.of(context).labelScanConfigureFirst);
      return;
    }
    final destination = selection.endpoint == null
        ? selection.provider.name
        : AiCredentialStorage.displayHost(selection.endpoint!) ??
              selection.provider.name;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AppModalSheet(
        identifier: 'nutrition-label-source',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(S.of(context).labelScanDisclosure(destination)),
            ),
            Semantics(
              identifier: 'nutrition-label-camera',
              child: ListTile(
                leading: const Icon(Icons.photo_camera_rounded),
                title: Text(S.of(context).mealImageTakePhoto),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
            ),
            Semantics(
              identifier: 'nutrition-label-gallery',
              child: ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(S.of(context).labelScanGallery),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    setState(() {
      _reading = true;
      _error = null;
    });
    try {
      final picked = await ImagePicker().pickImage(source: source);
      if (picked == null) return;
      final photo = await MealPhotoEncoder.encodeAndDiscardSource(
        picked.path,
        format: MealPhotoFormat.forProvider(selection.provider),
      );
      if (!mounted) return;
      if (photo == null) throw const FormatException('Unreadable image');
      final draft = widget.reader != null
          ? await widget.reader!(photo, selection)
          : await NutritionLabelApi(
              locator<http.Client>(),
            ).read(photo, selection);
      if (mounted) {
        setState(() {
          _image = photo.bytes;
          _apply(draft);
        });
      }
    } on MealInterpreterException catch (e) {
      if (!mounted) return;
      final s = S.of(context);
      setState(
        () => _error = switch (e.failure) {
          MealInterpreterFailure.auth => s.labelScanAuthError,
          MealInterpreterFailure.billing => s.labelScanBillingError,
          MealInterpreterFailure.unsupported ||
          MealInterpreterFailure.rejected => s.labelScanVisionError,
          MealInterpreterFailure.insecureDestination =>
            s.aiAssistModelsInsecureLabel,
          _ => s.labelScanReadError,
        },
      );
    } catch (_) {
      if (mounted) setState(() => _error = S.of(context).labelScanReadError);
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _reading || !_form.currentState!.validate()) return;
    if (!_draft.canSave) {
      setState(() => _error = S.of(context).labelScanValuesError);
      return;
    }
    final meal = _draft.toMeal();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.onSave != null) {
        await widget.onSave!(meal);
      } else {
        final bloc = locator<EditMealBloc>();
        try {
          await bloc.saveCustomMeal(meal);
        } finally {
          await bloc.close();
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(S.of(context).labelScanSaved)));
      Navigator.of(context).pop(meal);
    } catch (_) {
      if (mounted) setState(() => _error = S.of(context).labelScanSaveError);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final busy = _reading || _saving;
    return Scaffold(
      appBar: AppBar(title: Text(s.labelScanTitle)),
      bottomNavigationBar: _hasDraft
          ? AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Semantics(
                    identifier: 'nutrition-label-save',
                    child: FilledButton.icon(
                      onPressed: busy ? null : _save,
                      icon: const Icon(Icons.playlist_add_check_rounded),
                      label: Text(
                        _saving ? s.labelScanSaving : s.labelScanSave,
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                  ),
                ),
              ),
            )
          : null,
      body: SafeArea(
        top: false,
        child: AbsorbPointer(
          absorbing: busy,
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                Text(s.labelScanIntro),
                const SizedBox(height: 12),
                if (_image != null) ...[
                  Semantics(
                    identifier: 'nutrition-label-original',
                    child: InkWell(
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (context) => Dialog.fullscreen(
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: InteractiveViewer(
                                  child: Image.memory(
                                    _image!,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                              SafeArea(
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Semantics(
                                    identifier: 'nutrition-label-close-image',
                                    child: CloseButton(
                                      onPressed: () => Navigator.pop(context),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.memory(
                          _image!,
                          height: 150,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Semantics(
                      identifier: 'nutrition-label-pick',
                      child: FilledButton.tonalIcon(
                        onPressed: _pick,
                        icon: const Icon(Icons.document_scanner_outlined),
                        label: Text(
                          _hasDraft ? s.labelScanAgain : s.labelScanPick,
                        ),
                      ),
                    ),
                    Semantics(
                      identifier: 'nutrition-label-configure',
                      child: TextButton.icon(
                        onPressed: _configure,
                        icon: const Icon(Icons.settings_outlined),
                        label: Text(s.labelScanAiSettings),
                      ),
                    ),
                  ],
                ),
                if (_reading) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(s.labelScanReading),
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
                if (_hasDraft) ...[
                  const SizedBox(height: 16),
                  AppCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          s.labelScanReview,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (_notes.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(_notes),
                          ),
                        const SizedBox(height: 16),
                        _field('name', s.labelScanFoodName, text: true),
                        _field(
                          'brand',
                          s.labelScanBrand,
                          text: true,
                          optional: true,
                        ),
                        Text(
                          s.labelScanBasisHint,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        _field('basis', s.labelScanBasis, suffix: _unit),
                        Semantics(
                          identifier: 'nutrition-label-basis-unit',
                          child: SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'g', label: Text('g')),
                              ButtonSegment(value: 'ml', label: Text('ml')),
                            ],
                            selected: {_unit},
                            onSelectionChanged: (v) =>
                                setState(() => _unit = v.single),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _field('energy', s.energyLabel, suffix: _energyUnit),
                        Semantics(
                          identifier: 'nutrition-label-energy-unit',
                          child: SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'kcal', label: Text('kcal')),
                              ButtonSegment(value: 'kJ', label: Text('kJ')),
                            ],
                            selected: {_energyUnit},
                            onSelectionChanged: (v) =>
                                setState(() => _energyUnit = v.single),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _field('protein', s.proteinLabel, suffix: 'g'),
                        _field('fat', s.fatLabel, suffix: 'g'),
                        _field('carbs', s.carbsLabel, suffix: 'g'),
                        Semantics(
                          identifier: 'nutrition-label-optional',
                          child: ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: Text(s.labelScanOptional),
                            children: [
                              _field(
                                'fiber',
                                s.labelScanFiber,
                                suffix: 'g',
                                optional: true,
                              ),
                              _field(
                                'sodium',
                                s.labelScanSodium,
                                suffix: 'mg',
                                optional: true,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          s.labelScanNormalizeHint,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    String key,
    String label, {
    String? suffix,
    bool text = false,
    bool optional = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Semantics(
      identifier: 'nutrition-label-$key',
      child: TextFormField(
        controller: _fields[key],
        keyboardType: text
            ? TextInputType.text
            : const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.next,
        inputFormatters: text
            ? null
            : [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        decoration: InputDecoration(
          labelText: label,
          suffixText: suffix,
          border: const OutlineInputBorder(),
          errorMaxLines: 3,
        ),
        validator: (value) {
          if (optional && (value == null || value.trim().isEmpty)) return null;
          if (text) {
            return value == null || value.trim().isEmpty
                ? S.of(context).labelScanRequired
                : null;
          }
          final n = _number(key);
          return n == null || !n.isFinite || n < 0 || (key == 'basis' && n <= 0)
              ? S.of(context).labelScanRequired
              : null;
        },
      ),
    ),
  );
}
