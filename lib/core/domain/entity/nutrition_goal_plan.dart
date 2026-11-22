import 'dart:convert';

import 'package:equatable/equatable.dart';

enum MacroGoalMode { grams, percentage, perKg }

enum EnergyGoalMode { fixed, deficit }

enum TdeeMethod { iom2005, mifflinStJeor }

class MacroGoals extends Equatable {
  final double carbs;
  final double protein;
  final double fat;

  const MacroGoals(this.carbs, this.protein, this.fat);

  double get energy => carbs * 4 + protein * 4 + fat * 9;

  double differenceFrom(double target) => energy - target;

  bool differsSignificantly(double target) =>
      target > 0 && differenceFrom(target).abs() > target * .05 + .01;

  @override
  List<Object?> get props => [carbs, protein, fat];
}

class NutritionGoalPlan extends Equatable {
  final DateTime effectiveFrom;
  final EnergyGoalMode energyMode;
  final double energyValue;
  final MacroGoalMode macroMode;
  final double carbs;
  final double protein;
  final double fat;
  final double referenceWeightKg;
  final TdeeMethod tdeeMethod;
  final double activityMultiplier;

  const NutritionGoalPlan({
    required this.effectiveFrom,
    required this.energyMode,
    required this.energyValue,
    required this.macroMode,
    required this.carbs,
    required this.protein,
    required this.fat,
    required this.referenceWeightKg,
    this.tdeeMethod = TdeeMethod.iom2005,
    this.activityMultiplier = 1.5,
  });

  double calorieTarget(double tdee) =>
      energyMode == EnergyGoalMode.fixed ? energyValue : tdee - energyValue;

  MacroGoals macroGoals(double calorieTarget) => switch (macroMode) {
    MacroGoalMode.grams => MacroGoals(carbs, protein, fat),
    MacroGoalMode.perKg => MacroGoals(
      carbs * referenceWeightKg,
      protein * referenceWeightKg,
      fat * referenceWeightKg,
    ),
    MacroGoalMode.percentage => MacroGoals(
      calorieTarget * carbs / 100 / 4,
      calorieTarget * protein / 100 / 4,
      calorieTarget * fat / 100 / 9,
    ),
  };

  bool get isValid {
    if (![
      energyValue,
      carbs,
      protein,
      fat,
      referenceWeightKg,
      activityMultiplier,
    ].every((v) => v.isFinite)) {
      return false;
    }
    if (activityMultiplier < 1.1 || activityMultiplier > 2.5) return false;
    if (referenceWeightKg <= 0 || referenceWeightKg > 1000) return false;
    if (energyMode == EnergyGoalMode.fixed &&
        (energyValue <= 0 || energyValue > 20000)) {
      return false;
    }
    if (energyMode == EnergyGoalMode.deficit && energyValue.abs() > 10000) {
      return false;
    }
    if ([carbs, protein, fat].any((v) => v < 0 || v > 10000)) return false;
    if (macroMode == MacroGoalMode.percentage &&
        ((carbs + protein + fat - 100).abs() > .01 ||
            [carbs, protein, fat].any((v) => v > 100))) {
      return false;
    }
    return macroGoals(2000).energy > 0;
  }

  NutritionGoalPlan withGrams(MacroGoals grams) {
    final divisor = macroMode == MacroGoalMode.perKg ? referenceWeightKg : 1.0;
    return NutritionGoalPlan(
      effectiveFrom: effectiveFrom,
      energyMode: energyMode,
      energyValue: energyValue,
      macroMode: macroMode == MacroGoalMode.percentage
          ? MacroGoalMode.grams
          : macroMode,
      carbs: grams.carbs / divisor,
      protein: grams.protein / divisor,
      fat: grams.fat / divisor,
      referenceWeightKg: referenceWeightKg,
      tdeeMethod: tdeeMethod,
      activityMultiplier: activityMultiplier,
    );
  }

  NutritionGoalPlan? balanceCarbs(double calorieTarget) {
    final grams = macroGoals(calorieTarget);
    final available = calorieTarget - grams.protein * 4 - grams.fat * 9;
    if (available < 0) return null;
    return withGrams(MacroGoals(available / 4, grams.protein, grams.fat));
  }

  NutritionGoalPlan? scaleMacros(double calorieTarget) {
    final grams = macroGoals(calorieTarget);
    if (calorieTarget <= 0 || grams.energy <= 0) return null;
    final factor = calorieTarget / grams.energy;
    return withGrams(
      MacroGoals(
        grams.carbs * factor,
        grams.protein * factor,
        grams.fat * factor,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'effectiveFrom': _dayKey(effectiveFrom),
    'energyMode': energyMode.name,
    'energyValue': energyValue,
    'macroMode': macroMode.name,
    'carbs': carbs,
    'protein': protein,
    'fat': fat,
    'referenceWeightKg': referenceWeightKg,
    'tdeeMethod': tdeeMethod.name,
    'activityMultiplier': activityMultiplier,
  };

  factory NutritionGoalPlan.fromJson(Map<String, dynamic> json) {
    double number(String key) {
      final value = json[key];
      if (value is! num || !value.isFinite) {
        throw FormatException('Invalid nutrition goal: $key');
      }
      return value.toDouble();
    }

    final date = DateTime.tryParse(json['effectiveFrom'] as String? ?? '');
    if (date == null || _dayKey(date) != json['effectiveFrom']) {
      throw const FormatException('Invalid nutrition goal date');
    }
    final plan = NutritionGoalPlan(
      effectiveFrom: DateTime(date.year, date.month, date.day),
      energyMode: EnergyGoalMode.values.byName(json['energyMode'] as String),
      energyValue: number('energyValue'),
      macroMode: MacroGoalMode.values.byName(json['macroMode'] as String),
      carbs: number('carbs'),
      protein: number('protein'),
      fat: number('fat'),
      referenceWeightKg: number('referenceWeightKg'),
      tdeeMethod: json.containsKey('tdeeMethod')
          ? TdeeMethod.values.byName(json['tdeeMethod'] as String)
          : TdeeMethod.iom2005,
      activityMultiplier: json.containsKey('activityMultiplier')
          ? number('activityMultiplier')
          : 1.5,
    );
    if (!plan.isValid) throw const FormatException('Invalid nutrition goals');
    return plan;
  }

  @override
  List<Object?> get props => [
    effectiveFrom,
    energyMode,
    energyValue,
    macroMode,
    carbs,
    protein,
    fat,
    referenceWeightKg,
    tdeeMethod,
    activityMultiplier,
  ];
}

String _dayKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

class NutritionGoalSchedule extends Equatable {
  final List<NutritionGoalPlan> plans;

  const NutritionGoalSchedule([this.plans = const []]);

  NutritionGoalPlan? onDay(DateTime day) {
    final key = _dayKey(day);
    NutritionGoalPlan? result;
    for (final plan in plans) {
      if (_dayKey(plan.effectiveFrom).compareTo(key) <= 0 &&
          (result == null ||
              plan.effectiveFrom.isAfter(result.effectiveFrom))) {
        result = plan;
      }
    }
    return result;
  }

  NutritionGoalSchedule save(NutritionGoalPlan plan) {
    if (!plan.isValid) throw const FormatException('Invalid nutrition goals');
    final updated = [
      ...plans.where(
        (p) => _dayKey(p.effectiveFrom) != _dayKey(plan.effectiveFrom),
      ),
      plan,
    ]..sort((a, b) => a.effectiveFrom.compareTo(b.effectiveFrom));
    return NutritionGoalSchedule(List.unmodifiable(updated));
  }

  String encode() => jsonEncode({
    'version': 1,
    'plans': plans.map((p) => p.toJson()).toList(),
  });

  static NutritionGoalSchedule decode(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic> ||
          json['version'] != 1 ||
          json['plans'] is! List) {
        throw const FormatException('Invalid nutrition goal schedule');
      }
      var schedule = const NutritionGoalSchedule();
      for (final item in json['plans'] as List) {
        schedule = schedule.save(
          NutritionGoalPlan.fromJson(Map<String, dynamic>.from(item as Map)),
        );
      }
      return schedule;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Invalid nutrition goal schedule');
    }
  }

  static NutritionGoalSchedule tryDecode(String? raw) {
    if (raw == null) return const NutritionGoalSchedule();
    try {
      return decode(raw);
    } on FormatException {
      return const NutritionGoalSchedule();
    }
  }

  @override
  List<Object?> get props => [plans];
}
