import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_portion_entity.dart';
import 'package:opennutritracker/features/add_meal/util/portion_unit.dart';

List<int> visiblePortionIndices(MealEntity meal, {String? selectedUnit}) {
  final indices = <(String, int), int>{};
  final selected = selectedUnit != null && isPortionUnit(selectedUnit)
      ? effectivePortionIndex(selectedUnit)
      : null;
  for (var i = 0; i < meal.portions.length; i++) {
    final portion = meal.portions[i];
    final onlyWeight = RegExp(
      meal.isLiquid
          ? r'^\s*\d+(?:\.\d+)?\s*(?:毫升|ml)\s*$'
          : r'^\s*\d+(?:\.\d+)?\s*(?:克|g|grams?)\s*$',
      caseSensitive: false,
    ).hasMatch(portion.label);
    if (onlyWeight && i != selected) continue;
    final grams = portion.gramWeight;
    if (!grams.isFinite || grams <= 0) continue;
    final key = (portion.label.trim().toLowerCase(), (grams * 1000000).round());
    if (!indices.containsKey(key) || i == selected) indices[key] = i;
  }
  return indices.values.toList();
}

int? defaultPortionIndex(MealEntity meal, {String? countUnit}) {
  final indices = visiblePortionIndices(meal);
  if (indices.isEmpty) return null;
  if (countUnit == null) return indices.first;
  final tokens = countUnit == '个' || countUnit == '枚' || countUnit == '只'
      ? '个枚只'
      : countUnit;
  final matches = indices.where((i) {
    final label = meal.portions[i].label;
    final head = label.split(RegExp(r'[（(·]')).first.trim();
    final count = RegExp(
      '([0-9]+(?:[.,][0-9]+)?|[零〇一二两三四五六七八九十半¼½¾]+)?\\s*[$tokens]',
    ).firstMatch(head);
    return count != null &&
        (count[1] == null ||
            count[1] == '一' ||
            double.tryParse(count[1]!.replaceAll(',', '.')) == 1);
  }).toList();
  for (final i in matches) {
    if (RegExp(r'中|标准|普通').hasMatch(meal.portions[i].label)) return i;
  }
  return matches.isEmpty ? null : matches.first;
}

String portionDisplayLabel(
  MealPortionEntity portion,
  String gramUnitLabel, {
  String? localizedLabel,
}) {
  final label = localizedLabel ?? portion.label;
  final volume = gramUnitLabel == 'ml' || gramUnitLabel == '毫升';
  final mass = RegExp(
    volume
        ? r'(\d+(?:\.\d+)?)\s*(?:毫升|ml)\s*[)）]?$'
        : r'(\d+(?:\.\d+)?)\s*(?:克|g|grams?)\s*[)）]?$',
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
