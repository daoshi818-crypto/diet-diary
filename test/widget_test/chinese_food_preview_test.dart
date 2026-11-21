// Real production screens, real private catalogue; memory-only user history.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/presentation/widgets/food_quantity_dialog.dart';
import 'package:opennutritracker/features/add_meal/data/data_sources/chinese_food_data_source.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/food_sources_screen.dart';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
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
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/search_products_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_screen.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/add_meal_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/favourite_meal_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/favourite_toggle_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/food_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/products_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/recent_meal_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../helpers/fake_favourites.dart';

class _FakeGetIntakeUsecase implements GetIntakeUsecase {
  @override
  Future<List<IntakeEntity>> getRecentIntake() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _FakeGetConfigUsecase implements GetConfigUsecase {
  final bool imperial = false;

  _FakeGetConfigUsecase();

  @override
  Future<ConfigEntity> getConfig() async => ConfigEntity(
    true,
    true,
    false,
    AppThemeEntity.system,
    usesImperialFoodUnits: imperial,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _FakeCustomMealDataSource implements CustomMealDataSource {
  final List<MealDBO> meals = [];

  @override
  List<MealDBO> getAllCustomMeals() => meals;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _FakeRecipeDataSource implements RecipeDataSource {
  @override
  List<RecipeDBO> getAllRecipes() => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

/// An empty cache that accepts writes: cached copies would otherwise stand
/// in for remote results and blur what each provider returned.
class _FakeRemoteSearchCacheDataSource implements RemoteSearchCacheDataSource {
  @override
  Future<void> cacheFromSearch(Iterable<MealDBO> meals) async {}

  @override
  List<MealDBO> getAllByMostRecentlyTouched() => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

SearchProductsUseCase _useCase(
  ProductsRepository repository,
  GetConfigUsecase config, {
  _FakeCustomMealDataSource? customMeals,
}) => SearchProductsUseCase(
  repository,
  _FakeGetIntakeUsecase(),
  customMeals ?? _FakeCustomMealDataSource(),
  _FakeRemoteSearchCacheDataSource(),
  _FakeRecipeDataSource(),
  config,
);

final getIt = GetIt.instance;

late ProductsRepository _repository;
late _FakeCustomMealDataSource _customMeals;
FakeFavourites? _favourites;
late ProductsBloc _productsBloc;
late FoodBloc _foodBloc;
late int _expectedCount;

Future<void> _register() async {
  await getIt.reset();
  final source = ChineseFoodDataSource(
    read: () => File('assets/foods/catalog.json').readAsString(),
  );
  _expectedCount = await source.count();
  _repository = ProductsRepository.local(source);
  getIt.registerSingleton<ChineseFoodDataSource>(source);
  getIt.registerSingleton<ProductsRepository>(_repository);
  getIt.registerSingleton<RemoteSearchCacheDataSource>(
    _FakeRemoteSearchCacheDataSource(),
  );
  _customMeals = _FakeCustomMealDataSource();
  final config = _FakeGetConfigUsecase();
  final useCase = _useCase(_repository, config, customMeals: _customMeals);
  getIt.registerFactory<AddMealBloc>(() => AddMealBloc(config));
  getIt.registerFactory<ProductsBloc>(
    () => _productsBloc = ProductsBloc(useCase, config),
  );
  getIt.registerFactory<FoodBloc>(() => _foodBloc = FoodBloc(useCase, config));
  getIt.registerFactory<RecentMealBloc>(
    () => RecentMealBloc(_FakeGetIntakeUsecase(), config),
  );
  // #1307: the screen's Favourites source and the stars on its cards.
  await _favourites?.dispose();
  final favourites = _favourites = FakeFavourites();
  getIt.registerFactory<FavouriteMealBloc>(
    () => FavouriteMealBloc(favourites.get, config),
  );
  getIt.registerFactory<FavouriteToggleBloc>(
    () => FavouriteToggleBloc(favourites.get, favourites.toggle),
  );
}

Route<dynamic> _route(RouteSettings settings) => MaterialPageRoute<void>(
  settings: RouteSettings(
    name: settings.name,
    arguments: AddMealScreenArguments(
      AddMealType.lunchType,
      DateTime(2026, 11, 20),
      isFoodLibrary: true,
    ),
  ),
  builder: (_) => const AddMealScreen(),
);

final captureKey = GlobalKey();
final navKey = GlobalKey<NavigatorState>();
Widget wrap({Widget? home, RouteFactory? route}) => ChangeNotifierProvider(
  create: (_) => EnergyUnitProvider(),
  child: MaterialApp(
    navigatorKey: navKey,
    locale: const Locale('zh'),
    localizationsDelegates: const [
      S.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: S.supportedLocales,
    theme: buildAppTheme(AppPalette.light).copyWith(
      textTheme: buildAppTheme(
        AppPalette.light,
      ).textTheme.apply(fontFamily: 'ChinesePreview'),
      appBarTheme: buildAppTheme(AppPalette.light).appBarTheme.copyWith(
        titleTextStyle: const TextStyle(
          fontFamily: 'ChinesePreview',
          fontSize: 23,
          fontWeight: FontWeight.w700,
          color: Color(0xff2b2a27),
        ),
      ),
    ),
    builder: (context, child) =>
        RepaintBoundary(key: captureKey, child: child!),
    home: home,
    onGenerateRoute: route,
  ),
);

Future<void> capture(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  final boundary =
      captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final img = await boundary.toImage(pixelRatio: 2);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    await File('preview/$name.png').writeAsBytes(bytes.buffer.asUint8List());
    img.dispose();
  });
}

void main() {
  testWidgets(
    'actual Chinese catalogue renders and opens quantity selection',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        await Directory('preview').create(recursive: true);
        final fontFile = File(
          Platform.environment['FOOD_PREVIEW_FONT'] ??
              'C:/Windows/Fonts/msyh.ttc',
        );
        if (fontFile.existsSync()) {
          for (final family in ['ChinesePreview', 'Nunito']) {
            final font = FontLoader(family)
              ..addFont(fontFile.readAsBytes().then(ByteData.sublistView));
            await font.load();
          }
        }
        final icons = FontLoader('MaterialIcons')
          ..addFont(
            File(
              Platform.environment['FOOD_PREVIEW_ICON_FONT']!,
            ).readAsBytes().then(ByteData.sublistView),
          );
        await icons.load();
        await _register();
      });
      await tester.pumpWidget(wrap(route: _route));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '鸡蛋');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump(const Duration(milliseconds: 400));
      // The catalogue was decoded in runAsync (real event loop). Let its
      // completed Future deliver to the test's fake async zone before pumping.
      await tester.runAsync(() => _repository.getSupabaseFoodsByString('鸡蛋'));
      await tester.pumpAndSettle();
      expect(_productsBloc.state, isA<ProductsLoadedState>());
      expect(_foodBloc.state, isA<FoodLoadedState>());
      expect((_foodBloc.state as FoodLoadedState).food, isNotEmpty);
      expect(
        (_foodBloc.state as FoodLoadedState).food.where(
          (f) => f.name == '鸡蛋' && (f.brands?.isEmpty ?? true),
        ),
        hasLength(1),
        reason:
            'Only one unbranded generic egg appears after catalogue cleaning',
      );
      expect(find.textContaining('鸡蛋（者）'), findsNothing);
      expect(find.textContaining('鸡蛋'), findsWidgets);
      await capture(tester, '01-chinese-food-search');
      final quickAdd = find.bySemanticsIdentifier('meal-item-add');
      expect(quickAdd, findsWidgets);
      await tester.tap(quickAdd.first);
      await tester.pumpAndSettle();
      expect(find.byType(FoodQuantityDialog), findsOneWidget);
      final dialog = tester.widget<FoodQuantityDialog>(
        find.byType(FoodQuantityDialog),
      );
      expect(dialog.meal.name, contains('鸡蛋'));
      expect(dialog.meal.nutriments.energyKcal100, isNotNull);
      await capture(tester, '02-food-quantity');
      navKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(_customMeals.meals, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(wrap(home: const FoodSourcesScreen()));
      await tester.runAsync(() => getIt<ChineseFoodDataSource>().count());
      await tester.pumpAndSettle();
      expect(find.text('本地中文食物库'), findsOneWidget);
      expect(find.text('内置中文食物，支持离线搜索。'), findsOneWidget);
      expect(find.textContaining('$_expectedCount'), findsOneWidget);
      await capture(tester, '03-local-food-library');
      await tester.pumpWidget(const SizedBox.shrink());
      await getIt.reset();
      await _favourites?.dispose();
    },
    skip: !const bool.fromEnvironment('GENERATE_FOOD_PREVIEW'),
  );
}
