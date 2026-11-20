import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/presentation/widgets/floating_card_panel.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_activity/presentation/add_activity_screen.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_screen.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/features/add_meal/presentation/screens/bulk_add_screen.dart';
import 'package:opennutritracker/features/home/presentation/widgets/log_water_dialog.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// A single place for food, water, library and AI entry points.
class AddItemBottomSheet extends StatefulWidget {
  final DateTime day;
  final bool showActivityTracking;
  final bool usesImperialUnits;
  final IntakeTypeEntity? suggestedType;

  const AddItemBottomSheet({
    super.key,
    required this.day,
    this.showActivityTracking = true,
    this.usesImperialUnits = false,
    this.suggestedType,
  });

  @override
  State<AddItemBottomSheet> createState() => _AddItemBottomSheetState();
}

class _AddItemBottomSheetState extends State<AddItemBottomSheet> {
  late IntakeTypeEntity _type = widget.suggestedType ?? IntakeTypeEntity.lunch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    final s = S.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
            maxWidth: 560,
          ),
          child: FloatingCardPanel(
            closeIdentifier: 'logging-hub-close',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              s.addLabel,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                MaterialLocalizations.of(
                                  context,
                                ).formatMediumDate(widget.day),
                                textAlign: TextAlign.end,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: palette.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            for (final type in IntakeTypeEntity.values)
                              Semantics(
                                identifier: 'logging-meal-${type.name}',
                                child: ChoiceChip(
                                  label: Text(
                                    AddMealExtension.fromIntakeTypeEntity(
                                      type,
                                    ).getTypeName(context),
                                  ),
                                  selected: _type == type,
                                  onSelected: (_) =>
                                      setState(() => _type = type),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _entry(
                          'logging-record-meal',
                          Icons.restaurant_rounded,
                          s.loggingRecordMeal,
                          s.loggingRecordMealHint,
                          () => _openFood(context),
                        ),
                        const SizedBox(height: 8),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            // Keep two short rows on phones; fall back to one
                            // column for very narrow screens or larger text.
                            final columns =
                                constraints.maxWidth >= 300 &&
                                    MediaQuery.textScalerOf(
                                          context,
                                        ).scale(14) <=
                                        20
                                ? 2
                                : 1;
                            final width =
                                (constraints.maxWidth - 8 * (columns - 1)) /
                                columns;
                            Widget tile(Widget child) =>
                                SizedBox(width: width, child: child);
                            return Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                tile(
                                  _entry(
                                    'logging-record-water',
                                    Icons.water_drop_rounded,
                                    s.loggingRecordWater,
                                    s.loggingRecordWaterHint,
                                    () => _openWater(context),
                                    compact: true,
                                  ),
                                ),
                                tile(
                                  _entry(
                                    'logging-food-library',
                                    Icons.kitchen_outlined,
                                    s.loggingFoodLibrary,
                                    s.loggingFoodLibraryHint,
                                    () => _openFood(context, library: true),
                                    compact: true,
                                  ),
                                ),
                                tile(
                                  _entry(
                                    'logging-ai-photo',
                                    Icons.photo_camera_outlined,
                                    s.loggingPhoto,
                                    s.loggingPhotoHint,
                                    () => _openAi(context, photo: true),
                                    compact: true,
                                  ),
                                ),
                                tile(
                                  _entry(
                                    'logging-ai-describe',
                                    Icons.auto_awesome_outlined,
                                    s.loggingDescribe,
                                    s.loggingDescribeHint,
                                    () => _openAi(context, photo: false),
                                    compact: true,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        Center(
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            children: [
                              if (widget.showActivityTracking)
                                Semantics(
                                  identifier: 'add-item-activity',
                                  child: TextButton.icon(
                                    onPressed: () {
                                      final nav = Navigator.of(context);
                                      nav.pop();
                                      nav.pushNamed(
                                        NavigationOptions.addActivityRoute,
                                        arguments: AddActivityScreenArguments(
                                          day: widget.day,
                                        ),
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.directions_run_rounded,
                                    ),
                                    label: Text(s.activityLabel),
                                  ),
                                ),
                              Semantics(
                                identifier: 'add-item-recipes',
                                child: TextButton.icon(
                                  onPressed: () {
                                    final nav = Navigator.of(context);
                                    nav.pop();
                                    nav.pushNamed(
                                      NavigationOptions.recipesRoute,
                                    );
                                  },
                                  icon: const Icon(Icons.menu_book_outlined),
                                  label: Text(s.recipesLabel),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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

  Widget _entry(
    String id,
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap, {
    bool compact = false,
  }) {
    final theme = Theme.of(context);
    final iconWidget = Icon(icon, color: theme.colorScheme.primary, size: 24);
    return Semantics(
      identifier: id,
      hint: subtitle,
      child: AppCard(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: Dimens.radiusM,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 12 : 10,
          ),
          child: compact
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    iconWidget,
                    const SizedBox(height: 6),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelLarge,
                    ),
                  ],
                )
              : Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.12,
                        ),
                        borderRadius: Dimens.borderRadiusS,
                      ),
                      child: iconWidget,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right_rounded, size: 20),
                  ],
                ),
        ),
      ),
    );
  }

  void _openFood(BuildContext context, {bool library = false}) {
    final nav = Navigator.of(context);
    nav.pop();
    nav.pushNamed(
      NavigationOptions.addMealRoute,
      arguments: AddMealScreenArguments(
        AddMealExtension.fromIntakeTypeEntity(_type),
        widget.day,
        isFoodLibrary: library,
      ),
    );
  }

  void _openWater(BuildContext context) {
    final nav = Navigator.of(context);
    nav.pop();
    showDialog<void>(
      context: nav.context,
      builder: (_) =>
          LogWaterDialog(usesImperialUnits: widget.usesImperialUnits),
    );
  }

  void _openAi(BuildContext context, {required bool photo}) {
    final nav = Navigator.of(context);
    nav.pop();
    nav.pushNamed(
      NavigationOptions.bulkAddRoute,
      arguments: BulkAddScreenArguments(
        _type,
        widget.day,
        widget.usesImperialUnits,
        startWithPhoto: photo,
      ),
    );
  }
}
