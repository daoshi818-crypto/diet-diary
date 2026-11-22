import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:auto_size_text/auto_size_text.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/intake_details_dialog.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/presentation/widgets/meal_value_unit_text.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/energy_display.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/user_image_storage.dart';
import 'package:opennutritracker/features/diary/presentation/widgets/diary_sort_type.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// A logged intake, rendered as a full-width row: a rounded thumbnail, the meal
/// name and amount, and the energy on the trailing edge. Replaces the old
/// 120x120 tile so a day's meals read as a clean scannable list.
class IntakeCard extends StatelessWidget {
  static const double thumbSize = 52;

  final IntakeEntity intake;
  final Function(BuildContext, IntakeEntity)? onItemLongPressed;
  final Function(BuildContext, IntakeEntity, bool)? onItemTapped;
  final VoidCallback? onShare;
  final ValueChanged<IntakeTypeEntity>? onChangeMealType;
  final bool firstListElement;
  final bool usesImperialUnits;
  final DiarySortType? sortType;

  const IntakeCard({
    required super.key,
    required this.intake,
    this.onItemLongPressed,
    this.onItemTapped,
    this.onShare,
    this.onChangeMealType,
    required this.firstListElement,
    required this.usesImperialUnits,
    this.sortType,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final textTheme = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(Dimens.radiusM);
    final s = S.of(context);
    final macro = switch (sortType) {
      DiarySortType.protein => (intake.totalProteinsGram, s.proteinLabel),
      DiarySortType.carbs => (intake.totalCarbsGram, s.carbsLabel),
      DiarySortType.fat => (intake.totalFatsGram, s.fatLabel),
      _ => null,
    };
    final macroValue = macro == null
        ? null
        : NumberFormat.decimalPatternDigits(
            locale: Localizations.localeOf(context).toString(),
            decimalDigits: 1,
          ).format(macro.$1);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Dimens.spacing16,
        vertical: Dimens.spacing4,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          onTap: onItemTapped != null
              ? () => onTappedItem(context, usesImperialUnits)
              : null,
          onLongPress: onItemLongPressed != null
              ? () => onLongPressedItem(context)
              : null,
          child: AppCard(
            borderRadius: Dimens.radiusM,
            padding: const EdgeInsets.all(Dimens.spacing12),
            child: Row(
              children: [
                _Thumbnail(intake: intake, palette: palette),
                const SizedBox(width: Dimens.spacing12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AutoSizeText(
                        intake.meal.name ?? "?",
                        style: textTheme.titleSmall?.copyWith(
                          color: palette.textStrong,
                        ),
                        maxLines: 1,
                        minFontSize: 11,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      MealValueUnitText(
                        value: intake.amount,
                        meal: intake.meal,
                        usesImperialUnits: usesImperialUnits,
                        textStyle: textTheme.bodySmall?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Dimens.spacing8),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.4,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (macro != null)
                        Text(
                          '$macroValue ${s.gramUnit} ${macro.$2}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.labelMedium?.copyWith(
                            color: palette.textStrong,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      Text(
                        EnergyDisplay.formatWithUnit(context, intake.totalKcal),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: macro == null
                            ? textTheme.labelMedium?.copyWith(
                                color: palette.textStrong,
                                fontWeight: FontWeight.w700,
                              )
                            : textTheme.bodySmall?.copyWith(
                                color: palette.textMuted,
                              ),
                      ),
                    ],
                  ),
                ),
                if (onItemTapped != null ||
                    onChangeMealType != null ||
                    onShare != null)
                  Semantics(
                    identifier: 'intake-item-menu',
                    container: true,
                    child: PopupMenuButton<String>(
                      tooltip: s.loggingEditFood,
                      icon: Icon(
                        Icons.more_vert_rounded,
                        color: palette.textMuted,
                      ),
                      shape: Dimens.shapeM,
                      onSelected: (action) {
                        if (action == 'amount') {
                          onItemTapped?.call(
                            context,
                            intake,
                            usesImperialUnits,
                          );
                        } else if (action == 'type') {
                          _chooseMealType(context);
                        } else if (action == 'share') {
                          onShare?.call();
                        }
                      },
                      itemBuilder: (_) => [
                        if (onChangeMealType != null)
                          PopupMenuItem(
                            value: 'type',
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.swap_horiz_rounded),
                              title: Text(s.loggingMoveMeal),
                            ),
                          ),
                        if (onItemTapped != null)
                          PopupMenuItem(
                            value: 'amount',
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.scale_outlined),
                              title: Text(s.loggingEditFood),
                            ),
                          ),
                        if (onShare != null)
                          PopupMenuItem(
                            value: 'share',
                            child: Text(s.shareFoodLabel),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void onLongPressedItem(BuildContext context) {
    onItemLongPressed?.call(context, intake);
  }

  void onTappedItem(BuildContext context, bool usesImperialUnits) {
    showDialog<void>(
      context: context,
      builder: (_) => IntakeDetailsDialog(
        intake: intake,
        usesImperialUnits: usesImperialUnits,
        onEditAmount: () =>
            onItemTapped?.call(context, intake, usesImperialUnits),
      ),
    );
  }

  Future<void> _chooseMealType(BuildContext context) async {
    final s = S.of(context);
    final selected = await showDialog<IntakeTypeEntity>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: Dimens.shapeXL,
        title: Text(s.loggingMoveMeal),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(s.loggingMoveMealHint),
              const SizedBox(height: 12),
              for (final type in IntakeTypeEntity.values)
                Semantics(
                  identifier: 'intake-move-${type.name}',
                  child: ListTile(
                    shape: Dimens.shapeM,
                    selected: intake.type == type,
                    leading: Icon(type.getIconData()),
                    title: Text(
                      AddMealExtension.fromIntakeTypeEntity(
                        type,
                      ).getTypeName(context),
                    ),
                    trailing: intake.type == type
                        ? const Icon(Icons.check_rounded)
                        : null,
                    onTap: () => Navigator.of(dialogContext).pop(type),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(s.dialogCloseLabel),
          ),
        ],
      ),
    );
    if (selected != null && selected != intake.type && context.mounted) {
      onChangeMealType?.call(selected);
    }
  }
}

/// The leading thumbnail: a user photo, the remote OFF/FDC image, or a soft
/// fallback chip with a food icon — clipped to a rounded square.
class _Thumbnail extends StatelessWidget {
  final IntakeEntity intake;
  final AppPalette palette;

  const _Thumbnail({required this.intake, required this.palette});

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (intake.meal.localImagePath != null) {
      content = _LocalMealImage(relativePath: intake.meal.localImagePath!);
    } else if (intake.meal.mainImageUrl != null) {
      content = CachedNetworkImage(
        cacheManager: locator<CacheManager>(),
        imageUrl: intake.meal.mainImageUrl ?? "",
        fit: BoxFit.cover,
        errorWidget: (context, url, error) => _fallback(),
        placeholder: (context, url) => _fallback(),
      );
    } else {
      content = _fallback();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(Dimens.radiusS),
      child: SizedBox(
        width: IntakeCard.thumbSize,
        height: IntakeCard.thumbSize,
        child: content,
      ),
    );
  }

  Widget _fallback() => Container(
    color: palette.surfaceMuted,
    child: Icon(Icons.restaurant_rounded, color: palette.textMuted, size: 24),
  );
}

class _LocalMealImage extends StatelessWidget {
  final String relativePath;

  const _LocalMealImage({required this.relativePath});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: UserImageStorage.absolutePath(relativePath),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        if (!kIsWeb && !File(snapshot.data!).existsSync()) {
          return const SizedBox.shrink();
        }
        return Image(
          image: UserImageStorage.imageProvider(snapshot.data!),
          fit: BoxFit.cover,
        );
      },
    );
  }
}
