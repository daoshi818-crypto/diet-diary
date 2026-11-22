import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/activity_plan.dart';
import 'package:opennutritracker/core/domain/entity/kcal_goal_breakdown_entity.dart';
import 'package:opennutritracker/core/domain/entity/nutrition_goal_plan.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_pal_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/utils/calc/calorie_goal_calc.dart';
import 'package:opennutritracker/core/utils/calc/tdee_calc.dart';
import 'package:opennutritracker/features/settings/domain/goal_settings_backup.dart';

UserEntity _user() {
  final yesterday = DateTime.now().subtract(const Duration(days: 1));
  return UserEntity(
    birthday: DateTime(yesterday.year - 24, yesterday.month, yesterday.day),
    heightCM: 175,
    weightKG: 68,
    gender: UserGenderEntity.male,
    pal: UserPALEntity.active,
    goal: UserWeightGoalEntity.maintainWeight,
  );
}

const _cardio = WeeklyExercise(
  type: PlannedExerciseType.cardio,
  sessionsPerWeek: 3,
  minutesPerSession: 35,
  energySource: ExerciseEnergySource.activeCalories,
  caloriesPerSession: 250,
);

NutritionGoalPlan _plan(ActivityPlan activity, {double deficit = 200}) =>
    NutritionGoalPlan(
      effectiveFrom: DateTime(2026, 11, 22),
      energyMode: EnergyGoalMode.deficit,
      energyValue: deficit,
      macroMode: MacroGoalMode.percentage,
      carbs: 50,
      protein: 25,
      fat: 25,
      referenceWeightKg: 68,
      tdeeMethod: TdeeMethod.mifflinWeeklyActivity,
      activityPlan: activity,
    );

void main() {
  test(
    'office baseline is 1.2, independent of the old combined active category',
    () {
      final user = _user();
      final plan = _plan(const ActivityPlan());
      expect(TDEECalc.restingMifflinKcal(user), 1658.75);
      expect(CalorieGoalCalc.getTdee(user, plan: plan), 1990.5);
      expect(plan.activityPlan.exercises, isEmpty);
    },
  );

  test(
    'three cardio sessions average known active calories across seven days',
    () {
      const activity = ActivityPlan(exercises: [_cardio]);
      expect(activity.weeklyActiveCalories(68), 750);
      expect(activity.dailyExerciseCalories(68), closeTo(750 / 7, .0001));
      expect(
        CalorieGoalCalc.getTdee(_user(), plan: _plan(activity)),
        closeTo(1990.5 + 750 / 7, .0001),
      );
    },
  );

  test(
    'strength MET uses the whole session with the resting component removed',
    () {
      const exercise = WeeklyExercise(
        type: PlannedExerciseType.strength,
        sessionsPerWeek: 2,
        minutesPerSession: 45,
      );
      expect(exercise.met, 3.5);
      expect(exercise.activeCaloriesPerSession(68), closeTo(133.875, .0001));
      const activity = ActivityPlan(exercises: [exercise, _cardio]);
      expect(
        activity.dailyExerciseCalories(68),
        closeTo((267.75 + 750) / 7, .0001),
      );
    },
  );

  test(
    'total calories subtract resting once; active calories are used directly',
    () {
      const total = WeeklyExercise(
        type: PlannedExerciseType.cardio,
        sessionsPerWeek: 3,
        minutesPerSession: 35,
        energySource: ExerciseEnergySource.totalCalories,
        caloriesPerSession: 250,
      );
      expect(total.activeCaloriesPerSession(68), closeTo(250 - 41.65, .0001));
      expect(_cardio.activeCaloriesPerSession(68), 250);
      const low = WeeklyExercise(
        type: PlannedExerciseType.other,
        sessionsPerWeek: 1,
        minutesPerSession: 60,
        energySource: ExerciseEnergySource.totalCalories,
        caloriesPerSession: 10,
      );
      expect(low.activeCaloriesPerSession(68), 0);
    },
  );

  test('deficit, old +200 offset and logged exercise never get combined', () {
    final user = _user();
    final plan = _plan(const ActivityPlan(exercises: [_cardio]));
    final tdee = CalorieGoalCalc.getTdee(user, plan: plan);
    for (final logged in [0.0, 200.0, 700.0]) {
      expect(
        CalorieGoalCalc.getTotalKcalGoal(
          user,
          logged,
          plan: plan,
          kcalUserAdjustment: 200,
        ),
        closeTo(tdee - 200, .0001),
      );
    }
    expect(plan.calorieTarget(2500), 2300);
    expect(_plan(const ActivityPlan(), deficit: 0).calorieTarget(2500), 2500);
    expect(
      _plan(const ActivityPlan(), deficit: -200).calorieTarget(2500),
      2700,
    );
    final breakdown = KcalGoalBreakdownEntity.compute(
      user: user,
      totalKcalActivities: 600,
      userKcalAdjustment: 200,
      plan: plan,
    );
    expect(breakdown.manualKcalAdjustment, 0);
    expect(breakdown.effectiveAdjustmentKcal, closeTo(-200, .0001));
    expect(breakdown.totalKcalGoal, closeTo(tdee - 200, .0001));
  });

  test(
    'training changes with current weight; reference macro weight stays separate',
    () {
      const activity = ActivityPlan(
        exercises: [
          WeeklyExercise(
            type: PlannedExerciseType.strength,
            sessionsPerWeek: 2,
            minutesPerSession: 45,
          ),
        ],
      );
      final user = _user();
      final plan = _plan(activity);
      user.weightKG = 80;
      expect(
        CalorieGoalCalc.getTdee(user, plan: plan),
        TDEECalc.restingMifflinKcal(user) * 1.2 +
            activity.dailyExerciseCalories(80),
      );
      expect(plan.referenceWeightKg, 68);
    },
  );

  test(
    'weekly plan survives schedule, backup, macro correction and dated history',
    () {
      final plan = _plan(const ActivityPlan(exercises: [_cardio]));
      final old = NutritionGoalPlan(
        effectiveFrom: DateTime(2026, 11, 1),
        energyMode: EnergyGoalMode.fixed,
        energyValue: 2200,
        macroMode: MacroGoalMode.percentage,
        carbs: 50,
        protein: 25,
        fat: 25,
        referenceWeightKg: 68,
      );
      final schedule = const NutritionGoalSchedule().save(old).save(plan);
      final restored = NutritionGoalSchedule.decode(schedule.encode());
      expect(restored.onDay(DateTime(2026, 11, 10)), old);
      expect(restored.onDay(DateTime(2026, 11, 22)), plan);
      final backup = GoalSettingsBackup.fromJson(
        GoalSettingsBackup(
          nutritionGoalScheduleJson: schedule.encode(),
          kcalAdjustment: 200,
        ).toJson(),
      )!;
      expect(
        NutritionGoalSchedule.decode(backup.nutritionGoalScheduleJson!),
        schedule,
      );
      for (final adjusted in [
        plan.balanceCarbs(2000)!,
        plan.scaleMacros(2000)!,
      ]) {
        expect(adjusted.activityPlan, plan.activityPlan);
        expect(adjusted.tdeeMethod, TdeeMethod.mifflinWeeklyActivity);
      }
      final legacy = old.toJson()..remove('activityPlan');
      expect(NutritionGoalPlan.fromJson(legacy), old);
    },
  );

  test('missing or corrupt training data fails closed', () {
    final raw = _plan(const ActivityPlan(exercises: [_cardio])).toJson();
    expect(
      () => NutritionGoalPlan.fromJson({...raw}..remove('activityPlan')),
      throwsFormatException,
    );
    final bad = Map<String, dynamic>.from(_cardio.toJson())
      ..['sessionsPerWeek'] = 0;
    expect(() => WeeklyExercise.fromJson(bad), throwsFormatException);
    for (final number in [0.0, -1.0, double.nan, double.infinity, 29.0]) {
      expect(
        WeeklyExercise(
          type: PlannedExerciseType.strength,
          sessionsPerWeek: number,
          minutesPerSession: 45,
        ).isValid,
        isFalse,
      );
    }
    expect(
      const WeeklyExercise(
        type: PlannedExerciseType.cardio,
        sessionsPerWeek: 3,
        minutesPerSession: 35,
        energySource: ExerciseEnergySource.activeCalories,
      ).isValid,
      isFalse,
    );
  });
}
