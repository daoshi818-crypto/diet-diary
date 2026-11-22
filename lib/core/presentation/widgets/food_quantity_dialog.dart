import 'package:opennutritracker/core/presentation/widgets/app_modal_sheet.dart';
import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/features/add_meal/presentation/log_tray.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/core/utils/energy_display.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/features/meal_detail/presentation/widgets/meal_detail_bottom_sheet.dart';
import 'package:opennutritracker/features/meal_detail/util/meal_quantity_converter.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// The recording screen's own quantity controls, reused for quick add and edit.
/// No storage is written until the caller receives a confirmed selection.
class FoodQuantityDialog extends StatefulWidget {
  final MealEntity meal;
  final DateTime day;
  final IntakeTypeEntity type;
  final bool usesImperialUnits;
  final IntakeEntity? editingIntake;
  final bool asBottomSheet;
  final LogTrayItem? initialItem;

  const FoodQuantityDialog({
    super.key,
    required this.meal,
    required this.day,
    required this.type,
    required this.usesImperialUnits,
    this.editingIntake,
    this.asBottomSheet = false,
    this.initialItem,
  });

  @override
  State<FoodQuantityDialog> createState() => _FoodQuantityDialogState();
}

class _FoodQuantityDialogState extends State<FoodQuantityDialog> {
  late final TextEditingController _quantity;
  late String _unit;
  bool _nutritionOpen = false;
  bool _nutritionEdited = false;
  late final List<TextEditingController> _nutrition;

  @override
  void initState() {
    super.initState();
    final meal = widget.meal;
    final edit = widget.editingIntake;
    final initialAmount = edit?.amount ?? widget.initialItem?.amount;
    final rawUnit = meal.isLiquid ? UnitDropdownItem.ml : UnitDropdownItem.g;
    double quantity;
    if (initialAmount != null) {
      _unit = rawUnit.toString();
      quantity = initialAmount;
      if (widget.usesImperialUnits) {
        _unit = meal.isLiquid
            ? UnitDropdownItem.flOz.toString()
            : UnitDropdownItem.oz.toString();
        quantity = meal.isLiquid
            ? UnitCalc.mlToFlOz(quantity)
            : UnitCalc.gToOz(quantity);
      }
    } else {
      _unit = rawUnit.toString();
      quantity = 100;
      if (widget.usesImperialUnits) {
        _unit = meal.isLiquid
            ? UnitDropdownItem.flOz.toString()
            : UnitDropdownItem.oz.toString();
        quantity = 1;
      }
    }
    _quantity = TextEditingController(text: _number(quantity));
    final n = meal.nutriments;
    _nutrition =
        [
              n.energyKcal100,
              n.carbohydrates100,
              n.fat100,
              n.proteins100,
              n.fiber100,
              n.sugars100,
              n.saturatedFat100,
              n.sodium100,
            ]
            .map(
              (v) => TextEditingController(text: v == null ? '' : v.toString()),
            )
            .toList();
    for (final c in _nutrition) {
      c.addListener(_nutritionChanged);
    }
    _update(_quantity.text, _unit);
  }

  @override
  void dispose() {
    _quantity.dispose();
    for (final c in _nutrition) {
      c.removeListener(_nutritionChanged);
      c.dispose();
    }
    super.dispose();
  }

  String _number(double n) =>
      n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(2);

  void _update(String? quantity, String? unit) {
    if (unit != null) _unit = unit;
    if (mounted) setState(() {});
  }

  void _nutritionChanged() => setState(() => _nutritionEdited = true);

  double? _value(int index) =>
      double.tryParse(_nutrition[index].text.trim().replaceAll(',', '.'));

  bool _validNutrient(int index) {
    if (index >= 4 && _nutrition[index].text.trim().isEmpty) return true;
    final value = _value(index);
    return value != null && value.isFinite && value >= 0;
  }

  bool get _nutritionValid => List.generate(8, (i) => i).every(_validNutrient);

  MealEntity get _meal {
    if (widget.editingIntake == null || !_nutritionEdited || !_nutritionValid) {
      return widget.meal;
    }
    return widget.meal.withNutriments(
      widget.meal.nutriments.withEditedValues(
        energyKcal100: _value(0),
        carbohydrates100: _value(1),
        fat100: _value(2),
        proteins100: _value(3),
        fiber100: _value(4),
        sugars100: _value(5),
        saturatedFat100: _value(6),
        sodium100: _value(7),
      ),
    );
  }

  Widget _nutritionEditor(BuildContext context) {
    final s = S.of(context);
    final labels = [
      s.quickAddEnergyLabelKcal,
      s.carbsLabel,
      s.fatLabel,
      s.proteinLabel,
      s.fiberLabel,
      s.sugarLabel,
      s.saturatedFatLabel,
      s.sodiumLabel,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          identifier: 'food-edit-nutrition',
          child: TextButton.icon(
            onPressed: () => setState(() => _nutritionOpen = !_nutritionOpen),
            icon: Icon(_nutritionOpen ? Icons.expand_less : Icons.tune_rounded),
            label: Text(s.loggingEditNutrition),
          ),
        ),
        if (_nutritionOpen) ...[
          Text(
            s.loggingNutritionPer100(
              widget.meal.isLiquid ? s.milliliterUnit : s.gramUnit,
            ),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < _nutrition.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Semantics(
                identifier: 'food-nutrient-$i',
                child: TextFormField(
                  controller: _nutrition[i],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: i == _nutrition.length - 1
                      ? TextInputAction.done
                      : TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: labels[i],
                    suffixText: i == 0
                        ? 'kcal'
                        : i == 7
                        ? 'mg'
                        : s.gramUnit,
                    errorText: _validNutrient(i)
                        ? null
                        : s.loggingNutrientInvalid,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final amount = double.tryParse(_quantity.text.replaceAll(',', '.'));
    final base = amount != null && amount.isFinite && amount > 0
        ? convertQuantityToBaseUnit(amount, _unit, widget.meal)
        : 0.0;
    final meal = _meal;
    final content = MealDetailBottomSheet(
      product: meal,
      submissionEnabled: widget.editingIntake == null || _nutritionValid,
      day: widget.day,
      intakeTypeEntity: widget.type,
      allowMealTypeChange: widget.editingIntake == null,
      quantityTextController: _quantity,
      selectedUnit: _unit,
      usesImperialUnits: widget.usesImperialUnits,
      onQuantityOrUnitChanged: _update,
      confirmLabel: widget.editingIntake != null || widget.initialItem != null
          ? s.buttonSaveLabel
          : s.loggingConfirmAmount,
      onSelectionConfirmed: (item) async => Navigator.of(context).pop(item),
      layoutBuilder: (context, editor, actions) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.meal.name ?? '?',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text(
            meal.nutriments.energyPerUnit == null
                ? '—'
                : EnergyDisplay.formatWithUnit(
                    context,
                    base * meal.nutriments.energyPerUnit!,
                  ),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          editor,
          if (widget.editingIntake != null) _nutritionEditor(context),
          actions,
        ],
      ),
    );
    final sheet = AppModalSheet(identifier: 'food-quantity', child: content);
    if (widget.asBottomSheet) return sheet;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      child: sheet,
    );
  }
}

Future<LogTrayItem?> showFoodQuantitySheet({
  required BuildContext context,
  required MealEntity meal,
  required DateTime day,
  required IntakeTypeEntity type,
  required bool usesImperialUnits,
  IntakeEntity? editingIntake,
  LogTrayItem? initialItem,
}) => showModalBottomSheet<LogTrayItem>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (context) => FoodQuantityDialog(
    meal: meal,
    day: day,
    type: type,
    usesImperialUnits: usesImperialUnits,
    editingIntake: editingIntake,
    initialItem: initialItem,
    asBottomSheet: true,
  ),
);
