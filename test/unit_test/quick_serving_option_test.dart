import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_portion_entity.dart';
import 'package:opennutritracker/features/meal_detail/util/quick_serving_option.dart';
import 'package:opennutritracker/features/meal_detail/util/portion_display.dart';
import 'package:opennutritracker/features/meal_detail/util/food_entry_policy.dart';
import 'package:opennutritracker/features/meal_detail/util/food_weight_basis.dart';

// Locks in what the meal-detail sheet's quick-serving chip row is meant
// to show for each shape of food — the trio of ×-multipliers when the
// backend gave us a scalable serving, the 100 g shortcut whenever the
// unit dropdown would offer grams, both together for a solid with a
// serving, and nothing at all when the food is exclusively a liquid
// with no scalable serving (so 100 g would be a wrong unit).

const _nutriments = MealNutrimentsEntity(
  energyKcal100: 100,
  carbohydrates100: 10,
  fat100: 5,
  proteins100: 5,
  sugars100: 2,
  saturatedFat100: 1,
  fiber100: 1,
);

MealEntity _meal({
  double? servingQuantity,
  String? servingUnit,
  String? servingSize,
  String? mealUnit,
  List<MealPortionEntity> portions = const [],
}) {
  return MealEntity(
    code: 'quick-serving-test',
    name: 'Test product',
    url: null,
    mealQuantity: null,
    mealUnit: mealUnit,
    servingQuantity: servingQuantity,
    servingUnit: servingUnit,
    servingSize: servingSize,
    nutriments: _nutriments,
    source: MealSourceEntity.off,
    portions: portions,
  );
}

void main() {
  test('count entry is limited to packaged food and saved recipe servings', () {
    MealEntity product(
      MealSourceEntity source,
      String label, {
      String? brand,
      double weight = 30,
    }) => MealEntity(
      code: 'policy',
      name: 'Food',
      url: null,
      mealQuantity: null,
      mealUnit: 'g',
      servingQuantity: weight,
      servingUnit: 'g',
      servingSize: label,
      brands: brand,
      nutriments: _nutriments,
      source: source,
    );
    expect(offersCountedServings(product(MealSourceEntity.fdc, '一碗')), isFalse);
    expect(
      offersCountedServings(product(MealSourceEntity.fdc, '一份', brand: '餐厅')),
      isFalse,
    );
    expect(
      offersCountedServings(product(MealSourceEntity.fdc, '一袋', brand: '品牌')),
      isTrue,
    );
    expect(
      offersCountedServings(product(MealSourceEntity.custom, '一包（30克）')),
      isTrue,
    );
    expect(
      offersCountedServings(product(MealSourceEntity.custom, '一份')),
      isFalse,
    );
    expect(
      offersCountedServings(product(MealSourceEntity.off, '30 g')),
      isTrue,
    );
    expect(
      offersCountedServings(product(MealSourceEntity.recipe, '一份')),
      isTrue,
    );
    expect(
      offersCountedServings(
        product(MealSourceEntity.off, '一包', weight: double.nan),
      ),
      isFalse,
    );
    expect(
      offersCountedServings(product(MealSourceEntity.off, '一包', weight: 0)),
      isFalse,
    );
  });

  test(
    'weight basis remains explicit for rice, noodles and hydrated foods',
    () {
      expect(foodWeightBasis('大米（生）'), FoodWeightBasis.raw);
      expect(foodWeightBasis('米饭'), FoodWeightBasis.cooked);
      expect(foodWeightBasis('蒸米饭'), FoodWeightBasis.cooked);
      expect(foodWeightBasis('面条（富强粉,煮）'), FoodWeightBasis.cooked);
      expect(foodWeightBasis('粉丝（干）'), FoodWeightBasis.dry);
      expect(foodWeightBasis('河粉（湿）'), FoodWeightBasis.wet);
      expect(foodWeightBasis('扁豆（鲜）'), FoodWeightBasis.fresh);
      expect(foodWeightBasis('木耳（泡发）'), FoodWeightBasis.rehydrated);
      expect(foodWeightBasis('豆腐干'), isNull);
      expect(foodWeightBasis('生菜'), isNull);
    },
  );

  group('quickServingOptionsFor', () {
    test('household portions fill grams instead of a serving count', () {
      final food = MealEntity(
        code: 'rice',
        name: '米饭',
        mealUnit: 'g',
        url: null,
        mealQuantity: null,
        servingQuantity: null,
        servingUnit: null,
        servingSize: null,
        nutriments: _nutriments,
        source: MealSourceEntity.fdc,
        backendSource: 'local_calshot',
        portions: const [
          MealPortionEntity(label: '小碗', gramWeight: 150, localized: true),
          MealPortionEntity(label: '大碗', gramWeight: 300, localized: true),
        ],
      );
      final presets = quickServingOptionsFor(food, 'g');
      expect(presets.first.quantity, 150);
      expect(presets.first.unit, 'g');
      expect(presets[1].quantity, 300);
      expect(presets.every((p) => p.unit == 'g'), isTrue);
    });

    test('a non-packaged fallback serving is a weight preset', () {
      final food = MealEntity(
        code: 'egg',
        name: '鸡蛋',
        mealUnit: 'g',
        url: null,
        mealQuantity: null,
        servingQuantity: 50,
        servingSize: '中个',
        servingUnit: 'g',
        nutriments: _nutriments,
        source: MealSourceEntity.fdc,
      );
      final presets = quickServingOptionsFor(food, 'g');
      expect(presets.first.quantity, 50);
      expect(presets.first.unit, 'g');
      expect(presets.every((p) => p.unit == 'g'), isTrue);
    });

    test('named portions replace equal-weight portions and weight presets', () {
      final meal = _meal(
        mealUnit: 'g',
        portions: const [
          MealPortionEntity(label: '小个', gramWeight: 50, localized: true),
          MealPortionEntity(label: '50克', gramWeight: 50, localized: true),
          MealPortionEntity(label: '大个', gramWeight: 100, localized: true),
        ],
      );
      final options = quickServingOptionsFor(
        meal,
        'g',
        includeWeightPresets: true,
      );
      expect(options.map((o) => o.id), [
        'portion-0',
        'portion-2',
        '150g',
        '200g',
      ]);
      expect(options.first.label, '小个 · 50 g');
      expect(visiblePortionIndices(meal, selectedUnit: 'serving#1'), [1, 2]);
    });

    test('serving multipliers replace identical gram presets', () {
      final options = quickServingOptionsFor(
        _meal(servingQuantity: 100, servingUnit: 'g', mealUnit: 'g'),
        'g',
        includeWeightPresets: true,
      );
      expect(options.map((o) => o.id), [
        'half-serving',
        'one-serving',
        'double-serving',
        '150g',
      ]);
    });

    test('portion labels do not repeat a weight already present', () {
      for (final label in ['100克', '100 g', '一份（100克）']) {
        expect(
          portionDisplayLabel(
            MealPortionEntity(label: label, gramWeight: 100, localized: true),
            'g',
          ),
          label,
        );
      }
      expect(
        portionDisplayLabel(
          const MealPortionEntity(
            label: '半个',
            gramWeight: 25.5,
            localized: true,
          ),
          'g',
        ),
        '半个 · 25.5 g',
      );
    });

    test('solid food with a scalable serving offers all four presets', () {
      final options = quickServingOptionsFor(
        _meal(servingQuantity: 30, servingUnit: 'g', mealUnit: 'g'),
        'g',
      );

      expect(options, hasLength(4));
      expect(options.map((o) => o.id).toList(), [
        'half-serving',
        'one-serving',
        'double-serving',
        '100g',
      ]);
      expect(options.map((o) => o.label).toList(), ['½×', '1×', '2×', '100 g']);
      expect(options.map((o) => o.unit).toList(), [
        'serving',
        'serving',
        'serving',
        'g',
      ]);
      expect(options.map((o) => o.quantity).toList(), [0.5, 1, 2, 100]);
    });

    test('liquid food with a scalable serving offers only the multipliers', () {
      final options = quickServingOptionsFor(
        _meal(servingQuantity: 250, servingUnit: 'ml', mealUnit: 'ml'),
        'g',
      );

      expect(options.map((o) => o.id).toList(), [
        'half-serving',
        'one-serving',
        'double-serving',
      ]);
      expect(options.every((o) => o.unit == 'serving'), isTrue);
    });

    test('solid food without a serving still offers the 100 g shortcut', () {
      final options = quickServingOptionsFor(_meal(mealUnit: 'g'), 'g');

      expect(options, hasLength(1));
      expect(options.single.id, '100g');
      expect(options.single.label, '100 g');
      expect(options.single.unit, 'g');
      expect(options.single.quantity, 100);
    });

    test('meal with neither solid nor liquid unit (e.g. gml quick-add) still '
        'gets the 100 g shortcut, mirroring the unit dropdown', () {
      final options = quickServingOptionsFor(_meal(mealUnit: null), 'g');

      expect(options, hasLength(1));
      expect(options.single.id, '100g');
    });

    test('purely liquid food with no serving gets no chip row', () {
      final options = quickServingOptionsFor(_meal(mealUnit: 'ml'), 'g');

      expect(options, isEmpty);
    });

    test('gram unit label passes through so callers can localise it', () {
      final options = quickServingOptionsFor(_meal(mealUnit: 'g'), 'grams');

      expect(options.single.label, '100 grams');
      expect(options.single.id, '100g');
    });

    test('id values stay ASCII regardless of the localised label', () {
      // Simulates a Cyrillic gram unit (Ukrainian "г") to confirm the id used
      // for Semantics never absorbs the label's script — that identifier is
      // meant for accessibility + integration tests, not for display.
      final options = quickServingOptionsFor(
        _meal(servingQuantity: 30, mealUnit: 'g'),
        'г',
      );

      final gramChip = options.singleWhere((o) => o.unit == 'g');
      expect(gramChip.label, '100 г');
      expect(gramChip.id, '100g');
    });

    test('scalableServingQuantity recovers from servingSize when quantity is '
        'missing', () {
      final options = quickServingOptionsFor(
        _meal(servingSize: '1 slice (30 g)', mealUnit: 'g'),
        'g',
      );

      expect(options.map((o) => o.id).toList(), [
        'half-serving',
        'one-serving',
        'double-serving',
        '100g',
      ]);
    });
  });
}
