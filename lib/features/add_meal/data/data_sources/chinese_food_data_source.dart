import 'package:opennutritracker/features/add_meal/util/food_query.dart';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_portion_entity.dart';

/// Searches a complete offline snapshot; updates replace it after validation.
class ChineseFoodDataSource {
  final Future<String> Function() _read;
  Future<List<_LocalFood>>? _loading;

  ChineseFoodDataSource({Future<String> Function()? read})
    : _read =
          read ?? (() => rootBundle.loadString('assets/foods/catalog.json'));

  Future<List<_LocalFood>> _foods() => _loading ??= _load();

  Future<List<_LocalFood>> _load() async {
    try {
      return await compute(_decodeFoods, await _read());
    } catch (_) {
      _loading = null;
      rethrow;
    }
  }

  static Future<int> validateCatalog(String text) async =>
      compute(_countValidFoods, text);

  Future<void> activate(String text) async {
    final foods = await compute(_decodeFoods, text);
    _loading = Future.value(foods);
  }

  Future<int> count() async => (await _foods()).length;

  Future<MealEntity?> byCatalogId(String id) async =>
      (await _foods()).where((row) => row.meal.code == id).firstOrNull?.meal;

  Future<List<({MealEntity food, int rank})>> matchBatchName(
    String query,
  ) async {
    final q = batchFoodKey(query);
    if (q.isEmpty) return [];
    final rows = <({MealEntity food, int rank})>[];
    for (final row in await _foods()) {
      final food = row.meal;
      final name = batchFoodKey(food.name ?? '');
      final brand = batchFoodKey(food.brands ?? '');
      final rank = name == q
          ? 0
          : row.aliases.contains(q)
          ? 1
          : brand.isNotEmpty &&
                ('$brand$name' == q ||
                    '$name$brand' == q ||
                    row.aliases.any((alias) => '$brand$alias' == q))
          ? 2
          : row.searchText.contains(q) ||
                (brand.isNotEmpty &&
                    q.startsWith(brand) &&
                    q.length > brand.length &&
                    (name.contains(q.substring(brand.length)) ||
                        row.aliases.any(
                          (alias) => alias.contains(q.substring(brand.length)),
                        )))
          ? 3
          : null;
      if (rank != null) rows.add((food: food, rank: rank));
    }
    rows.sort((a, b) => a.rank.compareTo(b.rank));
    return rows.take(60).toList();
  }

  /// Demo content refers to an explicit original record, never a fuzzy hit.
  /// If an upstream ID has conflicting records, require an explicit choice.
  Future<MealEntity> bySourceId(String source, String id) async {
    return (await _foods())
        .where((food) => food.sourceKeys.contains('$source:$id'))
        .single
        .meal;
  }

  Future<List<MealEntity>> search(String query, {int limit = 60}) async {
    final terms = foodQueryTerms(query);
    if (terms.isEmpty) return const [];
    final matches = (await _foods())
        .where((f) => terms.every(f.searchText.contains))
        .toList();
    int score(_LocalFood f) {
      final name = f.meal.name!.toLowerCase().replaceAll(RegExp(r'\s+'), '');
      final q = terms.join();
      return name == q ? 0 : (name.startsWith(q) ? 1 : 2);
    }

    matches.sort((a, b) {
      final rank = score(a).compareTo(score(b));
      if (rank != 0) return rank;
      final length = a.meal.name!.length.compareTo(b.meal.name!.length);
      return length != 0 ? length : a.meal.code!.compareTo(b.meal.code!);
    });
    return matches.take(limit).map((f) => f.meal).toList();
  }

  Future<MealEntity?> barcode(String value) async {
    for (final food in await _foods()) {
      if (food.barcode == value) return food.meal;
    }
    return null;
  }
}

class _LocalFood {
  final MealEntity meal;
  final String searchText;
  final String? barcode;
  final Set<String> sourceKeys;
  final Set<String> aliases;
  const _LocalFood(
    this.meal,
    this.searchText,
    this.barcode,
    this.sourceKeys,
    this.aliases,
  );
}

String batchFoodKey(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

List<_LocalFood> _decodeFoods(String text) {
  final decoded = jsonDecode(text) as Map<String, dynamic>;
  if (decoded['schema_version'] != 1 || decoded['foods'] is! List) {
    throw const FormatException('Unsupported Chinese food catalogue');
  }
  final ids = <String>{};
  if ((decoded['foods'] as List).isEmpty) {
    throw const FormatException('Empty catalogue');
  }
  return (decoded['foods'] as List).map((entry) {
    final row = entry as Map<String, dynamic>;
    if (row['id'] is! String ||
        (row['id'] as String).isEmpty ||
        !ids.add(row['id'] as String) ||
        row['name'] is! String ||
        (row['name'] as String).trim().isEmpty ||
        !{'g', 'ml'}.contains(row['unit'])) {
      throw const FormatException('Invalid food identity');
    }
    final n = row['nutrients'] as Map<String, dynamic>;
    for (final nutrient in n.values) {
      if (nutrient != null &&
          (nutrient is! num || !nutrient.isFinite || nutrient < 0)) {
        throw const FormatException('Invalid food nutrients');
      }
    }
    final weights = <num>{};
    for (final p in row['portions'] as List) {
      final grams = p['grams'];
      if (p['label'] is! String ||
          grams is! num ||
          !grams.isFinite ||
          grams <= 0 ||
          grams > 10000 ||
          !weights.add(grams)) {
        throw const FormatException('Invalid portion');
      }
    }
    double? value(String key) => (n[key] as num?)?.toDouble();
    final portions = (row['portions'] as List)
        .map(
          (p) => MealPortionEntity(
            label: p['label'] as String,
            gramWeight: (p['grams'] as num).toDouble(),
            localized: true,
          ),
        )
        .toList();
    final first = portions.firstOrNull;
    final meal = MealEntity(
      code: row['id'] as String,
      name: row['name'] as String,
      brands: (row['brand'] as String?)?.isNotEmpty == true
          ? row['brand'] as String
          : null,
      url: '',
      mealQuantity: '100',
      mealUnit: row['unit'] as String,
      servingQuantity: first?.gramWeight,
      servingUnit: row['unit'] as String,
      servingSize: first?.label,
      servingSizeIsLocalized: first != null,
      nutriments: MealNutrimentsEntity(
        energyKcal100: value('energy_kcal'),
        carbohydrates100: value('carbohydrate_g'),
        fat100: value('fat_g'),
        proteins100: value('protein_g'),
        sugars100: value('sugars_g'),
        saturatedFat100: value('saturated_fat_g'),
        fiber100: value('fiber_g'),
        sodium100: value('sodium_mg'),
        calcium100: value('calcium_mg'),
        iron100: value('iron_mg'),
        potassium100: value('potassium_mg'),
        magnesium100: value('magnesium_mg'),
        zinc100: value('zinc_mg'),
        phosphorus100: value('phosphorus_mg'),
        cholesterol100: value('cholesterol_mg'),
        vitaminA100: value('vitamin_a_ug'),
        vitaminC100: value('vitamin_c_mg'),
        niacin100: value('niacin_mg'),
      ),
      source: MealSourceEntity.fdc,
      backendSource: 'local_${(row['sources'] as List).first['source']}',
      portions: portions,
      detailed: true,
    );
    return _LocalFood(
      meal,
      '${row['name']} ${row['brand']} ${row['category']} '
              '${(row['aliases'] as List).join(' ')}'
          .toLowerCase(),
      row['barcode'] as String?,
      {
        for (final source in row['sources'] as List)
          '${source['source']}:${source['id']}',
      },
      {
        for (final alias in row['aliases'] as List)
          batchFoodKey(alias.toString()),
      },
    );
  }).toList();
}

int _countValidFoods(String text) => _decodeFoods(text).length;
