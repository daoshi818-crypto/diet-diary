import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';

import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/widgets/food_quantity_dialog.dart';
import 'package:opennutritracker/core/data/data_source/remote_search_cache_data_source.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/data/data_sources/chinese_food_data_source.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_portion_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/search_products_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_screen.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/meal_search_bar.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/meal_item_card.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/add_meal_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/favourite_meal_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/favourite_toggle_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/food_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/products_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/recent_meal_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/log_tray.dart';
import 'package:opennutritracker/features/add_meal/presentation/screens/bulk_add_screen.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/log_tray_widgets.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/meal_detail/meal_detail_screen.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/features/meal_detail/util/food_entry_preferences.dart';
import 'package:opennutritracker/features/scanner/scanner_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../../helpers/fake_favourites.dart';
import '../../../helpers/test_l10n.dart';

MealEntity _meal(
  String name, {
  double kcal100 = 200,
  String? mealUnit = 'g',
  double? servingQuantity,
  String? servingSize,
  bool complete = true,
  MealSourceEntity source = MealSourceEntity.custom,
  bool detailed = false,
  List<MealPortionEntity> portions = const [],
}) => MealEntity(
  code: name,
  name: name,
  url: null,
  mealQuantity: null,
  mealUnit: mealUnit,
  servingQuantity: servingQuantity,
  servingUnit: 'g',
  servingSize: servingSize,
  nutriments: MealNutrimentsEntity(
    energyKcal100: kcal100,
    carbohydrates100: complete ? 10 : null,
    fat100: complete ? 5 : null,
    proteins100: complete ? 3 : null,
    sugars100: null,
    saturatedFat100: null,
    fiber100: null,
  ),
  source: source,
  detailed: detailed,
  portions: portions,
);

IntakeEntity _intake(MealEntity meal) => IntakeEntity(
  id: meal.name!,
  unit: 'g',
  amount: 100,
  type: IntakeTypeEntity.breakfast,
  meal: meal,
  dateTime: DateTime(2026, 10, 1),
);

class _FakeGetIntakeUsecase implements GetIntakeUsecase {
  final List<IntakeEntity> recent;

  _FakeGetIntakeUsecase(this.recent);

  @override
  Future<List<IntakeEntity>> getRecentIntake() async => recent;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _FakeGetConfigUsecase implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async =>
      const ConfigEntity(true, true, false, AppThemeEntity.system);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _FakeSearch implements SearchProductsUseCase {
  @override
  Future<SearchProductsResult> searchOFFProductsByString(
    String searchString, {
    bool skipRemote = false,
  }) async => const SearchProductsResult(meals: [], remoteSourceEmpty: true);

  @override
  Future<SearchProductsResult> searchFDCFoodByString(
    String searchString, {
    bool skipRemote = false,
    bool forResolution = false,
  }) async => const SearchProductsResult(meals: [], remoteSourceEmpty: true);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _FakeCache extends Fake implements RemoteSearchCacheDataSource {
  @override
  MealDBO? getDetailedByBarcode(String barcode) => null;

  @override
  Future<void> cache(MealDBO meal) async {}
}

/// Answers a barcode lookup with [full], or fails when it is null.
class _FakeProducts extends Fake implements ProductsRepository {
  @override
  bool get usesLocalFoods => false;

  MealEntity? full;
  var lookups = 0;

  /// When set, every lookup waits on it.
  Completer<void>? gate;

  @override
  Future<MealEntity> getOFFProductByBarcode(
    String barcode, {
    String? knownName,
  }) async {
    lookups++;
    await gate?.future;
    final meal = full;
    if (meal == null) throw StateError('offline');
    return meal;
  }
}

class _FakeMealDetailBloc extends Fake implements MealDetailBloc {
  final writes =
      <({String unit, String amount, String? name, IntakeTypeEntity type})>[];
  int? failAt;

  /// When set, every write waits on it.
  Completer<void>? gate;

  @override
  Future<void> close() async {}

  @override
  Future<void> addLocalIntake(
    String unit,
    double quantity,
    IntakeTypeEntity type,
    MealEntity meal,
    DateTime day,
  ) async {
    writes.add((
      unit: unit,
      amount: quantity.toString(),
      name: meal.name,
      type: type,
    ));
  }

  @override
  Future<void> addIntake(
    BuildContext context,
    String unit,
    String amountText,
    IntakeTypeEntity intakeTypeEntity,
    MealEntity meal,
    DateTime day,
  ) async {
    if (failAt == writes.length) throw StateError('write failed');
    await gate?.future;
    writes.add((
      unit: unit,
      amount: amountText,
      name: meal.name,
      type: intakeTypeEntity,
    ));
  }
}

class _FakeHomeBloc extends Fake implements HomeBloc {
  var refreshed = false;

  @override
  void add(HomeEvent event) => refreshed = true;
}

class _FakeDiaryBloc extends Fake implements DiaryBloc {
  @override
  void add(DiaryEvent event) {}
}

class _FakeCalendarDayBloc extends Fake implements CalendarDayBloc {
  @override
  void add(CalendarDayEvent event) {}
}

/// Quick add's direct write: records the intakes it stores.
class _RecordingAddIntakeUsecase extends Fake implements AddIntakeUsecase {
  final stored = <IntakeEntity>[];

  @override
  Future<void> addIntake(IntakeEntity intakeEntity) async =>
      stored.add(intakeEntity);
}

/// A day that already has its row, so Quick add only adds to its totals.
class _ExistingDayAddTrackedDayUsecase extends Fake
    implements AddTrackedDayUsecase {
  @override
  Future<bool> hasTrackedDay(DateTime day) async => true;

  @override
  Future<void> addDayCaloriesTracked(
    DateTime day,
    double caloriesTracked,
  ) async {}

  @override
  Future<void> addDayMacrosTracked(
    DateTime day, {
    double? carbsTracked,
    double? fatTracked,
    double? proteinTracked,
  }) async {}
}

final getIt = GetIt.instance;
FakeFavourites? _favourites;
late _FakeMealDetailBloc _mealDetailBloc;
late _FakeHomeBloc _homeBloc;
late _FakeProducts _products;
late _FakeCustomFoods _customFoods;

class _FoodEntryDB extends Fake implements HiveDBProvider {
  @override
  final Box<String> foodEntryBox = _FoodEntryBox();

  @override
  String get activeProfileId => 'test';
}

class _FoodEntryBox extends Fake implements Box<String> {
  final _values = <dynamic, String>{};

  @override
  String? get(dynamic key, {String? defaultValue}) =>
      _values[key] ?? defaultValue;

  @override
  Future<void> put(dynamic key, String value) async => _values[key] = value;
}

class _FakeCustomFoods extends Fake implements CustomMealDataSource {
  final entries = <MealDBO>[];
  final changes = StreamController<void>.broadcast();

  @override
  List<MealDBO> getAllCustomMeals() => List.of(entries);

  @override
  Stream<void> watch() => changes.stream;
}

Future<void> _register(List<MealEntity> recent) async {
  await getIt.reset();
  _customFoods = _FakeCustomFoods();
  addTearDown(_customFoods.changes.close);
  getIt.registerSingleton<CustomMealDataSource>(_customFoods);
  final config = _FakeGetConfigUsecase();
  final search = _FakeSearch();
  _mealDetailBloc = _FakeMealDetailBloc();
  _homeBloc = _FakeHomeBloc();
  getIt.registerFactory<AddMealBloc>(() => AddMealBloc(config));
  getIt.registerFactory<ProductsBloc>(() => ProductsBloc(search, config));
  getIt.registerFactory<FoodBloc>(() => FoodBloc(search, config));
  getIt.registerFactory<RecentMealBloc>(
    () => RecentMealBloc(
      _FakeGetIntakeUsecase(recent.map(_intake).toList()),
      config,
    ),
  );
  await _favourites?.dispose();
  final favourites = _favourites = FakeFavourites();
  getIt.registerFactory<FavouriteMealBloc>(
    () => FavouriteMealBloc(favourites.get, config),
  );
  getIt.registerFactory<FavouriteToggleBloc>(
    () => FavouriteToggleBloc(favourites.get, favourites.toggle),
  );
  getIt.registerFactory<MealDetailBloc>(() => _mealDetailBloc);
  getIt.registerFactory<HomeBloc>(() => _homeBloc);
  getIt.registerFactory<DiaryBloc>(() => _FakeDiaryBloc());
  getIt.registerFactory<CalendarDayBloc>(() => _FakeCalendarDayBloc());
  _products = _FakeProducts();
  getIt.registerSingleton<RemoteSearchCacheDataSource>(_FakeCache());
  getIt.registerSingleton<ProductsRepository>(_products);
}

/// Main at the bottom, the add-food screen pushed over it, and a recording
/// stub for every other route.
const _captureUi = bool.fromEnvironment('GENERATE_BATCH_PREVIEW');
final _batchPreviewBoundary = GlobalKey();

Widget _app(List<RouteSettings> pushed, {bool library = false}) =>
    ChangeNotifierProvider(
      create: (_) => EnergyUnitProvider(usesKilojoules: false),
      child: MaterialApp(
        locale: _captureUi ? const Locale('zh') : const Locale('en'),
        theme: _captureUi ? buildAppTheme(AppPalette.light) : null,
        builder: (context, child) =>
            RepaintBoundary(key: _batchPreviewBoundary, child: child!),
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.supportedLocales,
        initialRoute: NavigationOptions.mainRoute,
        onGenerateRoute: (settings) {
          if (settings.name == NavigationOptions.mainRoute) {
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) =>
                  const Scaffold(key: Key('main'), body: SizedBox()),
            );
          }
          if (settings.name == NavigationOptions.addMealRoute) {
            return MaterialPageRoute<void>(
              settings: RouteSettings(
                name: settings.name,
                arguments: AddMealScreenArguments(
                  AddMealType.breakfastType,
                  DateTime(2026, 10, 18),
                  isFoodLibrary: library,
                ),
              ),
              builder: (_) => const AddMealScreen(),
            );
          }
          pushed.add(settings);
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const Scaffold(body: SizedBox()),
          );
        },
      ),
    );

Future<void> _openAddMeal(
  WidgetTester tester,
  List<RouteSettings> pushed, {
  bool library = false,
}) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(pushed, library: library));
  await tester.pumpAndSettle();
  tester
      .state<NavigatorState>(find.byType(Navigator))
      .pushNamed(NavigationOptions.addMealRoute);
  if (getIt.isRegistered<ChineseFoodDataSource>()) {
    await tester.runAsync(() async {
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
  }
  await tester.pumpAndSettle();
}

Finder _plusOn(String name) => find.descendant(
  of: find.ancestor(of: _card(name), matching: find.byType(Row)).first,
  matching: find.bySemanticsIdentifier('meal-item-add'),
);

Finder _card(String name) =>
    find.textContaining(name, findRichText: true).first;

Finder _detailsOn(String name) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is MealItemCard && widget.mealEntity.name == name,
  ),
  matching: find.bySemanticsIdentifier('meal-item-detail'),
);

/// Scrolls the result into view first: once the list has items, the log
/// button takes the bottom of the screen and the results scroll above it.
Future<void> _tapPlus(
  WidgetTester tester,
  String name, {
  bool confirm = true,
}) async {
  await tester.ensureVisible(_plusOn(name));
  await tester.pumpAndSettle();
  await tester.tap(_plusOn(name));
  await tester.pumpAndSettle();
  if (confirm) await _confirmAmount(tester);
}

Future<void> _confirmAmount(WidgetTester tester) async {
  if (find.byType(FoodQuantityDialog).evaluate().isNotEmpty) {
    final confirm = find.widgetWithText(
      FilledButton,
      l10nEn.loggingConfirmAmount,
    );
    final button = tester.widget<FilledButton>(confirm);
    if (button.onPressed != null) {
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
    }
  }
}

Finder _logButton() => find.bySemanticsIdentifier('add-meal-tray-log');

Future<void> _openAiMethod(WidgetTester tester, String identifier) async {
  await tester.tap(find.bySemanticsIdentifier('add-meal-method-ai'));
  await tester.pumpAndSettle();
  await tester.tap(find.bySemanticsIdentifier(identifier));
  await tester.pumpAndSettle();
}

Future<void> _captureBatchUi(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary =
        _batchPreviewBoundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory(
      const String.fromEnvironment('BATCH_PREVIEW_DIR'),
    );
    await directory.create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    if (!_captureUi) return;
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
  });
  testWidgets(
    'fixed category rail survives search resize and cloud category updates',
    (tester) async {
      Map<String, dynamic> snapshot(String label) => {
        'schema_version': 1,
        'categories': [
          {'id': 'cloud-group', 'label': label},
        ],
        'foods': [
          {
            'id': 'cn-test-egg',
            'name': '鸡蛋',
            'brand': '',
            'unit': 'g',
            'category': '',
            'category_id': 'cloud-group',
            'aliases': [],
            'nutrients': {'energy_kcal': 144},
            'portions': [
              {'label': '中等个', 'grams': 50},
            ],
            'sources': [
              {'source': 'cn_fct', 'id': 'test-egg'},
            ],
          },
        ],
      };
      final catalog = ChineseFoodDataSource(
        read: () async => jsonEncode(snapshot('肉蛋奶')),
      );
      final food = (await tester.runAsync(
        () => catalog.browse(''),
      ))!.foods.single;
      await _register([food]);
      getIt.registerSingleton(catalog);
      await _openAddMeal(tester, [], library: true);
      for (final size in [
        const Size(375, 812),
        const Size(360, 640),
        const Size(812, 375),
      ]) {
        for (final scale in [1.0, 2.0]) {
          tester.view.physicalSize = size;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          await tester.pumpAndSettle();
          expect(
            find.bySemanticsIdentifier('food-category-rail').hitTestable(),
            findsOneWidget,
          );
          expect(
            find.bySemanticsIdentifier('meal-search-field').hitTestable(),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        }
      }
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.view.physicalSize = const Size(375, 812);
      await tester.pumpAndSettle();
      await tester.tap(find.text('肉蛋奶'));
      await tester.pumpAndSettle();
      expect(find.text('鸡蛋'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '不存在的食物');
      await tester.pumpAndSettle();
      expect(find.bySemanticsIdentifier('food-category-rail'), findsOneWidget);
      expect(find.text('鸡蛋'), findsNothing);
      await tester.runAsync(
        () => catalog.activate(jsonEncode(snapshot('云端改名'))),
      );
      await tester.pumpAndSettle();
      expect(find.text('云端改名'), findsOneWidget);
      expect(find.text('肉蛋奶'), findsNothing);
      await tester.enterText(find.byType(TextField), '鸡蛋');
      await tester.pumpAndSettle();
      expect(find.text('鸡蛋'), findsWidgets);
      expect(tester.takeException(), isNull);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    },
  );

  if (_captureUi) {
    testWidgets('capture actual food entry UI for review', (tester) async {
      final catalog = ChineseFoodDataSource(
        read: () => File('assets/foods/catalog.json').readAsString(),
      );
      final foods = (await tester.runAsync(() async {
        return [
          for (final name in ['鸡蛋', '玉米', '米饭', '苹果'])
            (await catalog.matchBatchName(name))
                .firstWhere(
                  (entry) => entry.food.brands?.trim().isNotEmpty != true,
                )
                .food,
        ];
      }))!;
      await _register(foods);
      getIt.registerSingleton<GetIntakeUsecase>(
        _FakeGetIntakeUsecase(foods.map(_intake).toList()),
      );
      getIt.registerSingleton(catalog);
      getIt.registerSingleton(FoodEntryPreferences(_FoodEntryDB()));
      await _openAddMeal(tester, [], library: true);
      tester.view.physicalSize = const Size(375, 812);
      await tester.pumpAndSettle();
      expect(find.bySemanticsIdentifier('food-category-rail'), findsOneWidget);
      await tester.tap(find.text('主食').first);
      await tester.pumpAndSettle();
      await _captureBatchUi(tester, 'food-library');
      await tester.tap(
        find.descendant(
          of: find.bySemanticsIdentifier('food-category-rail'),
          matching: find.text('全部'),
        ),
      );
      await tester.pumpAndSettle();
      final search = find.byType(TextField);
      await tester.enterText(search, '鸡蛋');
      await tester.pumpAndSettle();
      final plus = find.bySemanticsIdentifier('meal-item-add').first;
      await tester.tap(plus);
      await tester.pumpAndSettle();
      await _captureBatchUi(tester, 'quantity-grams');
      await tester.tap(find.text('分量').last);
      await tester.pumpAndSettle();
      await _captureBatchUi(tester, 'quantity-portions');
      await tester.tap(find.bySemanticsIdentifier('meal-detail-add'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('add-meal-review-tray'));
      await tester.pumpAndSettle();
      await _captureBatchUi(tester, 'tray-expanded');
      await tester.tap(find.bySemanticsIdentifier('add-meal-tray-edit').first);
      await tester.pumpAndSettle();
      expect(find.bySemanticsIdentifier('food-quantity-close'), findsOneWidget);
      await _captureBatchUi(tester, 'tray-edit');
      await tester.tap(find.bySemanticsIdentifier('food-quantity-close'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('food-tray-collapse'));
      await tester.pumpAndSettle();
      await tester.enterText(search, '');
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('add-meal-method-ai'));
      await tester.pumpAndSettle();
      await _captureBatchUi(tester, 'ai-methods');
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('add-meal-method-local-batch'),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '鸡蛋10个 玉米100g');
      await tester.runAsync(() async {
        await tester.tap(find.bySemanticsIdentifier('local-batch-match'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      for (final (index, label) in [(0, '早餐'), (1, '午餐')]) {
        final selector = find.bySemanticsIdentifier(
          'local-batch-meal-type-$index',
        );
        await tester.ensureVisible(selector);
        await tester.tap(selector);
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
      }
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 900));
      await tester.pumpAndSettle();
      await _captureBatchUi(tester, 'local-batch');
      await tester.tap(find.bySemanticsIdentifier('local-batch-edit-amount-0'));
      await tester.pumpAndSettle();
      await _captureBatchUi(tester, 'edit-amount');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'local batch reviews amounts and joins the shared tray before logging',
    (tester) async {
      final food = _meal('Corn');
      await _register([food]);
      getIt.registerSingleton<GetIntakeUsecase>(
        _FakeGetIntakeUsecase([_intake(food)]),
      );
      getIt.registerSingleton(
        ChineseFoodDataSource(
          read: () async => throw StateError('should use confirmed history'),
        ),
      );
      getIt.registerSingleton(FoodEntryPreferences(_FoodEntryDB()));
      final pushed = <RouteSettings>[];
      await _openAddMeal(tester, pushed);
      expect(find.bySemanticsIdentifier('add-meal-method-ai'), findsOneWidget);
      await tester.tap(
        find.bySemanticsIdentifier('add-meal-method-local-batch'),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Corn 50g');
      await tester.tap(find.text(l10nEn.localBatchMatch));
      await tester.pumpAndSettle();
      expect(find.text('50 g'), findsOneWidget);
      final edit = find.bySemanticsIdentifier('local-batch-edit-amount-0');
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        '50',
      );
      await tester.enterText(find.byType(TextFormField), '75');
      await tester.tap(find.bySemanticsIdentifier('food-quantity-close'));
      await tester.pumpAndSettle();
      expect(find.text('50 g'), findsOneWidget);
      expect(_mealDetailBloc.writes, isEmpty);
      expect(getIt<FoodEntryPreferences>().batchMatch('corn'), isNull);

      await tester.tap(edit);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '75');
      await tester.tap(find.bySemanticsIdentifier('meal-detail-add'));
      await tester.pumpAndSettle();
      expect(find.text('75 g'), findsOneWidget);
      expect(_mealDetailBloc.writes, isEmpty);
      await tester.tap(find.bySemanticsIdentifier('local-batch-meal-type-0'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10nEn.dinnerLabel).last);
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('local-batch-add-ready'));
      await tester.pumpAndSettle();
      expect(find.byType(AddMealScreen), findsOneWidget);
      final tray = tester
          .widget<LogTrayLogButton>(find.byType(LogTrayLogButton))
          .tray;
      expect(tray.items.single.amount, 75);
      expect(tray.items.single.intakeType, IntakeTypeEntity.dinner);
      expect(_mealDetailBloc.writes, isEmpty);
      expect(getIt<FoodEntryPreferences>().batchMatch('corn'), isNull);
      await tester.tap(_logButton());
      await tester.pumpAndSettle();
      expect(_mealDetailBloc.writes.single.amount, '75.0');
      expect(_mealDetailBloc.writes.single.type, IntakeTypeEntity.dinner);
      expect(getIt<FoodEntryPreferences>().batchMatch('corn'), isNotNull);
      expect(
        pushed.where((route) => route.name == NavigationOptions.bulkAddRoute),
        isEmpty,
      );
    },
  );

  testWidgets(
    'counted food shows its size and grams and joins mixed meal types in one tap',
    (tester) async {
      final egg = _meal(
        '鸡蛋',
        portions: const [
          MealPortionEntity(label: '小个', gramWeight: 40, localized: true),
          MealPortionEntity(label: '中等个', gramWeight: 50, localized: true),
          MealPortionEntity(label: '大个', gramWeight: 60, localized: true),
        ],
      );
      final corn = _meal('玉米');
      await _register([egg, corn]);
      getIt.registerSingleton<GetIntakeUsecase>(
        _FakeGetIntakeUsecase([_intake(egg), _intake(corn)]),
      );
      getIt.registerSingleton(
        ChineseFoodDataSource(
          read: () async => throw StateError('no remote request'),
        ),
      );
      await _openAddMeal(tester, []);
      await tester.tap(
        find.bySemanticsIdentifier('add-meal-method-local-batch'),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '鸡蛋10个 玉米50g');
      await tester.tap(find.text(l10nEn.localBatchMatch));
      await tester.pumpAndSettle();
      expect(find.text('10 × 中等个 · 50 g'), findsOneWidget);
      expect(find.textContaining('= 500 g'), findsOneWidget);
      for (final (index, label) in [
        (0, l10nEn.lunchLabel),
        (1, l10nEn.dinnerLabel),
      ]) {
        final selector = find.bySemanticsIdentifier(
          'local-batch-meal-type-$index',
        );
        await tester.ensureVisible(selector);
        await tester.tap(selector);
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.bySemanticsIdentifier('local-batch-add-ready'));
      await tester.pumpAndSettle();
      final tray = tester
          .widget<LogTrayLogButton>(find.byType(LogTrayLogButton))
          .tray;
      expect(tray.items.map((item) => item.amount), [500, 50]);
      expect(tray.items.map((item) => item.intakeType), [
        IntakeTypeEntity.lunch,
        IntakeTypeEntity.dinner,
      ]);
      expect(_mealDetailBloc.writes, isEmpty);
      await tester.tap(_logButton());
      await tester.pumpAndSettle();
      expect(_mealDetailBloc.writes.map((entry) => entry.amount), [
        '500.0',
        '50.0',
      ]);
    },
  );

  testWidgets(
    'missing portion stays pending and confirmed rows cannot be added twice',
    (tester) async {
      final corn = _meal('Corn');
      final egg = _meal('鸡蛋');
      await _register([corn, egg]);
      getIt.registerSingleton<GetIntakeUsecase>(
        _FakeGetIntakeUsecase([_intake(corn), _intake(egg)]),
      );
      getIt.registerSingleton(
        ChineseFoodDataSource(
          read: () async => throw StateError('no remote request'),
        ),
      );
      await _openAddMeal(tester, []);
      await tester.tap(
        find.bySemanticsIdentifier('add-meal-method-local-batch'),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Corn 50g 鸡蛋10个');
      await tester.tap(find.text(l10nEn.localBatchMatch));
      await tester.pumpAndSettle();
      expect(find.text(l10nEn.localBatchAmountNeeded), findsOneWidget);
      final add = find.bySemanticsIdentifier('local-batch-add-ready');
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('local-batch-results'),
          matching: find.text(l10nEn.localBatchAdded),
        ),
        findsOneWidget,
      );
      final button = tester.widget<FilledButton>(
        find.descendant(of: add, matching: find.byType(FilledButton)),
      );
      expect(button.onPressed, isNull);
      expect(
        find.bySemanticsIdentifier('local-batch-edit-amount-1'),
        findsOneWidget,
      );
      await tester.tap(find.bySemanticsIdentifier('local-batch-view-tray'));
      await tester.pumpAndSettle();
      final tray = tester
          .widget<LogTrayLogButton>(find.byType(LogTrayLogButton))
          .tray;
      expect(tray.items, hasLength(1));
      expect(tray.items.single.amount, 50);
      expect(_mealDetailBloc.writes, isEmpty);
    },
  );

  testWidgets('AI description opens the existing description screen', (
    tester,
  ) async {
    await _register([]);
    final pushed = <RouteSettings>[];
    await _openAddMeal(tester, pushed);
    await _openAiMethod(tester, 'add-meal-method-describe');
    await tester.pumpAndSettle();
    expect(
      pushed.where((route) => route.name == NavigationOptions.bulkAddRoute),
      hasLength(1),
    );
  });
  testWidgets(
    'quantity picker can change the meal independently of the library default',
    (tester) async {
      await _register([_meal('Oats')]);
      await _openAddMeal(tester, []);
      await _tapPlus(tester, 'Oats', confirm: false);
      await tester.tap(find.bySemanticsIdentifier('food-detail-meal-type'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10nEn.lunchLabel).last);
      await tester.pumpAndSettle();
      await _confirmAmount(tester);
      await tester.tap(_logButton());
      await tester.pumpAndSettle();
      expect(_mealDetailBloc.writes.single.type, IntakeTypeEntity.lunch);
    },
  );
  testWidgets(
    'one pending list records independently selected lunch and dinner',
    (tester) async {
      await _register([_meal('Oats'), _meal('Milk')]);
      await _openAddMeal(tester, [], library: true);
      Future<void> selectMeal(String id, String label) async {
        await tester.tap(find.bySemanticsIdentifier(id));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
      }

      expect(find.bySemanticsIdentifier('add-meal-type'), findsNothing);
      await _tapPlus(tester, 'Oats', confirm: false);
      await selectMeal('food-detail-meal-type', l10nEn.lunchLabel);
      await _confirmAmount(tester);
      await _tapPlus(tester, 'Milk', confirm: false);
      await selectMeal('food-detail-meal-type', l10nEn.dinnerLabel);
      await _confirmAmount(tester);
      final list = tester.widget<LogTrayLogButton>(
        find.byType(LogTrayLogButton),
      );
      expect(list.tray.items.map((item) => item.intakeType), [
        IntakeTypeEntity.lunch,
        IntakeTypeEntity.dinner,
      ]);
      await tester.tap(_logButton());
      await tester.pumpAndSettle();
      expect(_mealDetailBloc.writes.map((item) => item.type), [
        IntakeTypeEntity.lunch,
        IntakeTypeEntity.dinner,
      ]);
    },
  );

  test(
    'changing a row meal does not alter other entries or retry identity',
    () {
      final tray = LogTray(defaultIntakeType: IntakeTypeEntity.lunch);
      LogTrayItem entry(String name) => LogTrayItem(
        meal: _meal(name),
        unit: 'g',
        amount: 100,
        amountLabel: '100 g',
      );
      tray.add(entry('Oats'));
      tray.defaultIntakeType = IntakeTypeEntity.dinner;
      tray.add(entry('Milk'));
      final first = tray.items.first;
      tray.changeIntakeType(1, IntakeTypeEntity.snack);
      expect(tray.items.first, same(first));
      expect(tray.items.map((item) => item.intakeType), [
        IntakeTypeEntity.lunch,
        IntakeTypeEntity.snack,
      ]);
      tray.removeAll([first]);
      expect(tray.items.single.meal.name, 'Milk');
      tray.dispose();
    },
  );
  testWidgets(
    'custom foods filters the saved library, keeps its tab and follows edits',
    (tester) async {
      await _register([_meal('Recently logged only')]);
      _customFoods.entries.addAll([
        MealDBO.fromMealEntity(_meal('Homemade oats')),
        MealDBO.fromMealEntity(_meal('Homemade soup')),
      ]);
      await _openAddMeal(tester, [], library: true);
      final custom = find.bySemanticsIdentifier('add-meal-source-custom');
      await tester.ensureVisible(custom);
      await tester.tap(custom);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Homemade oats', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Homemade soup', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Recently logged only', findRichText: true),
        findsNothing,
      );
      final field = find.descendant(
        of: find.byType(MealSearchBar),
        matching: find.byType(TextField),
      );
      await tester.enterText(field, 'oats');
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Homemade oats', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Homemade soup', findRichText: true),
        findsNothing,
      );
      await tester.enterText(field, '');
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Homemade soup', findRichText: true),
        findsOneWidget,
      );
      _customFoods.entries.add(MealDBO.fromMealEntity(_meal('New saved food')));
      _customFoods.changes.add(null);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('New saved food', findRichText: true),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('food library keeps only the food-level meal selection', (
    tester,
  ) async {
    await _register([_meal('Oats')]);
    final pushed = <RouteSettings>[];
    await _openAddMeal(tester, pushed, library: true);
    expect(find.bySemanticsIdentifier('add-meal-type'), findsNothing);
    await tester.tap(_card('Oats'));
    await tester.pumpAndSettle();
    expect(pushed.last.name, NavigationOptions.mealDetailRoute);
    expect(find.byType(FoodQuantityDialog), findsNothing);
    expect(_logButton(), findsNothing);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    await tester.tap(_detailsOn('Oats'));
    await tester.pumpAndSettle();
    final detail = pushed.last.arguments as MealDetailScreenArguments;
    expect(detail.intakeTypeEntity, IntakeTypeEntity.breakfast);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    await _tapPlus(tester, 'Oats', confirm: false);
    await tester.tap(find.bySemanticsIdentifier('food-detail-meal-type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10nEn.snackLabel).last);
    await tester.pumpAndSettle();
    await _confirmAmount(tester);
    await tester.tap(_logButton());
    await tester.pumpAndSettle();
    expect(_mealDetailBloc.writes.single.type, IntakeTypeEntity.snack);
  });

  group('LogTray', () {
    test('sums energy and keeps order through removals', () {
      final tray = LogTray();
      addTearDown(tray.dispose);
      var notified = 0;
      tray.addListener(() => notified++);

      final a = _meal('A', kcal100: 200);
      final b = _meal('B', kcal100: 50);
      tray.add(LogTrayItem(meal: a, unit: 'g', amount: 150, amountLabel: ''));
      tray.addAll([
        LogTrayItem(meal: b, unit: 'g', amount: 200, amountLabel: ''),
        LogTrayItem(meal: a, unit: 'g', amount: 50, amountLabel: ''),
      ]);
      expect(tray.length, 3);
      expect(tray.totalKcal, closeTo(300 + 100 + 100, 0.001));

      tray.removeAt(0);
      expect(tray.items.map((i) => i.meal.name), ['B', 'A']);

      // By identity: an equal-looking entry that was not named stays.
      final again = LogTrayItem(
        meal: b,
        unit: 'g',
        amount: 200,
        amountLabel: '',
      );
      tray.add(again);
      tray.removeAll([tray.items.first]);
      expect(tray.items.map((i) => i.meal.name), ['A', 'B']);
      expect(identical(tray.items.last, again), isTrue);
      tray.clear();
      expect(tray.isEmpty, isTrue);
      expect(notified, 6);
    });

    test('a food on its way counts as collecting before it arrives', () {
      final tray = LogTray();
      addTearDown(tray.dispose);
      var notified = 0;
      tray.addListener(() => notified++);
      expect(tray.collects, isFalse);

      tray.beginPending();
      expect(tray.isEmpty, isTrue);
      expect(tray.collects, isTrue);

      // A lookup that ends without adding anything (a food the detail
      // screen has to open instead) leaves the list as it was.
      tray.endPending();
      expect(tray.collects, isFalse);

      tray.add(
        LogTrayItem(meal: _meal('A'), unit: 'g', amount: 1, amountLabel: ''),
      );
      expect(tray.collects, isTrue);
      expect(notified, 3);
    });
  });

  group('the log button', () {
    Future<void> pumpButton(WidgetTester tester, int items) async {
      final tray = LogTray();
      addTearDown(tray.dispose);
      for (var i = 0; i < items; i++) {
        tray.add(
          LogTrayItem(
            meal: _meal('M$i'),
            unit: 'g',
            amount: 100,
            amountLabel: '',
          ),
        );
      }
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => EnergyUnitProvider(usesKilojoules: false),
          child: MaterialApp(
            localizationsDelegates: const [
              S.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: S.supportedLocales,
            home: Scaffold(
              body: LogTrayLogButton(tray: tray, onPressed: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    // #1470: one item read "Log 1 items".
    testWidgets('one item reads singular', (tester) async {
      await pumpButton(tester, 1);
      expect(find.text('Log 1 item'), findsOneWidget);
    });

    testWidgets('two items read plural', (tester) async {
      await pumpButton(tester, 2);
      expect(find.text('Log 2 items'), findsOneWidget);
    });

    test('the review screen\'s add-to-list label agrees', () {
      expect(l10nEn.bulkAddToListLabel(1), 'Add 1 item');
      expect(l10nEn.bulkAddToListLabel(2), 'Add 2 items');
    });
  });

  group('the default amount behind the +', () {
    Future<LogTrayItem?> resolve(
      WidgetTester tester,
      MealEntity meal, {
      bool imperial = false,
      bool raw = false,
    }) async {
      LogTrayItem? item;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: S.supportedLocales,
          home: Builder(
            builder: (context) {
              item = defaultLogTrayItem(
                context,
                meal,
                usesImperialUnits: imperial,
                defaultToRawFoodUnits: raw,
              );
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      return item;
    }

    testWidgets('packaged food can default to one serving', (tester) async {
      final item = await resolve(
        tester,
        _meal('Bread', servingQuantity: 38, servingSize: '1包（38 g）'),
      );
      expect(item!.unit, 'serving');
      expect(item.amount, 38);
    });

    testWidgets(
      'household food defaults to grams with an old serving preference',
      (tester) async {
        final item = await resolve(
          tester,
          _meal('米饭', servingQuantity: 150, servingSize: '一碗'),
        );
        expect(item!.unit, 'g');
        expect(item.amount, 100);
      },
    );

    testWidgets('raw units win over the serving when the user prefers them', (
      tester,
    ) async {
      final item = await resolve(
        tester,
        _meal('Bread', servingQuantity: 38),
        raw: true,
      );
      expect(item!.unit, 'g');
      expect(item.amount, 100);
      expect(item.amountLabel, '100 ${l10nEn.gramUnit}');
    });

    testWidgets('imperial starts at one ounce', (tester) async {
      final item = await resolve(tester, _meal('Rice'), imperial: true);
      expect(item!.unit, 'oz');
      expect(item.amount, closeTo(28.35, 0.01));
    });

    testWidgets('a food missing a macro has no default', (tester) async {
      expect(await resolve(tester, _meal('Odd', complete: false)), isNull);
    });
  });

  group('the add-food screen', () {
    testWidgets('quick plus requires confirmation and closing adds nothing', (
      tester,
    ) async {
      await _register([_meal('Oats', kcal100: 380)]);
      await _openAddMeal(tester, []);
      await _tapPlus(tester, 'Oats', confirm: false);
      expect(find.byType(FoodQuantityDialog), findsOneWidget);
      expect(_logButton(), findsNothing);
      expect(_mealDetailBloc.writes, isEmpty);
      await tester.tap(find.bySemanticsIdentifier('food-quantity-close'));
      await tester.pumpAndSettle();
      expect(_logButton(), findsNothing);
      expect(_mealDetailBloc.writes, isEmpty);
    });

    testWidgets(
      'quick plus records the selected 150g rather than the initial 100g',
      (tester) async {
        await _register([_meal('Oats', kcal100: 380)]);
        await _openAddMeal(tester, []);
        await _tapPlus(tester, 'Oats', confirm: false);
        await tester.enterText(find.byType(TextFormField).last, '150');
        await tester.pumpAndSettle();
        await _confirmAmount(tester);
        await tester.tap(_logButton());
        await tester.pumpAndSettle();
        expect(_mealDetailBloc.writes.single.amount, '150.0');
      },
    );

    testWidgets(
      'custom portions remember the specification and reset the count',
      (tester) async {
        final oats = _meal('Oats');
        await _register([oats]);
        getIt.registerSingleton(FoodEntryPreferences(_FoodEntryDB()));
        await _openAddMeal(tester, []);
        await _tapPlus(tester, 'Oats', confirm: false);
        await tester.tap(find.text(l10nEn.foodPortionMode));
        await tester.pumpAndSettle();
        Finder field(String id) => find.descendant(
          of: find.bySemanticsIdentifier(id),
          matching: find.byType(TextFormField),
        );
        await tester.enterText(field('food-custom-portion-name'), 'My bowl');
        await tester.enterText(field('food-custom-portion-size'), '120');
        final save = find.widgetWithText(FilledButton, l10nEn.buttonSaveLabel);
        await tester.pumpAndSettle();
        expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(getIt<FoodEntryPreferences>().customPortions(oats), {
          'My bowl': 120.0,
        });
        expect(find.textContaining('My bowl'), findsOneWidget);
        final quantity = find.descendant(
          of: find.bySemanticsIdentifier('meal-detail-quantity'),
          matching: find.byType(TextFormField),
        );
        await tester.enterText(quantity, '2');
        await tester.pumpAndSettle();
        final input = find.descendant(
          of: quantity,
          matching: find.byType(TextField),
        );
        expect(
          tester.widget<TextField>(input).decoration?.helperText,
          '= 240 g',
        );
        await _confirmAmount(tester);

        await _tapPlus(tester, 'Oats', confirm: false);
        expect(find.textContaining('My bowl'), findsOneWidget);
        expect(tester.widget<TextFormField>(quantity).controller!.text, '1');
        expect(
          tester.widget<TextField>(input).decoration?.helperText,
          '= 120 g',
        );
        await tester.tap(find.bySemanticsIdentifier('food-quantity-close'));
        await tester.pumpAndSettle();
        await tester.tap(_logButton());
        await tester.pumpAndSettle();
        expect(_mealDetailBloc.writes.single.amount, '240.0');
      },
    );

    testWidgets('+ confirms the chosen amount, and the list can be edited', (
      tester,
    ) async {
      await _register([_meal('Oats', kcal100: 380), _meal('Milk')]);
      await _openAddMeal(tester, []);

      expect(_logButton(), findsNothing);
      await _tapPlus(tester, 'Oats');
      await tester.pumpAndSettle();
      await _tapPlus(tester, 'Milk');
      await tester.pumpAndSettle();

      expect(find.text(l10nEn.bulkAddSubmitLabel(2)), findsOneWidget);
      expect(find.text('580 kcal'), findsOneWidget);
      await tester.tap(find.bySemanticsIdentifier('add-meal-review-tray'));
      await tester.pumpAndSettle();
      expect(find.text(l10nEn.foodTrayReview), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.bySemanticsIdentifier('add-meal-tray-list'), findsOneWidget);

      await tester.tap(find.byTooltip(l10nEn.logTrayRemoveLabel).first);
      await tester.pumpAndSettle();
      expect(find.text(l10nEn.bulkAddSubmitLabel(1)), findsOneWidget);

      await tester.tap(find.byTooltip(l10nEn.logTrayRemoveLabel).first);
      await tester.pumpAndSettle();
      expect(_logButton(), findsNothing);
      expect(_mealDetailBloc.writes, isEmpty);
    });

    testWidgets(
      'a long tray opens a full page and cancelling its amount editor preserves the list',
      (tester) async {
        await _register([_meal('Oats'), _meal('Milk'), _meal('Apple')]);
        await _openAddMeal(tester, []);
        for (final name in ['Oats', 'Milk', 'Apple']) {
          await _tapPlus(tester, name);
        }
        await tester.tap(find.bySemanticsIdentifier('add-meal-review-tray'));
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsIdentifier('food-tray-view-all'));
        await tester.pumpAndSettle();
        expect(
          find.bySemanticsIdentifier('food-tray-back-to-library'),
          findsOneWidget,
        );
        expect(find.byType(BottomSheet), findsNothing);
        await tester.tap(
          find.bySemanticsIdentifier('add-meal-tray-edit').first,
        );
        await tester.pumpAndSettle();
        expect(
          find.bySemanticsIdentifier('food-quantity-close'),
          findsOneWidget,
        );
        await tester.enterText(find.byType(TextFormField), '75');
        await tester.tap(find.bySemanticsIdentifier('food-quantity-close'));
        await tester.pumpAndSettle();
        final tray = tester
            .widget<LogTrayLogButton>(find.byType(LogTrayLogButton))
            .tray;
        expect(tray.length, 3);
        expect(tray.items.first.amount, 100);
        await tester.tap(
          find.bySemanticsIdentifier('food-tray-back-to-library'),
        );
        await tester.pumpAndSettle();
        expect(find.bySemanticsIdentifier('meal-search-field'), findsOneWidget);
        expect(_mealDetailBloc.writes, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('one button logs the whole list and returns to the day', (
      tester,
    ) async {
      await _register([_meal('Oats', kcal100: 380), _meal('Milk')]);
      await _openAddMeal(tester, []);
      await _tapPlus(tester, 'Oats');
      await tester.pumpAndSettle();
      await _tapPlus(tester, 'Milk');
      await tester.pumpAndSettle();

      await tester.tap(_logButton());
      await tester.pumpAndSettle();

      expect(_mealDetailBloc.writes.map((w) => w.name), ['Oats', 'Milk']);
      expect(_mealDetailBloc.writes.first.unit, 'g');
      expect(_mealDetailBloc.writes.first.amount, '100.0');
      expect(_homeBloc.refreshed, isTrue);
      expect(find.byKey(const Key('main')), findsOneWidget);
    });

    testWidgets('a failed write keeps only what was not logged', (
      tester,
    ) async {
      await _register([_meal('Oats'), _meal('Milk')]);
      await _openAddMeal(tester, []);
      await _tapPlus(tester, 'Oats');
      await tester.pumpAndSettle();
      await _tapPlus(tester, 'Milk');
      await tester.pumpAndSettle();
      _mealDetailBloc.failAt = 1;

      await tester.tap(_logButton());
      await tester.pumpAndSettle();

      expect(find.text(l10nEn.logTrayLogFailedLabel), findsOneWidget);
      // Oats is in the diary; retrying must not write it a second time.
      expect(find.text(l10nEn.bulkAddSubmitLabel(1)), findsOneWidget);
      _mealDetailBloc.failAt = null;
      await tester.tap(_logButton());
      await tester.pumpAndSettle();
      expect(_mealDetailBloc.writes.map((w) => w.name), ['Oats', 'Milk']);
    });

    testWidgets('leaving with items on the list asks first', (tester) async {
      await _register([_meal('Oats')]);
      await _openAddMeal(tester, []);
      await _tapPlus(tester, 'Oats');
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text(l10nEn.discardChangesTitle), findsOneWidget);
      await tester.tap(find.text(l10nEn.dialogCancelLabel));
      await tester.pumpAndSettle();
      expect(find.byType(AddMealScreen), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10nEn.discardChangesConfirmLabel));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('main')), findsOneWidget);
      expect(_mealDetailBloc.writes, isEmpty);
    });

    testWidgets('every screen it opens is handed the same list', (
      tester,
    ) async {
      await _register([_meal('Oats')]);
      final pushed = <RouteSettings>[];
      await _openAddMeal(tester, pushed);

      await tester.tap(_detailsOn('Oats'));
      await tester.pumpAndSettle();
      final detail = pushed.last.arguments as MealDetailScreenArguments;
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsIdentifier('add-meal-method-barcode'));
      await tester.pumpAndSettle();
      final scanner = pushed.last.arguments as ScannerScreenArguments;
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();

      await _openAiMethod(tester, 'add-meal-method-photo');
      await tester.pumpAndSettle();
      final review = pushed.last.arguments as BulkAddScreenArguments;

      expect(detail.logTray, isNotNull);
      expect(scanner.logTray, same(detail.logTray));
      expect(review.logTray, same(detail.logTray));
    });

    Future<void> fillQuickAdd(WidgetTester tester) async {
      await tester.tap(find.bySemanticsIdentifier('add-meal-quick-add'));
      await tester.pumpAndSettle();
      Finder field(String id) => find.descendant(
        of: find.bySemanticsIdentifier(id),
        matching: find.byType(TextField),
      );
      await tester.enterText(field('quick-add-title'), 'Cake');
      await tester.enterText(field('quick-add-energy'), '350');
      await tester.pumpAndSettle();
    }

    testWidgets('Quick add\'s Add to list puts its entry on the list', (
      tester,
    ) async {
      await _register([]);
      await _openAddMeal(tester, []);

      await fillQuickAdd(tester);
      await tester.tap(find.bySemanticsIdentifier('quick-add-meal-type'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10nEn.dinnerLabel).last);
      await tester.pumpAndSettle();
      // With nothing on the list yet, Add itself logs at once (#1520), so
      // starting a list is the second button.
      await tester.tap(find.bySemanticsIdentifier('quick-add-add-to-list'));
      await tester.pumpAndSettle();

      expect(find.byType(AddMealScreen), findsOneWidget);
      expect(find.text(l10nEn.bulkAddSubmitLabel(1)), findsOneWidget);
      expect(find.text('350 kcal'), findsWidgets);
      expect(_mealDetailBloc.writes, isEmpty);

      await tester.tap(_logButton());
      await tester.pumpAndSettle();
      expect(_mealDetailBloc.writes.single.name, 'Cake');
      expect(_mealDetailBloc.writes.single.type, IntakeTypeEntity.dinner);
    });

    testWidgets('with nothing on the list, Quick add\'s Add logs at once', (
      tester,
    ) async {
      await _register([]);
      final addIntake = _RecordingAddIntakeUsecase();
      getIt
        ..registerSingleton<AddIntakeUsecase>(addIntake)
        ..registerSingleton<AddTrackedDayUsecase>(
          _ExistingDayAddTrackedDayUsecase(),
        );
      await _openAddMeal(tester, []);

      await fillQuickAdd(tester);
      await tester.tap(find.bySemanticsIdentifier('quick-add-submit'));
      await tester.pumpAndSettle();

      // Logged and back on the day, as before the list existed (#1520).
      expect(addIntake.stored.single.meal.name, 'Cake');
      expect(find.byKey(const Key('main')), findsOneWidget);
      expect(_mealDetailBloc.writes, isEmpty);
    });

    testWidgets('once the list has items, Quick add\'s Add joins it', (
      tester,
    ) async {
      await _register([_meal('Oats')]);
      await _openAddMeal(tester, []);
      await _tapPlus(tester, 'Oats');
      await tester.pumpAndSettle();

      await fillQuickAdd(tester);
      expect(find.bySemanticsIdentifier('quick-add-add-to-list'), findsNothing);
      await tester.tap(find.bySemanticsIdentifier('quick-add-submit'));
      await tester.pumpAndSettle();

      expect(find.byType(AddMealScreen), findsOneWidget);
      expect(find.text(l10nEn.bulkAddSubmitLabel(2)), findsOneWidget);
      expect(_mealDetailBloc.writes, isEmpty);
    });

    testWidgets(
      'with a + still fetching, Quick add\'s Add joins the list instead of '
      'leaving without that food',
      (tester) async {
        await _register([_meal('Granola', source: MealSourceEntity.off)]);
        final addIntake = _RecordingAddIntakeUsecase();
        getIt
          ..registerSingleton<AddIntakeUsecase>(addIntake)
          ..registerSingleton<AddTrackedDayUsecase>(
            _ExistingDayAddTrackedDayUsecase(),
          );
        _products.full = _meal(
          'Granola',
          source: MealSourceEntity.off,
          servingQuantity: 45,
          servingSize: '45 g',
          detailed: true,
        );
        await _openAddMeal(tester, []);
        final gate = _products.gate = Completer<void>();
        await _tapPlus(tester, 'Granola');
        await tester.pump();

        await fillQuickAdd(tester);
        // The list is still empty, but Granola is on its way onto it.
        expect(
          find.bySemanticsIdentifier('quick-add-add-to-list'),
          findsNothing,
        );
        await tester.tap(find.bySemanticsIdentifier('quick-add-submit'));
        await tester.pumpAndSettle();
        expect(addIntake.stored, isEmpty);
        expect(find.byType(AddMealScreen), findsOneWidget);

        gate.complete();
        await tester.pumpAndSettle();
        await _confirmAmount(tester);
        await tester.tap(_logButton());
        await tester.pumpAndSettle();
        expect(_mealDetailBloc.writes.map((w) => w.name), ['Cake', 'Granola']);
      },
    );

    testWidgets('leaving while a + is still fetching does not throw', (
      tester,
    ) async {
      await _register([_meal('Granola', source: MealSourceEntity.off)]);
      _products.full = _meal(
        'Granola',
        source: MealSourceEntity.off,
        detailed: true,
      );
      await _openAddMeal(tester, []);
      final gate = _products.gate = Completer<void>();
      await _tapPlus(tester, 'Granola');
      await tester.pump();

      // The list is empty, so Back leaves at once and disposes it.
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(find.byType(AddMealScreen), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();
      await _confirmAmount(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the log button stays above the keyboard (#1520)', (
      tester,
    ) async {
      await _register([_meal('Oats')]);
      await _openAddMeal(tester, []);
      await _tapPlus(tester, 'Oats');
      await tester.pumpAndSettle();

      final search = find.descendant(
        of: find.byType(MealSearchBar),
        matching: find.byType(TextField),
      );
      await tester.showKeyboard(search);
      const keyboard = 336.0;
      tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      // Above the keyboard's top edge, where it can be seen and tapped.
      final screenHeight = tester.view.physicalSize.height;
      expect(_logButton(), findsOneWidget);
      expect(
        tester.getBottomLeft(_logButton()).dy,
        lessThanOrEqualTo(screenHeight - keyboard),
      );
      // Moving the button did not take the focus off the search field,
      // which would close the keyboard again.
      final editable = tester.widget<EditableText>(
        find.descendant(of: search, matching: find.byType(EditableText)),
      );
      expect(editable.focusNode.hasFocus, isTrue);

      await tester.tap(_logButton());
      await tester.pumpAndSettle();
      expect(_mealDetailBloc.writes.single.name, 'Oats');
    });

    testWidgets('+ on a thin search hit hydrates and defaults to grams', (
      tester,
    ) async {
      await _register([_meal('Granola', source: MealSourceEntity.off)]);
      _products.full = _meal(
        'Granola',
        source: MealSourceEntity.off,
        servingQuantity: 45,
        servingSize: '45 g',
        detailed: true,
      );
      await _openAddMeal(tester, []);

      await _tapPlus(tester, 'Granola');
      await tester.pumpAndSettle();
      await tester.tap(_logButton());
      await tester.pumpAndSettle();

      expect(_products.lookups, 1);
      final write = _mealDetailBloc.writes.single;
      expect(write.unit, 'g');
      expect(write.amount, '100.0');
    });

    testWidgets('+ keeps the thin record when the lookup fails', (
      tester,
    ) async {
      await _register([_meal('Granola', source: MealSourceEntity.off)]);
      await _openAddMeal(tester, []);

      await _tapPlus(tester, 'Granola');
      await tester.pumpAndSettle();
      await tester.tap(_logButton());
      await tester.pumpAndSettle();

      expect(_mealDetailBloc.writes.single.unit, 'g');
      expect(_mealDetailBloc.writes.single.amount, '100.0');
    });

    testWidgets('logging waits for a + that is still fetching its food', (
      tester,
    ) async {
      await _register([
        _meal('Oats'),
        _meal('Granola', source: MealSourceEntity.off),
      ]);
      _products.full = _meal(
        'Granola',
        source: MealSourceEntity.off,
        servingQuantity: 45,
        servingSize: '45 g',
        detailed: true,
      );
      await _openAddMeal(tester, []);
      await _tapPlus(tester, 'Oats');
      await tester.pumpAndSettle();
      final gate = _products.gate = Completer<void>();

      await _tapPlus(tester, 'Granola');
      await tester.pump();
      final log = find.descendant(
        of: _logButton(),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      expect(tester.widget<ButtonStyleButton>(log).onPressed, isNull);

      gate.complete();
      await tester.pumpAndSettle();
      await _confirmAmount(tester);
      expect(tester.widget<ButtonStyleButton>(log).onPressed, isNotNull);
      await tester.tap(log);
      await tester.pumpAndSettle();

      expect(_mealDetailBloc.writes.map((w) => w.name), ['Oats', 'Granola']);
    });

    testWidgets('the list cannot change while it is being written', (
      tester,
    ) async {
      await _register([_meal('Oats'), _meal('Milk')]);
      await _openAddMeal(tester, []);
      await _tapPlus(tester, 'Oats');
      await tester.pumpAndSettle();
      await _tapPlus(tester, 'Milk');
      await tester.pumpAndSettle();
      final gate = _mealDetailBloc.gate = Completer<void>();

      await tester.tap(_logButton());
      await tester.pump();
      await tester.tap(
        find.bySemanticsIdentifier('add-meal-review-tray'),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(find.bySemanticsIdentifier('add-meal-tray-list'), findsNothing);
      expect(find.text(l10nEn.bulkAddSubmitLabel(2)), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
      await _confirmAmount(tester);
      expect(_mealDetailBloc.writes.map((w) => w.name), ['Oats', 'Milk']);
      expect(find.byKey(const Key('main')), findsOneWidget);
    });

    testWidgets(
      'a food missing a macro explains the missing value and cannot add',
      (tester) async {
        await _register([_meal('Odd', complete: false)]);
        final pushed = <RouteSettings>[];
        await _openAddMeal(tester, pushed);

        await _tapPlus(tester, 'Odd');
        await tester.pumpAndSettle();

        expect(pushed, isEmpty);
        expect(find.byType(FoodQuantityDialog), findsOneWidget);
        final confirm = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, l10nEn.loggingConfirmAmount),
        );
        expect(confirm.onPressed, isNull);
        expect(_logButton(), findsNothing);
      },
    );
  });
}
