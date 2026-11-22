import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/activity_plan.dart';
import 'package:opennutritracker/core/presentation/widgets/activity_plan_editor.dart';
import 'package:opennutritracker/features/onboarding/domain/entity/user_activity_selection_entity.dart';
import 'package:opennutritracker/generated/l10n.dart';

class OnboardingActivityPageBody extends StatefulWidget {
  final Function(bool active, UserActivitySelectionEntity? selectedActivity)
  setButtonContent;
  final UserActivitySelectionEntity? initialActivity;
  final ActivityPlan? initialPlan;
  final ValueChanged<ActivityPlan>? onPlanChanged;
  final double? weightKg;

  const OnboardingActivityPageBody({
    super.key,
    required this.setButtonContent,
    this.initialActivity,
    this.initialPlan,
    this.onPlanChanged,
    this.weightKg,
  });

  @override
  State<OnboardingActivityPageBody> createState() =>
      _OnboardingActivityPageBodyState();
}

class _OnboardingActivityPageBodyState
    extends State<OnboardingActivityPageBody> {
  late UserActivitySelectionEntity? _selected = widget.initialActivity;
  late ActivityPlan _plan =
      widget.initialPlan ??
      ActivityPlan(
        dailyActivity:
            DailyActivityLevel.values[widget.initialActivity?.index ?? 0],
      );

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          S.of(context).activityLabel,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        ActivityPlanEditor(
          value: _plan,
          weightKg: widget.weightKg,
          dailyActivitySelected: _selected != null,
          dailyIdentifierPrefix: 'onboarding-activity',
          onDailySelected: (level) =>
              _selected = UserActivitySelectionEntity.values[level.index],
          onChanged: (plan) {
            setState(() => _plan = plan);
            widget.onPlanChanged?.call(plan);
            widget.setButtonContent(_selected != null, _selected);
          },
        ),
      ],
    ),
  );
}
