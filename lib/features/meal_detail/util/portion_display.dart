import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_portion_entity.dart';
import 'package:opennutritracker/features/add_meal/util/portion_unit.dart';

List<int> visiblePortionIndices(MealEntity meal, {String? selectedUnit}) {
  final indices = <int, int>{};
  final selected = selectedUnit != null && isPortionUnit(selectedUnit)
      ? effectivePortionIndex(selectedUnit)
      : null;
  for (var i = 0; i < meal.portions.length; i++) {
    final portion = meal.portions[i];
    final onlyWeight = RegExp(
      r'^\s*\d+(?:\.\d+)?\s*(?:克|g|grams?)\s*$',
      caseSensitive: false,
    ).hasMatch(portion.label);
    if (onlyWeight && i != selected) continue;
    final grams = portion.gramWeight;
    if (!grams.isFinite || grams <= 0) continue;
    final key = (grams * 1000000).round();
    if (!indices.containsKey(key) || i == selected) indices[key] = i;
  }
  return indices.values.toList();
}

String portionDisplayLabel(
  MealPortionEntity portion,
  String gramUnitLabel, {
  String? localizedLabel,
}) {
  final label = localizedLabel ?? portion.label;
  final mass = RegExp(
    r'(\d+(?:\.\d+)?)\s*(?:克|g|grams?)\s*[)）]?$',
    caseSensitive: false,
  ).firstMatch(label);
  if (mass != null &&
      (double.parse(mass[1]!) - portion.gramWeight).abs() < 0.000001) {
    return label;
  }
  final grams = portion.gramWeight;
  final weight = grams == grams.roundToDouble()
      ? grams.toInt().toString()
      : grams.toString();
  return '$label · $weight $gramUnitLabel';
}
