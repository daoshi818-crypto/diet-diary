import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/presentation/main_screen.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_screen.dart';
import 'package:opennutritracker/features/activity_detail/presentation/bloc/activity_detail_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:opennutritracker/features/trends/presentation/bloc/trends_bloc.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/usecase/import_workouts_usecase.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/fasting/presentation/bloc/fasting_bloc.dart';
import 'package:opennutritracker/features/home/home_page.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/home/presentation/widgets/dashboard_widget.dart';
import 'package:opennutritracker/features/home/presentation/widgets/intake_vertical_list.dart';
import 'package:opennutritracker/features/home/presentation/widgets/log_water_dialog.dart';
import 'package:opennutritracker/features/home/presentation/widgets/quick_water_widget.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/set_weight_dialog.dart';
import 'package:opennutritracker/generated/l10n.dart';

final _capture = GlobalKey();
final _day = DateTime(2026, 11, 22);

HomeLoadedState _state(int water, {bool showActivity = false}) =>
    HomeLoadedState(
      showDisclaimerDialog: false,
      totalKcalDaily: 2088,
      tdeeKcal: 2488,
      totalKcalLeft: 2088,
      totalKcalSupplied: 0,
      totalKcalBurned: 0,
      totalCarbsIntake: 0,
      totalFatsIntake: 0,
      totalProteinsIntake: 0,
      totalCarbsGoal: 250,
      totalFatsGoal: 60,
      totalProteinsGoal: 120,
      userActivityList: const [],
      breakfastIntakeList: const [],
      lunchIntakeList: const [],
      dinnerIntakeList: const [],
      snackIntakeList: const [],
      usesImperialUnits: false,
      bodyWeightUnit: BodyWeightUnit.kg,
      userWeightKg: 68,
      breakfastKcalTarget: 500,
      lunchKcalTarget: 800,
      dinnerKcalTarget: 788,
      snackKcalTarget: 0,
      breakfastSharePct: 25,
      lunchSharePct: 40,
      dinnerSharePct: 35,
      snackSharePct: 0,
      userGender: UserGenderEntity.male,
      userCaloriesProfile: null,
      waterMlToday: water,
      waterGoalMl: 2000,
      waterIntakes: const [],
      showActivityTracking: showActivity,
    );

class _Home extends Fake implements HomeBloc {
  final _changes = StreamController<HomeState>.broadcast();
  int water = 500;
  bool showActivity = false;
  @override
  HomeState get state => _state(water, showActivity: showActivity);
  @override
  Stream<HomeState> get stream => _changes.stream;
  @override
  DateTime get currentDay => _day;
  @override
  void add(HomeEvent event) {}
  @override
  Future<void> addWaterIntake(int amount) async {
    water += amount;
    _changes.add(state);
  }

  @override
  Future<void> close() => _changes.close();
}

class _Import extends Fake implements ImportWorkoutsUsecase {
  @override
  Future<int> importIfDue() async => 0;
}

class _Meal extends Fake implements MealDetailBloc {}

class _Fasting extends Fake implements FastingBloc {
  @override
  FastingState get state => const FastingIdle();
  @override
  Stream<FastingState> get stream => const Stream.empty();
  @override
  void add(FastingEvent event) {}
  @override
  Future<void> close() async {}
}

class _Config extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async =>
      ConfigEntity(true, true, false, AppThemeEntity.system);
}

class _Diary extends Fake implements DiaryBloc {
  @override
  DiaryState get state => DiaryLoadingState();
  @override
  Stream<DiaryState> get stream => const Stream.empty();
  @override
  DateTime get currentDay => _day;
}

class _Calendar extends Fake implements CalendarDayBloc {}

class _Activity extends Fake implements ActivityDetailBloc {}

class _Profile extends Fake implements ProfileBloc {
  @override
  ProfileState get state => ProfileLoadingState();
  @override
  Stream<ProfileState> get stream => const Stream.empty();
}

class _Trends extends Fake implements TrendsBloc {
  @override
  TrendsState get state => const TrendsLoading();
  @override
  Stream<TrendsState> get stream => const Stream.empty();
  @override
  void add(TrendsEvent event) {}
}

void main() {
  late _Home home;
  setUpAll(() async {
    if (!const bool.fromEnvironment('GENERATE_GOAL_PREVIEW')) return;
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
  setUp(() {
    home = _Home();
    GetIt.I.registerSingleton<HomeBloc>(home);
    GetIt.I.registerSingleton<ImportWorkoutsUsecase>(_Import());
    GetIt.I.registerFactory<MealDetailBloc>(_Meal.new);
    GetIt.I.registerFactory<FastingBloc>(_Fasting.new);
  });
  tearDown(() async {
    await home.close();
    await GetIt.I.reset();
  });

  for (final size in [const Size(375, 667), const Size(812, 375)]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'main shell $size dark=$dark keeps controls clear at $scale',
          (tester) async {
            home.showActivity = true;
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
            tester.view.viewPadding = const FakeViewPadding(
              top: 24,
              bottom: 34,
            );
            addTearDown(tester.view.reset);
            GetIt.I.registerSingleton<GetConfigUsecase>(_Config());
            GetIt.I.registerSingleton<DiaryBloc>(_Diary());
            GetIt.I.registerSingleton<CalendarDayBloc>(_Calendar());
            GetIt.I.registerSingleton<ActivityDetailBloc>(_Activity());
            GetIt.I.registerSingleton<ProfileBloc>(_Profile());
            GetIt.I.registerSingleton<TrendsBloc>(_Trends());
            final pushed = <RouteSettings>[];
            await tester.pumpWidget(
              ChangeNotifierProvider(
                create: (_) => EnergyUnitProvider(),
                child: MaterialApp(
                  locale: const Locale('zh'),
                  localizationsDelegates: const [
                    S.delegate,
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  supportedLocales: S.supportedLocales,
                  theme: buildAppTheme(
                    dark ? AppPalette.dark : AppPalette.light,
                  ),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: RepaintBoundary(key: _capture, child: child!),
                  ),
                  onGenerateRoute: (settings) {
                    pushed.add(settings);
                    return MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(),
                    );
                  },
                  home: const MainScreen(),
                ),
              ),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 500));
            final water = find.bySemanticsIdentifier('home-quick-water');
            final food = find.bySemanticsIdentifier('home-quick-food');
            expect(tester.getSize(water), const Size(48, 48));
            expect(tester.getSize(food), const Size(48, 48));
            final add = find.bySemanticsIdentifier('fab-add-item');
            expect(add, findsOneWidget);
            expect(
              tester.getRect(food).center.dx,
              tester.getRect(water).center.dx,
            );
            expect(
              tester.getRect(food).bottom,
              lessThanOrEqualTo(tester.getRect(water).top),
            );
            final navBar = find.byType(BottomAppBar);
            expect(find.ancestor(of: food, matching: navBar), findsNothing);
            expect(find.ancestor(of: water, matching: navBar), findsNothing);
            expect(tester.getRect(food).left, greaterThan(size.width / 2));
            expect(
              tester.getRect(water).bottom + 8,
              lessThanOrEqualTo(tester.getRect(navBar).top),
            );
            expect(
              tester.getRect(food).top,
              greaterThanOrEqualTo(tester.getRect(find.byType(HomePage)).top),
            );
            expect(tester.getRect(add).overlaps(tester.getRect(food)), isFalse);
            expect(
              tester.getRect(add).overlaps(tester.getRect(water)),
              isFalse,
            );
            final nav = ['nav-home', 'nav-diary', 'nav-trends', 'nav-you'];
            expect(
              tester.getSize(find.byType(BottomAppBar)).height,
              closeTo(78 + 34 + 12 * (scale - 1), .01),
            );
            for (final id in nav) {
              final rect = tester.getRect(find.bySemanticsIdentifier(id));
              expect(rect.bottom, lessThanOrEqualTo(size.height - 34));
              expect(rect.width, closeTo((size.width - 56) / 4, .01));
              expect(rect.height, greaterThanOrEqualTo(48));
            }
            if (const bool.fromEnvironment('GENERATE_GOAL_PREVIEW')) {
              await tester.runAsync(() async {
                final dir = Directory(
                  const String.fromEnvironment('GOAL_PREVIEW_DIR'),
                );
                await dir.create(recursive: true);
                final boundary =
                    _capture.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary;
                final img = await boundary.toImage(pixelRatio: 1.5);
                final bytes = await img.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await File(
                  '${dir.path}/main-shell-${size.width.toInt()}-$dark-$scale.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
                img.dispose();
              });
            }
            final scrollable = find
                .descendant(
                  of: find.byType(HomePage),
                  matching: find.byType(Scrollable),
                )
                .first;
            final dinner = find.byWidgetPredicate(
              (widget) => widget is IntakeVerticalList && widget.title == '晚餐',
            );
            await tester.scrollUntilVisible(
              dinner,
              180,
              scrollable: scrollable,
            );
            final lastMenu = find.descendant(
              of: dinner,
              matching: find.bySemanticsIdentifier('intake-section-menu'),
            );
            await Scrollable.ensureVisible(
              tester.element(lastMenu),
              alignment: 0,
            );
            await tester.pump();
            expect(lastMenu.hitTestable(), findsOneWidget);
            expect(
              tester.getRect(lastMenu).overlaps(tester.getRect(food)),
              isFalse,
            );
            expect(
              tester.getRect(lastMenu).overlaps(tester.getRect(water)),
              isFalse,
            );
            final mealMenuX = tester.getCenter(lastMenu).dx;
            final position = tester.state<ScrollableState>(scrollable).position;
            position.jumpTo(position.maxScrollExtent);
            await tester.pump();
            final activityMenu = find.bySemanticsIdentifier(
              'activity-section-menu',
            );
            expect(activityMenu.hitTestable(), findsOneWidget);
            expect(tester.getCenter(activityMenu).dx, closeTo(mealMenuX, .01));
            expect(
              tester.getRect(activityMenu).overlaps(tester.getRect(food)),
              isFalse,
            );
            expect(
              tester.getRect(activityMenu).overlaps(tester.getRect(water)),
              isFalse,
            );
            await tester.tap(add);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 500));
            expect(
              find.byKey(const ValueKey('logging-hub-panel')),
              findsOneWidget,
            );
            Navigator.of(
              tester.element(find.byKey(const ValueKey('logging-hub-panel'))),
            ).pop();
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 500));
            await tester.tapAt(tester.getTopLeft(water) + const Offset(3, 3));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 500));
            expect(find.byType(LogWaterDialog), findsOneWidget);
            await tester.tap(find.bySemanticsIdentifier('log-water-save'));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 500));
            expect(home.water, 750);
            await tester.tap(food);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 500));
            expect(pushed.single.name, NavigationOptions.addMealRoute);
            expect(
              (pushed.single.arguments as AddMealScreenArguments).day,
              _day,
            );
            final navigator = tester.state<NavigatorState>(
              find.byType(Navigator).first,
            );
            navigator.pop();
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 500));
            await tester.tap(find.bySemanticsIdentifier('nav-diary'));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 500));
            await tester.tap(find.bySemanticsIdentifier('fab-add-item'));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 500));
            final panel = find.byKey(const ValueKey('logging-hub-panel'));
            final close = find.bySemanticsIdentifier('logging-hub-close');
            expect(tester.getRect(panel).top, greaterThanOrEqualTo(0));
            expect(
              tester.getRect(panel).bottom,
              lessThanOrEqualTo(tester.getRect(close).top - 8),
            );
            expect(
              tester.getRect(close).bottom,
              lessThanOrEqualTo(size.height),
            );
            expect(close.hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
          },
        );
      }
    }
  }

  for (final size in [const Size(375, 667), const Size(812, 375)]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'real home fits $size dark=$dark scale=$scale and keeps water usable',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            await tester.pumpWidget(
              ChangeNotifierProvider(
                create: (_) => EnergyUnitProvider(),
                child: MaterialApp(
                  locale: const Locale('zh'),
                  localizationsDelegates: const [
                    S.delegate,
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  supportedLocales: S.supportedLocales,
                  theme: buildAppTheme(
                    dark ? AppPalette.dark : AppPalette.light,
                  ),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(scale),
                      disableAnimations: true,
                    ),
                    child: RepaintBoundary(key: _capture, child: child!),
                  ),
                  home: const Scaffold(body: HomePage()),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final water = find.bySemanticsIdentifier('home-water-chip');
            final weight = find.bySemanticsIdentifier('home-weight-chip');
            expect(water.hitTestable(), findsOneWidget);
            expect(weight.hitTestable(), findsOneWidget);
            expect(
              tester.getRect(water).bottom,
              lessThanOrEqualTo(
                tester.getRect(find.byType(DashboardWidget)).top,
              ),
            );
            if (const bool.fromEnvironment('GENERATE_GOAL_PREVIEW')) {
              await tester.runAsync(() async {
                final dir = Directory(
                  const String.fromEnvironment('GOAL_PREVIEW_DIR'),
                );
                await dir.create(recursive: true);
                final boundary =
                    _capture.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary;
                final img = await boundary.toImage(pixelRatio: 1.5);
                final data = await img.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await File(
                  '${dir.path}/home-${size.width.toInt()}-$dark-$scale.png',
                ).writeAsBytes(data!.buffer.asUint8List());
                img.dispose();
              });
            }
            await tester.tap(water);
            await tester.pumpAndSettle();
            expect(find.byType(LogWaterDialog), findsOneWidget);
            await tester.tap(find.bySemanticsIdentifier('log-water-save'));
            await tester.pumpAndSettle();
            expect(home.water, 750);
            expect(
              tester
                  .widget<QuickWaterWidget>(find.byType(QuickWaterWidget))
                  .waterMlToday,
              750,
            );
            await tester.tap(weight);
            await tester.pumpAndSettle();
            expect(find.byType(SetWeightDialog), findsOneWidget);
            await tester.tap(find.text('取消'));
            await tester.pumpAndSettle();
            final meal = find.byWidgetPredicate(
              (widget) => widget is IntakeVerticalList && widget.title == '早餐',
            );
            await tester.scrollUntilVisible(
              meal,
              140,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pumpAndSettle();
            expect(
              tester.getSize(meal).height,
              lessThanOrEqualTo(scale > 1 ? 112 : 100),
            );
            final title = find.descendant(of: meal, matching: find.text('早餐'));
            expect(
              tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
              isFalse,
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
          },
        );
      }
    }
  }
}
