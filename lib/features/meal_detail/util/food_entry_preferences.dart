import 'dart:convert';

import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_portion_entity.dart';
import 'package:opennutritracker/features/add_meal/util/portion_unit.dart';
import 'package:opennutritracker/features/meal_detail/util/portion_display.dart';

class FoodEntryPreferences {
  final HiveDBProvider _db;

  FoodEntryPreferences(this._db);

  static FoodEntryPreferences? get current =>
      locator.isRegistered<FoodEntryPreferences>()
      ? locator<FoodEntryPreferences>()
      : null;

  String _foodKey(MealEntity food) => jsonEncode([
    food.source.name,
    food.backendSource,
    food.code ?? [food.name, food.brands],
    food.isLiquid,
  ]);

  String _customKey(MealEntity food) => 'portions:${_foodKey(food)}';
  String _lastKey(MealEntity food) =>
      'last:${_db.activeProfileId}:${_foodKey(food)}';

  String _batchKey(String query) =>
      'batch:${_db.activeProfileId}:${jsonEncode(query)}';

  String? batchMatch(String query) => _db.foodEntryBox.get(_batchKey(query));

  Future<void> rememberBatchMatch(String query, String identity) =>
      _db.foodEntryBox.put(_batchKey(query), identity);

  Map<String, double> customPortions(MealEntity food) {
    final raw = _db.foodEntryBox.get(_customKey(food));
    if (raw == null) return {};
    final values = jsonDecode(raw) as Map<String, dynamic>;
    return values.map(
      (label, value) => MapEntry(label, (value as num).toDouble()),
    );
  }

  MealEntity withCustomPortions(MealEntity food) {
    final custom = customPortions(food);
    if (custom.isEmpty) return food;
    final original = [...food.portions];
    final base = food.scalableServingQuantity;
    if (original.isEmpty && base != null && base.isFinite && base > 0) {
      original.add(
        MealPortionEntity(
          label: food.servingSize?.trim().isNotEmpty == true
              ? food.servingSize!
              : '1 serving',
          gramWeight: base,
          localized: food.servingSizeIsLocalized,
        ),
      );
    }
    return food.withPortions([
      ...original,
      for (final entry in custom.entries)
        if (!original.any(
          (p) => p.label == entry.key && p.gramWeight == entry.value,
        ))
          MealPortionEntity(
            label: entry.key,
            gramWeight: entry.value,
            localized: true,
          ),
    ]);
  }

  Future<void> savePortion(MealEntity food, String name, double amount) =>
      _db.foodEntryBox.put(
        _customKey(food),
        jsonEncode({...customPortions(food), name: amount}),
      );

  String? lastUnit(MealEntity food) {
    final value = _db.foodEntryBox.get(_lastKey(food));
    if (value == null) return null;
    if (value == 'g' || value == 'oz') return food.isLiquid ? null : value;
    if (value == 'ml' || value == 'fl.oz') return food.isSolid ? null : value;
    if (value == 'serving') {
      return food.portions.isEmpty && (food.scalableServingQuantity ?? 0) > 0
          ? value
          : null;
    }
    for (final i in visiblePortionIndices(food)) {
      if (_signature(food.portions[i]) == value) return portionUnit(i);
    }
    return null;
  }

  Future<void> remember(MealEntity food, String unit) {
    final index = effectivePortionIndex(unit);
    final value =
        isPortionUnit(unit) && index >= 0 && index < food.portions.length
        ? _signature(food.portions[index])
        : storedUnit(unit);
    return _db.foodEntryBox.put(_lastKey(food), value);
  }

  String _signature(MealPortionEntity portion) => 'portion:${portion.label}';
}
