import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/compute_recipe_nutrition_usecase.dart';
import 'package:opennutritracker/core/presentation/widgets/food_quantity_dialog.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/meal_detail/util/meal_quantity_converter.dart';
import 'package:opennutritracker/generated/l10n.dart';

class IngredientQuantitySelection {
  final MealEntity meal;
  final double amount;
  final String unit;
  const IngredientQuantitySelection({
    required this.meal,
    required this.amount,
    required this.unit,
  });
}

Future<IngredientQuantitySelection?> showIngredientQuantityDialog(
  BuildContext context, {
  required MealEntity meal,
  double? initialAmount,
  String? initialUnit,
}) async {
  (double, String)? initial;
  if (initialAmount != null && initialUnit != null) {
    if ([
      'kg',
      'mg',
      'l',
      'cl',
      'dl',
      'gml',
      'g/ml',
      'fl oz',
    ].contains(initialUnit)) {
      final base = ComputeRecipeNutritionUseCase().convertAmountToGrams(
        amount: initialAmount,
        unit: initialUnit,
      );
      if (base != null) initial = (base, meal.isLiquid ? 'ml' : 'g');
    } else {
      initial = (initialAmount, initialUnit);
    }
  }
  final selection = await showFoodQuantitySheet(
    context: context,
      meal: meal,
    day: DateTime.now(),
    type: IntakeTypeEntity.lunch,
    usesImperialUnits: false,
    allowMealTypeChange: false,
    requireCompleteNutrition: false,
    requireQuantity: true,
    initialQuantity: initial,
    confirmLabel: initialAmount == null
        ? S.of(context).addLabel
        : S.of(context).buttonSaveLabel,
  );
  if (selection == null) return null;
  final unit = selection.selectionUnit ?? selection.unit;
  final perUnit = convertQuantityToBaseUnit(1, unit, selection.meal);
  return IngredientQuantitySelection(
    meal: selection.meal,
    amount: selection.amount / perUnit,
    unit: unit,
  );
}
