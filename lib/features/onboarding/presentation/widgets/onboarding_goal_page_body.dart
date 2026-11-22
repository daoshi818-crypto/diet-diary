import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/onboarding/domain/entity/goal_suggestion_entity.dart';
import 'package:opennutritracker/features/onboarding/domain/entity/user_goal_selection_entity.dart';
import 'package:opennutritracker/generated/l10n.dart';

class OnboardingGoalPageBody extends StatefulWidget {
  final Function(bool active, UserGoalSelectionEntity? selectedGoal)
  setButtonContent;
  final UserGoalSelectionEntity? initialGoal;
  final double? initialDeficit;
  final ValueChanged<double>? onDeficitChanged;
  final double? estimatedTdee;

  /// Entered on the previous pages, and used only to derive the suggestion.
  /// Without them the page shows no suggestion.
  final double? heightCm;
  final double? weightKg;
  final double? targetWeightKg;

  const OnboardingGoalPageBody({
    super.key,
    required this.setButtonContent,
    this.initialGoal,
    this.initialDeficit,
    this.onDeficitChanged,
    this.estimatedTdee,
    this.heightCm,
    this.weightKg,
    this.targetWeightKg,
  });

  @override
  State<OnboardingGoalPageBody> createState() => _OnboardingGoalPageBodyState();
}

class _OnboardingGoalPageBodyState extends State<OnboardingGoalPageBody> {
  late UserGoalSelectionEntity? _selected = widget.initialGoal;
  late final _deficit = TextEditingController(
    text: (widget.initialDeficit ?? _defaultDeficit(_selected)).toStringAsFixed(
      0,
    ),
  );

  static double _defaultDeficit(UserGoalSelectionEntity? goal) =>
      switch (goal) {
        UserGoalSelectionEntity.loseWeight => 500,
        UserGoalSelectionEntity.gainWeigh => -500,
        _ => 0,
      };

  @override
  void dispose() {
    _deficit.dispose();
    super.dispose();
  }

  double get _deficitValue => _deficit.text.trim().isEmpty
      ? 0
      : double.tryParse(_deficit.text.replaceAll(',', '.')) ?? double.nan;

  bool get _validDeficit =>
      _deficitValue.isFinite &&
      _deficitValue.abs() <= 10000 &&
      (widget.estimatedTdee == null ||
          (widget.estimatedTdee! - _deficitValue > 0 &&
              widget.estimatedTdee! - _deficitValue <= 20000));

  void _report() {
    widget.onDeficitChanged?.call(_deficitValue);
    widget.setButtonContent(_selected != null && _validDeficit, _selected);
  }

  /// Derived on every build rather than cached, so going back to the
  /// height/weight page and changing a value can't leave the badge marking
  /// the goal the old numbers pointed at. It is pure arithmetic on three
  /// doubles, so there is nothing to save by holding on to it.
  GoalSuggestionEntity? get _suggestion => GoalSuggestionEntity.from(
    heightCm: widget.heightCm,
    weightKg: widget.weightKg,
    targetWeightKg: widget.targetWeightKg,
  );

  String _label(UserGoalSelectionEntity goal) {
    switch (goal) {
      case UserGoalSelectionEntity.loseWeight:
        return S.of(context).goalLoseWeight;
      case UserGoalSelectionEntity.maintainWeight:
        return S.of(context).goalMaintainWeight;
      case UserGoalSelectionEntity.gainWeigh:
        return S.of(context).goalGainWeight;
    }
  }

  static const _identifierSuffix = {
    UserGoalSelectionEntity.loseWeight: 'lose',
    UserGoalSelectionEntity.maintainWeight: 'maintain',
    UserGoalSelectionEntity.gainWeigh: 'gain',
  };

  @override
  Widget build(BuildContext context) {
    final suggestion = _suggestion;
    return SingleChildScrollView(
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              S.of(context).goalLabel,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              S.of(context).onboardingGoalQuestionSubtitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: Dimens.spacing16),
            for (final goal in UserGoalSelectionEntity.values) ...[
              _buildGoalRow(goal, suggestion),
              const SizedBox(height: Dimens.spacing8),
            ],
            if (suggestion != null) ...[
              const SizedBox(height: Dimens.spacing8),
              _buildSuggestionCard(suggestion),
            ],
            if (_selected != null) ...[
              const SizedBox(height: 20),
              Semantics(
                identifier: 'onboarding-calorie-deficit',
                child: TextFormField(
                  controller: _deficit,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
                  ],
                  decoration: InputDecoration(
                    labelText: S.of(context).goalDeficitInput,
                    suffixText: 'kcal',
                    border: const OutlineInputBorder(),
                    errorText: _validDeficit
                        ? null
                        : _deficitValue.isFinite && _deficitValue.abs() <= 10000
                        ? S.of(context).goalEnergyError
                        : S.of(context).goalDeficitError,
                    errorMaxLines: 3,
                    suffixIcon: Semantics(
                      identifier: 'onboarding-deficit-clear',
                      child: IconButton(
                        tooltip: S.of(context).buttonResetLabel,
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          setState(() => _deficit.clear());
                          _report();
                        },
                      ),
                    ),
                  ),
                  onChanged: (_) {
                    setState(() {});
                    _report();
                  },
                ),
              ),
              const SizedBox(height: 8),
              Text(
                S.of(context).goalDeficitHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGoalRow(
    UserGoalSelectionEntity goal,
    GoalSuggestionEntity? suggestion,
  ) {
    final isSuggested = suggestion?.goal == goal;
    // A Wrap: at a large font the badge moves under the chip rather than
    // overflowing the row.
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Dimens.spacing8,
      runSpacing: Dimens.spacing4,
      children: [
        Semantics(
          identifier: 'onboarding-goal-${_identifierSuffix[goal]}',
          child: ChoiceChip(
            label: Text(
              _label(goal),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            selected: _selected == goal,
            onSelected: (_) => _onSelected(goal),
          ),
        ),
        if (isSuggested) _buildSuggestedBadge(),
      ],
    );
  }

  /// Marks the suggested option without selecting it. The user still makes
  /// the choice, with the numbers' direction stated.
  Widget _buildSuggestedBadge() {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Dimens.spacing8,
        vertical: Dimens.spacing4,
      ),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(Dimens.radiusS),
      ),
      child: Text(
        S.of(context).onboardingGoalSuggestedBadge,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: colors.onSecondaryContainer),
      ),
    );
  }

  /// States what the suggestion rests on, so it reads as a derivation rather
  /// than an opinion the app is handing down.
  Widget _buildSuggestionCard(GoalSuggestionEntity suggestion) {
    final String reason;
    switch (suggestion.basis) {
      case GoalSuggestionBasis.targetWeight:
        reason = S.of(context).onboardingGoalSuggestionTarget;
      case GoalSuggestionBasis.bmi:
        reason = S
            .of(context)
            .onboardingGoalSuggestionBmi(
              suggestion.bmi!.toStringAsFixed(1),
              suggestion.nutritionalStatus!.getName(context),
            );
    }

    return Container(
      padding: const EdgeInsets.all(Dimens.spacing12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(Dimens.radiusS),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: Dimens.spacing8),
          Expanded(
            child: Text(reason, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }

  void _onSelected(UserGoalSelectionEntity goal) {
    setState(() {
      if (_selected != goal) {
        _deficit.text = _defaultDeficit(goal).toStringAsFixed(0);
      }
      _selected = goal;
    });
    _report();
  }
}
