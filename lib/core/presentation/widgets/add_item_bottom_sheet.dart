import 'package:opennutritracker/core/presentation/widgets/app_modal_sheet.dart';
import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_activity/presentation/add_activity_screen.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_screen.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/features/add_meal/presentation/screens/bulk_add_screen.dart';
import 'package:opennutritracker/features/add_meal/presentation/screens/nutrition_label_screen.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
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
    final s = S.of(context);
    return AppModalSheet(
      identifier: 'logging-hub',
      panelKey: const ValueKey('logging-hub-panel'),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.addLabel, style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
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
                    onSelected: (_) => setState(() => _type = type),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns =
                  constraints.maxWidth >= 300 &&
                      MediaQuery.textScalerOf(context).scale(14) <= 20
                  ? 3
                  : 2;
              final width =
                  (constraints.maxWidth - 8 * (columns - 1)) / columns;
              Widget tile(
                String id,
                IconData icon,
                String title,
                String hint,
                VoidCallback onTap,
              ) => SizedBox(
                width: width,
                child: _entry(id, icon, title, hint, onTap),
              );
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  tile(
                    'logging-record-meal',
                    Icons.restaurant_rounded,
                    s.loggingRecordMeal,
                    s.loggingRecordMealHint,
                    () => _openFood(context),
                  ),
                  tile(
                    'logging-record-water',
                    Icons.water_drop_rounded,
                    s.loggingRecordWater,
                    s.loggingRecordWaterHint,
                    () => _openWater(context),
                  ),
                  tile(
                    'logging-nutrition-label',
                    Icons.document_scanner_outlined,
                    s.labelScanShortTitle,
                    s.labelScanIntro,
                    () => _openLabel(context),
                  ),
                  tile(
                    'logging-food-library',
                    Icons.kitchen_outlined,
                    s.loggingFoodLibrary,
                    s.loggingFoodLibraryHint,
                    () => _openFood(context, library: true),
                  ),
                  tile(
                    'logging-ai-photo',
                    Icons.photo_camera_outlined,
                    s.loggingPhoto,
                    s.loggingPhotoHint,
                    () => _openAi(context, photo: true),
                  ),
                  tile(
                    'logging-ai-describe',
                    Icons.auto_awesome_outlined,
                    s.loggingDescribe,
                    s.loggingDescribeHint,
                    () => _openAi(context, photo: false),
                  ),
                ],
              );
            },
          ),
          Wrap(
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
                        arguments: AddActivityScreenArguments(day: widget.day),
                      );
                    },
                    icon: const Icon(Icons.directions_run_rounded),
                    label: Text(s.activityLabel),
                  ),
                ),
              Semantics(
                identifier: 'add-item-recipes',
                child: TextButton.icon(
                  onPressed: () {
                    final nav = Navigator.of(context);
                    nav.pop();
                    nav.pushNamed(NavigationOptions.recipesRoute);
                  },
                  icon: const Icon(Icons.menu_book_outlined),
                  label: Text(s.recipesLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _entry(
    String id,
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(context);
    return Semantics(
      identifier: id,
      hint: subtitle,
      child: AppCard(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: Dimens.radiusM,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: theme.colorScheme.primary, size: 24),
            const SizedBox(height: 6),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openLabel(BuildContext context) async {
    final nav = Navigator.of(context);
    nav.pop();
    final meal = await nav.push<MealEntity>(
      MaterialPageRoute(builder: (_) => const NutritionLabelScreen()),
    );
    if (meal == null || !nav.mounted) return;
    nav.pushNamed(
      NavigationOptions.addMealRoute,
      arguments: AddMealScreenArguments(
        AddMealExtension.fromIntakeTypeEntity(_type),
        widget.day,
        initialMeal: meal,
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
