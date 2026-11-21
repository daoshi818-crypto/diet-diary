import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';

bool offersCountedServings(MealEntity meal) {
  final weight = meal.scalableServingQuantity;
  final hasWeight =
      (weight != null && weight.isFinite && weight > 0) ||
      meal.portions.any((p) => p.gramWeight.isFinite && p.gramWeight > 0);
  if (!hasWeight) return false;
  if (meal.source == MealSourceEntity.off ||
      meal.source == MealSourceEntity.recipe) {
    return true;
  }
  if (meal.brands?.trim().isNotEmpty != true &&
      meal.source != MealSourceEntity.custom) {
    return false;
  }
  final labels = [meal.servingSize ?? '', ...meal.portions.map((p) => p.label)];
  return labels.any(
    (label) => RegExp(
      r'袋|包|瓶|盒|罐|桶|\b(?:pack(?:et|age)?|bottle|can|carton)\b',
      caseSensitive: false,
    ).hasMatch(label),
  );
}
