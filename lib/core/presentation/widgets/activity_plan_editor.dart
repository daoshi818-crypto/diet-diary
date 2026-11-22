import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:opennutritracker/core/domain/entity/activity_plan.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/generated/l10n.dart';

String dailyActivityTitle(S s, DailyActivityLevel level) => switch (level) {
  DailyActivityLevel.sedentary => s.dailyActivitySedentary,
  DailyActivityLevel.light => s.dailyActivityLight,
  DailyActivityLevel.moderate => s.dailyActivityModerate,
  DailyActivityLevel.strenuous => s.dailyActivityStrenuous,
};

String exerciseTypeTitle(S s, PlannedExerciseType type) => switch (type) {
  PlannedExerciseType.strength => s.plannedExerciseStrength,
  PlannedExerciseType.cardio => s.plannedExerciseCardio,
  PlannedExerciseType.other => s.plannedExerciseOther,
};

String _intensityTitle(S s, ExerciseIntensity intensity) => switch (intensity) {
  ExerciseIntensity.light => s.exerciseIntensityLight,
  ExerciseIntensity.moderate => s.exerciseIntensityModerate,
  ExerciseIntensity.vigorous => s.exerciseIntensityVigorous,
};

String _energySourceTitle(S s, ExerciseEnergySource source) => switch (source) {
  ExerciseEnergySource.estimated => s.exerciseEnergyEstimated,
  ExerciseEnergySource.activeCalories => s.exerciseEnergyActive,
  ExerciseEnergySource.totalCalories => s.exerciseEnergyTotal,
};

String _number(double value) =>
    value.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');

class ActivityPlanEditor extends StatelessWidget {
  final ActivityPlan value;
  final ValueChanged<ActivityPlan> onChanged;
  final double? weightKg;
  final bool dailyActivitySelected;
  final ValueChanged<DailyActivityLevel>? onDailySelected;
  final String dailyIdentifierPrefix;

  const ActivityPlanEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.weightKg,
    this.dailyActivitySelected = true,
    this.onDailySelected,
    this.dailyIdentifierPrefix = 'activity-plan-daily',
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final colors = Theme.of(context).colorScheme;
    const suffixes = ['sedentary', 'low', 'active', 'very'];
    final descriptions = [
      s.dailyActivitySedentaryHint,
      s.dailyActivityLightHint,
      s.dailyActivityModerateHint,
      s.dailyActivityStrenuousHint,
    ];
    final hasWeight = weightKg != null && weightKg!.isFinite && weightKg! > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          s.dailyActivityTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(s.dailyActivityHint),
        const SizedBox(height: 12),
        for (final level in DailyActivityLevel.values) ...[
          Semantics(
            identifier: '$dailyIdentifierPrefix-${suffixes[level.index]}',
            selected: dailyActivitySelected && value.dailyActivity == level,
            child: AppCard(
              color: dailyActivitySelected && value.dailyActivity == level
                  ? colors.primaryContainer
                  : null,
              padding: const EdgeInsets.all(12),
              onTap: () {
                onDailySelected?.call(level);
                onChanged(
                  ActivityPlan(
                    dailyActivity: level,
                    exercises: value.exercises,
                  ),
                );
              },
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${dailyActivityTitle(s, level)} · ×${level.multiplier}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color:
                                    dailyActivitySelected &&
                                        value.dailyActivity == level
                                    ? colors.onPrimaryContainer
                                    : null,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          descriptions[level.index],
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color:
                                    dailyActivitySelected &&
                                        value.dailyActivity == level
                                    ? colors.onPrimaryContainer
                                    : null,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    dailyActivitySelected && value.dailyActivity == level
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: dailyActivitySelected && value.dailyActivity == level
                        ? colors.onPrimaryContainer
                        : null,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 12),
        Text(
          s.weeklyExerciseTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(s.weeklyExerciseHint),
        const SizedBox(height: 12),
        if (value.exercises.isEmpty)
          Text(
            s.weeklyExerciseEmpty,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        for (var i = 0; i < value.exercises.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          exerciseTypeTitle(s, value.exercises[i].type),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      Semantics(
                        identifier: 'activity-plan-edit-$i',
                        child: IconButton(
                          tooltip: s.editItemDialogTitle,
                          onPressed: () => _edit(context, i),
                          icon: const Icon(Icons.edit_outlined, size: 20),
                        ),
                      ),
                      Semantics(
                        identifier: 'activity-plan-delete-$i',
                        child: IconButton(
                          tooltip: s.dialogDeleteLabel,
                          onPressed: () => onChanged(
                            ActivityPlan(
                              dailyActivity: value.dailyActivity,
                              exercises: List.unmodifiable(
                                [...value.exercises]..removeAt(i),
                              ),
                            ),
                          ),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    s.weeklyExerciseSchedule(
                      _number(value.exercises[i].sessionsPerWeek),
                      _number(value.exercises[i].minutesPerSession),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value.exercises[i].energySource ==
                            ExerciseEnergySource.estimated
                        ? '${_intensityTitle(s, value.exercises[i].intensity)} · ${value.exercises[i].met} MET'
                        : '${_energySourceTitle(s, value.exercises[i].energySource)} · ${_number(value.exercises[i].caloriesPerSession!)} kcal',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (hasWeight)
                    Text(
                      s.exerciseActivePerSession(
                        value.exercises[i]
                            .activeCaloriesPerSession(weightKg!)
                            .round()
                            .toString(),
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        Semantics(
          identifier: 'activity-plan-add-exercise',
          child: OutlinedButton.icon(
            onPressed: value.exercises.length >= 14
                ? null
                : () => _edit(context, null),
            icon: const Icon(Icons.add_rounded),
            label: Text(s.weeklyExerciseAdd),
          ),
        ),
        if (hasWeight)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              s.weeklyExerciseAverage(
                value.weeklyActiveCalories(weightKg!).round().toString(),
                value.dailyExerciseCalories(weightKg!).round().toString(),
              ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        const SizedBox(height: 8),
        Text(
          s.exerciseNetEnergyHint,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Future<void> _edit(BuildContext context, int? index) async {
    final result = await showDialog<WeeklyExercise>(
      context: context,
      builder: (_) => _WeeklyExerciseDialog(
        initialValue: index == null ? null : value.exercises[index],
      ),
    );
    if (result == null) return;
    final exercises = [...value.exercises];
    if (index == null) {
      exercises.add(result);
    } else {
      exercises[index] = result;
    }
    onChanged(
      ActivityPlan(
        dailyActivity: value.dailyActivity,
        exercises: List.unmodifiable(exercises),
      ),
    );
  }
}

class ActivityPlanSummary extends StatelessWidget {
  final ActivityPlan plan;
  final double weightKg;
  final double restingKcal;
  final String Function(double)? formatEnergy;

  const ActivityPlanSummary({
    super.key,
    required this.plan,
    required this.weightKg,
    required this.restingKcal,
    this.formatEnergy,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final baseline = restingKcal * plan.dailyActivity.multiplier;
    String energy(double value) =>
        formatEnergy?.call(value) ?? '${value.round()} kcal';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(s.goalTdeeWeeklyFormula),
        const SizedBox(height: 8),
        _row(s.goalRestingEnergy, energy(restingKcal)),
        _row(
          '${s.goalDailyEnergy} · ×${plan.dailyActivity.multiplier}',
          energy(baseline),
        ),
        _row(
          s.goalExerciseDaily,
          '+${energy(plan.dailyExerciseCalories(weightKg))}',
        ),
        const Divider(height: 20),
        _row(
          s.goalTdeeLabel,
          energy(baseline + plan.dailyExerciseCalories(weightKg)),
        ),
      ],
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 12,
      runSpacing: 4,
      children: [Text(label), Text(value)],
    ),
  );
}

class _WeeklyExerciseDialog extends StatefulWidget {
  final WeeklyExercise? initialValue;
  const _WeeklyExerciseDialog({this.initialValue});

  @override
  State<_WeeklyExerciseDialog> createState() => _WeeklyExerciseDialogState();
}

class _WeeklyExerciseDialogState extends State<_WeeklyExerciseDialog> {
  final _form = GlobalKey<FormState>();
  late PlannedExerciseType _type =
      widget.initialValue?.type ?? PlannedExerciseType.strength;
  late ExerciseIntensity _intensity =
      widget.initialValue?.intensity ?? ExerciseIntensity.moderate;
  late ExerciseEnergySource _source =
      widget.initialValue?.energySource ?? ExerciseEnergySource.estimated;
  late final _sessions = TextEditingController(
    text: widget.initialValue == null
        ? ''
        : _number(widget.initialValue!.sessionsPerWeek),
  );
  late final _minutes = TextEditingController(
    text: widget.initialValue == null
        ? ''
        : _number(widget.initialValue!.minutesPerSession),
  );
  late final _calories = TextEditingController(
    text: widget.initialValue?.caloriesPerSession == null
        ? ''
        : _number(widget.initialValue!.caloriesPerSession!),
  );

  @override
  void dispose() {
    _sessions.dispose();
    _minutes.dispose();
    _calories.dispose();
    super.dispose();
  }

  double _value(TextEditingController controller) =>
      double.tryParse(controller.text.replaceAll(',', '.')) ?? double.nan;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AlertDialog(
      title: Text(s.weeklyExerciseAdd),
      scrollable: true,
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                identifier: 'exercise-type',
                child: DropdownButtonFormField<PlannedExerciseType>(
                  initialValue: _type,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: s.exerciseTypeLabel),
                  items: [
                    for (final type in PlannedExerciseType.values)
                      DropdownMenuItem(
                        value: type,
                        child: Text(exerciseTypeTitle(s, type)),
                      ),
                  ],
                  onChanged: (type) {
                    if (type != null) setState(() => _type = type);
                  },
                ),
              ),
              const SizedBox(height: 16),
              _input(
                'exercise-sessions',
                _sessions,
                s.exerciseSessionsLabel,
                s.trendsPerWeekSuffix,
                28,
              ),
              const SizedBox(height: 16),
              _input(
                'exercise-minutes',
                _minutes,
                s.exerciseMinutesLabel,
                s.minuteShortLabel,
                720,
              ),
              const SizedBox(height: 16),
              Semantics(
                identifier: 'exercise-energy-source',
                child: DropdownButtonFormField<ExerciseEnergySource>(
                  initialValue: _source,
                  isExpanded: true,
                  itemHeight: null,
                  decoration: InputDecoration(
                    labelText: s.exerciseEnergySourceLabel,
                  ),
                  items: [
                    for (final source in ExerciseEnergySource.values)
                      DropdownMenuItem(
                        value: source,
                        child: Text(_energySourceTitle(s, source)),
                      ),
                  ],
                  onChanged: (source) {
                    if (source != null) setState(() => _source = source);
                  },
                ),
              ),
              const SizedBox(height: 16),
              if (_source == ExerciseEnergySource.estimated) ...[
                Semantics(
                  identifier: 'exercise-intensity',
                  child: DropdownButtonFormField<ExerciseIntensity>(
                    initialValue: _intensity,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: s.exerciseIntensityLabel,
                    ),
                    items: [
                      for (final intensity in ExerciseIntensity.values)
                        DropdownMenuItem(
                          value: intensity,
                          child: Text(_intensityTitle(s, intensity)),
                        ),
                    ],
                    onChanged: (intensity) {
                      if (intensity != null) {
                        setState(() => _intensity = intensity);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  s.exerciseEstimateHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ] else ...[
                _input(
                  'exercise-calories',
                  _calories,
                  s.exerciseCaloriesLabel,
                  'kcal',
                  10000,
                ),
                const SizedBox(height: 8),
                Text(
                  _source == ExerciseEnergySource.activeCalories
                      ? s.exerciseActiveEnergyHint
                      : s.exerciseTotalEnergyHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.dialogCancelLabel),
        ),
        Semantics(
          identifier: 'exercise-save',
          child: FilledButton(
            onPressed: () {
              if (!_form.currentState!.validate()) return;
              Navigator.of(context).pop(
                WeeklyExercise(
                  type: _type,
                  sessionsPerWeek: _value(_sessions),
                  minutesPerSession: _value(_minutes),
                  intensity: _intensity,
                  energySource: _source,
                  caloriesPerSession: _source == ExerciseEnergySource.estimated
                      ? null
                      : _value(_calories),
                ),
              );
            },
            child: Text(s.buttonSaveLabel),
          ),
        ),
      ],
    );
  }

  Widget _input(
    String id,
    TextEditingController controller,
    String label,
    String unit,
    double maximum,
  ) => Semantics(
    identifier: id,
    child: TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.next,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      decoration: InputDecoration(
        labelText: label,
        suffixText: unit,
        border: const OutlineInputBorder(),
        errorMaxLines: 2,
      ),
      validator: (_) {
        final number = _value(controller);
        return !number.isFinite || number <= 0 || number > maximum
            ? S.of(context).exerciseNumberError(_number(maximum))
            : null;
      },
    ),
  );
}
