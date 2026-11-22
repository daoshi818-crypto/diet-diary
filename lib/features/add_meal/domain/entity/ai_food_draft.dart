import 'package:opennutritracker/core/utils/food_name_validator.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/nutrition_label_draft.dart';

class AiFoodDraft {
  final MealEntity meal;
  final double amount;
  final bool amountEstimated;
  final String notes;

  const AiFoodDraft({
    required this.meal,
    required this.amount,
    required this.amountEstimated,
    this.notes = '',
  });

  factory AiFoodDraft.fromJson(Map<String, dynamic> json) {
    final label = NutritionLabelDraft.fromJson({
      ...json,
      'basisQuantity': 100,
      'energyUnit': 'kcal',
    });
    final rawAmount = json['amount'];
    final amount = rawAmount is num ? rawAmount.toDouble() : null;
    if (!FoodNameValidator.isValid(label.name) ||
        !label.canSave ||
        label.protein! + label.fat! + label.carbs! > 105 ||
        amount == null ||
        !amount.isFinite ||
        amount <= 0 ||
        amount > 10000) {
      throw const FormatException('Invalid food analysis');
    }
    return AiFoodDraft(
      meal: label.toMeal(),
      amount: amount,
      amountEstimated: json['amountEstimated'] != false,
      notes: label.notes,
    );
  }
}
