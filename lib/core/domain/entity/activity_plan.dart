import 'package:equatable/equatable.dart';

enum DailyActivityLevel {
  sedentary(1.2),
  light(1.35),
  moderate(1.5),
  strenuous(1.7);

  final double multiplier;
  const DailyActivityLevel(this.multiplier);
}

enum PlannedExerciseType { strength, cardio, other }

enum ExerciseIntensity { light, moderate, vigorous }

enum ExerciseEnergySource { estimated, activeCalories, totalCalories }

class WeeklyExercise extends Equatable {
  final PlannedExerciseType type;
  final double sessionsPerWeek;
  final double minutesPerSession;
  final ExerciseIntensity intensity;
  final ExerciseEnergySource energySource;
  final double? caloriesPerSession;

  const WeeklyExercise({
    required this.type,
    required this.sessionsPerWeek,
    required this.minutesPerSession,
    this.intensity = ExerciseIntensity.moderate,
    this.energySource = ExerciseEnergySource.estimated,
    this.caloriesPerSession,
  });

  double get met => switch (type) {
    PlannedExerciseType.strength => switch (intensity) {
      ExerciseIntensity.light => 3,
      ExerciseIntensity.moderate => 3.5,
      ExerciseIntensity.vigorous => 6,
    },
    PlannedExerciseType.cardio ||
    PlannedExerciseType.other => switch (intensity) {
      ExerciseIntensity.light => 4,
      ExerciseIntensity.moderate => 6,
      ExerciseIntensity.vigorous => 8,
    },
  };

  double activeCaloriesPerSession(double weightKg) {
    final resting = 3.5 * weightKg / 200 * minutesPerSession;
    return switch (energySource) {
      ExerciseEnergySource.estimated => (met - 1) * resting,
      ExerciseEnergySource.activeCalories => caloriesPerSession!,
      ExerciseEnergySource.totalCalories =>
        (caloriesPerSession! - resting).clamp(0, double.infinity),
    };
  }

  double weeklyActiveCalories(double weightKg) =>
      activeCaloriesPerSession(weightKg) * sessionsPerWeek;

  bool get isValid =>
      sessionsPerWeek.isFinite &&
      sessionsPerWeek > 0 &&
      sessionsPerWeek <= 28 &&
      minutesPerSession.isFinite &&
      minutesPerSession > 0 &&
      minutesPerSession <= 720 &&
      (caloriesPerSession == null ||
          (caloriesPerSession!.isFinite &&
              caloriesPerSession! > 0 &&
              caloriesPerSession! <= 10000)) &&
      (energySource == ExerciseEnergySource.estimated ||
          (caloriesPerSession != null &&
              caloriesPerSession!.isFinite &&
              caloriesPerSession! > 0 &&
              caloriesPerSession! <= 10000));

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'sessionsPerWeek': sessionsPerWeek,
    'minutesPerSession': minutesPerSession,
    'intensity': intensity.name,
    'energySource': energySource.name,
    if (caloriesPerSession != null) 'caloriesPerSession': caloriesPerSession,
  };

  factory WeeklyExercise.fromJson(Map<String, dynamic> json) {
    final result = WeeklyExercise(
      type: PlannedExerciseType.values.byName(json['type'] as String),
      sessionsPerWeek: (json['sessionsPerWeek'] as num).toDouble(),
      minutesPerSession: (json['minutesPerSession'] as num).toDouble(),
      intensity: ExerciseIntensity.values.byName(json['intensity'] as String),
      energySource: ExerciseEnergySource.values.byName(
        json['energySource'] as String,
      ),
      caloriesPerSession: (json['caloriesPerSession'] as num?)?.toDouble(),
    );
    if (!result.isValid) throw const FormatException('Invalid weekly exercise');
    return result;
  }

  @override
  List<Object?> get props => [
    type,
    sessionsPerWeek,
    minutesPerSession,
    intensity,
    energySource,
    caloriesPerSession,
  ];
}

class ActivityPlan extends Equatable {
  final DailyActivityLevel dailyActivity;
  final List<WeeklyExercise> exercises;

  const ActivityPlan({
    this.dailyActivity = DailyActivityLevel.sedentary,
    this.exercises = const [],
  });

  double weeklyActiveCalories(double weightKg) => exercises.fold(
    0,
    (total, exercise) => total + exercise.weeklyActiveCalories(weightKg),
  );

  double dailyExerciseCalories(double weightKg) =>
      weeklyActiveCalories(weightKg) / 7;

  bool get isValid =>
      exercises.length <= 14 && exercises.every((e) => e.isValid);

  Map<String, dynamic> toJson() => {
    'dailyActivity': dailyActivity.name,
    'exercises': exercises.map((e) => e.toJson()).toList(),
  };

  factory ActivityPlan.fromJson(Map<String, dynamic> json) {
    final result = ActivityPlan(
      dailyActivity: DailyActivityLevel.values.byName(
        json['dailyActivity'] as String,
      ),
      exercises: List.unmodifiable(
        (json['exercises'] as List).map(
          (item) =>
              WeeklyExercise.fromJson(Map<String, dynamic>.from(item as Map)),
        ),
      ),
    );
    if (!result.isValid) throw const FormatException('Invalid activity plan');
    return result;
  }

  @override
  List<Object?> get props => [dailyActivity, exercises];
}
