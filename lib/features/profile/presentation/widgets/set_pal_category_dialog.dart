import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/user_pal_entity.dart';
import 'package:opennutritracker/generated/l10n.dart';

class SetPALCategoryDialog extends StatelessWidget {
  const SetPALCategoryDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final options = [
      (
        UserPALEntity.sedentary,
        s.palSedentaryLabel,
        s.palSedentaryDescriptionLabel,
      ),
      (
        UserPALEntity.lowActive,
        s.palLowLActiveLabel,
        s.palLowActiveDescriptionLabel,
      ),
      (UserPALEntity.active, s.palActiveLabel, s.palActiveDescriptionLabel),
      (
        UserPALEntity.veryActive,
        s.palVeryActiveLabel,
        s.palVeryActiveDescriptionLabel,
      ),
    ];
    return SimpleDialog(
      title: Text(S.of(context).selectPalCategoryLabel),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Text(s.goalActivityGuide),
        ),
        for (final option in options)
          Semantics(
            identifier: 'profile-pal-${option.$1.name}',
            child: SimpleDialogOption(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              onPressed: () => Navigator.pop(context, option.$1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.$2,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(option.$3, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
