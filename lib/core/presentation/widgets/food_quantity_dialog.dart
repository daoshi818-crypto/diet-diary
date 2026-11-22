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

  const FoodQuantityDialog({
    super.key,
    required this.meal,
    required this.day,
    required this.type,
    required this.usesImperialUnits,
    this.editingIntake,
    this.asBottomSheet = false,
  });

  @override
  State<FoodQuantityDialog> createState() => _FoodQuantityDialogState();
}

class _FoodQuantityDialogState extends State<FoodQuantityDialog> {
  late final TextEditingController _quantity;
  late String _unit;

  @override
  void initState() {
    super.initState();
    final meal = widget.meal;
    final edit = widget.editingIntake;
    final rawUnit = meal.isLiquid ? UnitDropdownItem.ml : UnitDropdownItem.g;
    double quantity;
    if (edit != null) {
      _unit = rawUnit.toString();
      quantity = edit.amount;
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
    _update(_quantity.text, _unit);
  }

  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  String _number(double n) =>
      n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(2);

  void _update(String? quantity, String? unit) {
    if (unit != null) _unit = unit;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final amount = double.tryParse(_quantity.text.replaceAll(',', '.'));
    final base = amount != null && amount.isFinite && amount > 0
        ? convertQuantityToBaseUnit(amount, _unit, widget.meal)
        : 0.0;
    final content = MealDetailBottomSheet(
      product: widget.meal,
      day: widget.day,
      intakeTypeEntity: widget.type,
      allowMealTypeChange: widget.editingIntake == null,
      quantityTextController: _quantity,
      selectedUnit: _unit,
      usesImperialUnits: widget.usesImperialUnits,
      onQuantityOrUnitChanged: _update,
      confirmLabel: widget.editingIntake == null
          ? s.loggingConfirmAmount
          : s.loggingSaveAmount,
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
            widget.meal.nutriments.energyPerUnit == null
                ? '—'
                : EnergyDisplay.formatWithUnit(
                    context,
                    base * widget.meal.nutriments.energyPerUnit!,
                  ),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          editor,
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
    asBottomSheet: true,
  ),
);
