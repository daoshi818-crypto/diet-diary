import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
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

  const FoodQuantityDialog({
    super.key,
    required this.meal,
    required this.day,
    required this.type,
    required this.usesImperialUnits,
    this.editingIntake,
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
    } else if (meal.scalableServingQuantity != null ||
        meal.portions.isNotEmpty) {
      _unit = UnitDropdownItem.serving.toString();
      quantity = 1;
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
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: Dimens.shapeXL,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.editingIntake == null
                          ? s.loggingChooseAmount
                          : s.loggingEditAmount,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.meal.name ?? '?',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      s.loggingAmountHint,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      EnergyDisplay.formatWithUnit(
                        context,
                        base * (widget.meal.nutriments.energyPerUnit ?? 0),
                      ),
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ],
                ),
              ),
              MealDetailBottomSheet(
                product: widget.meal,
                day: widget.day,
                intakeTypeEntity: widget.type,
                quantityTextController: _quantity,
                selectedUnit: _unit,
                usesImperialUnits: widget.usesImperialUnits,
                onQuantityOrUnitChanged: _update,
                confirmLabel: widget.editingIntake == null
                    ? s.loggingConfirmAmount
                    : s.loggingSaveAmount,
                onSelectionConfirmed: (item) async {
                  Navigator.of(context).pop(item);
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Semantics(
                  identifier: 'food-quantity-close',
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: Text(s.dialogCloseLabel),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
