import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/nutrition_goal_plan.dart';

void main() {
  NutritionGoalPlan plan({
    MacroGoalMode mode = MacroGoalMode.perKg,
    EnergyGoalMode energyMode = EnergyGoalMode.deficit,
    double energy = 400,
    double carbs = 3,
    double protein = 1.6,
    double fat = .7,
    DateTime? date,
  }) => NutritionGoalPlan(
    effectiveFrom: date ?? DateTime(2026, 11, 21),
    energyMode: energyMode,
    energyValue: energy,
    macroMode: mode,
    carbs: carbs,
    protein: protein,
    fat: fat,
    referenceWeightKg: 65,
  );

  test(
    '65 kg coefficients do not overwrite the independent calorie target',
    () {
      final p = plan();
      final target = p.calorieTarget(2200);
      final macros = p.macroGoals(target);
      expect(target, 1800);
      expect(macros, const MacroGoals(195, 104, 45.5));
      expect(macros.energy, 1605.5);
      expect(macros.differsSignificantly(target), isTrue);
      expect(macros.differenceFrom(target), -194.5);
    },
  );

  test('percentage mode follows calories while grams stay fixed', () {
    final percentage = plan(
      mode: MacroGoalMode.percentage,
      carbs: 50,
      protein: 25,
      fat: 25,
    );
    expect(percentage.macroGoals(1800).energy, closeTo(1800, .0001));
    final fixed = plan(
      mode: MacroGoalMode.grams,
      carbs: 195,
      protein: 104,
      fat: 45.5,
    );
    expect(fixed.macroGoals(1800), fixed.macroGoals(2200));
  });

  test(
    'carb repair keeps protein, fat, reference weight and energy settings',
    () {
      final fixed = plan().balanceCarbs(1800)!;
      final macros = fixed.macroGoals(1800);
      expect(macros.protein, 104);
      expect(macros.fat, 45.5);
      expect(macros.carbs, closeTo(243.625, .0001));
      expect(macros.energy, closeTo(1800, .0001));
      expect(fixed.macroMode, MacroGoalMode.perKg);
      expect(fixed.energyValue, 400);
      expect(fixed.referenceWeightKg, 65);
    },
  );

  test('repair never creates negative carbohydrate targets', () {
    expect(plan().balanceCarbs(500), isNull);
  });

  test('scaling preserves the macro ratio and coefficient mode', () {
    final p = plan();
    final corrected = p.scaleMacros(1800)!;
    final grams = corrected.macroGoals(1800);
    expect(grams.energy, closeTo(1800, .0001));
    expect(grams.protein / grams.fat, closeTo(104 / 45.5, .0001));
    expect(corrected.macroMode, MacroGoalMode.perKg);
  });

  test('direct calories are independent of TDEE', () {
    final p = plan(energyMode: EnergyGoalMode.fixed, energy: 1800);
    expect(p.calorieTarget(2200), 1800);
    expect(p.calorieTarget(2600), 1800);
  });

  test('schedule round-trips, replaces today, and preserves prior targets', () {
    final old = plan(date: DateTime(2026, 11, 1), energy: 300);
    final today = plan();
    final schedule = const NutritionGoalSchedule().save(old).save(today);
    final reopened = NutritionGoalSchedule.decode(schedule.encode());
    expect(reopened.onDay(DateTime(2026, 10, 31)), isNull);
    expect(reopened.onDay(DateTime(2026, 11, 20)), old);
    expect(reopened.onDay(DateTime(2026, 11, 21)), today);
    expect(reopened.save(plan(energy: 500)).plans.length, 2);
  });

  test('invalid and non-finite values cannot become saved goals', () {
    expect(plan(energy: double.nan).isValid, isFalse);
    expect(plan(mode: MacroGoalMode.percentage).isValid, isFalse);
    expect(plan(carbs: -1).isValid, isFalse);
    expect(
      () => NutritionGoalSchedule.decode('{"version":2,"plans":[]}'),
      throwsFormatException,
    );
    expect(NutritionGoalSchedule.tryDecode('broken').plans, isEmpty);
  });
}
