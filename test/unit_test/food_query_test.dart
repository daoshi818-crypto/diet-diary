import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/util/food_query.dart';

void main() {
  test('space keywords are AND matched across name and brand in any order', () {
    final meal = MealEntity(
      code: 'oat',
      name: '即食燕麦片',
      brands: '西麦',
      url: null,
      mealQuantity: null,
      mealUnit: 'g',
      servingQuantity: null,
      servingUnit: null,
      servingSize: null,
      nutriments: MealNutrimentsEntity.empty(),
      source: MealSourceEntity.custom,
    );
    for (final query in [
      '西麦 麦片',
      '麦片 西麦',
      '  西麦   麦片  ',
      '西麦\t麦片',
      '西麦 西麦 麦片',
    ]) {
      expect(foodMatchesQuery(meal, query), true, reason: query);
    }
    expect(foodMatchesQuery(meal, '西麦 牛奶'), false);
    expect(foodMatchesQuery(meal, ''), true);
    expect(foodTextMatches('meal tuna', ['Tuna rice meal']), true);
    expect(foodTextMatches('rice chicken', ['Tuna rice meal']), false);
  });
}
