import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/meal_nutriments_dbo.dart';
import 'package:opennutritracker/core/data/dbo/recipe_ingredient_dbo.dart';
import 'package:opennutritracker/core/domain/entity/recipe_ingredient_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_portion_entity.dart';
import 'package:opennutritracker/features/recipes/domain/entity/shared_recipe_payload.dart';

const _food = MealEntity(
  code: 'egg',
  name: '鸡蛋',
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: null,
  servingUnit: null,
  servingSize: null,
  nutriments: MealNutrimentsEntity(
    energyKcal100: 144,
    carbohydrates100: 2,
    proteins100: 13,
    fat100: 10,
    sugars100: null,
    saturatedFat100: null,
    fiber100: null,
  ),
  source: MealSourceEntity.custom,
  portions: [MealPortionEntity(label: '中个', gramWeight: 50, localized: true)],
);

const _ingredient = RecipeIngredientEntity(
  snapshotMeal: _food,
  amount: 3,
  unit: 'serving',
  convertedAmountG: 150,
);

void main() {
  test(
    'JSON export retains named portions and old exports remain readable',
    () {
      final json =
          jsonDecode(jsonEncode(_ingredient.toDBO().toJson()))
              as Map<String, dynamic>;
      final restored = RecipeIngredientEntity.fromDBO(
        RecipeIngredientDBO.fromJson(json),
      );
      expect(restored.snapshotMeal.portions, _food.portions);
      expect(restored.amount, 3);
      expect(restored.unit, 'serving');
      json.remove('portions');
      final legacy = RecipeIngredientEntity.fromDBO(
        RecipeIngredientDBO.fromJson(json),
      );
      expect(legacy.snapshotMeal.portions, isEmpty);
      expect(legacy.convertedAmountG, 150);
    },
  );

  test(
    'Hive keeps portion specifications after closing and reopening storage',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'recipe-portions-',
      );
      final hive = Hive;
      hive.init(directory.path);
      hive.registerAdapter(MealDBOAdapter());
      hive.registerAdapter(MealSourceDBOAdapter());
      hive.registerAdapter(MealNutrimentsDBOAdapter());
      hive.registerAdapter(RecipeIngredientDBOAdapter());
      addTearDown(() async {
        await hive.close();
        await directory.delete(recursive: true);
      });
      var box = await hive.openBox<RecipeIngredientDBO>('ingredients');
      await box.put('egg', _ingredient.toDBO());
      await box.close();
      box = await hive.openBox<RecipeIngredientDBO>('ingredients');
      final restored = RecipeIngredientEntity.fromDBO(box.get('egg')!);
      expect(restored.snapshotMeal.portions, _food.portions);
      expect(restored.unit, 'serving');
      expect(restored.convertedAmountG, 150);
    },
  );

  for (final unit in ['g', 'ml']) {
    test(
      'shared $unit portions retain actual amount without the source library',
      () {
        final ingredient = _ingredient.copyWith(
          snapshotMeal: MealEntity(
            code: _food.code,
            name: _food.name,
            url: null,
            mealQuantity: null,
            mealUnit: unit,
            servingQuantity: null,
            servingUnit: null,
            servingSize: null,
            nutriments: _food.nutriments,
            source: _food.source,
            portions: _food.portions,
          ),
        );
        final shared = SharedRecipeIngredient.fromIngredient(ingredient);
        final restored = SharedRecipeIngredient.fromArray(
          jsonDecode(jsonEncode(shared.toArray())) as List<dynamic>,
        ).toIngredient();
        expect(restored.amount, 150);
        expect(restored.unit, unit);
        expect(restored.snapshotMeal.isLiquid, unit == 'ml');
        expect(restored.convertedAmountG, 150);
      },
    );
  }
}
