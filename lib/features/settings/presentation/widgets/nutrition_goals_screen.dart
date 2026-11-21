import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:opennutritracker/core/domain/entity/nutrition_goal_plan.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/utils/calc/calorie_goal_calc.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';
import 'package:opennutritracker/core/utils/calc/macro_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/tracked_day_lock.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/kcal_goal_info_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';

Future<void> openNutritionGoals(BuildContext context) async {
  final saved = await Navigator.of(
    context,
  ).push<bool>(MaterialPageRoute(builder: (_) => const NutritionGoalsScreen()));
  if (saved != true) return;
  locator<HomeBloc>().add(const LoadItemsEvent());
  locator<DiaryBloc>().add(const LoadDiaryYearEvent());
  locator<CalendarDayBloc>().add(RefreshCalendarDayEvent());
  locator<SettingsBloc>().add(LoadSettingsEvent());
}

class NutritionGoalsData {
  final double tdee;
  final NutritionGoalPlan plan;

  const NutritionGoalsData({required this.tdee, required this.plan});
}

class NutritionGoalsScreen extends StatefulWidget {
  final NutritionGoalsData? initialData;
  final Future<bool> Function(NutritionGoalPlan)? onSave;

  const NutritionGoalsScreen({super.key, this.initialData, this.onSave});

  @override
  State<NutritionGoalsScreen> createState() => _NutritionGoalsScreenState();
}

class _NutritionGoalsScreenState extends State<NutritionGoalsScreen> {
  final _form = GlobalKey<FormState>();
  final _energy = TextEditingController();
  final _weight = TextEditingController();
  final _carbs = TextEditingController();
  final _protein = TextEditingController();
  final _fat = TextEditingController();
  final _startedOn = ProfileStamp.now();
  NutritionGoalsData? _data;
  EnergyGoalMode _energyMode = EnergyGoalMode.fixed;
  MacroGoalMode _macroMode = MacroGoalMode.grams;
  String? _error;
  bool _saving = false;
  bool _validate = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _applyData(widget.initialData!);
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final config = await locator<GetConfigUsecase>().getConfig();
      final user = await locator<GetUserUsecase>().getUserData();
      final day = DayBoundaryCalc.currentLogicalDayMinutes(
        config.dayStartOffsetTotalMinutes,
      );
      final target = CalorieGoalCalc.getTotalKcalGoal(
        user,
        0,
        kcalUserAdjustment: config.userKcalAdjustment,
        caloriesTaperEnabled: user.caloriesTaperEnabled,
      );
      final plan = config.nutritionGoalSchedule.onDay(day);
      final data = NutritionGoalsData(
        tdee: CalorieGoalCalc.getTdee(user),
        plan: NutritionGoalPlan(
          effectiveFrom: day,
          energyMode: plan?.energyMode ?? EnergyGoalMode.fixed,
          energyValue: plan?.energyValue ?? target,
          macroMode: plan?.macroMode ?? MacroGoalMode.percentage,
          carbs:
              plan?.carbs ??
              (config.userCarbGoalPct ?? MacroCalc.defaultCarbsPercentageGoal) *
                  100,
          protein:
              plan?.protein ??
              (config.userProteinGoalPct ??
                      MacroCalc.defaultProteinsPercentageGoal) *
                  100,
          fat:
              plan?.fat ??
              (config.userFatGoalPct ?? MacroCalc.defaultFatsPercentageGoal) *
                  100,
          referenceWeightKg: plan?.referenceWeightKg ?? user.weightKG,
        ),
      );
      if (mounted) setState(() => _applyData(data));
    } catch (_) {
      if (mounted) setState(() => _error = 'load');
    }
  }

  String _number(double value) =>
      value.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');

  String _grams(double value) =>
      value.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');

  void _applyData(NutritionGoalsData data) {
    _data = data;
    _energyMode = data.plan.energyMode;
    _macroMode = data.plan.macroMode;
    _energy.text = _number(data.plan.energyValue);
    _weight.text = _number(data.plan.referenceWeightKg);
    _writeMacros(data.plan);
    _error = null;
  }

  void _writeMacros(NutritionGoalPlan plan) {
    _macroMode = plan.macroMode;
    _carbs.text = _number(plan.carbs);
    _protein.text = _number(plan.protein);
    _fat.text = _number(plan.fat);
  }

  double _value(TextEditingController controller) =>
      double.tryParse(controller.text.replaceAll(',', '.')) ?? double.nan;

  NutritionGoalPlan get _plan => NutritionGoalPlan(
    effectiveFrom: _data!.plan.effectiveFrom,
    energyMode: _energyMode,
    energyValue: _value(_energy),
    macroMode: _macroMode,
    carbs: _value(_carbs),
    protein: _value(_protein),
    fat: _value(_fat),
    referenceWeightKg: _value(_weight),
  );

  void _changeMacroMode(MacroGoalMode mode) {
    final plan = _plan;
    final calories = plan.calorieTarget(_data!.tdee);
    final grams = plan.macroGoals(calories);
    if (![
          grams.carbs,
          grams.protein,
          grams.fat,
        ].every((n) => n.isFinite && n >= 0) ||
        grams.energy <= 0 ||
        !plan.referenceWeightKg.isFinite ||
        plan.referenceWeightKg <= 0) {
      setState(() => _validate = true);
      return;
    }
    setState(() {
      _macroMode = mode;
      final divisor = mode == MacroGoalMode.perKg
          ? plan.referenceWeightKg
          : 1.0;
      _carbs.text = _number(
        mode == MacroGoalMode.percentage
            ? grams.carbs * 4 / grams.energy * 100
            : grams.carbs / divisor,
      );
      _protein.text = _number(
        mode == MacroGoalMode.percentage
            ? grams.protein * 4 / grams.energy * 100
            : grams.protein / divisor,
      );
      _fat.text = _number(
        mode == MacroGoalMode.percentage
            ? 100 - _value(_carbs) - _value(_protein)
            : grams.fat / divisor,
      );
    });
  }

  Future<void> _save() async {
    setState(() => _validate = true);
    if (!_form.currentState!.validate()) return;
    var plan = _plan;
    final calories = plan.calorieTarget(_data!.tdee);
    if (!plan.isValid ||
        !calories.isFinite ||
        calories <= 0 ||
        calories > 20000) {
      setState(() => _error = 'values');
      return;
    }
    if (plan.macroGoals(calories).differsSignificantly(calories)) {
      final reviewed = await _review(plan, calories);
      if (reviewed == null || !mounted) return;
      plan = reviewed;
      setState(() => _writeMacros(plan));
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = widget.onSave != null
          ? await widget.onSave!(plan)
          : await locator<SettingsBloc>().saveNutritionGoals(
              plan,
              startedOn: _startedOn,
            );
      if (!mounted) return;
      if (saved) {
        Navigator.of(context).pop(true);
      } else {
        setState(() => _error = 'save');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'save');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<NutritionGoalPlan?> _review(NutritionGoalPlan plan, double target) {
    final s = S.of(context);
    final balanced = plan.balanceCarbs(target);
    final scaled = plan.scaleMacros(target);
    return showModalBottomSheet<NutritionGoalPlan>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                s.goalReviewTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(s.goalMacroMismatch),
              const SizedBox(height: 16),
              _reviewChoice(
                'goals-balance-carbs',
                s.goalBalanceCarbs,
                balanced,
                target,
              ),
              if (balanced == null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(s.goalCannotBalance),
                ),
              _reviewChoice(
                'goals-scale-macros',
                s.goalScaleMacros,
                scaled,
                target,
              ),
              _reviewChoice(
                'goals-keep-values',
                s.goalKeepValues,
                plan,
                target,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reviewChoice(
    String id,
    String title,
    NutritionGoalPlan? plan,
    double target,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Semantics(
      identifier: id,
      child: OutlinedButton(
        onPressed: plan == null ? null : () => Navigator.of(context).pop(plan),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Text(title, textAlign: TextAlign.center),
              if (plan != null)
                Text(
                  _preview(plan.macroGoals(target)),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ),
    ),
  );

  String _preview(MacroGoals grams) =>
      '${S.of(context).goalMacroPreview}\n'
      '${_grams(grams.carbs)} / ${_grams(grams.protein)} / ${_grams(grams.fat)} g'
      ' · ${grams.energy.round()} kcal';

  @override
  void dispose() {
    for (final controller in [_energy, _weight, _carbs, _protein, _fat]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    if (_data == null) {
      return Scaffold(
        appBar: AppBar(title: Text(s.nutritionGoalsTitle)),
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : Semantics(
                  identifier: 'goals-retry',
                  child: TextButton(
                    onPressed: () {
                      setState(() => _error = null);
                      _load();
                    },
                    child: Text(s.goalLoadError),
                  ),
                ),
        ),
      );
    }
    final plan = _plan;
    final target = plan.calorieTarget(_data!.tdee);
    final grams = plan.macroGoals(target);
    final validPreview = plan.isValid && target.isFinite && target > 0;
    final difference = _data!.tdee - target;
    final unit = switch (_macroMode) {
      MacroGoalMode.grams => 'g',
      MacroGoalMode.percentage => '%',
      MacroGoalMode.perKg => 'g/kg',
    };
    return Scaffold(
      appBar: AppBar(title: Text(s.nutritionGoalsTitle)),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Semantics(
            identifier: 'goals-save',
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(s.goalSave),
            ),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: AbsorbPointer(
          absorbing: _saving,
          child: Form(
            key: _form,
            autovalidateMode: _validate
                ? AutovalidateMode.always
                : AutovalidateMode.disabled,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(s.nutritionGoalsSubtitle),
                const SizedBox(height: 16),
                AppCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _summary(s.goalTdeeLabel, '${_data!.tdee.round()} kcal'),
                      _summary(
                        s.goalIntakeLabel,
                        validPreview ? '${target.round()} kcal' : '—',
                      ),
                      _summary(
                        difference < 0
                            ? s.goalPlannedSurplus
                            : s.goalPlannedDeficit,
                        validPreview ? '${difference.abs().round()} kcal' : '—',
                      ),
                      const Divider(height: 24),
                      Text(
                        s.goalActivityIncluded,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (widget.initialData == null)
                        Semantics(
                          identifier: 'goals-calculation-info',
                          child: TextButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const KcalGoalInfoScreen(),
                              ),
                            ),
                            icon: const Icon(
                              Icons.info_outline_rounded,
                              size: 18,
                            ),
                            label: Text(s.settingsKcalGoalInfoLabel),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _section(s.goalEnergyMode, [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final mode in EnergyGoalMode.values)
                        Semantics(
                          identifier: 'goals-energy-${mode.name}',
                          child: ChoiceChip(
                            label: Text(
                              mode == EnergyGoalMode.fixed
                                  ? s.goalFixedMode
                                  : s.goalDeficitMode,
                            ),
                            selected: _energyMode == mode,
                            onSelected: (_) => setState(() {
                              final oldTarget = _plan.calorieTarget(
                                _data!.tdee,
                              );
                              _energyMode = mode;
                              _energy.text = _number(
                                mode == EnergyGoalMode.fixed
                                    ? oldTarget
                                    : _data!.tdee - oldTarget,
                              );
                            }),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _field(
                    'goals-energy-input',
                    _energy,
                    _energyMode == EnergyGoalMode.fixed
                        ? s.goalIntakeLabel
                        : s.goalDeficitInput,
                    'kcal',
                    (n) {
                      if (!n.isFinite) return s.goalEnergyError;
                      if (_energyMode == EnergyGoalMode.deficit &&
                          n.abs() > 10000) {
                        return s.goalDeficitError;
                      }
                      final result = _energyMode == EnergyGoalMode.fixed
                          ? n
                          : _data!.tdee - n;
                      return result <= 0 || result > 20000
                          ? s.goalEnergyError
                          : null;
                    },
                    signed: _energyMode == EnergyGoalMode.deficit,
                  ),
                  if (_energyMode == EnergyGoalMode.deficit)
                    Text(
                      s.goalDeficitHint,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ]),
                const SizedBox(height: 20),
                _section(s.goalMacroMode, [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final mode in MacroGoalMode.values)
                        Semantics(
                          identifier: 'goals-macro-${mode.name}',
                          child: ChoiceChip(
                            label: Text(switch (mode) {
                              MacroGoalMode.grams => s.goalModeGrams,
                              MacroGoalMode.percentage => s.goalModePercentage,
                              MacroGoalMode.perKg => s.goalModePerKg,
                            }),
                            selected: _macroMode == mode,
                            onSelected: (_) => _changeMacroMode(mode),
                          ),
                        ),
                    ],
                  ),
                  if (_macroMode == MacroGoalMode.perKg) ...[
                    const SizedBox(height: 16),
                    _field(
                      'goals-reference-weight',
                      _weight,
                      s.goalReferenceWeight,
                      'kg',
                      (n) => !n.isFinite || n <= 0 || n > 1000
                          ? s.goalWeightError
                          : null,
                    ),
                    Text(
                      s.goalReferenceWeightHint,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 16),
                  for (final item in [
                    ('carbs', _carbs, s.carbsLabel),
                    ('protein', _protein, s.proteinLabel),
                    ('fat', _fat, s.fatLabel),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _field(
                        'goals-${item.$1}',
                        item.$2,
                        item.$3,
                        unit,
                        (n) =>
                            !n.isFinite ||
                                n < 0 ||
                                n >
                                    (_macroMode == MacroGoalMode.percentage
                                        ? 100
                                        : 10000)
                            ? s.goalNumberError
                            : null,
                      ),
                    ),
                  if (_macroMode == MacroGoalMode.percentage &&
                      (plan.carbs + plan.protein + plan.fat - 100).abs() > .01)
                    Text(
                      s.goalPercentageError,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (validPreview) ...[
                    _summary(s.goalMacroEnergy, '${grams.energy.round()} kcal'),
                    _summary(
                      s.goalEnergyDifference,
                      '${grams.differenceFrom(target) > 0 ? '+' : ''}'
                      '${grams.differenceFrom(target).round()} kcal',
                    ),
                    Text(
                      _preview(grams),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (grams.differsSignificantly(target))
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          s.goalMacroMismatch,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ]),
                const SizedBox(height: 16),
                Text(
                  s.goalEffectiveToday,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error == 'values' ? s.goalValuesError : s.goalSaveError,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => AppCard(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        ...children,
      ],
    ),
  );

  Widget _summary(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 16,
      runSpacing: 4,
      children: [
        Text(label),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    ),
  );

  Widget _field(
    String id,
    TextEditingController controller,
    String label,
    String unit,
    String? Function(double) validate, {
    bool signed = false,
  }) => Semantics(
    identifier: id,
    child: TextFormField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(
        decimal: true,
        signed: signed,
      ),
      textInputAction: TextInputAction.next,
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          RegExp(signed ? r'[0-9.,\-]' : r'[0-9.,]'),
        ),
      ],
      decoration: InputDecoration(
        labelText: label,
        suffixText: unit,
        errorMaxLines: 3,
        border: const OutlineInputBorder(),
      ),
      validator: (_) => validate(_value(controller)),
      onChanged: (_) => setState(() => _error = null),
    ),
  );
}
