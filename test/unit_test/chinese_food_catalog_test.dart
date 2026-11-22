import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'dart:convert';
import 'dart:io';
import 'package:opennutritracker/features/meal_detail/util/meal_quantity_converter.dart';
import 'package:opennutritracker/features/meal_detail/util/quick_serving_option.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/data_source/recipe_data_source.dart';
import 'package:opennutritracker/core/data/data_source/remote_search_cache_data_source.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/recipe_dbo.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/toggle_favourite_meal_usecase.dart';
import 'package:opennutritracker/features/add_meal/data/data_sources/chinese_food_data_source.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/search_products_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/search_debounce.dart';
import 'package:opennutritracker/features/add_meal/util/meal_relevance_ranker.dart';
import 'package:opennutritracker/features/meal_detail/util/hydrate_off_meal.dart';
import 'package:opennutritracker/features/scanner/data/product_not_found_exception.dart';
import 'package:opennutritracker/features/scanner/domain/usecase/search_product_by_barcode_usecase.dart';

Map<String, Object?> _food(String id, String name, {double kcal = 144}) => {
  'id': id,
  'name': name,
  'brand': '',
  'category': '蛋类',
  'unit': 'g',
  'aliases': ['Egg'],
  'barcode': id == 'cn-egg' ? '12345678' : null,
  'sources': [
    {'source': 'cn_fct', 'id': id},
  ],
  'nutrients': {
    'energy_kcal': kcal,
    'protein_g': 13,
    'carbohydrate_g': 1.1,
    'fat_g': 9.5,
    'sodium_mg': 142,
  },
  'portions': [
    {'label': '一个中等鸡蛋', 'grams': 50},
  ],
};

MealDBO _snapshot(
  MealEntity meal, {
  String? code,
  String? name,
  MealSourceDBO? source,
  bool? detailed,
}) {
  final original = MealDBO.fromMealEntity(meal);
  return MealDBO(
    code: code ?? original.code,
    name: name ?? original.name,
    brands: original.brands,
    thumbnailImageUrl: original.thumbnailImageUrl,
    mainImageUrl: original.mainImageUrl,
    url: original.url,
    mealQuantity: original.mealQuantity,
    mealUnit: original.mealUnit,
    servingQuantity: original.servingQuantity,
    servingUnit: original.servingUnit,
    servingSize: original.servingSize,
    nutriments: original.nutriments,
    source: source ?? original.source,
    detailed: detailed ?? original.detailed,
    backendSource: original.backendSource,
    dataVersion: original.dataVersion,
  );
}

class _Custom extends Fake implements CustomMealDataSource {
  final List<MealDBO> meals = [];
  @override
  List<MealDBO> getAllCustomMeals() => meals;
}

class _Recipes extends Fake implements RecipeDataSource {
  @override
  List<RecipeDBO> getAllRecipes() => [];
}

class _Intakes extends Fake implements GetIntakeUsecase {
  @override
  Future<List<IntakeEntity>> getRecentIntake() async => [];
}

class _Config extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async => ConfigEntity(
    true,
    true,
    false,
    AppThemeEntity.system,
    // An old preference must not switch the Chinese library off.
    foodSourceToggles: const {'local_cn_fct': false, 'fdc_survey': false},
  );
}

class _Cache extends Fake implements RemoteSearchCacheDataSource {
  final List<MealDBO> meals = [];
  int writes = 0;
  @override
  List<MealDBO> getAllByMostRecentlyTouched() => meals;
  @override
  MealDBO? getDetailedByBarcode(String barcode) => meals.firstOrNull;
  @override
  Future<void> cacheFromSearch(Iterable<MealDBO> incoming) async => writes++;
  @override
  Future<void> cache(MealDBO meal) async => writes++;
}

class _Favourites extends Fake implements ToggleFavouriteMealUsecase {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('real bundled catalogue resolves the mixed cola corn potato description', () async {
    final source = ChineseFoodDataSource(read: () => File('assets/foods/catalog.json').readAsString());
    final search = SearchProductsUseCase(ProductsRepository.local(source),
      _Intakes(), _Custom(), _Cache(), _Recipes(), _Config());
    final resolved = await ResolveParsedMealsUseCase(search).resolve(
      parseMealText('无糖可乐 玉米100g 土豆50g').items);
    expect(resolved.map((row) => row.parsed.query), ['无糖可乐', '玉米', '土豆']);
    expect(resolved.every((row) => row.isResolved), isTrue);
    expect(resolved.map((row) => row.parsed.quantity), [null, 100, 50]);
  });
  late ChineseFoodDataSource source;
  late ProductsRepository repository;
  late _Cache cache;
  late _Custom custom;
  setUp(() {
    source = ChineseFoodDataSource(
      read: () async => jsonEncode({
        'schema_version': 1,
        'foods': [
          _food('cn-egg', '鸡蛋'),
          _food('cn-egg-other', '煮鸡蛋', kcal: 160),
        ],
      }),
    );
    repository = ProductsRepository.local(source);
    cache = _Cache();
    custom = _Custom();
  });

  test(
    'Chinese, aliases, exact ranking, portions and mg retain their units',
    () async {
      final food = (await source.search('蛋')).first;
      expect(food.name, '鸡蛋');
      expect(food.portions.single.gramWeight, 50);
      expect(food.servingSizeIsLocalized, true);
      expect(food.nutriments.sodium100, 142);
      expect(food.nutriments.fiber100, isNull);
      expect(food.nutriments.vitaminA100, isNull);
      expect(await source.search('EGG'), hasLength(2));
      expect(await source.search(' '), isEmpty);
      expect((await source.bySourceId('cn_fct', 'cn-egg')).code, 'cn-egg');
    },
  );

  test(
    'both legacy search entries use the offline corpus and merge by id',
    () async {
      final products = await repository.getOFFProductsByString('蛋');
      final foods = await repository.getSupabaseFoodsByString(
        '蛋',
        forResolution: true,
      );
      expect(repository.usesLocalFoods, true);
      expect(
        mergeAndRankMeals(products, foods, '蛋'),
        hasLength(2),
        reason: 'Two tabs collapse; distinct preparations remain selectable',
      );
      expect(
        (await repository.getOFFProductByBarcode('12345678')).code,
        'cn-egg',
      );
      await expectLater(
        repository.getOFFProductByBarcode('missing'),
        throwsA(isA<ProductNotFoundException>()),
      );
    },
  );

  test(
    'one Chinese character searches; blank and one Latin character wait',
    () {
      expect(isSearchQueryLongEnough(' 蛋 '), true);
      expect(isSearchQueryLongEnough('米'), true);
      expect(isSearchQueryLongEnough('a'), false);
      expect(isSearchQueryLongEnough('ab'), true);
      expect(isSearchQueryLongEnough(' '), false);
    },
  );

  test(
    'retries an asset read after failure instead of poisoning its cache',
    () async {
      var reads = 0;
      final retrySource = ChineseFoodDataSource(
        read: () async {
          if (++reads == 1) {
            throw const FileSystemException('test read failure');
          }
          return jsonEncode({
            'schema_version': 1,
            'foods': [_food('cn-egg', '鸡蛋')],
          });
        },
      );
      await expectLater(
        retrySource.count(),
        throwsA(isA<FileSystemException>()),
      );
      expect(await retrySource.count(), 1);
    },
  );

  test(
    'old remote cache is hidden, custom foods and snapshots are preserved',
    () async {
      final food = (await source.search('鸡蛋')).first;
      final remote = _snapshot(food, name: '鸡蛋 Egg (legacy English)');
      cache.meals.add(remote);
      custom.meals.add(
        _snapshot(
          food,
          code: 'my-egg',
          name: '我的鸡蛋',
          source: MealSourceDBO.custom,
        ),
      );
      final usecase = SearchProductsUseCase(
        repository,
        _Intakes(),
        custom,
        cache,
        _Recipes(),
        _Config(),
      );
      for (final result in [
        await usecase.searchOFFProductsByString('蛋'),
        await usecase.searchFDCFoodByString('蛋'),
      ]) {
        expect(result.meals.map((m) => m.name), ['我的鸡蛋', '鸡蛋', '煮鸡蛋']);
        expect(result.remoteSourceFailed, false);
        expect(result.meals.last.portions, isNotEmpty);
      }
      expect(cache.writes, 0);
      expect(cache.meals.single.name, '鸡蛋 Egg (legacy English)');
      expect(custom.meals.single.name, '我的鸡蛋');
    },
  );

  test(
    'barcode skips legacy English cache and custom food still wins',
    () async {
      final food = await repository.getOFFProductByBarcode('12345678');
      cache.meals.add(_snapshot(food, name: 'Old English Egg'));
      final usecase = SearchProductByBarcodeUseCase(
        repository,
        custom,
        cache,
        _Favourites(),
      );
      expect((await usecase.searchProductByBarcode('12345678')).name, '鸡蛋');
      await expectLater(
        usecase.searchProductByBarcode('missing'),
        throwsA(isA<ProductNotFoundException>()),
      );
      custom.meals.add(
        _snapshot(
          food,
          code: '12345678',
          name: '自定义鸡蛋',
          source: MealSourceDBO.custom,
        ),
      );
      expect((await usecase.searchProductByBarcode('12345678')).name, '自定义鸡蛋');
      expect(cache.writes, 0);
    },
  );

  test('historical OFF detail never requests remote hydration', () async {
    final food = (await source.search('鸡蛋')).first;
    final historical = _snapshot(
      food,
      source: MealSourceDBO.off,
      detailed: false,
    );
    expect(
      await fetchDetailedOffMeal(
        MealEntity.fromMealDBO(historical),
        cache,
        repository,
      ),
      isNull,
    );
    expect(cache.writes, 0);
  });

  test(
    'actual raw and hydrated foods scale against their own nutrient basis',
    () async {
      final actual = ChineseFoodDataSource();
      for (final entry in [
        ('calshot', '962545', '大米（生）', 346.0),
        ('cn_fct', '012401x', '蒸米饭', 116.0),
        ('cn_fct', '22201', '粉丝（干）', 338.0),
        ('calshot', '551', '粉丝（湿）', 125.0),
        ('cn_fct', '019010', '荞麦面（干）', 340.0),
        ('calshot', '545', '荞麦面（熟）', 132.0),
      ]) {
        final meal = await actual.bySourceId(entry.$1, entry.$2);
        expect(meal.name, entry.$3);
        final weight = convertQuantityToBaseUnit(150, 'g', meal);
        expect(
          weight * meal.nutriments.energyPerUnit!,
          closeTo(entry.$4 * 1.5, .001),
        );
        for (final option in quickServingOptionsFor(meal, '克')) {
          expect(option.unit, 'g');
          expect(
            convertQuantityToBaseUnit(option.quantity, option.unit, meal),
            option.quantity,
          );
        }
      }
      final wet = await actual.bySourceId('calshot', '550');
      expect(
        wet.portions.any((p) => RegExp('干炒|汤河粉').hasMatch(p.label)),
        false,
      );
      final hydrated = await actual.bySourceId('calshot', '178');
      expect(hydrated.portions.any((p) => p.label.contains('干木耳')), false);
    },
  );

  test(
    'refreshed volume foods scale in ml without a density conversion',
    () async {
      final actual = ChineseFoodDataSource();
      final drink = await actual.bySourceId('fatsecret', '/热量营养/喜茶/咸酪藏茶/100毫升');
      expect(drink.isLiquid, true);
      expect(drink.mealUnit, 'ml');
      expect(drink.nutriments.energyKcal100, 48);
      expect(kcalForQuantity(250, 'ml', drink), closeTo(120, .001));
      final sauce = await actual.bySourceId('fatsecret', '/热量营养/东古/海鲜酱油/1份');
      expect(sauce.mealUnit, 'ml');
      expect(kcalForQuantity(15, 'ml', sauce), closeTo(13, .001));
      final greens = await actual.bySourceId('cn_fct', '48040');
      expect(greens.nutriments.energyKcal100, 53);
      for (final option in quickServingOptionsFor(sauce, '克')) {
        expect(option.unit, 'ml');
        expect(option.label.contains('克'), false);
      }
    },
  );

  test(
    'private snapshot has Chinese names, unique ids and three sources',
    () async {
      final file = File('assets/foods/catalog.json');
      expect(
        file.existsSync(),
        true,
        reason: 'Run tool/build_chinese_food_catalog.py first',
      );
      final rows =
          (jsonDecode(await file.readAsString()) as Map)['foods'] as List;
      expect(rows.length, greaterThan(10000));
      expect(rows.map((f) => f['id']).toSet(), hasLength(rows.length));
      expect(
        rows.every(
          (f) => RegExp(r'[\u3400-\u9fff]').hasMatch(f['name'] as String),
        ),
        true,
      );
      final sources = rows
          .expand((f) => f['sources'] as List)
          .map((s) => s['source'])
          .toSet();
      expect(sources, {'cn_fct', 'calshot', 'fatsecret'});
      expect(
        rows.map((f) => '${f['name']}|${f['brand']}|${f['unit']}').toSet(),
        hasLength(rows.length),
        reason: 'A food identity must appear once even when nutrition differs',
      );
      final egg = rows.singleWhere(
        (f) => f['name'] == '鸡蛋' && f['brand'] == '',
      );
      expect(egg['nutrition_source']['source'], 'cn_fct');
      expect(
        rows.where((f) => f['name'] == '煮鸡蛋' && f['brand'] == ''),
        hasLength(1),
      );
      expect(rows.any((f) => (f['name'] as String).contains('（者）')), false);
      expect(
        rows.any((f) => RegExp('代表值|平均值|均值').hasMatch(f['name'] as String)),
        false,
      );
      expect(rows.where((f) => f['name'] == '蒸米饭'), isNotEmpty);
      expect(rows.any((f) => (f['name'] as String).contains('\ufffd')), false);
      for (final row in rows) {
        final portions = row['portions'] as List;
        expect(
          portions.map((p) => p['grams']).toSet(),
          hasLength(portions.length),
          reason: row['name'],
        );
      }
      final actual = ChineseFoodDataSource();
      expect(await actual.count(), rows.length);
      expect(await actual.search('鸡蛋'), isNotEmpty);
      expect(await actual.search('米饭'), isNotEmpty);
      expect((await actual.bySourceId('calshot', '855')).code, egg['id']);
    },
  );
}
