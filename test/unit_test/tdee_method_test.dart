import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/calories_profile_entity.dart';
import 'package:opennutritracker/core/domain/entity/kcal_goal_breakdown_entity.dart';
import 'package:opennutritracker/core/domain/entity/nutrition_goal_plan.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_pal_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/utils/calc/calorie_goal_calc.dart';
import 'package:opennutritracker/core/utils/calc/tdee_calc.dart';

UserEntity _user(UserGenderEntity gender, [CaloriesProfileEntity? profile]) {
  final yesterday = DateTime.now().subtract(const Duration(days: 1));
  return UserEntity(
    birthday: DateTime(yesterday.year - 24, yesterday.month, yesterday.day),
    heightCM: 175,
    weightKG: 68,
    gender: gender,
    pal: UserPALEntity.active,
    goal: UserWeightGoalEntity.maintainWeight,
    caloriesProfile: profile,
  );
}

NutritionGoalPlan _plan([double factor = 1.5]) => NutritionGoalPlan(
  effectiveFrom: DateTime(2026, 11, 22),
  energyMode: EnergyGoalMode.deficit,
  energyValue: 400,
  macroMode: MacroGoalMode.grams,
  carbs: 250,
  protein: 120,
  fat: 60,
  referenceWeightKg: 68,
  tdeeMethod: TdeeMethod.mifflinStJeor,
  activityMultiplier: factor,
);

void main() {
  test(
    'user case exposes IOM and Mifflin difference without target hardcoding',
    () {
      final user = _user(UserGenderEntity.male);
      expect(user.age, 24);
      expect(TDEECalc.restingMifflinKcal(user), 1658.75);
      expect(TDEECalc.getTDEEKcalMifflin(user, 1.5), 2488.125);
      expect(TDEECalc.getTDEEKcalIOM2005(user), closeTo(2974.9495, .001));
      expect(CalorieGoalCalc.getTdee(user, plan: _plan()), 2488.125);
      expect(
        CalorieGoalCalc.getTotalKcalGoal(user, 0, plan: _plan()),
        2088.125,
      );
      expect(
        CalorieGoalCalc.getTotalKcalGoal(user, 600, plan: _plan()),
        2088.125,
      );
      final breakdown = KcalGoalBreakdownEntity.compute(
        user: user,
        totalKcalActivities: 600,
        plan: _plan(),
      );
      expect(breakdown.tdeeKcal, 2488.125);
      expect(breakdown.totalKcalGoal, 2088.125);
    },
  );

  test('female and profile variants use their own resting offsets', () {
    expect(
      TDEECalc.restingMifflinKcal(_user(UserGenderEntity.female)),
      1492.75,
    );
    expect(
      TDEECalc.restingMifflinKcal(_user(UserGenderEntity.nonBinary)),
      1575.75,
    );
    expect(
      TDEECalc.restingMifflinKcal(
        _user(
          UserGenderEntity.nonBinary,
          CaloriesProfileEntity.testosteroneTypical,
        ),
      ),
      1658.75,
    );
    expect(
      TDEECalc.restingMifflinKcal(
        _user(
          UserGenderEntity.nonBinary,
          CaloriesProfileEntity.estrogenTypical,
        ),
      ),
      1492.75,
    );
  });

  test('formula settings survive backup and macro balancing', () {
    final plan = _plan(1.45);
    final encoded = const NutritionGoalSchedule().save(plan).encode();
    expect(NutritionGoalSchedule.decode(encoded).plans.single, plan);
    for (final p in [plan.balanceCarbs(2000)!, plan.scaleMacros(2000)!]) {
      expect(p.tdeeMethod, TdeeMethod.mifflinStJeor);
      expect(p.activityMultiplier, 1.45);
      expect(p.energyValue, 400);
    }
    final legacy = plan.toJson()
      ..remove('tdeeMethod')
      ..remove('activityMultiplier');
    expect(NutritionGoalPlan.fromJson(legacy).tdeeMethod, TdeeMethod.iom2005);
  });

  test('invalid factors never become saved plans or calculated results', () {
    for (final factor in [1.09, 2.51, double.nan, double.infinity]) {
      expect(_plan(factor).isValid, isFalse);
      expect(
        () => TDEECalc.getTDEEKcalMifflin(_user(UserGenderEntity.male), factor),
        throwsArgumentError,
      );
    }
  });
}
