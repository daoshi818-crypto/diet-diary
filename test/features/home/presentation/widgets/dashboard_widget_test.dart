import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/kcal_goal_breakdown_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_breakdown_usecase.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/features/home/presentation/widgets/dashboard_widget.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/kcal_goal_info_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:provider/provider.dart';

import '../../../../fixture/user_entity_fixtures.dart';

final _capture = GlobalKey();
const _visual = bool.fromEnvironment('GENERATE_GOAL_PREVIEW');

class _FakeBreakdownUsecase extends Fake
    implements GetKcalGoalBreakdownUsecase {
  final KcalGoalBreakdownEntity breakdown;

  _FakeBreakdownUsecase(this.breakdown);

  @override
  Future<KcalGoalBreakdownEntity> getBreakdown() async => breakdown;
}

Widget _wrap(Widget child) {
  return ChangeNotifierProvider(
    create: (_) => EnergyUnitProvider(usesKilojoules: false),
    child: MaterialApp(
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: S.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  setUpAll(() async {
    if (_visual) {
      await (FontLoader('Nunito')..addFont(
            File(
              'C:/Windows/Fonts/msyh.ttc',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
      final iconFont = Platform.environment['FOOD_PREVIEW_ICON_FONT'];
      if (iconFont != null) {
        await (FontLoader(
              'MaterialIcons',
            )..addFont(File(iconFont).readAsBytes().then(ByteData.sublistView)))
            .load();
      }
    }
  });
  setUp(() {
    // The gauge navigates to KcalGoalInfoScreen, which pulls its usecase
    // from the locator when none is injected.
    locator.registerSingleton<GetKcalGoalBreakdownUsecase>(
      _FakeBreakdownUsecase(
        KcalGoalBreakdownEntity.compute(
          user: UserEntityFixtures.youngSedentaryMaleWantingToMaintainWeight,
          totalKcalActivities: 0,
        ),
      ),
    );
  });

  tearDown(() {
    GetIt.instance.reset();
  });

  DashboardWidget dashboardWidget({
    required double totalKcalLeft,
    bool showPlan = false,
  }) {
    return DashboardWidget(
      totalKcalSupplied: 2800,
      totalKcalBurned: 200,
      totalKcalDaily: 2500,
      tdeeKcal: showPlan ? 2800 : null,
      totalKcalLeft: totalKcalLeft,
      totalCarbsIntake: 100,
      totalFatsIntake: 30,
      totalProteinsIntake: 60,
      totalCarbsGoal: 375,
      totalFatsGoal: 69.5,
      totalProteinsGoal: 93,
    );
  }

  for (final size in [
    const Size(360, 640),
    const Size(375, 667),
    const Size(812, 375),
  ]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('compact dashboard $size dark=$dark text=$scale', (
          tester,
        ) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            ChangeNotifierProvider(
              create: (_) => EnergyUnitProvider(usesKilojoules: true),
              child: MaterialApp(
                locale: const Locale('zh'),
                localizationsDelegates: const [
                  S.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                supportedLocales: S.supportedLocales,
                theme: buildAppTheme(dark ? AppPalette.dark : AppPalette.light),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: true,
                  ),
                  child: RepaintBoundary(key: _capture, child: child!),
                ),
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: dashboardWidget(
                      totalKcalLeft: -12345,
                      showPlan: true,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (scale == 1) {
            final gauge = find.bySemanticsIdentifier('home-kcal-gauge');
            expect(tester.getSize(gauge).height, lessThanOrEqualTo(130));
            expect(
              tester.getSize(find.byType(DashboardWidget)).height,
              lessThan(400),
            );
          }
          expect(find.text('碳水'), findsOneWidget);
          expect(find.text('脂肪'), findsOneWidget);
          expect(find.text('蛋白质'), findsOneWidget);
          expect(find.bySemanticsIdentifier('home-kcal-gauge'), findsOneWidget);
          expect(find.bySemanticsIdentifier('home-edit-goals'), findsOneWidget);
          expect(find.text('30 / 69.5 g'), findsOneWidget);
          if (_visual && size == const Size(360, 640)) {
            await tester.runAsync(() async {
              final boundary =
                  _capture.currentContext!.findRenderObject()
                      as RenderRepaintBoundary;
              final rendered = await boundary.toImage(pixelRatio: 2);
              final bytes = await rendered.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final dir = const String.fromEnvironment('GOAL_PREVIEW_DIR');
              await File(
                '$dir/dashboard-$dark-$scale.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              rendered.dispose();
            });
          }
        });
      }
    }
  }

  testWidgets(
    'kcal gauge uses the error color when intake exceeds the daily goal',
    (tester) async {
      await tester.pumpWidget(_wrap(dashboardWidget(totalKcalLeft: -300)));
      await tester.pumpAndSettle();

      final gauge = tester.widget<CircularPercentIndicator>(
        find.byType(CircularPercentIndicator),
      );

      expect(gauge.progressColor, ThemeData().colorScheme.error);
    },
  );

  testWidgets(
    'kcal gauge exposes a semantic tap action that opens the goal screen '
    '(regression: excludeSemantics stripped the GestureDetector tap, so '
    'screen readers announced a button that could not be activated)',
    (tester) async {
      final semanticsHandle = tester.ensureSemantics();
      await tester.binding.setSurfaceSize(const Size(500, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_wrap(dashboardWidget(totalKcalLeft: 1900)));
      await tester.pumpAndSettle();

      final gauge = tester.widget<CircularPercentIndicator>(
        find.byType(CircularPercentIndicator),
      );
      expect(gauge.progressColor, ThemeData().colorScheme.primary);

      final gaugeFinder = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.identifier == 'home-kcal-gauge',
      );
      expect(gaugeFinder, findsOneWidget);

      final node = tester.getSemantics(gaugeFinder);
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
        reason:
            'excludeSemantics drops the GestureDetector\'s tap action, '
            'so the Semantics node must register its own onTap',
      );

      // Activate the node the way TalkBack/VoiceOver do — via the semantic
      // action, not a pointer tap.
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pumpAndSettle();

      expect(find.byType(KcalGoalInfoScreen), findsOneWidget);

      semanticsHandle.dispose();
    },
  );
}
