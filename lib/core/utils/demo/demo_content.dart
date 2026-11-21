import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

import 'package:opennutritracker/core/domain/entity/custom_activity_template_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/physical_activity_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_ingredient_entity.dart';
import 'package:opennutritracker/core/domain/entity/water_intake_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_custom_activity_template_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/save_recipe_usecase.dart';
import 'package:opennutritracker/core/utils/demo/unsplash_attribution.dart';
import 'package:opennutritracker/core/utils/id_generator.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/user_image_storage.dart';
import 'package:opennutritracker/features/add_meal/data/data_sources/chinese_food_data_source.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';

/// Shared, duration-agnostic demo content: the curated food set, activity
/// pool, recipes, and the algorithm that turns a day's macro targets into
/// realistic intake entries. Both the dev-only 365-day QA fixture
/// (`lib/dev/main_dev.dart`) and the production "try it with sample data"
/// onboarding flow build on this — only how many days and how strict the
/// adherence is (see `demo_seeder.dart`'s `DemoSeedOptions`) differs
/// between them.
///
/// Fixed seed for [demoRng]. Re-applied via [resetDemoRng] at the start of
/// every `seedDemoData` call so a second try-demo / `just dev_seed` in the
/// same process reproduces the same fixture rather than continuing the
/// previous run's RNG stream.
const demoRngSeed = 1337;

/// The current-streak guarantee and all day-to-day randomisation (which
/// foods/portions/times are picked) read off this single fixed-seed
/// generator, so the data looks organically noisy (no obvious repeating
/// cycle in the calorie/water graphs) while still being reproducible
/// across runs — handy for a dev tool where you want the same fixture
/// every time you reseed, not a new random one.
var demoRng = Random(demoRngSeed);

/// Reset [demoRng] to a fresh `Random([demoRngSeed])`. Called by
/// `seedDemoData` before generating content.
void resetDemoRng() => demoRng = Random(demoRngSeed);

/// [hour]:00 plus up to 44 random minutes, so logged times don't land on
/// the exact same clock minute every single day.
DateTime jitteredTime(DateTime day, int hour) =>
    DateTime(day.year, day.month, day.day, hour, demoRng.nextInt(45));

/// The fixed set of foods used to build every day's intake and the
/// recipes. Grouped so [buildDailyIntakes] and [seedRecipes] don't have
/// to know how they were constructed.
typedef DemoFoods = ({
  MealEntity oatmeal,
  MealEntity brownRice,
  MealEntity wholegrainBread,
  MealEntity chickenBreast,
  MealEntity greekYogurt,
  MealEntity salmon,
  MealEntity oliveOil,
  MealEntity almonds,
  MealEntity banana,
  MealEntity apple,
  MealEntity broccoli,
});

final _log = Logger('DemoContent');

/// Directory holding the bundled demo meal photos, one JPEG per curated
/// Unsplash photo id. Registered in `pubspec.yaml`.
const _mealPhotoAssetDir = 'assets/demo/meals';

/// Copies the bundled photo for [photoId] into local meal-image storage
/// under [ownerCode] and records the photographer credit in the sidecar
/// that `UnsplashCreditFromSidecar` reads back.
///
/// The photos ship with the app rather than being hotlinked from
/// Unsplash's CDN, so seeding — and every later render of a demo meal —
/// needs no network access at all. Mirrors the profile-avatar import in
/// `demo_seeder.dart`.
///
/// Returns null on any failure: a missing photo should fall back to the
/// placeholder thumbnail, not abort the seed.
Future<String?> _importMealPhoto(String photoId, String ownerCode) async {
  if (kIsWeb) return '$_mealPhotoAssetDir/$photoId.jpg';
  try {
    final bytes = (await rootBundle.load(
      '$_mealPhotoAssetDir/$photoId.jpg',
    )).buffer.asUint8List();
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/demo_meal_$photoId.jpg');
    try {
      await tempFile.writeAsBytes(bytes, flush: true);
      final relativePath = await UserImageStorage.importFrom(
        kind: UserImageKind.meal,
        ownerId: ownerCode,
        sourcePath: tempFile.path,
      );
      final credit = unsplashCreditForUrl(unsplashImageUrl(photoId));
      if (credit != null) {
        await UserImageStorage.writeCredit(
          relativePath,
          name: credit.name,
          profileUrl: credit.profileUrl,
        );
      }
      return relativePath;
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  } catch (e) {
    _log.warning('Could not import bundled demo meal photo $photoId: $e');
    return null;
  }
}

/// The demo uses the same private Chinese catalogue as food search. Photos
/// remain bundled examples; nutrition is copied without inventing missing data.
Future<DemoFoods> buildDemoFoods({ChineseFoodDataSource? catalogue}) async {
  final source = catalogue ?? ChineseFoodDataSource();
  Future<MealEntity> meal(String sourceId, String photoId) async {
    final food = await source.bySourceId('calshot', sourceId);
    return MealEntity(
      code: food.code,
      name: food.name,
      brands: food.brands,
      url: food.url,
      mealQuantity: food.mealQuantity,
      mealUnit: food.mealUnit,
      servingQuantity: food.servingQuantity,
      servingUnit: food.servingUnit,
      servingSize: food.servingSize,
      servingSizeIsLocalized: food.servingSizeIsLocalized,
      nutriments: food.nutriments,
      source: food.source,
      backendSource: food.backendSource,
      portions: food.portions,
      detailed: true,
      localImagePath: await _importMealPhoto(photoId, food.code!),
    );
  }

  return (
    oatmeal: await meal('460', '1548807371-30dc1bbe6cb5'),
    brownRice: await meal('140', '1593357849627-cbbc9fda6b05'),
    wholegrainBread: await meal('411', '1552056413-b8b5eed0170b'),
    chickenBreast: await meal('1422', '1762631934518-f75e233413ca'),
    greekYogurt: await meal('885', '1571212515416-fef01fc43637'),
    salmon: await meal('324786', '1739785938237-73b3654200d5'),
    oliveOil: await meal('962536', '1757801333069-f7b3cabaec4a'),
    almonds: await meal('920', '1627820752174-acae1b399128'),
    banana: await meal('340', '1757332050958-b797a022c910'),
    apple: await meal('339', '1567306226416-28f0efdc88ce'),
    broccoli: await meal('172', '1646161762904-043f71f256f1'),
  );
}

double _roundToNearest5g(double grams) => grams <= 0 ? 0.0 : max(10.0, (grams / 5).round() * 5.0);

/// Grams of [meal] needed to supply [targetGrams] of the macro read off by
/// [macroPer100] (e.g. `(n) => n.proteins100`). Zero when the food doesn't
/// carry that macro or the target is already met.
double _gramsFor(
  MealEntity meal,
  double targetGrams,
  double? Function(MealNutrimentsEntity) macroPer100,
) {
  final per100 = macroPer100(meal.nutriments) ?? 0;
  if (per100 <= 0 || targetGrams <= 0) return 0;
  return targetGrams / per100 * 100;
}

double _macroGrams(
  MealEntity meal,
  double amount,
  double? Function(MealNutrimentsEntity) macroPer100,
) => (macroPer100(meal.nutriments) ?? 0) * amount / 100;

/// Builds the day's intake by solving for each food's portion in turn —
/// veg and fruit are fixed-size sides; the carb target is split across a
/// breakfast and a dinner starch (rather than one giant bowl of rice);
/// the fat target is split across a dinner oil and a snack-time handful
/// of almonds; and the protein source is sized last, to whatever protein
/// target is left after every other food's contribution is known. Both
/// the splitting and the protein-last ordering exist for the same
/// reason: a single food sized to cover an entire day's target for one
/// macro produces an unrealistic portion (900g+ of rice) and, for
/// protein specifically, routinely overshoots the goal once the other
/// foods' incidental protein is added on top.
///
/// Which foods and what split ratios are chosen is randomised per day
/// (see [demoRng]) rather than rotated through a fixed cycle, so the
/// week doesn't visibly repeat itself.
List<IntakeEntity> buildDailyIntakes(
  DateTime day,
  ({double carbs, double fat, double protein}) targetMacros,
  DemoFoods foods,
) {
  final carbPool = [foods.oatmeal, foods.brownRice, foods.wholegrainBread];
  final proteinPool = [foods.chickenBreast, foods.greekYogurt, foods.salmon];
  final carbMealA = carbPool[demoRng.nextInt(carbPool.length)];
  final carbMealB = carbPool[demoRng.nextInt(carbPool.length)];
  final proteinMeal = proteinPool[demoRng.nextInt(proteinPool.length)];
  final fruitMeal = demoRng.nextBool() ? foods.banana : foods.apple;

  final veggieAmount = 80.0 + demoRng.nextInt(60); // 80-139g
  final fruitAmount = 100.0 + demoRng.nextInt(60); // 100-159g
  final veggieCarb = _macroGrams(foods.broccoli, veggieAmount, (n) => n.carbohydrates100);
  final veggieFat = _macroGrams(foods.broccoli, veggieAmount, (n) => n.fat100);
  final veggieProtein = _macroGrams(foods.broccoli, veggieAmount, (n) => n.proteins100);
  final fruitCarb = _macroGrams(fruitMeal, fruitAmount, (n) => n.carbohydrates100);
  final fruitFat = _macroGrams(fruitMeal, fruitAmount, (n) => n.fat100);
  final fruitProtein = _macroGrams(fruitMeal, fruitAmount, (n) => n.proteins100);

  // Carb target split ~30-60% breakfast / rest dinner starch.
  final carbShareA = 0.3 + demoRng.nextDouble() * 0.3;
  final remainingCarb = targetMacros.carbs - veggieCarb - fruitCarb;
  final carbAmountA = _roundToNearest5g(
    _gramsFor(carbMealA, remainingCarb * carbShareA, (n) => n.carbohydrates100),
  );
  final carbAmountB = _roundToNearest5g(
    _gramsFor(
      carbMealB,
      remainingCarb * (1 - carbShareA),
      (n) => n.carbohydrates100,
    ),
  );
  final carbFat =
      _macroGrams(carbMealA, carbAmountA, (n) => n.fat100) +
      _macroGrams(carbMealB, carbAmountB, (n) => n.fat100);
  final carbProtein =
      _macroGrams(carbMealA, carbAmountA, (n) => n.proteins100) +
      _macroGrams(carbMealB, carbAmountB, (n) => n.proteins100);

  // Fat target split ~50-75% dinner oil / rest a handful of almonds.
  final oilShare = 0.5 + demoRng.nextDouble() * 0.25;
  final remainingFat = targetMacros.fat - veggieFat - fruitFat - carbFat;
  final oilAmount = _roundToNearest5g(
    _gramsFor(foods.oliveOil, remainingFat * oilShare, (n) => n.fat100),
  );
  final almondAmount = _roundToNearest5g(
    _gramsFor(
      foods.almonds,
      remainingFat * (1 - oilShare),
      (n) => n.fat100,
    ),
  );
  final almondProtein = _macroGrams(foods.almonds, almondAmount, (n) => n.proteins100);

  final remainingProtein = targetMacros.protein -
      veggieProtein -
      fruitProtein -
      carbProtein -
      almondProtein;
  final proteinAmount = _roundToNearest5g(
    _gramsFor(proteinMeal, remainingProtein, (n) => n.proteins100),
  );

  return [
    IntakeEntity(
      id: IdGenerator.getUniqueID(),
      unit: 'g',
      amount: carbAmountA,
      type: IntakeTypeEntity.breakfast,
      meal: carbMealA,
      dateTime: jitteredTime(day, 8),
    ),
    IntakeEntity(
      id: IdGenerator.getUniqueID(),
      unit: 'g',
      amount: proteinAmount,
      type: IntakeTypeEntity.lunch,
      meal: proteinMeal,
      dateTime: jitteredTime(day, 13),
    ),
    IntakeEntity(
      id: IdGenerator.getUniqueID(),
      unit: 'g',
      amount: veggieAmount,
      type: IntakeTypeEntity.dinner,
      meal: foods.broccoli,
      dateTime: jitteredTime(day, 19),
    ),
    IntakeEntity(
      id: IdGenerator.getUniqueID(),
      unit: 'g',
      amount: carbAmountB,
      type: IntakeTypeEntity.dinner,
      meal: carbMealB,
      dateTime: jitteredTime(day, 19),
    ),
    IntakeEntity(
      id: IdGenerator.getUniqueID(),
      unit: 'g',
      amount: oilAmount,
      type: IntakeTypeEntity.dinner,
      meal: foods.oliveOil,
      dateTime: jitteredTime(day, 19),
    ),
    IntakeEntity(
      id: IdGenerator.getUniqueID(),
      unit: 'g',
      amount: fruitAmount,
      type: IntakeTypeEntity.snack,
      meal: fruitMeal,
      dateTime: jitteredTime(day, 16),
    ),
    IntakeEntity(
      id: IdGenerator.getUniqueID(),
      unit: 'g',
      amount: almondAmount,
      type: IntakeTypeEntity.snack,
      meal: foods.almonds,
      dateTime: jitteredTime(day, 16),
    ),
  ].where((intake) => intake.amount > 0).toList();
}

const _runningVigorous = PhysicalActivityEntity(
  '12150',
  'Running, vigorous effort',
  'Running at a fast pace',
  12.0,
  [],
  PhysicalActivityTypeEntity.running,
);
const _bicyclingModerate = PhysicalActivityEntity(
  '01015',
  'Bicycling, moderate speed',
  'Bicycling at a moderate speed on flat terrain',
  8.0,
  [],
  PhysicalActivityTypeEntity.bicycling,
);
const _dancingLight = PhysicalActivityEntity(
  '03015',
  'Dancing, light effort',
  'Dancing with light effort, e.g., slow ballroom dancing',
  4.0,
  [],
  PhysicalActivityTypeEntity.dancing,
);
const demoActivityPool = [_runningVigorous, _bicyclingModerate, _dancingLight];

/// 2-4 glasses of randomised size — a fixed "500 + 500 + 300-600" pattern
/// repeating every few days made the Trends water graph look mechanical;
/// real logging is noisier (and some days people just log less).
List<WaterIntakeEntity> buildDailyWater(DateTime day) {
  final glassCount = 2 + demoRng.nextInt(3);
  final hours = [8, 11, 15, 18, 21];
  return [
    for (var i = 0; i < glassCount; i++)
      WaterIntakeEntity(
        id: IdGenerator.getUniqueID(),
        dateTime: jitteredTime(day, hours[i]),
        amountMl: 200 + demoRng.nextInt(5) * 100, // 200-600 ml
      ),
  ];
}

MealNutrimentsEntity _emptyRecipeNutriments() => MealNutrimentsEntity.empty();

/// A handful of saved recipes spanning breakfast and dinner, high-protein
/// and lighter options — `SaveRecipeUseCase.save` recomputes the
/// aggregated nutriments from the ingredient list, so only the ingredient
/// amounts need to be realistic.
Future<void> seedRecipes(DateTime now, DemoFoods foods) async {
  RecipeIngredientEntity ingredient(MealEntity meal, double amountG) =>
      RecipeIngredientEntity(
        snapshotMeal: meal,
        amount: amountG,
        unit: 'g',
        convertedAmountG: amountG,
      );

  final recipes = [
    RecipeEntity(
      id: IdGenerator.getUniqueID(),
      name: '鸡胸肉糙米饭',
      description: '鸡胸肉搭配糙米饭，适合提前备餐。',
      ingredients: [
        ingredient(foods.chickenBreast, 200),
        ingredient(foods.brownRice, 150),
      ],
      totalWeightG: 350,
      aggregatedNutrimentsPer100: _emptyRecipeNutriments(),
      createdAt: now,
      updatedAt: now,
      servingsCount: 2,
      tags: const ['high-protein'],
    ),
    RecipeEntity(
      id: IdGenerator.getUniqueID(),
      name: '三文鱼蔬菜饭',
      description:
          '三文鱼搭配糙米饭与西兰花，双人晚餐示例。',
      ingredients: [
        ingredient(foods.salmon, 180),
        ingredient(foods.brownRice, 150),
        ingredient(foods.broccoli, 100),
      ],
      totalWeightG: 430,
      aggregatedNutrimentsPer100: _emptyRecipeNutriments(),
      createdAt: now,
      updatedAt: now,
      servingsCount: 2,
      tags: const ['omega-3', 'high-protein'],
    ),
    RecipeEntity(
      id: IdGenerator.getUniqueID(),
      name: '香蕉杏仁燕麦粥',
      description: '燕麦粥搭配香蕉与杏仁。',
      ingredients: [
        ingredient(foods.oatmeal, 200),
        ingredient(foods.banana, 100),
        ingredient(foods.almonds, 20),
      ],
      totalWeightG: 320,
      aggregatedNutrimentsPer100: _emptyRecipeNutriments(),
      createdAt: now,
      updatedAt: now,
      servingsCount: 1,
      tags: const ['breakfast', 'vegetarian'],
    ),
    RecipeEntity(
      id: IdGenerator.getUniqueID(),
      name: '香蕉杏仁酸奶杯',
      description: '希腊酸奶搭配香蕉片与杏仁。',
      ingredients: [
        ingredient(foods.greekYogurt, 200),
        ingredient(foods.banana, 80),
        ingredient(foods.almonds, 15),
      ],
      totalWeightG: 295,
      aggregatedNutrimentsPer100: _emptyRecipeNutriments(),
      createdAt: now,
      updatedAt: now,
      servingsCount: 1,
      tags: const ['breakfast', 'high-protein'],
    ),
  ];

  final saveRecipe = locator<SaveRecipeUseCase>();
  for (final recipe in recipes) {
    await saveRecipe.save(recipe);
  }
}

Future<void> seedCustomActivityTemplate() async {
  await locator<AddCustomActivityTemplateUsecase>().addTemplate(
    const CustomActivityTemplateEntity(
      name: 'Gym session',
      typicalKcal: 400,
      notes: 'Full-body strength training',
    ),
  );
}
