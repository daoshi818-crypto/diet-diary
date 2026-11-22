import 'package:opennutritracker/features/meal_detail/util/food_weight_basis.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/energy_display.dart';
import 'package:opennutritracker/core/utils/extensions.dart';
import 'package:opennutritracker/core/presentation/widgets/meal_value_unit_text.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/presentation/log_tray.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/favourite_toggle_button.dart';
import 'package:opennutritracker/features/meal_detail/meal_detail_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';

class MealItemCard extends StatelessWidget {
  final DateTime day;
  final AddMealType addMealType;
  final MealEntity mealEntity;
  final bool usesImperialUnits;
  final String? favouriteSemanticsIdentifier;

  /// The add-food screen's "To log" list. With one, opening the food adds
  /// to it instead of logging, and [onQuickAdd] answers the +.
  final LogTray? logTray;

  /// What the + does when there is a list: add the food at its default
  /// amount without opening it. Null keeps the + opening the detail screen.
  final VoidCallback? onQuickAdd;

  const MealItemCard({
    super.key,
    required this.day,
    required this.mealEntity,
    required this.addMealType,
    required this.usesImperialUnits,
    this.favouriteSemanticsIdentifier,
    this.logTray,
    this.onQuickAdd,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    final energy = mealEntity.nutriments.energyKcal100;
    final s = S.of(context);
    final packageQuantity = mealEntity.mealQuantity?.toLenientDoubleOrNull();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: AppCard(
        onTap: onQuickAdd ?? () => _onItemPressed(context),
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (mealEntity.thumbnailImageUrl?.isNotEmpty == true) ...[
                  ClipRRect(
                    borderRadius: Dimens.borderRadiusM,
                    child: CachedNetworkImage(
                      cacheManager: locator<CacheManager>(),
                      fit: BoxFit.cover,
                      width: 48,
                      height: 48,
                      imageUrl: mealEntity.thumbnailImageUrl!,
                      errorWidget: (_, _, _) =>
                          const Icon(Icons.restaurant_rounded),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AutoSizeText(
                        mealEntity.name ?? '?',
                        maxLines: 2,
                        minFontSize: 14,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: palette.textStrong,
                            ),
                      ),
                      if (!(mealEntity.backendSource?.startsWith('local_') ??
                              false) &&
                          packageQuantity != null)
                        MealValueUnitText(
                          value: packageQuantity,
                          meal: mealEntity,
                          usesImperialUnits: usesImperialUnits,
                        ),
                      if (mealEntity.brands?.trim().isNotEmpty == true)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            mealEntity.brands!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: palette.textMuted),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Semantics(
                  identifier: 'meal-item-add',
                  child: IconButton.filled(
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    tooltip: s.loggingChooseAmount,
                    icon: const Icon(Icons.add_rounded),
                    onPressed: onQuickAdd ?? () => _onItemPressed(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(
                        energy == null
                            ? '—'
                            : EnergyDisplay.formatWithUnit(context, energy),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: palette.textStrong,
                        ),
                      ),
                      Text(
                        ' / 100 ${mealEntity.isLiquid ? s.milliliterUnit : s.gramUnit}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                      if (foodWeightBasisLabel(s, mealEntity.name)
                          case final basis?)
                        Text(
                          basis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: palette.textMuted),
                        ),
                      if (mealEntity.source == MealSourceEntity.recipe)
                        Text(
                          s.additionalInfoLabelRecipe,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                    ],
                  ),
                ),
                if (onQuickAdd != null)
                  Semantics(
                    identifier: 'meal-item-detail',
                    child: IconButton(
                      tooltip: s.nutritionInfoLabel,
                      icon: const Icon(Icons.info_outline_rounded),
                      onPressed: () => _onItemPressed(context),
                    ),
                  ),
                FavouriteToggleButton(
                  meal: mealEntity,
                  semanticsIdentifier: favouriteSemanticsIdentifier,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _onItemPressed(BuildContext context) {
    Navigator.of(context).pushNamed(
      NavigationOptions.mealDetailRoute,
      arguments: MealDetailScreenArguments(
        mealEntity,
        addMealType.getIntakeType(),
        day,
        usesImperialUnits,
        logTray: logTray,
      ),
    );
  }
}
