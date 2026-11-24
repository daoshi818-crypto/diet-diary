import 'dart:math' as math;
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/rendering.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/features/add_meal/data/data_sources/chinese_food_data_source.dart';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/data/data_source/remote_search_cache_data_source.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_macro_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/favourite_toggle_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/meal_detail/meal_detail_screen.dart';
import 'package:opennutritracker/features/meal_detail/presentation/widgets/meal_detail_nutriments_table.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../../helpers/fake_favourites.dart';

// #1126: when the user has opted into raw units in Settings, the meal-detail
// dropdown must skip the serving default even for a food with a scalable
// serving. Off keeps the pre-existing behaviour — serving still wins.

const _nutriments = MealNutrimentsEntity(
  energyKcal100: 100,
  carbohydrates100: 10,
  fat100: 5,
  proteins100: 5,
  sugars100: 2,
  saturatedFat100: 1,
  fiber100: 1,
);

MealEntity _solidWithServing() => MealEntity(
  code: 'raw-units-test-solid',
  name: 'Solid product',
  url: null,
  mealQuantity: '100',
  mealUnit: 'g',
  servingQuantity: 30,
  servingUnit: 'g',
  servingSize: '30 g',
  nutriments: _nutriments,
  source: MealSourceEntity.custom,
);

MealEntity _liquidWithServing() => MealEntity(
  code: 'raw-units-test-liquid',
  name: 'Liquid product',
  url: null,
  mealQuantity: '100',
  mealUnit: 'ml',
  servingQuantity: 250,
  servingUnit: 'ml',
  servingSize: '250 ml',
  nutriments: _nutriments,
  source: MealSourceEntity.custom,
);

// Thin OFF search result: `source: off, detailed: false`, no serving fields.
// Opening this triggers `HydrateMealEvent`, which the bloc resolves through
// the products repository into the corresponding [_liquidHydratedOff] below.
MealEntity _liquidThinOff() => MealEntity(
  code: 'thin-off-liquid',
  name: 'Thin OFF liquid',
  url: null,
  mealQuantity: '100',
  mealUnit: 'ml',
  servingQuantity: null,
  servingUnit: null,
  servingSize: null,
  nutriments: _nutriments,
  source: MealSourceEntity.off,
);

MealEntity _liquidHydratedOff() => MealEntity(
  code: 'thin-off-liquid',
  name: 'Thin OFF liquid',
  url: null,
  mealQuantity: '100',
  mealUnit: 'ml',
  servingQuantity: 250,
  servingUnit: 'ml',
  servingSize: '250 ml',
  nutriments: _nutriments,
  source: MealSourceEntity.off,
  detailed: true,
);

double _maxScrollOffset(WidgetTester tester) {
  final states = tester.stateList<ScrollableState>(find.byType(Scrollable));
  return states.fold<double>(0, (m, s) => math.max(m, s.position.pixels));
}

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('FOOD_UI_CAPTURE')) return;
    for (final family in ['FoodUiCapture', 'Nunito']) {
      final font = FontLoader(family)
        ..addFont(
          File(
            Platform.environment['FOOD_PREVIEW_FONT'] ??
                'C:/Windows/Fonts/msyh.ttc',
          ).readAsBytes().then(ByteData.sublistView),
        );
      await font.load();
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        File(
          Platform.environment['FOOD_PREVIEW_ICON_FONT']!,
        ).readAsBytes().then(ByteData.sublistView),
      );
    await icons.load();
  });
  final getIt = GetIt.instance;
  MealDetailBloc? bloc;
  late bool defaultToRawFoodUnits;
  MealEntity? hydratedFor;

  setUp(() {
    bloc = null;
    defaultToRawFoodUnits = false;
    hydratedFor = null;
    getIt.registerLazySingleton<MealDetailBloc>(
      () => bloc = MealDetailBloc(
        _FakeAddIntakeUsecase(),
        _FakeAddTrackedDayUsecase(),
        _FakeGetKcalGoalUsecase(),
        _FakeGetMacroGoalUsecase(),
        _FakeGetTrackedDayUsecase(),
        _FakeProductsRepository(() => hydratedFor),
        _FakeRemoteSearchCacheDataSource(),
      ),
    );
    getIt.registerLazySingleton<GetConfigUsecase>(
      () => _FakeGetConfigUsecase(() => defaultToRawFoodUnits),
    );
    getIt.registerLazySingleton<GetIntakeUsecase>(_FakeGetIntakeUsecase.new);
    getIt.registerLazySingleton<CacheManager>(_FakeCacheManager.new);
    // #1307: the detail page's star.
    final favourites = FakeFavourites();
    getIt.registerFactory<FavouriteToggleBloc>(
      () => FavouriteToggleBloc(favourites.get, favourites.toggle),
    );
    getIt.registerLazySingleton<HomeBloc>(_FakeHomeBloc.new);
    getIt.registerLazySingleton<DiaryBloc>(_FakeDiaryBloc.new);
    getIt.registerLazySingleton<CalendarDayBloc>(_FakeCalendarDayBloc.new);
  });

  tearDown(() async {
    await getIt.reset();
  });

  Future<void> pumpMealDetail(
    WidgetTester tester,
    MealEntity meal, {
    Size size = const Size(600, 800),
    double scale = 1,
    bool dark = false,
    double keyboard = 0,
  }) async {
    // 600x800 leaves the CustomScrollView with a real maxScrollExtent, so
    // the scroll-offset assertion below can actually fail if the race guard
    // regresses. A taller viewport clamps `animateTo` to 0 and the test
    // passes vacuously.
    tester.view.physicalSize = size;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final navigatorKey = GlobalKey<NavigatorState>();
    Route<void> routeFor(RouteSettings settings) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const MealDetailScreen(),
      );
    }

    await tester.pumpWidget(
      ChangeNotifierProvider<EnergyUnitProvider>(
        create: (_) => EnergyUnitProvider(),
        child: MaterialApp(
          navigatorKey: navigatorKey,
          theme: buildAppTheme(dark ? AppPalette.dark : AppPalette.light)
              .copyWith(
                textTheme: const bool.fromEnvironment('FOOD_UI_CAPTURE')
                    ? buildAppTheme(
                        dark ? AppPalette.dark : AppPalette.light,
                      ).textTheme.apply(fontFamily: 'FoodUiCapture')
                    : null,
              ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: RepaintBoundary(
              key: const ValueKey('detail-capture'),
              child: child!,
            ),
          ),
          locale: const Locale('zh'),
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: S.supportedLocales,
          initialRoute: NavigationOptions.mealDetailRoute,
          onGenerateInitialRoutes: (_) => [
            routeFor(
              RouteSettings(
                name: NavigationOptions.mealDetailRoute,
                arguments: MealDetailScreenArguments(
                  meal,
                  IntakeTypeEntity.breakfast,
                  DateTime(2026, 9, 14),
                  false,
                ),
              ),
            ),
          ],
          onGenerateRoute: routeFor,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'quantity keeps focus and its input connection when the keyboard resizes detail',
    (tester) async {
      await pumpMealDetail(
        tester,
        _solidWithServing(),
        size: const Size(375, 667),
      );
      final field = find.byType(TextFormField).first;
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      final editable = find.descendant(
        of: field,
        matching: find.byType(EditableText),
      );
      final input = tester.state<EditableTextState>(editable);
      expect(input.widget.focusNode.hasFocus, isTrue);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(
        identical(tester.state<EditableTextState>(editable), input),
        isTrue,
      );
      expect(input.widget.focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      tester.testTextInput.enterText('175');
      await tester.pumpAndSettle();
      expect(bloc!.state.totalQuantityConverted, '175.0');
      expect(tester.getBottomLeft(field).dy, lessThanOrEqualTo(667 - 300));
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      expect(
        identical(tester.state<EditableTextState>(editable), input),
        isTrue,
      );
      expect(input.widget.controller.text, '175');
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(320, 640),
    const Size(375, 667),
    const Size(812, 375),
    const Size(768, 1024),
  ]) {
    for (final scale in [1.0, 2.0]) {
      for (final dark in [false, true]) {
        testWidgets(
          'local library grams and accessible detail: $size scale=$scale dark=$dark',
          (tester) async {
            defaultToRawFoodUnits = false;
            final source = ChineseFoodDataSource(
              read: () => File('assets/foods/catalog.json').readAsString(),
            );
            final meal = (await tester.runAsync(
              () => source.search('蒸米饭'),
            ))!.first;
            await pumpMealDetail(
              tester,
              meal,
              size: size,
              scale: scale,
              dark: dark,
            );
            expect(bloc!.state.selectedUnit, 'g');
            expect(bloc!.state.totalQuantityConverted, '100.0');
            expect(
              tester.widget<Scaffold>(find.byType(Scaffold)).bottomSheet,
              isNull,
            );
            final field = find.byType(TextFormField).first;
            await tester.ensureVisible(field);
            await tester.enterText(field, '50');
            await tester.pumpAndSettle();
            expect(bloc!.state.totalQuantityConverted, '50.0');
            expect(
              bloc!.state.totalKcal,
              closeTo(meal.nutriments.energyKcal100! / 2, .001),
            );
            final table = find.byType(MealDetailNutrimentsTable);
            await tester.scrollUntilVisible(
              table,
              180,
              scrollable: find
                  .descendant(
                    of: find.byKey(const ValueKey('meal-detail-content')),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            await tester.pumpAndSettle();
            final add = find.byWidgetPredicate(
              (w) =>
                  w is Semantics &&
                  w.properties.identifier == 'meal-detail-add',
            );
            if (add.evaluate().isEmpty) {
              await tester.scrollUntilVisible(
                add,
                180,
                maxScrolls: 80,
                scrollable: find
                    .descendant(
                      of: find.byKey(const ValueKey('meal-detail-content')),
                      matching: find.byType(Scrollable),
                    )
                    .first,
              );
            } else {
              await tester.ensureVisible(add);
            }
            await tester.pumpAndSettle();
            expect(add.hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
            if (const bool.fromEnvironment('FOOD_UI_CAPTURE') &&
                scale == 1 &&
                size.width == 375) {
              await tester.drag(
                find.byKey(const ValueKey('meal-detail-content')),
                const Offset(0, 2000),
              );
              await tester.pumpAndSettle();
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey('detail-capture')),
              );
              await tester.runAsync(() async {
                final picture = await boundary.toImage(pixelRatio: 2);
                final bytes = await picture.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                const folder = String.fromEnvironment(
                  'FOOD_UI_CAPTURE_DIR',
                  defaultValue: 'build/food-ui-checks',
                );
                await Directory(folder).create(recursive: true);
                await File(
                  '$folder/detail-${dark ? 'dark' : 'light'}.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
                picture.dispose();
              });
            }
          },
        );
      }
    }
  }

  for (final size in [
    const Size(320, 640),
    const Size(375, 667),
    const Size(812, 375),
    const Size(768, 1024),
  ]) {
    for (final scale in [1.0, 2.0]) {
      for (final dark in [false, true]) {
        testWidgets(
          'household picker converts servings: $size scale=$scale dark=$dark',
          (tester) async {
            final source = ChineseFoodDataSource(
              read: () => File('assets/foods/catalog.json').readAsString(),
            );
            final meal = (await tester.runAsync(
              () => source.bySourceId('calshot', '538'),
            ))!;
            await pumpMealDetail(
              tester,
              meal,
              size: size,
              scale: scale,
              dark: dark,
            );
            final mode = find.text('分量');
            final scrollable = find
                .descendant(
                  of: find.byKey(const ValueKey('meal-detail-content')),
                  matching: find.byType(Scrollable),
                )
                .first;
            await tester.scrollUntilVisible(mode, 160, scrollable: scrollable);
            await tester.ensureVisible(mode);
            await tester.tap(mode);
            await tester.pumpAndSettle();
            final menu = find.byType(DropdownButtonFormField<String>);
            await tester.scrollUntilVisible(menu, 90, scrollable: scrollable);
            await tester.ensureVisible(menu);
            await tester.tap(menu);
            await tester.pumpAndSettle();
            final portion = find.textContaining('一份外卖米饭').last;
            await tester.ensureVisible(portion);
            await tester.tap(portion);
            await tester.pumpAndSettle();
            expect(bloc!.state.selectedUnit, startsWith('serving'));
            expect(bloc!.state.totalQuantityConverted, '250.0');
            expect(bloc!.state.totalKcal, closeTo(325, .001));
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets(
    'keyboard leaves quantity and confirmation reachable at large text',
    (tester) async {
      final source = ChineseFoodDataSource(
        read: () => File('assets/foods/catalog.json').readAsString(),
      );
      final meal = (await tester.runAsync(() => source.search('鸡蛋')))!.first;
      await pumpMealDetail(
        tester,
        meal,
        size: const Size(320, 640),
        scale: 2,
        keyboard: 300,
      );
      final field = find.byType(TextFormField).first;
      await tester.ensureVisible(field);
      await tester.enterText(field, '50');
      await tester.pumpAndSettle();
      expect(bloc!.state.totalQuantityConverted, '50.0');
      final add = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.identifier == 'meal-detail-add',
      );
      if (add.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          add,
          180,
          maxScrolls: 80,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('meal-detail-content')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
      } else {
        await tester.ensureVisible(add);
      }
      await tester.pumpAndSettle();
      expect(add.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ordinary food stays in grams even with the old serving preference',
    (tester) async {
      defaultToRawFoodUnits = false;
      await pumpMealDetail(tester, _solidWithServing());

      expect(bloc!.state.selectedUnit, 'g');
      expect(bloc!.state.totalQuantityConverted, '100.0');
      // The initial-selection writes to `quantityTextController` used to
      // scroll the calorie field into view, collapsing the app bar the
      // moment the screen opened. Guard should keep the view at the top.
      expect(_maxScrollOffset(tester), 0.0);
    },
  );

  testWidgets('on: solid with a scalable serving lands on grams with 100 g', (
    tester,
  ) async {
    defaultToRawFoodUnits = true;
    await pumpMealDetail(tester, _solidWithServing());
    expect(bloc!.state.selectedUnit, 'g');
    expect(bloc!.state.totalQuantityConverted, '100.0');
    expect(_maxScrollOffset(tester), 0.0);
  });

  testWidgets('on: liquid with a scalable serving lands on ml with 100 ml', (
    tester,
  ) async {
    defaultToRawFoodUnits = true;
    await pumpMealDetail(tester, _liquidWithServing());

    expect(bloc!.state.selectedUnit, 'ml');
    expect(bloc!.state.totalQuantityConverted, '100.0');
    expect(_maxScrollOffset(tester), 0.0);
  });

  testWidgets(
    'off: thin OFF liquid hydrates to a serving-carrying full product '
    'and still lands on volume',
    (tester) async {
      defaultToRawFoodUnits = false;
      hydratedFor = _liquidHydratedOff();
      await pumpMealDetail(tester, _liquidThinOff());

      expect(bloc!.state.selectedUnit, 'ml');
      expect(bloc!.state.totalQuantityConverted, '100.0');
      expect(_maxScrollOffset(tester), 0.0);
    },
  );

  testWidgets('on: thin OFF liquid hydrates but the raw-units preference still '
      'wins, landing on ml/100', (tester) async {
    defaultToRawFoodUnits = true;
    hydratedFor = _liquidHydratedOff();
    await pumpMealDetail(tester, _liquidThinOff());

    expect(bloc!.state.selectedUnit, 'ml');
    expect(bloc!.state.totalQuantityConverted, '100.0');
    expect(_maxScrollOffset(tester), 0.0);
  });
}

class _FakeGetConfigUsecase implements GetConfigUsecase {
  final bool Function() defaultToRawFoodUnitsProvider;

  _FakeGetConfigUsecase(this.defaultToRawFoodUnitsProvider);

  @override
  Future<ConfigEntity> getConfig() async {
    return ConfigEntity(
      true,
      true,
      false,
      AppThemeEntity.system,
      defaultToRawFoodUnits: defaultToRawFoodUnitsProvider(),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _FakeAddIntakeUsecase implements AddIntakeUsecase {
  @override
  Future<void> addIntake(IntakeEntity intakeEntity) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _FakeAddTrackedDayUsecase implements AddTrackedDayUsecase {
  @override
  Future<bool> hasTrackedDay(DateTime day) async => true;

  @override
  Future<void> addDayCaloriesTracked(DateTime day, double kcal) async {}

  @override
  Future<void> addDayMacrosTracked(
    DateTime day, {
    double? carbsTracked,
    double? fatTracked,
    double? proteinTracked,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _FakeGetKcalGoalUsecase implements GetKcalGoalUsecase {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _FakeGetMacroGoalUsecase implements GetMacroGoalUsecase {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _FakeGetTrackedDayUsecase implements GetTrackedDayUsecase {
  @override
  Future<TrackedDayEntity?> getTrackedDay(DateTime day) async =>
      TrackedDayEntity(
        day: day,
        calorieGoal: 2200,
        caloriesTracked: 800,
        carbsGoal: 250,
        carbsTracked: 100,
        fatGoal: 70,
        fatTracked: 30,
        proteinGoal: 120,
        proteinTracked: 50,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _FakeProductsRepository implements ProductsRepository {
  @override
  bool get usesLocalFoods => false;

  final MealEntity? Function() hydratedProvider;

  _FakeProductsRepository(this.hydratedProvider);

  @override
  Future<MealEntity> getOFFProductByBarcode(
    String barcode, {
    String? knownName,
  }) async {
    final hydrated = hydratedProvider();
    if (hydrated == null) {
      throw StateError('No hydrated product configured for barcode $barcode');
    }
    return hydrated;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _FakeRemoteSearchCacheDataSource implements RemoteSearchCacheDataSource {
  @override
  Future<void> touch(String barcode) async {}

  @override
  MealDBO? getDetailedByBarcode(String barcode) => null;

  @override
  Future<void> cache(MealDBO meal) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _FakeGetIntakeUsecase implements GetIntakeUsecase {
  @override
  Future<List<IntakeEntity>> getBreakfastIntakeByDay(
    DateTime day, {
    int dayStartOffsetHours = 0,
    int dayStartOffsetMinutes = 0,
  }) async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _FakeHomeBloc implements HomeBloc {
  @override
  void add(HomeEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _FakeDiaryBloc implements DiaryBloc {
  @override
  void add(DiaryEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _FakeCalendarDayBloc implements CalendarDayBloc {
  @override
  void add(CalendarDayEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _FakeCacheManager implements CacheManager {
  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) => const Stream<FileResponse>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}
