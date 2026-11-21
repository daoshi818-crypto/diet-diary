import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/nutrition_goal_plan.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/nutrition_goals_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';

final _capture = GlobalKey();
final _day = DateTime(2026, 11, 21);
const _visual = bool.fromEnvironment('GENERATE_GOAL_PREVIEW');

NutritionGoalPlan _plan({MacroGoalMode mode = MacroGoalMode.perKg}) =>
    NutritionGoalPlan(
      effectiveFrom: _day,
      energyMode: EnergyGoalMode.fixed,
      energyValue: 1800,
      macroMode: mode,
      carbs: mode == MacroGoalMode.perKg ? 3 : 195,
      protein: mode == MacroGoalMode.perKg ? 1.6 : 104,
      fat: mode == MacroGoalMode.perKg ? .7 : 45.5,
      referenceWeightKg: 65,
    );

Widget _wrap({
  NutritionGoalPlan? plan,
  double scale = 1,
  bool dark = false,
  Future<bool> Function(NutritionGoalPlan)? onSave,
}) => MaterialApp(
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
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: RepaintBoundary(key: _capture, child: child!),
  ),
  home: NutritionGoalsScreen(
    initialData: NutritionGoalsData(tdee: 2400, plan: plan ?? _plan()),
    onSave: onSave ?? (_) async => false,
  ),
);

Finder _id(String value) => find.bySemanticsIdentifier(value);

Future<void> _show(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      180,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await Scrollable.ensureVisible(tester.element(finder), alignment: .15);
  await tester.pumpAndSettle();
}

Future<void> _edit(WidgetTester tester, String id, String value) async {
  final field = find.descendant(
    of: _id(id),
    matching: find.byType(TextFormField),
  );
  await _show(tester, field);
  await tester.enterText(field, value);
  await tester.pump();
}

Future<void> _save(WidgetTester tester) async {
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
  await tester.tap(_id('goals-save'));
  await tester.pumpAndSettle();
}

Future<void> _screenshot(WidgetTester tester, String name) async {
  if (!_visual) return;
  await tester.runAsync(() async {
    const folder = String.fromEnvironment(
      'GOAL_PREVIEW_DIR',
      defaultValue: 'preview/goals',
    );
    await Directory(folder).create(recursive: true);
    final boundary =
        _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$folder/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    if (!_visual) return;
    final font = FontLoader('Nunito')
      ..addFont(
        File(
          'C:/Windows/Fonts/msyh.ttc',
        ).readAsBytes().then(ByteData.sublistView),
      );
    await font.load();
    final iconPath = Platform.environment['FOOD_PREVIEW_ICON_FONT'];
    if (iconPath != null) {
      await (FontLoader('MaterialIcons')
            ..addFont(File(iconPath).readAsBytes().then(ByteData.sublistView)))
          .load();
    }
  });

  testWidgets('65 kg coefficients keep the independent 1800 kcal target', (
    tester,
  ) async {
    NutritionGoalPlan? saved;
    await tester.pumpWidget(
      _wrap(
        onSave: (plan) async {
          saved = plan;
          return false;
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1800 kcal'), findsOneWidget);
    expect(find.text('600 kcal'), findsOneWidget);
    await _save(tester);
    expect(saved, isNull);
    expect(find.text('核对营养目标'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.textContaining('195 / 104 / 45.5 g'),
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(_id('goals-keep-values'));
    await tester.tap(_id('goals-keep-values'));
    await tester.pumpAndSettle();
    expect(saved!.calorieTarget(2400), 1800);
    expect(saved!.macroGoals(1800), const MacroGoals(195, 104, 45.5));
  });

  testWidgets('carb correction previews grams and preserves protein and fat', (
    tester,
  ) async {
    NutritionGoalPlan? saved;
    await tester.pumpWidget(
      _wrap(
        onSave: (plan) async {
          saved = plan;
          return false;
        },
      ),
    );
    await tester.pumpAndSettle();
    await _save(tester);
    expect(find.textContaining('243.6 / 104 / 45.5 g'), findsOneWidget);
    await tester.tap(_id('goals-balance-carbs'));
    await tester.pumpAndSettle();
    final grams = saved!.macroGoals(1800);
    expect(grams.carbs, closeTo(243.625, .001));
    expect(grams.protein, 104);
    expect(grams.fat, 45.5);
    expect(grams.energy, closeTo(1800, .001));
    expect(saved!.macroMode, MacroGoalMode.perKg);
  });

  testWidgets('gram goals save independently of the intake target', (
    tester,
  ) async {
    NutritionGoalPlan? saved;
    await tester.pumpWidget(
      _wrap(
        plan: _plan(mode: MacroGoalMode.grams),
        onSave: (plan) async {
          saved = plan;
          return false;
        },
      ),
    );
    await tester.pumpAndSettle();
    await _save(tester);
    await tester.ensureVisible(_id('goals-keep-values'));
    await tester.tap(_id('goals-keep-values'));
    await tester.pumpAndSettle();
    expect(saved!.macroMode, MacroGoalMode.grams);
    expect(saved!.energyValue, 1800);
    expect(saved!.macroGoals(1800), const MacroGoals(195, 104, 45.5));
  });

  testWidgets('percentage goals use the independent calorie target', (
    tester,
  ) async {
    NutritionGoalPlan? saved;
    await tester.pumpWidget(
      _wrap(
        onSave: (plan) async {
          saved = plan;
          return false;
        },
      ),
    );
    await tester.pumpAndSettle();
    await _show(tester, _id('goals-macro-percentage'));
    await tester.tap(_id('goals-macro-percentage'));
    await tester.pumpAndSettle();
    await _edit(tester, 'goals-carbs', '50');
    await _edit(tester, 'goals-protein', '25');
    await _edit(tester, 'goals-fat', '25');
    await _save(tester);
    expect(saved!.macroMode, MacroGoalMode.percentage);
    expect(saved!.macroGoals(1800), const MacroGoals(225, 112.5, 50));
    expect(find.text('核对营养目标'), findsNothing);
  });

  testWidgets('proportional correction keeps all three macro ratios', (
    tester,
  ) async {
    NutritionGoalPlan? saved;
    await tester.pumpWidget(
      _wrap(
        onSave: (plan) async {
          saved = plan;
          return false;
        },
      ),
    );
    await tester.pumpAndSettle();
    await _save(tester);
    await tester.ensureVisible(_id('goals-scale-macros'));
    await tester.tap(_id('goals-scale-macros'));
    await tester.pumpAndSettle();
    final grams = saved!.macroGoals(1800);
    expect(grams.energy, closeTo(1800, .001));
    expect(grams.carbs / grams.protein, closeTo(195 / 104, .001));
    expect(grams.fat / grams.protein, closeTo(45.5 / 104, .001));
  });

  testWidgets(
    'custom deficit changes intake independently of coefficient macros',
    (tester) async {
      NutritionGoalPlan? saved;
      await tester.pumpWidget(
        _wrap(
          onSave: (plan) async {
            saved = plan;
            return false;
          },
        ),
      );
      await tester.pumpAndSettle();
      await _show(tester, _id('goals-energy-deficit'));
      await tester.tap(_id('goals-energy-deficit'));
      await tester.pumpAndSettle();
      await _edit(tester, 'goals-energy-input', '450');
      await _save(tester);
      await tester.ensureVisible(_id('goals-keep-values'));
      await tester.tap(_id('goals-keep-values'));
      await tester.pumpAndSettle();
      expect(saved!.calorieTarget(2400), 1950);
      expect(saved!.macroGoals(1950), const MacroGoals(195, 104, 45.5));
    },
  );

  testWidgets('invalid percentages do not save', (tester) async {
    var saves = 0;
    await tester.pumpWidget(
      _wrap(
        onSave: (_) async {
          saves++;
          return false;
        },
      ),
    );
    await tester.pumpAndSettle();
    await _show(tester, _id('goals-macro-percentage'));
    await tester.tap(_id('goals-macro-percentage'));
    await tester.pumpAndSettle();
    await _edit(tester, 'goals-carbs', '99');
    await _save(tester);
    expect(saves, 0);
    expect(find.text('核对营养目标'), findsNothing);
  });

  testWidgets('zero macros are rejected without a percentage error', (
    tester,
  ) async {
    var saves = 0;
    await tester.pumpWidget(
      _wrap(
        plan: _plan(mode: MacroGoalMode.grams),
        onSave: (_) async {
          saves++;
          return false;
        },
      ),
    );
    await tester.pumpAndSettle();
    for (final id in ['goals-carbs', 'goals-protein', 'goals-fat']) {
      await _edit(tester, id, '0');
    }
    await _save(tester);
    expect(saves, 0);
    expect(find.text('供能比例之和须为 100%'), findsNothing);
    await tester.ensureVisible(find.text('请检查热量、营养素和参考体重；营养素不能全部为 0。'));
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('small screen dark=$dark scale=$scale and keyboard', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_wrap(dark: dark, scale: scale));
        await tester.pumpAndSettle();
        await _screenshot(tester, 'goals-top-$dark-$scale');
        await _edit(tester, 'goals-fat', '.8');
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        await tester.pumpAndSettle();
        await tester.ensureVisible(_id('goals-fat'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        tester.view.viewInsets = FakeViewPadding.zero;
        await tester.pumpAndSettle();
        await _screenshot(tester, 'goals-macros-$dark-$scale');
        await _save(tester);
        expect(find.text('核对营养目标'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _screenshot(tester, 'goals-review-$dark-$scale');
      });
    }
  }
}
