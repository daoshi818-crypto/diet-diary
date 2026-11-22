import 'dart:convert';

import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/features/add_meal/data/data_sources/chinese_food_data_source.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/features/add_meal/util/portion_unit.dart';
import 'package:opennutritracker/features/meal_detail/util/food_entry_preferences.dart';
import 'package:opennutritracker/features/meal_detail/util/portion_display.dart';

typedef LocalBatchMatch = ({MealEntity? selected, List<MealEntity> choices});

class LocalBatchMatcher {
  final ChineseFoodDataSource catalog;
  final CustomMealDataSource custom;
  final GetIntakeUsecase intakes;
  final FoodEntryPreferences? preferences;

  LocalBatchMatcher(this.catalog, this.custom, this.intakes, this.preferences);

  List<MealEntity> get _customFoods =>
      custom.getAllCustomMeals().map(MealEntity.fromMealDBO).toList();

  static String? foodIdentity(MealEntity food) {
    final id = food.code;
    if (id == null || id.isEmpty) return null;
    return jsonEncode([
      food.source.name,
      food.backendSource?.startsWith('local_') == true
          ? 'local'
          : food.backendSource,
      id,
    ]);
  }

  Future<List<LocalBatchMatch>> match(List<ParsedMealItem> rows) async {
    final recent = await intakes.getRecentIntake();
    final customFoods = _customFoods;
    final known = <String, MealEntity>{
      for (final food in [
        ...recent.reversed.map((intake) => intake.meal),
        ...customFoods,
      ])
        ?foodIdentity(food): food,
    };
    return Future.wait(
      rows.map((row) async {
        final key = batchFoodKey(row.query);
        final saved = preferences?.batchMatch(key);
        if (saved != null) {
          final identity = jsonDecode(saved) as List<dynamic>;
          final catalogFood = identity[1] == 'local'
              ? await catalog.byCatalogId(identity[2] as String)
              : null;
          final confirmed = catalogFood ?? known[saved];
          if (confirmed != null) {
            return (selected: confirmed, choices: <MealEntity>[confirmed]);
          }
        }
        final previous = recent
            .map((intake) => intake.meal)
            .where((food) => batchFoodKey(food.name ?? '') == key)
            .firstOrNull;
        if (previous != null) {
          final fresh =
              previous.backendSource?.startsWith('local_') == true &&
                  previous.code != null
              ? await catalog.byCatalogId(previous.code!)
              : known[foodIdentity(previous)];
          final food = fresh ?? previous;
          return (selected: food, choices: <MealEntity>[food]);
        }

        final candidates = [
          ...await catalog.matchBatchName(row.query),
          for (final food in customFoods)
            if (batchFoodKey(food.name ?? '') == key) (food: food, rank: 0),
        ]..sort((a, b) => a.rank.compareTo(b.rank));
        final choices = _distinct(candidates.map((entry) => entry.food));
        final best = candidates.firstOrNull?.rank;
        final strongest = _distinct(
          candidates
              .where((entry) => entry.rank == best)
              .map((entry) => entry.food),
        );
        return (
          selected: best != null && best < 3 && strongest.length == 1
              ? strongest.single
              : null,
          choices: choices,
        );
      }),
    );
  }

  Future<List<MealEntity>> search(String query) async {
    final key = batchFoodKey(query);
    if (key.isEmpty) return [];
    return _distinct([
      for (final food in _customFoods)
        if (batchFoodKey(food.name ?? '').contains(key)) food,
      ...await catalog.search(query),
    ]);
  }

  Future<void> remember(String query, MealEntity food) async {
    final id = foodIdentity(food);
    if (id != null) {
      await preferences?.rememberBatchMatch(batchFoodKey(query), id);
    }
  }

  static List<MealEntity> _distinct(Iterable<MealEntity> foods) {
    final seen = <Object>{};
    return [
      for (final food in foods)
        if (seen.add(foodIdentity(food) ?? food)) food,
    ];
  }
}

(double, String)? localBatchInitialQuantity(
  ParsedMealItem item,
  MealEntity food, {
  FoodEntryPreferences? preferences,
}) {
  final quantity = item.quantity;
  if (quantity == null) return null;
  switch (item.unit) {
    case 'g' || 'oz':
      return food.isLiquid ? null : (quantity, item.unit!);
    case 'ml' || 'fl.oz':
      return food.isLiquid ? (quantity, item.unit!) : null;
    case 'serving':
      final withPortions = preferences?.withCustomPortions(food) ?? food;
      final count = item.portion;
      if (count == null) return null;
      final index = defaultPortionIndex(
        withPortions,
        countUnit: count == '份' ? null : count,
      );
      if (index != null) return (quantity, portionUnit(index));
      if (count == '份' &&
          withPortions.portions.isEmpty &&
          (withPortions.scalableServingQuantity ?? 0) > 0) {
        return (quantity, 'serving');
      }
  }
  return null;
}
