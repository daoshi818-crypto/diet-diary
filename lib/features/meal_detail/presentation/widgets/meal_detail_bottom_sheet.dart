import 'package:opennutritracker/core/presentation/widgets/meal_type_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/serving_label_localizer.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/core/utils/navigation_predicates.dart';
import 'package:opennutritracker/features/add_meal/presentation/log_tray.dart';
import 'package:opennutritracker/features/add_meal/util/portion_unit.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/features/meal_detail/util/food_entry_preferences.dart';
import 'package:opennutritracker/features/meal_detail/util/portion_display.dart';
import 'package:opennutritracker/features/meal_detail/util/food_weight_basis.dart';
import 'package:opennutritracker/features/meal_detail/util/meal_quantity_converter.dart';
import 'package:opennutritracker/generated/l10n.dart';

class MealDetailBottomSheet extends StatefulWidget {
  final MealEntity product;
  final DateTime day;
  final IntakeTypeEntity intakeTypeEntity;
  final TextEditingController quantityTextController;
  final MealDetailBloc? mealDetailBloc;

  final String selectedUnit;

  /// Whether the user chose imperial food units, which the serving entry's
  /// label follows like every other amount on the screen.
  final bool usesImperialUnits;

  final Function(String?, String?) onQuantityOrUnitChanged;

  /// The add-food screen's "To log" list, when the sheet was opened from it.
  ///
  /// While the list is empty the main button still logs this food at once,
  /// as it did before the list existed, and a second button starts a list
  /// instead (#1520). Once the list has items, the main button adds to it.
  final LogTray? logTray;
  final Future<void> Function(LogTrayItem)? onSelectionConfirmed;
  final String? confirmLabel;
  final bool allowMealTypeChange;
  final bool submissionEnabled;
  final MealEntity Function()? onCustomPortionsChanged;
  final bool rememberSelection;
  final Widget Function(BuildContext, Widget editor, Widget actions)?
  layoutBuilder;

  const MealDetailBottomSheet({
    super.key,
    required this.product,
    required this.day,
    required this.intakeTypeEntity,
    required this.quantityTextController,
    required this.onQuantityOrUnitChanged,
    this.mealDetailBloc,
    required this.selectedUnit,
    this.usesImperialUnits = false,
    this.logTray,
    this.onSelectionConfirmed,
    this.confirmLabel,
    this.allowMealTypeChange = true,
    this.submissionEnabled = true,
    this.onCustomPortionsChanged,
    this.rememberSelection = true,
    this.layoutBuilder,
  });

  @override
  State<MealDetailBottomSheet> createState() => _MealDetailBottomSheetState();
}

class _MealDetailBottomSheetState extends State<MealDetailBottomSheet> {
  final _quantityFocusNode = FocusNode();

  /// Set from the first tap on Add until its submission ends. The save can
  /// wait for the tracked-day lock (#1317) with the sheet still open, and
  /// a second tap would pass the duplicate check again and log the meal
  /// twice.
  bool _submitting = false;
  late IntakeTypeEntity _intakeType;

  @override
  void initState() {
    super.initState();
    _intakeType = widget.intakeTypeEntity;
    widget.quantityTextController.addListener(_onQuantityChanged);
    _quantityFocusNode.addListener(_onQuantityFocusChanged);
    // "Add" or "Add to list" follows the list, which a food arriving from
    // a + on the add-food screen changes while this sheet is open.
    widget.logTray?.addListener(_onTrayChanged);
  }

  @override
  void dispose() {
    widget.logTray?.removeListener(_onTrayChanged);
    _quantityFocusNode.removeListener(_onQuantityFocusChanged);
    _quantityFocusNode.dispose();
    widget.quantityTextController.removeListener(_onQuantityChanged);
    super.dispose();
  }

  void _onTrayChanged() => setState(() {});

  /// Whether Add puts the food on the list rather than logging it: the list
  /// holds something or a food is on its way onto it (LogTray.collects).
  bool get _addsToList {
    final logTray = widget.logTray;
    return logTray != null && logTray.collects;
  }

  void _onQuantityFocusChanged() {
    if (_quantityFocusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_quantityFocusNode.hasFocus) return;
        _selectAllQuantityText();
      });
    }
  }

  void _selectAllQuantityText() {
    final text = widget.quantityTextController.text;
    widget.quantityTextController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: text.length,
    );
  }

  void _onQuantityChanged() {
    widget.onQuantityOrUnitChanged(
      widget.quantityTextController.text,
      widget.selectedUnit,
    );
  }

  void _applyQuantity(double quantity, String unit) {
    final text = _formatQuantity(double.parse(quantity.toStringAsFixed(2)));
    widget.quantityTextController.removeListener(_onQuantityChanged);
    widget.quantityTextController.text = text;
    widget.quantityTextController.addListener(_onQuantityChanged);
    widget.onQuantityOrUnitChanged(text, unit);
  }

  String get _mode => isPortionUnit(widget.selectedUnit)
      ? 'serving'
      : ['ml', 'fl.oz'].contains(widget.selectedUnit)
      ? 'ml'
      : 'g';

  Iterable<int> get _portionIndices => visiblePortionIndices(widget.product);

  bool get _hasLegacyPortion =>
      widget.product.portions.isEmpty &&
      (widget.product.scalableServingQuantity ?? 0) > 0;

  void _changeMode(String mode) {
    if (mode == _mode) return;
    if (mode == 'serving') {
      final index = defaultPortionIndex(widget.product);
      if (index != null || _hasLegacyPortion) {
        _applyQuantity(1, index == null ? 'serving' : portionUnit(index));
      } else {
        _addCustomPortion();
      }
      return;
    }
    final unit = widget.usesImperialUnits
        ? (mode == 'ml' ? 'fl.oz' : 'oz')
        : mode;
    final oldQuantity = double.tryParse(
      widget.quantityTextController.text.replaceAll(',', '.'),
    );
    final sameBasis = _mode == 'serving' || _mode == mode;
    final base = oldQuantity != null && oldQuantity.isFinite && sameBasis
        ? convertQuantityToBaseUnit(
            oldQuantity,
            widget.selectedUnit,
            widget.product,
          )
        : null;
    _applyQuantity(
      base == null
          ? (widget.usesImperialUnits ? 1 : 100)
          : base / convertQuantityToBaseUnit(1, unit, widget.product),
      unit,
    );
  }

  Future<void> _addCustomPortion() async {
    final prefs = FoodEntryPreferences.current;
    if (prefs == null || widget.onCustomPortionsChanged == null) return;
    _quantityFocusNode.unfocus();
    final food = widget.product;
    final s = S.of(context);
    var name = s.servingLabel;
    double? size;
    final unit = food.isLiquid ? s.milliliterUnit : s.gramUnit;
    final custom = await showDialog<(String, double)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          scrollable: true,
          title: Text(s.foodCustomPortion),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                identifier: 'food-custom-portion-name',
                child: TextFormField(
                  initialValue: name,
                  maxLength: 40,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(labelText: s.foodPortionName),
                  onChanged: (text) => update(() => name = text),
                ),
              ),
              Semantics(
                identifier: 'food-custom-portion-size',
                child: TextFormField(
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: s.foodPortionBaseAmount,
                    suffixText: unit,
                  ),
                  onChanged: (text) => update(
                    () => size = double.tryParse(
                      text.trim().replaceAll(',', '.'),
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.dialogCancelLabel),
            ),
            FilledButton(
              onPressed:
                  name.trim().isEmpty ||
                      food.portions.any(
                        (portion) =>
                            portion.label.trim().toLowerCase() ==
                                name.trim().toLowerCase() &&
                            !prefs
                                .customPortions(food)
                                .containsKey(portion.label),
                      ) ||
                      size == null ||
                      !size!.isFinite ||
                      size! <= 0 ||
                      size! > 10000
                  ? null
                  : () => Navigator.pop(context, (name.trim(), size!)),
              child: Text(s.buttonSaveLabel),
            ),
          ],
        ),
      ),
    );
    if (!mounted || custom == null) return;
    await prefs.savePortion(food, custom.$1, custom.$2);
    if (!mounted) return;
    final updated = widget.onCustomPortionsChanged!();
    final index = updated.portions.lastIndexWhere(
      (p) => p.label == custom.$1 && p.gramWeight == custom.$2,
    );
    if (index >= 0) _applyQuantity(1, portionUnit(index));
  }

  String _baseUnitLabel(S s) =>
      widget.product.isLiquid ? s.milliliterUnit : s.gramUnit;

  Future<void> _rememberSelection(MealEntity product, String unit) async {
    if (!widget.rememberSelection) return;
    try {
      await FoodEntryPreferences.current?.remember(product, unit);
    } catch (_) {
      // A preference write must not prevent logging food.
    }
  }

  String _formatQuantity(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final missing = _hasRequiredProductInfoMissing();
    final portionItems = _portionItems(s);
    final quantity = double.tryParse(
      widget.quantityTextController.text.replaceAll(',', '.'),
    );
    final canSubmit =
        !missing &&
        widget.submissionEnabled &&
        !_submitting &&
        quantity != null &&
        quantity.isFinite &&
        quantity > 0 &&
        quantity <= 10000;
    final editor = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.allowMealTypeChange) ...[
          MealTypeSelector(
            identifier: 'food-detail-meal-type',
            value: _intakeType,
            onChanged: _submitting
                ? null
                : (type) => setState(() => _intakeType = type),
          ),
          const SizedBox(height: 12),
        ],
        if (!missing) ...[
          Semantics(
            identifier: 'meal-detail-unit',
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: 'serving',
                  label: Text(s.foodPortionMode, maxLines: 2),
                  enabled:
                      _portionIndices.isNotEmpty ||
                      _hasLegacyPortion ||
                      widget.onCustomPortionsChanged != null,
                ),
                ButtonSegment(
                  value: 'g',
                  label: Text(s.foodMassMode, maxLines: 2),
                  enabled: !widget.product.isLiquid,
                ),
                ButtonSegment(
                  value: 'ml',
                  label: Text(s.foodVolumeMode, maxLines: 2),
                  enabled: widget.product.isLiquid,
                ),
              ],
              selected: {_mode},
              onSelectionChanged: _submitting
                  ? null
                  : (selection) => _changeMode(selection.single),
            ),
          ),
          if (_mode == 'serving') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    identifier: 'meal-detail-portion',
                    container: true,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(widget.selectedUnit),
                      isExpanded: true,
                      itemHeight: null,
                      initialValue:
                          portionItems.any(
                            (item) => item.value == widget.selectedUnit,
                          )
                          ? widget.selectedUnit
                          : null,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: s.foodPortionSpec,
                      ),
                      items: portionItems,
                      onChanged: (unit) {
                        if (unit != null) _applyQuantity(quantity ?? 1, unit);
                      },
                    ),
                  ),
                ),
                if (widget.onCustomPortionsChanged != null)
                  Semantics(
                    identifier: 'food-add-custom-portion',
                    child: IconButton(
                      onPressed: _addCustomPortion,
                      icon: const Icon(Icons.add_rounded),
                      tooltip: s.foodCustomPortion,
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Semantics(
            identifier: 'meal-detail-quantity',
            child: TextFormField(
              controller: widget.quantityTextController,
              focusNode: _quantityFocusNode,
              onTap: _selectAllQuantityText,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _quantityFocusNode.unfocus(),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'^\d+([.,]\d{0,2})?$'),
                ),
              ],
              decoration: InputDecoration(
                border: const OutlineInputBorder(
                  borderRadius: Dimens.borderRadiusM,
                ),
                labelText: _mode == 'serving'
                    ? s.quantityLabel
                    : _mode == 'ml'
                    ? s.foodVolumeMode
                    : s.foodMassMode,
                suffixText: switch (widget.selectedUnit) {
                  'oz' => s.ozUnit,
                  'fl.oz' => s.flOzUnit,
                  _ => _mode == 'serving' ? null : _baseUnitLabel(s),
                },
                helperText:
                    _mode == 'serving' && quantity != null && quantity.isFinite
                    ? '= ${_formatQuantity(double.parse(convertQuantityToBaseUnit(quantity, widget.selectedUnit, widget.product).toStringAsFixed(2)))} ${_baseUnitLabel(s)}'
                    : foodWeightBasisLabel(s, widget.product.name),
              ),
            ),
          ),
        ],
        if (missing)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              '${s.missingProductInfo}\n${s.missingProductInfoFields(_missingRequiredProductInfo().join(', '))}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
    final actions = SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              identifier: 'meal-detail-add',
              child: FilledButton.icon(
                onPressed: canSubmit
                    ? () => onAddButtonPressed(context, toList: _addsToList)
                    : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                icon: Icon(
                  widget.onSelectionConfirmed != null
                      ? Icons.check_rounded
                      : Icons.add_rounded,
                ),
                label: Text(
                  widget.confirmLabel ??
                      (_addsToList ? s.addToListLabel : s.addLabel),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            if (widget.logTray != null && !_addsToList)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Semantics(
                  identifier: 'meal-detail-add-to-list',
                  child: OutlinedButton.icon(
                    onPressed: canSubmit
                        ? () => onAddButtonPressed(context, toList: true)
                        : null,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    icon: const Icon(Icons.playlist_add_rounded),
                    label: Text(s.addToListLabel),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    return widget.layoutBuilder?.call(context, editor, actions) ??
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: editor,
            ),
            actions,
          ],
        );
  }

  bool _hasRequiredProductInfoMissing() =>
      _missingRequiredProductInfo().isNotEmpty;

  /// The labels of the required values the product lacks, so the warning
  /// can say which one is missing (#1474).
  List<String> _missingRequiredProductInfo() {
    final productNutriments = widget.product.nutriments;
    final s = S.of(context);
    return [
      if (productNutriments.energyKcal100 == null) s.energyLabel,
      if (productNutriments.carbohydrates100 == null) s.carbohydrateLabel,
      if (productNutriments.fat100 == null) s.fatLabel,
      if (productNutriments.proteins100 == null) s.proteinLabel,
    ];
  }

  /// Logs the food, or with [toList] puts it on the add-food screen's list.
  Future<void> onAddButtonPressed(
    BuildContext context, {
    bool toList = false,
  }) async {
    // Checked here, not only through the disabled button: a second tap
    // can land before the rebuild that disables it.
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await _submit(context, toList: toList);
    } finally {
      // A save that succeeds leaves the sheet; a rejected quantity, a
      // cancelled duplicate or a failed save lets the user try again.
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submit(BuildContext context, {required bool toList}) async {
    // Validate quantity (#209, #210)
    final quantityText = widget.quantityTextController.text.replaceAll(
      ',',
      '.',
    );
    final quantity = double.tryParse(quantityText);

    if (quantity == null || !quantity.isFinite || quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).loggingAmountInvalid)),
      );
      return;
    }

    // Reasonable maximum limit per meal (#210)
    if (quantity > 10000) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).loggingAmountInvalid)),
      );
      return;
    }

    final product = widget.product;
    final unit = widget.selectedUnit;
    final amount = convertQuantityToBaseUnit(quantity, unit, product);
    final intakeType = _intakeType;
    if (!amount.isFinite || amount <= 0) return;

    // A confirmed choice is returned to the caller; no duplicate check or
    // diary write belongs to the quick picker or an existing-entry edit.
    if (widget.onSelectionConfirmed != null) {
      await _rememberSelection(product, unit);
      if (!context.mounted) return;
      await widget.onSelectionConfirmed!(
        LogTrayItem(
          meal: widget.product,
          intakeType: _intakeType,
          unit: storedUnit(unit),
          selectionUnit: unit,
          amount: amount,
          amountLabel: logTrayAmountLabel(
            context,
            quantity,
            unit,
            widget.product,
          ),
        ),
      );
      return;
    }

    // Check for duplicate additions (#212)
    final isDuplicate = await _checkForDuplicate(context);
    if (!context.mounted) return;
    if (isDuplicate) {
      final shouldAdd = await _showDuplicateDialog(context);
      if (!context.mounted) return;
      if (shouldAdd != true) return;
    }

    final logTray = widget.logTray;
    // Asked again rather than taken from the press: a food can reach the
    // list during the checks above, and logging on its own would leave it.
    if (logTray != null && (toList || logTray.collects)) {
      await _rememberSelection(product, unit);
      if (!context.mounted) return;
      // Onto the list, with exactly what `addIntake` below would have been
      // given; the add-food screen writes it when the list is logged.
      logTray.add(
        LogTrayItem(
          meal: product,
          intakeType: intakeType,
          unit: storedUnit(unit),
          selectionUnit: unit,
          amount: amount,
          amountLabel: logTrayAmountLabel(context, quantity, unit, product),
        ),
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(S.of(context).logTrayAddedLabel)));
      // Back to the list, past the scanner too when that is how the user
      // came: it replaced itself with this screen.
      Navigator.of(
        context,
      ).popUntil(namedRouteOrFirst(NavigationOptions.addMealRoute));
      return;
    }

    // The refreshes below only see the intake once it is stored, which
    // can wait for the tracked-day lock (#1317).
    await widget.mealDetailBloc!.addIntake(
      context,
      unit,
      amount.toString(),
      intakeType,
      product,
      widget.day,
    );
    await _rememberSelection(product, unit);

    // Refresh Home Page
    locator<HomeBloc>().add(const LoadItemsEvent());

    // Refresh Diary Page - Pass the day to preserve selection (#154)
    locator<DiaryBloc>().add(const LoadDiaryYearEvent());
    locator<CalendarDayBloc>().add(const RefreshCalendarDayEvent());

    if (!context.mounted) return;
    // Show snackbar and return to dashboard
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(S.of(context).infoAddedIntakeLabel)));
    Navigator.of(
      context,
    ).popUntil(namedRouteOrFirst(NavigationOptions.mainRoute));
  }

  // #212: Check if this meal was already added today for the same meal type
  Future<bool> _checkForDuplicate(BuildContext context) async {
    final getIntakeUsecase = locator<GetIntakeUsecase>();
    final List<IntakeEntity> todayIntakes;

    switch (_intakeType) {
      case IntakeTypeEntity.breakfast:
        todayIntakes = await getIntakeUsecase.getBreakfastIntakeByDay(
          widget.day,
        );
        break;
      case IntakeTypeEntity.lunch:
        todayIntakes = await getIntakeUsecase.getLunchIntakeByDay(widget.day);
        break;
      case IntakeTypeEntity.dinner:
        todayIntakes = await getIntakeUsecase.getDinnerIntakeByDay(widget.day);
        break;
      case IntakeTypeEntity.snack:
        todayIntakes = await getIntakeUsecase.getSnackIntakeByDay(widget.day);
        break;
    }

    // Check if meal with same code or name already exists
    return todayIntakes.any(
      (intake) =>
          (widget.product.code != null &&
              intake.meal.code == widget.product.code) ||
          (widget.product.name != null &&
              intake.meal.name == widget.product.name),
    );
  }

  // #212: Show confirmation dialog for duplicate meals
  Future<bool?> _showDuplicateDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(S.of(context).warningLabel),
          content: Text(S.of(context).duplicateMealDialogContent),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(S.of(context).dialogCancelLabel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(S.of(context).addLabel),
            ),
          ],
        );
      },
    );
  }

  List<DropdownMenuItem<String>> _portionItems(S s) => [
    for (final index in _portionIndices)
      DropdownMenuItem(
        value: portionUnit(index),
        child: Text(
          portionDisplayLabel(
            widget.product.portions[index],
            _baseUnitLabel(s),
            localizedLabel: localizeServingLabel(
              s,
              widget.product.portions[index].label,
            ),
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    if (_hasLegacyPortion)
      DropdownMenuItem(
        value: 'serving',
        child: Text(
          widget.product.servingSize?.trim().isNotEmpty == true
              ? localizeServingLabel(s, widget.product.servingSize!)
              : '${s.servingLabel} · ${widget.product.scalableServingQuantity} ${_baseUnitLabel(s)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
  ];
}
