import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/food_quantity_dialog.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/nutrition_label_draft.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/search_products_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_screen.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/add_meal_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/favourite_meal_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/favourite_toggle_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/food_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/products_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/recent_meal_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/screens/bulk_add_screen.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/log_tray_widgets.dart';
import 'package:opennutritracker/features/scanner/scanner_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../../helpers/fake_favourites.dart';
import '../../../helpers/test_l10n.dart';

class _FakeGetIntakeUsecase implements GetIntakeUsecase {
  @override
  Future<List<IntakeEntity>> getRecentIntake() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _FakeGetConfigUsecase implements GetConfigUsecase {
  final bool imperial;

  _FakeGetConfigUsecase({this.imperial = false});

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

class _FakeSearch implements SearchProductsUseCase {
  @override
  Future<SearchProductsResult> searchOFFProductsByString(
    String searchString, {
    bool skipRemote = false,
  }) async => const SearchProductsResult(
    meals: <MealEntity>[],
    remoteSourceEmpty: true,
  );

  @override
  Future<SearchProductsResult> searchFDCFoodByString(
    String searchString, {
    bool skipRemote = false,
    bool forResolution = false,
  }) async => const SearchProductsResult(
    meals: <MealEntity>[],
    remoteSourceEmpty: true,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

/// A keystore holding only the flag that hides the AI features (#1518).
class _HiddenAiStorage implements FlutterSecureStorage {
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => key == 'AiAssistHiddenTag' ? 'true' : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final getIt = GetIt.instance;
FakeFavourites? _favourites;

Future<void> _register({bool imperial = false, bool aiHidden = false}) async {
  await getIt.reset();
  if (aiHidden) {
    getIt.registerSingleton<AiCredentialStorage>(
      AiCredentialStorage(_HiddenAiStorage()),
    );
  }
  final config = _FakeGetConfigUsecase(imperial: imperial);
  final search = _FakeSearch();
  getIt.registerFactory<AddMealBloc>(() => AddMealBloc(config));
  getIt.registerFactory<ProductsBloc>(() => ProductsBloc(search, config));
  getIt.registerFactory<FoodBloc>(() => FoodBloc(search, config));
  getIt.registerFactory<RecentMealBloc>(
    () => RecentMealBloc(_FakeGetIntakeUsecase(), config),
  );
  await _favourites?.dispose();
  final favourites = _favourites = FakeFavourites();
  getIt.registerFactory<FavouriteMealBloc>(
    () => FavouriteMealBloc(favourites.get, config),
  );
  getIt.registerFactory<FavouriteToggleBloc>(
    () => FavouriteToggleBloc(favourites.get, favourites.toggle),
  );
}

/// The add-food screen at the root, and a stub for every route it pushes
/// that records what it was asked for.
final _captureAdd = GlobalKey();

Widget _app(
  List<RouteSettings> pushed, {
  MealEntity? initialMeal,
  bool chinese = false,
  bool dark = false,
  double scale = 1,
}) => ChangeNotifierProvider(
  create: (_) => EnergyUnitProvider(),
  child: MaterialApp(
    locale: chinese ? const Locale('zh') : const Locale('en'),
    theme: ThemeData(
      fontFamily: 'Nunito',
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF555E8C),
        brightness: dark ? Brightness.dark : Brightness.light,
      ),
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: RepaintBoundary(key: _captureAdd, child: child!),
    ),
    localizationsDelegates: const [
      S.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: S.supportedLocales,
    onGenerateRoute: (settings) {
      if (settings.name == Navigator.defaultRouteName) {
        return MaterialPageRoute<void>(
          settings: RouteSettings(
            name: settings.name,
            arguments: AddMealScreenArguments(
              AddMealType.breakfastType,
              DateTime(2026, 10, 18),
              initialMeal: initialMeal,
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

Future<void> _captureScreen(
  WidgetTester tester,
  Size size,
  double scale,
) async {
  if (const bool.fromEnvironment('GENERATE_GOAL_PREVIEW')) {
    await tester.runAsync(() async {
      final boundary =
          _captureAdd.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory(const String.fromEnvironment('GOAL_PREVIEW_DIR'));
      await dir.create(recursive: true);
      await File(
        '${dir.path}/add-food-${size.width.toInt()}-'
        '${size.height.toInt()}-$scale.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      img.dispose();
    });
  }
}

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('GENERATE_GOAL_PREVIEW')) return;
    await (FontLoader('CustomIcons')..addFont(
          File(
            'fonts/CustomIcons.ttf',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
    await (FontLoader('Nunito')..addFont(
          File(
            'C:/Windows/Fonts/msyh.ttc',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
    final icons = Platform.environment['FOOD_PREVIEW_ICON_FONT'];
    if (icons != null) {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(File(icons).readAsBytes().then(ByteData.sublistView))).load();
    }
  });
  for (final size in const [Size(375, 812), Size(360, 640), Size(812, 375)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Chinese food search remains usable at $size / $scale', (
        tester,
      ) async {
        await _register();
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final meal = const NutritionLabelDraft(
          name: '原味燕麦片',
          basisQuantity: 100,
          energy: 263,
          energyUnit: 'kcal',
          protein: 8,
          fat: 3,
          carbs: 51,
        ).toMeal();
        await tester.pumpWidget(
          _app(
            [],
            initialMeal: meal,
            chinese: true,
            dark: scale == 2,
            scale: scale,
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.bySemanticsIdentifier('meal-detail-add'),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsIdentifier('meal-detail-add'));
        await tester.pumpAndSettle();
        final search = find.bySemanticsIdentifier('meal-search-field');
        final submit = find.bySemanticsIdentifier('meal-search-submit');
        final recent = find.widgetWithText(ChoiceChip, '最近');
        final review = find.bySemanticsIdentifier('add-meal-review-tray');
        final log = find.bySemanticsIdentifier('add-meal-tray-log');
        expect(search.hitTestable(), findsOneWidget);
        expect(submit.hitTestable(), findsOneWidget);
        expect(recent.hitTestable(), findsOneWidget);
        expect(review.hitTestable(), findsOneWidget);
        expect(log.hitTestable(), findsOneWidget);
        expect(find.text('记录 1 项'), findsOneWidget);
        expect(find.textContaining('"记录'), findsNothing);
        final initialSearch = tester.getRect(search);
        final initialRecent = tester.getRect(recent);
        expect(initialSearch.bottom, lessThanOrEqualTo(initialRecent.top));
        expect(tester.getRect(log).bottom, lessThanOrEqualTo(size.height));
        await _captureScreen(tester, size, scale);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(tester.getRect(search), initialSearch);
        expect(tester.getRect(recent), initialRecent);
        expect(tester.getRect(review).overlaps(tester.getRect(log)), isFalse);
        expect(tester.takeException(), isNull);
        if (size.height > size.width) {
          final field = find.descendant(
            of: search,
            matching: find.byType(TextField),
          );
          await tester.showKeyboard(field);
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          await tester.pumpAndSettle();
          await tester.ensureVisible(log);
          await tester.pumpAndSettle();
          expect(
            tester.getRect(log).bottom,
            lessThanOrEqualTo(size.height - 280),
          );
          expect(tester.takeException(), isNull);
          tester.view.viewInsets = FakeViewPadding.zero;
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
        }
        await tester.tap(review);
        await tester.pumpAndSettle();
        expect(find.text('原味燕麦片'), findsOneWidget);
        await tester.tap(find.bySemanticsIdentifier('add-meal-tray-remove'));
        await tester.pumpAndSettle();
        Navigator.of(tester.element(find.byType(LogTrayList))).pop();
        await tester.pumpAndSettle();
        expect(find.bySemanticsIdentifier('add-meal-tray-log'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await getIt.reset();
        await _favourites?.dispose();
        _favourites = null;
      });
    }
  }

  testWidgets(
    'saved nutrition label opens grams and adds the corrected amount',
    (tester) async {
      await _register();
      final meal = const NutritionLabelDraft(
        name: '原味燕麦片',
        basisQuantity: 30,
        energy: 450,
        energyUnit: 'kJ',
        protein: 3,
        fat: 2,
        carbs: 20,
      ).toMeal();
      await tester.pumpWidget(_app([], initialMeal: meal));
      await tester.pump();
      await tester.pumpAndSettle();

      final quantity = tester.widget<FoodQuantityDialog>(
        find.byType(FoodQuantityDialog),
      );
      expect(quantity.meal.name, '原味燕麦片');
      expect(quantity.asBottomSheet, isTrue);
      expect(find.text('g'), findsWidgets);
      final amount = find.descendant(
        of: find.byType(FoodQuantityDialog),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(amount, '60');
      await tester.tap(find.bySemanticsIdentifier('meal-detail-add'));
      await tester.pumpAndSettle();
      expect(find.byType(FoodQuantityDialog), findsNothing);
      expect(find.bySemanticsIdentifier('add-meal-tray-log'), findsOneWidget);
      final item = tester
          .widget<LogTrayLogButton>(find.byType(LogTrayLogButton))
          .tray
          .items
          .single;
      expect(item.amount, 60);
      expect(item.amountLabel, '60 g');
      expect(item.kcal, closeTo(900 / 4.184, .001));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await getIt.reset();
      await _favourites?.dispose();
      _favourites = null;
    },
  );

  testWidgets('entry methods stay above search while typing', (tester) async {
    await _register();
    await tester.pumpWidget(_app([]));
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsIdentifier('add-meal-method-barcode'),
      findsOneWidget,
    );
    expect(find.bySemanticsIdentifier('add-meal-method-photo'), findsOneWidget);
    expect(
      find.bySemanticsIdentifier('add-meal-method-describe'),
      findsOneWidget,
    );
    expect(find.text(l10nEn.addMealSnapMealLabel), findsOneWidget);
    // The barcode moved from the field's suffix to its own tile, and the
    // second screen's app-bar icon is gone: both now start from here.
    expect(find.bySemanticsIdentifier('meal-search-barcode'), findsNothing);
    expect(find.bySemanticsIdentifier('add-meal-bulk-add'), findsNothing);
  });

  testWidgets('with the AI features hidden, Snap meal goes and Describe '
      'loses its AI badge (#1518)', (tester) async {
    await _register(aiHidden: true);
    await tester.pumpWidget(_app([]));
    await tester.pumpAndSettle();

    expect(find.bySemanticsIdentifier('add-meal-method-photo'), findsNothing);
    expect(find.text(l10nEn.addMealSnapMealLabel), findsNothing);
    expect(
      find.bySemanticsIdentifier('add-meal-method-barcode'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier('add-meal-method-describe'),
      findsOneWidget,
    );
    expect(find.text('AI'), findsNothing);
    expect(find.byIcon(Icons.auto_awesome_rounded), findsNothing);
  });

  testWidgets('Barcode opens the scanner for this meal', (tester) async {
    await _register();
    final pushed = <RouteSettings>[];
    await tester.pumpWidget(_app(pushed));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier('add-meal-method-barcode'));
    await tester.pumpAndSettle();

    expect(pushed.single.name, NavigationOptions.scannerRoute);
    expect(
      (pushed.single.arguments as ScannerScreenArguments).intakeTypeEntity,
      IntakeTypeEntity.breakfast,
    );
  });

  testWidgets('Describe opens its own page without an inline panel', (
    tester,
  ) async {
    await _register(imperial: true);
    final pushed = <RouteSettings>[];
    await tester.pumpWidget(_app(pushed));
    await tester.pumpAndSettle();
    final search = find.bySemanticsIdentifier('meal-search-field');
    expect(
      tester
          .getRect(find.bySemanticsIdentifier('add-meal-method-describe'))
          .bottom,
      lessThan(tester.getRect(search).top),
    );
    await tester.enterText(
      find.descendant(of: search, matching: find.byType(TextField)),
      '美式',
    );
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier('add-meal-method-photo').hitTestable(),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier('add-meal-method-barcode').hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.bySemanticsIdentifier('add-meal-method-describe'));

    await tester.pumpAndSettle();
    expect(pushed.single.name, NavigationOptions.bulkAddRoute);
    final args = pushed.single.arguments as BulkAddScreenArguments;
    expect(args.initialText, isNull);
    expect(args.startWithPhoto, isFalse);
    expect(args.usesImperialUnits, isTrue);
    expect(find.bySemanticsIdentifier('add-meal-describe-input'), findsNothing);
  });

  testWidgets('Snap meal goes to the review screen ready for a photo', (
    tester,
  ) async {
    await _register();
    final pushed = <RouteSettings>[];
    await tester.pumpWidget(_app(pushed));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier('add-meal-method-photo'));
    await tester.pumpAndSettle();

    expect(pushed.single.name, NavigationOptions.bulkAddRoute);
    final args = pushed.single.arguments as BulkAddScreenArguments;
    expect(args.startWithPhoto, isTrue);
    expect(args.initialText, isNull);
  });

  // Portrait and the landscape case #165 was about: the tiles and the open
  // panel scroll inside their own share rather than push the results off.
  for (final size in const [Size(360, 780), Size(780, 360)]) {
    testWidgets('the screen fits with Describe open at $size', (tester) async {
      await _register();
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final pushed = <RouteSettings>[];
      await tester.pumpWidget(_app(pushed));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('add-meal-method-describe'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.bySemanticsIdentifier('add-meal-describe-input'),
        findsNothing,
      );
      expect(pushed.single.name, NavigationOptions.bulkAddRoute);
    });
  }
}
