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
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
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

Widget _wrap(Widget child, {Locale? locale}) {
  return ChangeNotifierProvider(
    create: (_) => EnergyUnitProvider(usesKilojoules: false),
    child: MaterialApp(
      locale: locale,
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
    double carbsIntake = 142.6,
    double carbsGoal = 258.4,
  }) {
    return DashboardWidget(
      totalKcalSupplied: 2800,
      totalKcalBurned: 200,
      totalKcalDaily: 2500,
      tdeeKcal: showPlan ? 2800 : null,
      totalKcalLeft: totalKcalLeft,
      totalCarbsIntake: carbsIntake,
      totalFatsIntake: 30,
      totalProteinsIntake: 60,
      totalCarbsGoal: carbsGoal,
      totalFatsGoal: 69.5,
      totalProteinsGoal: 93,
    );
  }

  for (final size in [
    const Size(320, 640),
    const Size(360, 640),
    const Size(375, 667),
    const Size(812, 375),
  ]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.3, 2.0]) {
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
              lessThan(size.width < 360 ? 480 : 400),
            );
          }
          expect(find.text('碳水'), findsOneWidget);
          expect(find.text('脂肪'), findsOneWidget);
          expect(find.text('蛋白质'), findsOneWidget);
          expect(find.bySemanticsIdentifier('home-kcal-gauge'), findsOneWidget);
          expect(find.bySemanticsIdentifier('home-edit-goals'), findsOneWidget);
          expect(find.text('30/69.5g'), findsOneWidget);
          expect(find.text('142.6/258.4g'), findsOneWidget);
          expect(find.text('余 115.8g'), findsOneWidget);
          expect(find.text('余 39.5g'), findsOneWidget);
          expect(find.text('余 33g'), findsOneWidget);
          final cards = [
            for (final id in ['carbs', 'fat', 'protein'])
              find.descendant(
                of: find.bySemanticsIdentifier('home-macro-$id'),
                matching: find.byType(AppCard),
              ),
          ];
          final expectedSize = tester.getSize(cards.first);
          final progressTops = <double>[];
          final valueTops = <double>[];
          final valueFontSizes = <double>[];
          final remainingTops = <double>[];
          final remainingFontSizes = <double>[];
          for (final card in cards) {
            final actualSize = tester.getSize(card);
            expect(actualSize.width, closeTo(expectedSize.width, 0.01));
            expect(actualSize.height, closeTo(expectedSize.height, 0.01));
            for (final remaining in [false, true]) {
              final value = find.descendant(
                of: card,
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is RichText &&
                      (remaining
                          ? widget.text.toPlainText().startsWith('余 ')
                          : widget.text.toPlainText().contains('/')),
                ),
              );
              final paragraph = tester.renderObject<RenderParagraph>(value);
              (remaining ? remainingFontSizes : valueFontSizes).add(
                paragraph.text.style!.fontSize!,
              );
              final boxes = paragraph.getBoxesForSelection(
                TextSelection(
                  baseOffset: 0,
                  extentOffset: paragraph.text.toPlainText().length,
                ),
              );
              expect(boxes.map((box) => box.top).toSet(), hasLength(1));
              expect(paragraph.didExceedMaxLines, isFalse);
              final bounds = MatrixUtils.transformRect(
                paragraph.getTransformTo(null),
                Offset.zero & paragraph.size,
              );
              final cardBounds = tester.getRect(card);
              expect(bounds.left, greaterThanOrEqualTo(cardBounds.left + 12));
              expect(bounds.right, lessThanOrEqualTo(cardBounds.right - 12));
              (remaining ? remainingTops : valueTops).add(bounds.top);
            }
            progressTops.add(
              tester
                  .getTopLeft(
                    find.descendant(
                      of: card,
                      matching: find.byType(LinearProgressIndicator),
                    ),
                  )
                  .dy,
            );
          }
          for (final tops in [
            progressTops,
            valueTops,
            valueFontSizes,
            remainingTops,
            remainingFontSizes,
          ]) {
            expect(tops[1], closeTo(tops[0], 0.01));
            expect(tops[2], closeTo(tops[0], 0.01));
          }
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

  for (final entry in [
    (intake: 142.6, goal: 258.4, text: '余 115.8g', over: false),
    (intake: 258.4, goal: 258.4, text: '余 0g', over: false),
    (intake: 270.4, goal: 258.4, text: '超 12g', over: true),
    (intake: 0.0, goal: 0.0, text: '余 0g', over: false),
    (intake: 12.0, goal: 0.0, text: '超 12g', over: true),
    (intake: 0.1, goal: 0.3, text: '余 0.2g', over: false),
    (intake: 258.44, goal: 258.4, text: '余 0g', over: false),
  ]) {
    testWidgets('macro balance ${entry.intake}/${entry.goal}', (tester) async {
      await tester.pumpWidget(
        _wrap(
          dashboardWidget(
            totalKcalLeft: 1000,
            carbsIntake: entry.intake,
            carbsGoal: entry.goal,
          ),
          locale: const Locale('zh'),
        ),
      );
      await tester.pumpAndSettle();
      final card = find.bySemanticsIdentifier('home-macro-carbs');
      expect(
        find.descendant(of: card, matching: find.text(entry.text)),
        findsOneWidget,
      );
      final value = tester.widget<RichText>(
        find.descendant(
          of: card,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is RichText && widget.text.toPlainText() == entry.text,
          ),
        ),
      );
      expect(
        value.text.style!.color,
        entry.over
            ? ThemeData().colorScheme.error
            : AppPalette.light.textStrong,
      );
      expect(tester.takeException(), isNull);
    });
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
