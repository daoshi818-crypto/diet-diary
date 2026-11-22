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
import 'package:opennutritracker/features/meal_detail/util/quick_serving_option.dart';
import 'package:opennutritracker/features/meal_detail/util/portion_display.dart';
import 'package:opennutritracker/features/meal_detail/util/food_entry_policy.dart';
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

  @override
  void initState() {
    super.initState();
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

  void _onQuickServingSelected(QuickServingOption option) {
    final quantityText = _formatQuantity(option.quantity);
    // Detach the change listener before the programmatic write, otherwise
    // setting the controller's text fires _onQuantityChanged with the OLD
    // unit before the callback below applies option.unit — so every chip
    // tap emitted a stale-unit UpdateKcalEvent (100 g briefly computed as
    // 100 servings) before landing on the right one.
    widget.quantityTextController.removeListener(_onQuantityChanged);
    widget.quantityTextController.text = quantityText;
    widget.quantityTextController.addListener(_onQuantityChanged);
    widget.onQuantityOrUnitChanged(quantityText, option.unit);
  }

  void _onUnitSelected(String? unit) {
    if (unit == null || unit == widget.selectedUnit) return;
    final entered = double.tryParse(
      widget.quantityTextController.text.replaceAll(',', '.'),
    );
    final base = entered != null && entered.isFinite
        ? convertQuantityToBaseUnit(
            entered,
            widget.selectedUnit,
            widget.product,
          )
        : 100.0;
    final quantity = isPortionUnit(unit)
        ? 1.0
        : base / convertQuantityToBaseUnit(1, unit, widget.product);
    widget.quantityTextController.removeListener(_onQuantityChanged);
    widget.quantityTextController.text = _formatQuantity(
      double.parse(quantity.toStringAsFixed(2)),
    );
    widget.quantityTextController.addListener(_onQuantityChanged);
    widget.onQuantityOrUnitChanged(widget.quantityTextController.text, unit);
  }

  Future<void> _choosePortion(List<QuickServingOption> options) async {
    _quantityFocusNode.unfocus();
    final selection = await showModalBottomSheet<QuickServingOption>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Text(
                  S.of(context).foodChoosePortion,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Flexible(
                child: Semantics(
                  identifier: 'meal-detail-portion-options',
                  container: true,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, index) => ListTile(
                      key: ValueKey('portion-option-${options[index].id}'),
                      leading: const Icon(Icons.straighten_rounded),
                      title: Text(options[index].label),
                      onTap: () => Navigator.of(context).pop(options[index]),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted && selection != null) _onQuickServingSelected(selection);
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
    final counted = offersCountedServings(widget.product);
    final quantity = double.tryParse(
      widget.quantityTextController.text.replaceAll(',', '.'),
    );
    final canSubmit =
        !missing &&
        !_submitting &&
        quantity != null &&
        quantity.isFinite &&
        quantity > 0 &&
        quantity <= 10000;
    final options = missing
        ? const <QuickServingOption>[]
        : quickServingOptionsFor(
            widget.product,
            s.gramUnit,
            includeWeightPresets: true,
          );
    final editor = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final quantityField = Semantics(
              identifier: 'meal-detail-quantity',
              container: true,
              child: TextFormField(
                enabled: !missing,
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
                  labelText: counted ? s.quantityLabel : s.foodWeightLabel,
                  helperText: foodWeightBasisLabel(s, widget.product.name),
                  labelStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            );
            final unitField = Semantics(
              identifier: 'meal-detail-unit',
              container: true,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                itemHeight: null,
                menuMaxHeight: MediaQuery.sizeOf(context).height * .5,
                isDense: false,
                initialValue: widget.selectedUnit,
                key: ValueKey(widget.selectedUnit),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(
                    borderRadius: Dimens.borderRadiusM,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  labelText: s.unitLabel,
                  labelStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                items: [
                  if (widget.product.isSolid || !widget.product.isLiquid)
                    ..._getSolidUnitDropdownItems(context),
                  if (widget.product.isLiquid || !widget.product.isSolid)
                    ..._getLiquidUnitDropdownItems(context),
                  if (widget.product.portions.isNotEmpty) ...[
                    for (final i in visiblePortionIndices(
                      widget.product,
                      selectedUnit: widget.selectedUnit,
                    ))
                      if (portionUnit(i) == widget.selectedUnit)
                        DropdownMenuItem<String>(
                          value: portionUnit(i),
                          child: Text(
                            portionDisplayLabel(
                              widget.product.portions[i],
                              widget.product.isLiquid ? 'ml' : s.gramUnit,
                              localizedLabel: localizeServingLabel(
                                s,
                                widget.product.portions[i].label,
                              ),
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                  ] else if (widget.product.scalableServingQuantity != null &&
                      (counted ||
                          widget.selectedUnit ==
                              UnitDropdownItem.serving.toString()))
                    _getServingDropdownItem(context),
                  if (widget.selectedUnit == UnitDropdownItem.gml.toString())
                    ..._getOtherDropdownItems(context),
                ],
                onChanged: missing ? null : _onUnitSelected,
              ),
            );
            if (constraints.maxWidth < 280 ||
                MediaQuery.textScalerOf(context).scale(16) > 22) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  quantityField,
                  const SizedBox(height: 16),
                  unitField,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: quantityField),
                const SizedBox(width: 16),
                Expanded(child: unitField),
              ],
            );
          },
        ),
        if (options.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(
              identifier: 'meal-detail-more-portions',
              child: OutlinedButton.icon(
                onPressed: () => _choosePortion(options),
                icon: const Icon(Icons.straighten_rounded),
                label: Text(s.foodChoosePortion),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
          ),
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

    // A confirmed choice is returned to the caller; no duplicate check or
    // diary write belongs to the quick picker or an existing-entry edit.
    if (widget.onSelectionConfirmed != null) {
      final unit = widget.selectedUnit;
      final amount = convertQuantityToBaseUnit(quantity, unit, widget.product);
      if (!amount.isFinite || amount <= 0) return;
      await widget.onSelectionConfirmed!(
        LogTrayItem(
          meal: widget.product,
          unit: storedUnit(unit),
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
      // Onto the list, with exactly what `addIntake` below would have been
      // given; the add-food screen writes it when the list is logged.
      final state = widget.mealDetailBloc!.state;
      logTray.add(
        LogTrayItem(
          meal: widget.product,
          unit: storedUnit(state.selectedUnit),
          amount: double.parse(
            state.totalQuantityConverted.replaceAll(',', '.'),
          ),
          amountLabel: logTrayAmountLabel(
            context,
            quantity,
            state.selectedUnit,
            widget.product,
          ),
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
      widget.mealDetailBloc!.state.selectedUnit,
      widget.mealDetailBloc!.state.totalQuantityConverted,
      widget.intakeTypeEntity,
      widget.product,
      widget.day,
    );

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

    switch (widget.intakeTypeEntity) {
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

  DropdownMenuItem<String> _getServingDropdownItem(BuildContext context) {
    // Custom meals are seeded from MealEntity.empty(), which carries an empty
    // servingSize string rather than null. An empty (or whitespace-only)
    // description should fall through to the constructed label so the option
    // doesn't render blank — otherwise '' wins over the ?? fallback (#495).
    final servingSize = widget.product.servingSize;
    // Serving labels are stored in English (see MealEntity._spServingLabel);
    // translate the common household units at display time.
    final servingLabel = (servingSize != null && servingSize.trim().isNotEmpty)
        ? localizeServingLabel(S.of(context), servingSize)
        : '${S.of(context).servingLabel} (${widget.product.servingQuantity} ${widget.product.servingUnit})';
    // The label is the food's own text, in grams or millilitres (#1368).
    final servingText = widget.usesImperialUnits
        ? imperialServingLabel(S.of(context), servingLabel)
        : servingLabel;
    return DropdownMenuItem(
      value: UnitDropdownItem.serving.toString(),
      // The serving's weight ends the text; at a large font it wraps
      // rather than being cut off.
      child: Text(servingText, overflow: TextOverflow.ellipsis, maxLines: 3),
    );
  }

  List<DropdownMenuItem<String>> _getSolidUnitDropdownItems(
    BuildContext context,
  ) {
    return [
      DropdownMenuItem(
        value: UnitDropdownItem.g.toString(),
        child: Text(
          S.of(context).gramUnit,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
      DropdownMenuItem(
        value: UnitDropdownItem.oz.toString(),
        child: Text(
          S.of(context).ozUnit,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
    ];
  }

  List<DropdownMenuItem<String>> _getLiquidUnitDropdownItems(
    BuildContext context,
  ) {
    return [
      DropdownMenuItem(
        value: UnitDropdownItem.ml.toString(),
        child: Text(
          S.of(context).milliliterUnit,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
      DropdownMenuItem(
        value: UnitDropdownItem.flOz.toString(),
        child: Text(
          S.of(context).flOzUnit,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
    ];
  }

  List<DropdownMenuItem<String>> _getOtherDropdownItems(BuildContext context) {
    return [
      DropdownMenuItem(
        value: UnitDropdownItem.gml.toString(),
        child: Text(
          "${S.of(context).notAvailableLabel} (${S.of(context).gramMilliliterUnit})",
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
    ];
  }
}
