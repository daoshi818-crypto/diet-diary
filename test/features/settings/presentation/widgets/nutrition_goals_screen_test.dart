import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/activity_plan.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/domain/entity/nutrition_goal_plan.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_pal_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/nutrition_goals_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/kcal_goal_info_screen.dart';
import 'package:provider/provider.dart';

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
  UserEntity? user,
  double scale = 1,
  bool dark = false,
  bool loadStored = false,
  double tdee = 2400,
  double legacyOffset = 0,
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
    initialData: loadStored
        ? null
        : NutritionGoalsData(
            tdee: tdee,
            plan: plan ?? _plan(),
            user: user,
            legacyOffset: legacyOffset,
          ),
    onSave: onSave ?? (_) async => false,
  ),
);

Finder _id(String value) => find.bySemanticsIdentifier(value);

class _StoredConfig extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async => ConfigEntity(
    true,
    true,
    false,
    AppThemeEntity.system,
    userKcalAdjustment: 200,
  );
}

class _StoredUser extends Fake implements GetUserUsecase {
  @override
  Future<UserEntity> getUserData() async {
    final day = DateTime.now().subtract(const Duration(days: 1));
    return UserEntity(
      birthday: DateTime(day.year - 24, day.month, day.day),
      heightCM: 175,
      weightKG: 68,
      gender: UserGenderEntity.male,
      pal: UserPALEntity.active,
      goal: UserWeightGoalEntity.maintainWeight,
    );
  }
}

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

  testWidgets('2500 minus 200 is 2300; the deficit can be cleared to zero', (
    tester,
  ) async {
    NutritionGoalPlan? saved;
    await tester.pumpWidget(
      _wrap(
        tdee: 2500,
        legacyOffset: 200,
        plan: NutritionGoalPlan(
          effectiveFrom: _day,
          energyMode: EnergyGoalMode.deficit,
          energyValue: 200,
          macroMode: MacroGoalMode.percentage,
          carbs: 50,
          protein: 25,
          fat: 25,
          referenceWeightKg: 68,
        ),
        onSave: (plan) async {
          saved = plan;
          return false;
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2300 kcal'), findsOneWidget);
    expect(
      find.textContaining('TDEE 2500 − 缺口 200 ＝ 目标摄入 2300'),
      findsOneWidget,
    );
    await _edit(tester, 'goals-energy-input', '');
    await _save(tester);
    expect(saved!.energyValue, 0);
    expect(saved!.calorieTarget(2500), 2500);
    await _edit(tester, 'goals-energy-input', '200');
    await _save(tester);
    expect(saved!.calorieTarget(2500), 2300);
  });

  testWidgets(
    'new plan excludes an old +200 offset and defaults to split activity',
    (tester) async {
      GetIt.I.registerSingleton<GetConfigUsecase>(_StoredConfig());
      GetIt.I.registerSingleton<GetUserUsecase>(_StoredUser());
      addTearDown(GetIt.I.reset);
      NutritionGoalPlan? saved;
      await tester.pumpWidget(
        _wrap(
          loadStored: true,
          onSave: (plan) async {
            saved = plan;
            return false;
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('旧版热量调整（200 kcal）不计入本次新目标'), findsOneWidget);
      await _save(tester);
      expect(saved!.energyMode, EnergyGoalMode.deficit);
      expect(saved!.energyValue, 0);
      expect(saved!.tdeeMethod, TdeeMethod.mifflinWeeklyActivity);
      expect(saved!.activityPlan, const ActivityPlan());
      expect(saved!.calorieTarget(1990.5), 1990.5);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'calculation details follow the unsaved deficit and activity plan',
    (tester) async {
      final user = await _StoredUser().getUserData();
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => EnergyUnitProvider(),
          child: _wrap(
            user: user,
            plan: NutritionGoalPlan(
              effectiveFrom: _day,
              energyMode: EnergyGoalMode.deficit,
              energyValue: 200,
              macroMode: MacroGoalMode.percentage,
              carbs: 50,
              protein: 25,
              fat: 25,
              referenceWeightKg: 68,
              tdeeMethod: TdeeMethod.mifflinWeeklyActivity,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _edit(tester, 'goals-energy-input', '350');
      tester.testTextInput.hide();
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await _show(tester, _id('goals-calculation-info'));
      await tester.tap(_id('goals-calculation-info'));
      await tester.pumpAndSettle();
      final screen = tester.widget<KcalGoalInfoScreen>(
        find.byType(KcalGoalInfoScreen),
      );
      expect(screen.breakdown!.plan!.energyValue, 350);
      expect(screen.breakdown!.tdeeKcal, closeTo(1990.5, .001));
      expect(screen.breakdown!.totalKcalGoal, closeTo(1640.5, .001));
      expect(screen.breakdown!.manualKcalAdjustment, 0);
      expect(tester.takeException(), isNull);
    },
  );

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

  for (final scale in [1.0, 2.0]) {
    testWidgets('split TDEE editor fits a small screen at scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final user = await _StoredUser().getUserData();
      await tester.pumpWidget(
        _wrap(
          user: user,
          scale: scale,
          plan: NutritionGoalPlan(
            effectiveFrom: _day,
            energyMode: EnergyGoalMode.deficit,
            energyValue: 200,
            macroMode: MacroGoalMode.percentage,
            carbs: 50,
            protein: 25,
            fat: 25,
            referenceWeightKg: 68,
            tdeeMethod: TdeeMethod.mifflinWeeklyActivity,
            activityPlan: const ActivityPlan(
              exercises: [
                WeeklyExercise(
                  type: PlannedExerciseType.strength,
                  sessionsPerWeek: 2,
                  minutesPerSession: 45,
                ),
                WeeklyExercise(
                  type: PlannedExerciseType.cardio,
                  sessionsPerWeek: 3,
                  minutesPerSession: 35,
                  energySource: ExerciseEnergySource.activeCalories,
                  caloriesPerSession: 250,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _screenshot(tester, 'split-tdee-top-$scale');
      await _show(tester, _id('activity-plan-daily-sedentary'));
      await _screenshot(tester, 'split-tdee-daily-$scale');
      await _show(tester, _id('activity-plan-add-strength'));
      await _screenshot(tester, 'split-tdee-workouts-$scale');
      await tester.tap(_id('activity-plan-add-strength'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _screenshot(tester, 'split-tdee-dialog-$scale');
      Navigator.of(tester.element(_id('weekly-exercise-close'))).pop();
      await tester.pumpAndSettle();
      await _edit(tester, 'goals-energy-input', '200');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'TDEE activity factor and custom deficit update the same saved plan',
    (tester) async {
      final day = DateTime.now().subtract(const Duration(days: 1));
      NutritionGoalPlan? saved;
      await tester.pumpWidget(
        _wrap(
          user: UserEntity(
            birthday: DateTime(day.year - 24, day.month, day.day),
            heightCM: 175,
            weightKG: 68,
            gender: UserGenderEntity.male,
            pal: UserPALEntity.active,
            goal: UserWeightGoalEntity.maintainWeight,
          ),
          plan: NutritionGoalPlan(
            effectiveFrom: _day,
            energyMode: EnergyGoalMode.deficit,
            energyValue: 400,
            macroMode: MacroGoalMode.percentage,
            carbs: 50,
            protein: 25,
            fat: 25,
            referenceWeightKg: 68,
            tdeeMethod: TdeeMethod.mifflinStJeor,
            activityMultiplier: 1.5,
          ),
          onSave: (plan) async {
            saved = plan;
            return false;
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2488 kcal'), findsOneWidget);
      expect(find.text('2088 kcal'), findsOneWidget);
      expect(find.textContaining('记录运动不会再次增加'), findsOneWidget);
      await _show(tester, _id('goals-activity-factor'));
      await _screenshot(tester, 'goals-activity-factor');
      await _edit(tester, 'goals-activity-factor', '1.35');
      await _save(tester);
      expect(saved!.activityMultiplier, 1.35);
      expect(saved!.tdeeMethod, TdeeMethod.mifflinStJeor);
      expect(saved!.energyValue, 400);
    },
  );

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
        expect(
          tester.getRect(_id('goals-save')).bottom,
          lessThanOrEqualTo(640 - 280),
        );
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
