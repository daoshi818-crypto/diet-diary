import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';

List<String> foodQueryTerms(String query) => query
    .toLowerCase()
    .trim()
    .split(RegExp(r'\s+'))
    .where((term) => term.isNotEmpty)
    .toSet()
    .toList();

bool foodTextMatches(String query, Iterable<String?> values) {
  final text = values.whereType<String>().join(' ').toLowerCase();
  return foodQueryTerms(query).every(text.contains);
}

bool foodMatchesQuery(MealEntity meal, String query) =>
    foodTextMatches(query, [meal.name, meal.brands]);
