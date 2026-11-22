import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/meal_value_unit_text.dart';
import 'package:opennutritracker/core/presentation/widgets/app_modal_sheet.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/energy_display.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/generated/l10n.dart';

class IntakeDetailsDialog extends StatelessWidget {
  final IntakeEntity intake;
  final bool usesImperialUnits;
  final VoidCallback onEditAmount;

  const IntakeDetailsDialog({
    super.key,
    required this.intake,
    required this.usesImperialUnits,
    required this.onEditAmount,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final palette = theme.brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    final type = AddMealExtension.fromIntakeTypeEntity(intake.type);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: AppModalSheet(
        identifier: 'intake-detail',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      intake.type.getIconData(),
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        type.getTypeName(context),
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  intake.meal.name ?? '?',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                MealValueUnitText(
                  value: intake.amount,
                  meal: intake.meal,
                  usesImperialUnits: usesImperialUnits,
                ),
                const SizedBox(height: 24),
                Text(
                  s.loggingIntakeNutrition,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: palette.textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  EnergyDisplay.formatWithUnit(context, intake.totalKcal),
                  style: theme.textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _macro(
                      context,
                      s.carbsLabel,
                      intake.totalCarbsGram,
                      palette.carbs,
                    ),
                    _macro(
                      context,
                      s.fatLabel,
                      intake.totalFatsGram,
                      palette.fat,
                    ),
                    _macro(
                      context,
                      s.proteinLabel,
                      intake.totalProteinsGram,
                      palette.protein,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
            Semantics(
              identifier: 'intake-detail-edit-amount',
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  onEditAmount();
                },
                icon: const Icon(Icons.scale_outlined),
                label: Text(s.loggingEditAmount),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _macro(BuildContext context, String name, double grams, Color color) =>
      Container(
        constraints: const BoxConstraints(minWidth: 84),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: Dimens.borderRadiusM,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 6),
            Text(
              '${grams.toStringAsFixed(1)} ${S.of(context).gramUnit}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
}
