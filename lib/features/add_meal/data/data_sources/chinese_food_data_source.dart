import 'package:opennutritracker/features/add_meal/util/food_query.dart';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_portion_entity.dart';

/// A private offline snapshot. Never falls back to a remote food database.
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

  Future<int> count() async => (await _foods()).length;

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
  const _LocalFood(this.meal, this.searchText, this.barcode, this.sourceKeys);
}

List<_LocalFood> _decodeFoods(String text) {
  final decoded = jsonDecode(text) as Map<String, dynamic>;
  if (decoded['schema_version'] != 1 || decoded['foods'] is! List) {
    throw const FormatException('Unsupported Chinese food catalogue');
  }
  return (decoded['foods'] as List).map((entry) {
    final row = entry as Map<String, dynamic>;
    final n = row['nutrients'] as Map<String, dynamic>;
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
    );
  }).toList();
}
