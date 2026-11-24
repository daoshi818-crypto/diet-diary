import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_portion_entity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/data/repository/recipe_repository.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_ingredient_entity.dart';
import 'package:opennutritracker/core/domain/usecase/compute_recipe_nutrition_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/save_recipe_usecase.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/recipes/presentation/bloc/recipe_builder_bloc.dart';
import 'package:opennutritracker/features/recipes/presentation/screens/recipe_builder_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';
import 'package:opennutritracker/features/meal_detail/presentation/food_nutrition_screen.dart';
import 'package:opennutritracker/features/meal_detail/presentation/widgets/meal_detail_nutriments_table.dart';
import 'package:opennutritracker/core/presentation/widgets/food_quantity_dialog.dart';

import '../../../../helpers/test_l10n.dart';

class _FakeRecipeRepository implements RecipeRepository {
  @override
  Future<void> saveRecipe(RecipeEntity recipe) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

RecipeEntity _soup({required double totalWeightG}) {
  return RecipeEntity(
    id: 'soup-1',
    name: 'Soup',
    description: null,
    ingredients: [
      RecipeIngredientEntity(
        snapshotMeal: MealEntity(
          code: 'stock',
          name: 'stock',
          url: null,
          mealQuantity: null,
          mealUnit: 'g',
          servingQuantity: null,
          servingUnit: null,
          servingSize: null,
          nutriments: MealNutrimentsEntity(
            energyKcal100: 90,
            carbohydrates100: null,
            fat100: null,
            proteins100: null,
            sugars100: null,
            saturatedFat100: null,
            fiber100: null,
          ),
          source: MealSourceEntity.off,
        ),
        amount: 800,
        unit: 'g',
        convertedAmountG: 800,
      ),
    ],
    totalWeightG: totalWeightG,
    aggregatedNutrimentsPer100: MealNutrimentsEntity.empty(),
    createdAt: DateTime.utc(2026, 9, 1),
    updatedAt: DateTime.utc(2026, 9, 1),
    servingsCount: null,
  );
}

const _captureUi = bool.fromEnvironment('RECIPE_UI_CAPTURE');
final _captureKey = GlobalKey();

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary =
        _captureKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory(
      const String.fromEnvironment('RECIPE_UI_CAPTURE_DIR'),
    );
    await directory.create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Widget _app(RecipeEntity? existing) {
  return ChangeNotifierProvider<EnergyUnitProvider>(
    create: (_) => EnergyUnitProvider(),
    child: MaterialApp(
      locale: _captureUi ? const Locale('zh') : null,
      theme: _captureUi ? buildAppTheme(AppPalette.light) : null,
      builder: (context, child) =>
          RepaintBoundary(key: _captureKey, child: child!),
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: S.supportedLocales,
      onGenerateRoute: (_) => MaterialPageRoute(
        settings: RouteSettings(
          arguments: RecipeBuilderArguments(existing: existing),
        ),
        builder: (_) => const RecipeBuilderScreen(),
      ),
    ),
  );
}

/// The total-weight field's two states (#1277, PR #1280 review): a weight
/// typed in by hand has to say so, and has to have a way back to the sum.
void main() {
  setUpAll(() async {
    if (_captureUi) {
      for (final (family, path) in [
        ('Nunito', 'C:/Windows/Fonts/msyh.ttc'),
        ('CustomIcons', 'fonts/CustomIcons.ttf'),
        (
          'MaterialIcons',
          'E:/DevCaches/flutter-ont/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
        ),
      ]) {
        await (FontLoader(
          family,
        )..addFont(File(path).readAsBytes().then(ByteData.sublistView))).load();
      }
    }
    final compute = ComputeRecipeNutritionUseCase();
    GetIt.instance.registerFactory<RecipeBuilderBloc>(
      () => RecipeBuilderBloc(
        compute,
        SaveRecipeUseCase(_FakeRecipeRepository(), compute),
      ),
    );
  });

  tearDownAll(() => GetIt.instance.reset());

  Finder reset() => find.bySemanticsIdentifier('recipe-builder-weight-reset');

  /// The weight field sits below the fold of a lazily built list, so on the
  /// default test screen it is never built at all. A tall view builds the
  /// whole form.
  Future<void> pumpBuilder(WidgetTester tester, RecipeEntity existing) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(existing));
    await tester.pumpAndSettle();
  }

  Finder weightField() =>
      find.widgetWithText(TextField, l10nEn.recipeTotalWeightLabel);

  if (_captureUi) {
    testWidgets('capture recipe portions and ingredient nutrition', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final base = _soup(totalWeightG: 150);
      final food = MealEntity(
        code: 'egg',
        name: '鸡蛋',
        url: null,
        mealQuantity: null,
        mealUnit: 'g',
        servingQuantity: null,
        servingUnit: null,
        servingSize: null,
        nutriments: const MealNutrimentsEntity(
          energyKcal100: 144,
          carbohydrates100: 2,
          fat100: 10,
          proteins100: 13,
          sugars100: null,
          saturatedFat100: null,
          fiber100: null,
        ),
        source: MealSourceEntity.custom,
        portions: const [
          MealPortionEntity(label: '中个', gramWeight: 50, localized: true),
        ],
      );
      await tester.pumpWidget(
        _app(
          base.copyWith(
            name: '鸡蛋餐',
            ingredients: [
              RecipeIngredientEntity(
                snapshotMeal: food,
                amount: 3,
                unit: 'serving',
                convertedAmountG: 150,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final detail = find.bySemanticsIdentifier('recipe-ingredient-detail');
      await tester.ensureVisible(detail);
      await _capture(tester, 'recipe-ingredients');
      await tester.tap(find.text('鸡蛋'));
      await tester.pumpAndSettle();
      await _capture(tester, 'recipe-ingredient-nutrition');
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('recipe-ingredient-edit-amount'),
      );
      await tester.pumpAndSettle();
      expect(find.text('= 150 g'), findsOneWidget);
      await _capture(tester, 'recipe-portion-picker');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'ingredient title opens its nutrition and edit uses the shared amount picker',
    (tester) async {
      await pumpBuilder(tester, _soup(totalWeightG: 800));
      final ingredient = find.bySemanticsIdentifier('recipe-ingredient-detail');
      await tester.ensureVisible(ingredient);
      await tester.tap(find.text('stock'));
      await tester.pumpAndSettle();
      expect(find.byType(FoodNutritionScreen), findsOneWidget);
      final table = tester.widget<MealDetailNutrimentsTable>(
        find.byType(MealDetailNutrimentsTable).first,
      );
      expect(table.referenceAmount, 800);
      expect(find.text('720 kcal'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      final edit = find.bySemanticsIdentifier('recipe-ingredient-edit-amount');
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(find.byType(FoodQuantityDialog), findsOneWidget);
      expect(find.text('Weight'), findsWidgets);
      expect(find.text('Volume'), findsOneWidget);
      expect(find.text('Portion'), findsOneWidget);
      expect(find.bySemanticsIdentifier('food-detail-meal-type'), findsNothing);
      await tester.enterText(find.byType(TextFormField), '700');
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('food-quantity-close'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(weightField()).controller!.text, '800');
    },
      );

  testWidgets('a typed weight says so, and Use ingredient total undoes it', (
    tester,
  ) async {
    await pumpBuilder(tester, _soup(totalWeightG: 720));

    expect(find.text(l10nEn.recipeTotalWeightManualHelper), findsOneWidget);
    expect(
      tester.widget<TextField>(weightField()).controller!.text,
      '720',
    );

    await tester.ensureVisible(reset());
    await tester.tap(reset());
    await tester.pumpAndSettle();

    expect(
      find.text(l10nEn.recipeTotalWeightCalculatedHelper),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(weightField()).controller!.text,
      '800',
    );
    expect(reset(), findsNothing, reason: 'nothing left to undo');
  });

  testWidgets('a calculated weight says so, with nothing to undo', (
    tester,
  ) async {
    await pumpBuilder(tester, _soup(totalWeightG: 800));

    expect(
      find.text(l10nEn.recipeTotalWeightCalculatedHelper),
      findsOneWidget,
    );
    expect(reset(), findsNothing);
  });

  testWidgets('typing a weight switches the field to entered manually', (
    tester,
  ) async {
    await pumpBuilder(tester, _soup(totalWeightG: 800));

    await tester.ensureVisible(weightField());
    await tester.enterText(weightField(), '650');
    await tester.pumpAndSettle();

    expect(find.text(l10nEn.recipeTotalWeightManualHelper), findsOneWidget);
    expect(reset(), findsOneWidget);
  });

  /// Pushed over a blank page, as the recipe detail screen opens it, so
  /// that Back has somewhere to go.
  Future<void> pumpPushedBuilder(
    WidgetTester tester,
    RecipeEntity existing,
  ) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ChangeNotifierProvider<EnergyUnitProvider>(
        create: (_) => EnergyUnitProvider(),
        child: MaterialApp(
          navigatorKey: navigator,
          localizationsDelegates: const [S.delegate],
          supportedLocales: S.supportedLocales,
          home: const Scaffold(),
        ),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        settings: RouteSettings(
          arguments: RecipeBuilderArguments(existing: existing),
        ),
        builder: (_) => const RecipeBuilderScreen(),
      ),
    );
    await tester.pumpAndSettle();
  }

  // #1443: an opened recipe is never empty, so Back asked to discard
  // changes even when nothing had been touched.
  for (final totalWeightG in [800.0, 720.0]) {
    testWidgets(
        'Back leaves an unedited recipe without asking '
        '(total ${totalWeightG.toStringAsFixed(0)} g)', (tester) async {
      await pumpPushedBuilder(tester, _soup(totalWeightG: totalWeightG));
      expect(find.byType(RecipeBuilderScreen), findsOneWidget);

      // What Android's back gesture delivers.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text(l10nEn.discardChangesTitle), findsNothing);
      expect(find.byType(RecipeBuilderScreen), findsNothing);
    });
  }

  testWidgets('Back still asks once the recipe was edited', (tester) async {
    await pumpPushedBuilder(tester, _soup(totalWeightG: 800));

    await tester.enterText(
      find.widgetWithText(TextField, l10nEn.recipeNameLabel),
      'Soup with leeks',
    );
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text(l10nEn.discardChangesTitle), findsOneWidget);
    expect(find.byType(RecipeBuilderScreen), findsOneWidget);
  });

  // Back compares what Save would write, not the whole state: a failed save
  // leaves `saveError` behind, and the content is back to what was loaded.
  testWidgets('Back leaves without asking once a failed save is undone',
      (tester) async {
    await pumpPushedBuilder(tester, _soup(totalWeightG: 800));
    final name = find.widgetWithText(TextField, l10nEn.recipeNameLabel);

    await tester.enterText(name, '');
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10nEn.recipeSaveLabel));
    await tester.pumpAndSettle();
    expect(find.text(l10nEn.recipeNameRequiredLabel), findsOneWidget);

    await tester.enterText(name, 'Soup');
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text(l10nEn.discardChangesTitle), findsNothing);
    expect(find.byType(RecipeBuilderScreen), findsNothing);
  });

  // Save writes a blank description as null, so a description typed into
  // and cleared again is no change.
  testWidgets('Back leaves without asking once a typed description is cleared',
      (tester) async {
    await pumpPushedBuilder(tester, _soup(totalWeightG: 800));
    final description =
        find.widgetWithText(TextField, l10nEn.recipeDescriptionLabel);

    await tester.enterText(description, 'Hearty');
    await tester.pumpAndSettle();
    await tester.enterText(description, '');
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text(l10nEn.discardChangesTitle), findsNothing);
    expect(find.byType(RecipeBuilderScreen), findsNothing);
  });
}
