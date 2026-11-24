import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/recipe_ingredient_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/energy_display.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:opennutritracker/features/add_meal/presentation/log_tray.dart';
import 'package:opennutritracker/features/add_meal/util/portion_unit.dart';
import 'package:opennutritracker/features/meal_detail/presentation/food_nutrition_screen.dart';

class IngredientListItem extends StatelessWidget {
  final RecipeIngredientEntity ingredient;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  const IngredientListItem({
    super.key,
    required this.ingredient,
    this.onEdit,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final accent = Theme.of(context).colorScheme.primary;
    final textTheme = Theme.of(context).textTheme;

    final meal = ingredient.snapshotMeal;
    final kcalPer100 = meal.nutriments.energyKcal100 ?? 0;
    final contributionKcal = kcalPer100 * ingredient.convertedAmountG / 100;
    final amountStr = ingredient.amount % 1 == 0
        ? ingredient.amount.toStringAsFixed(0)
        : ingredient.amount.toStringAsFixed(1);
    final amountLabel =
        ['g', 'ml', 'oz', 'fl.oz'].contains(ingredient.unit) ||
            isPortionUnit(ingredient.unit)
        ? logTrayAmountLabel(context, ingredient.amount, ingredient.unit, meal)
        : '$amountStr ${ingredient.unit}';
    final baseLabel =
        '${ingredient.convertedAmountG.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '')} '
        '${meal.isLiquid ? S.of(context).milliliterUnit : S.of(context).gramUnit}';
    final displayAmount = isPortionUnit(ingredient.unit)
        ? '$amountLabel · $baseLabel'
        : amountLabel;

    return Semantics(
      identifier: 'recipe-ingredient-detail',
      child: Material(
        color: Colors.transparent,
        borderRadius: Dimens.borderRadiusM,
        child: InkWell(
          borderRadius: Dimens.borderRadiusM,
          onTap: () => showFoodNutritionDetails(
            context,
            meal: meal,
            amount: ingredient.convertedAmountG,
            amountLabel: displayAmount,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Dimens.spacing8,
              vertical: Dimens.spacing12,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: Dimens.borderRadiusS,
                  ),
                  child: Icon(Icons.eco_rounded, color: accent, size: 22),
                ),
                const SizedBox(width: Dimens.spacing12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        meal.name ?? '?',
                        // What tells foods apart ("raw", "dried") often ends
                        // the name, so it wraps rather than being cut off.
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$displayAmount · '
                        '${EnergyDisplay.formatWithUnit(context, contributionKcal)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onEdit != null)
                  Semantics(
                    identifier: 'recipe-ingredient-edit-amount',
                    child: IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 22),
                      tooltip: S.of(context).loggingEditAmount,
                      onPressed: onEdit,
                    ),
                  ),
                if (onRemove != null)
                  Semantics(
                    identifier: 'recipe-ingredient-remove',
                    child: IconButton(
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        color: palette.textMuted,
                        size: 22,
                      ),
                      tooltip: S.of(context).removeIngredientLabel,
                      onPressed: onRemove,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
