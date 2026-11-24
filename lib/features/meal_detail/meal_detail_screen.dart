import 'package:opennutritracker/features/meal_detail/util/food_entry_preferences.dart';
import 'package:opennutritracker/features/add_meal/util/portion_unit.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/meal_value_unit_text.dart';
import 'package:opennutritracker/core/presentation/widgets/image_full_screen.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/energy_display.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/demo/unsplash_attribution.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/presentation/log_tray.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/favourite_toggle_button.dart';
import 'package:opennutritracker/features/edit_meal/presentation/edit_meal_screen.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/features/meal_detail/presentation/widgets/daily_kcal_overview.dart';
import 'package:opennutritracker/features/meal_detail/presentation/widgets/meal_detail_bottom_sheet.dart';
import 'package:opennutritracker/features/meal_detail/presentation/widgets/meal_detail_macro_nutrients.dart';
import 'package:opennutritracker/features/meal_detail/presentation/widgets/meal_detail_nutriments_table.dart';
import 'package:opennutritracker/features/meal_detail/presentation/widgets/meal_info_button.dart';
import 'package:opennutritracker/features/meal_detail/presentation/widgets/meal_placeholder.dart';
import 'package:opennutritracker/features/meal_detail/presentation/widgets/off_disclaimer.dart';
import 'package:opennutritracker/generated/l10n.dart';

class MealDetailScreen extends StatefulWidget {
  const MealDetailScreen({super.key});

  @override
  State<MealDetailScreen> createState() => _MealDetailScreenState();
}

class _MealDetailScreenState extends State<MealDetailScreen> {
  static const String _initialQuantityMetric = '100';
  static const String _initialQuantityImperial = '1';

  final log = Logger('ItemDetailScreen');

  late MealDetailBloc _mealDetailBloc;
  final _scrollController = ScrollController();

  late MealEntity meal;
  late MealEntity _sourceMeal;
  late DateTime _day;
  late IntakeTypeEntity intakeTypeEntity;

  final quantityTextController = TextEditingController();
  late bool _usesImperialUnits;
  LogTray? _logTray;
  bool _showMicronutrients = false;

  String _initialUnit = "";
  String _initialQuantity = "";

  // Set on the first didChangeDependencies pass, which is the only one that
  // reads the route arguments and requests hydration (see there).
  bool _argumentsRead = false;
  bool _userChangedSelection = false;

  bool _applyingInitialSelection = false;

  @override
  void initState() {
    _mealDetailBloc = locator<MealDetailBloc>();
    _loadDetailPreferences();
    super.initState();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    quantityTextController.dispose();
    super.dispose();
  }

  Future<void> _loadDetailPreferences() async {
    final config = await locator<GetConfigUsecase>().getConfig();
    if (!mounted) return;
    setState(() => _showMicronutrients = config.showMicronutrients);
  }

  @override
  void didChangeDependencies() {
    // Read once: opening the unit menu must not restore a thin search hit.
    if (!_argumentsRead) {
      final args =
          ModalRoute.of(context)?.settings.arguments
              as MealDetailScreenArguments;
      _sourceMeal = args.mealEntity;
      meal =
          FoodEntryPreferences.current?.withCustomPortions(_sourceMeal) ??
          _sourceMeal;
      _day = args.day;
      intakeTypeEntity = args.intakeTypeEntity;
      _usesImperialUnits = args.usesImperialUnits;
      _logTray = args.logTray;
      _argumentsRead = true;

      // Thin OFF search results get hydrated to the full product record
      // (serving fields + micronutrients) once, in the background; the
      // listener in build() swaps the displayed meal in when it arrives.
      _mealDetailBloc.add(HydrateMealEvent(meal));
    }

    if (_initialUnit.isEmpty) {
      _mealDetailBloc.add(LoadDailyTotalsEvent(_day));
      _applyInitialSelection();
    }

    super.didChangeDependencies();
  }

  void _applyInitialSelection() {
    final remembered = FoodEntryPreferences.current?.lastUnit(meal);

    _applyingInitialSelection = true;
    try {
      if (_initialUnit == "") {
        // `scalableServingQuantity`, not `hasServingValues` (#629): the latter
        // is true for a record whose serving is unparseable text, and nothing
        // can scale those — they defaulted to "1 serving" and logged 1 g.
        if (remembered != null) {
          _initialUnit = remembered;
        } else if (meal.isLiquid) {
          _initialUnit = _usesImperialUnits
              ? UnitDropdownItem.flOz.toString()
              : UnitDropdownItem.ml.toString();
        } else {
          _initialUnit = _usesImperialUnits
              ? UnitDropdownItem.oz.toString()
              : UnitDropdownItem.g.toString();
        }
        _mealDetailBloc.add(
          UpdateKcalEvent(meal: meal, selectedUnit: _initialUnit),
        );
      }

      if (_initialQuantity == "") {
        // Gated the same way as the unit above, so a bare "1" can never end
        // up beside a weight unit.
        if (isPortionUnit(_initialUnit)) {
          _initialQuantity = "1";
          quantityTextController.text = "1";
        } else if (['oz', 'fl.oz'].contains(_initialUnit)) {
          _initialQuantity = _initialQuantityImperial;
          quantityTextController.text = _initialQuantityImperial;
        } else {
          _initialQuantity = _initialQuantityMetric;
          quantityTextController.text = _initialQuantityMetric;
        }
        _mealDetailBloc.add(
          UpdateKcalEvent(
            meal: meal,
            totalQuantity: quantityTextController.text,
            selectedUnit: _initialUnit,
          ),
        );
      }
    } finally {
      _applyingInitialSelection = false;
    }
  }

  /// Apply the hydrated full product to the screen. If the user hasn't touched
  /// the quantity/unit yet, re-pick the defaults (so serving becomes the
  /// default now that serving data exists); otherwise just recompute totals
  /// against the fuller nutriments while keeping the user's selection.
  void _onMealHydrated(MealEntity full) {
    setState(() {
      _sourceMeal = full;
      meal = FoodEntryPreferences.current?.withCustomPortions(full) ?? full;
    });
    if (_userChangedSelection) {
      _mealDetailBloc.add(
        UpdateKcalEvent(
          meal: meal,
          totalQuantity: quantityTextController.text,
          selectedUnit: _mealDetailBloc.state.selectedUnit,
        ),
      );
    } else {
      _initialUnit = "";
      _initialQuantity = "";
      _applyInitialSelection();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    return BlocListener<MealDetailBloc, MealDetailState>(
      bloc: _mealDetailBloc,
      listenWhen: (prev, curr) =>
          curr.hydratedMeal != null && curr.hydratedMeal != prev.hydratedMeal,
      listener: (context, state) => _onMealHydrated(state.hydratedMeal!),
      child: Scaffold(
        backgroundColor: palette.canvas,
        appBar: AppBar(
          title: Text(
            S.of(context).loggingChooseAmount,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            FavouriteToggleButton(
              meal: meal,
              semanticsIdentifier: 'meal-detail-favourite',
            ),
            Semantics(
              identifier: 'meal-detail-edit',
              child: IconButton(
                tooltip: S.of(context).editMealLabel,
                icon: const Icon(Icons.edit_rounded),
                onPressed: () => Navigator.of(context).pushNamed(
                  NavigationOptions.editMealRoute,
                  arguments: EditMealScreenArguments(
                    _day,
                    meal,
                    intakeTypeEntity,
                    _usesImperialUnits,
                    logTray: _logTray,
                  ),
                ),
              ),
            ),
          ],
        ),
        body: BlocBuilder<MealDetailBloc, MealDetailState>(
          bloc: _mealDetailBloc,
          builder: (context, state) => MealDetailBottomSheet(
            product: meal,
            day: _day,
            intakeTypeEntity: intakeTypeEntity,
            selectedUnit: state.selectedUnit,
            usesImperialUnits: _usesImperialUnits,
            mealDetailBloc: _mealDetailBloc,
            quantityTextController: quantityTextController,
            onCustomPortionsChanged: FoodEntryPreferences.current == null
                ? null
                : (updated) {
                    setState(() => meal = updated);
                    return meal;
                  },
            onQuantityOrUnitChanged: onQuantityOrUnitChanged,
            logTray: _logTray,
            layoutBuilder: (context, editor, actions) => LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 400;
                final content = _getLoadedContent(
                  context,
                  state,
                  editor,
                  compact ? actions : null,
                );
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      children: [
                        Expanded(child: content),
                        if (!compact)
                          Material(color: palette.surface, child: actions),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _getLoadedContent(
    BuildContext context,
    MealDetailState state,
    Widget editor,
    Widget? inlineActions,
  ) {
    final palette = Theme.of(context).brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    final s = S.of(context);
    final imageUrl = meal.mainImageUrl;
    return ListView(
      key: const ValueKey('meal-detail-content'),
      controller: _scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Text(
          meal.name ?? '?',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (meal.brands?.trim().isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              meal.brands!,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: palette.textMuted),
            ),
          ),
        if (imageUrl != null && imageUrl.isNotEmpty) ...[
          const SizedBox(height: 16),
          Center(
            child: Semantics(
              identifier: 'meal-detail-image',
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.of(context).pushNamed(
                  NavigationOptions.imageFullScreenRoute,
                  arguments: ImageFullScreenArguments(imageUrl),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Hero(
                    tag: ImageFullScreen.fullScreenHeroTag,
                    child: CachedNetworkImage(
                      width: 160,
                      height: 160,
                      cacheManager: locator<CacheManager>(),
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => const MealPlaceholder(),
                      errorWidget: (_, _, _) => const MealPlaceholder(),
                    ),
                  ),
                ),
              ),
            ),
          ),
          UnsplashCreditLine(imageUrl: imageUrl),
        ],
        const SizedBox(height: 24),
        AppCard(padding: const EdgeInsets.all(16), child: editor),
        const SizedBox(height: 16),
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    meal.nutriments.energyKcal100 == null
                        ? missingNutrientPlaceholder
                        : EnergyDisplay.formatWithUnit(
                            context,
                            state.totalKcal,
                          ),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  MealValueUnitText(
                    value: double.tryParse(state.totalQuantityConverted) ?? 0,
                    meal: meal,
                    displayUnit: meal.isLiquid ? 'ml' : 'g',
                    usesImperialUnits: _usesImperialUnits,
                    textStyle: Theme.of(context).textTheme.bodyMedium,
                    prefix: '/ ',
                  ),
                ],
              ),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns =
                      constraints.maxWidth < 280 ||
                          MediaQuery.textScalerOf(context).scale(16) > 24
                      ? 1
                      : 3;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 16,
                    children: [
                      for (final item in [
                        (
                          s.carbsLabel,
                          meal.nutriments.carbohydrates100 == null
                              ? null
                              : state.totalCarbs,
                          palette.carbs,
                        ),
                        (
                          s.fatLabel,
                          meal.nutriments.fat100 == null
                              ? null
                              : state.totalFat,
                          palette.fat,
                        ),
                        (
                          s.proteinLabel,
                          meal.nutriments.proteins100 == null
                              ? null
                              : state.totalProtein,
                          palette.protein,
                        ),
                      ])
                        SizedBox(
                          width:
                              (constraints.maxWidth - (columns - 1) * 12) /
                              columns,
                          child: MealDetailMacroNutrients(
                            typeString: item.$1,
                            value: item.$2,
                            color: item.$3,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        if (state.dayKcalGoal > 0) ...[
          const SizedBox(height: 16),
          AppCard(
            padding: const EdgeInsets.all(16),
            child: DailyKcalOverview(
              dayKcalConsumed: state.dayKcalConsumed,
              dayKcalGoal: state.dayKcalGoal,
              currentSelectionKcal: state.totalKcal,
            ),
          ),
        ],
        const SizedBox(height: 24),
        if (state.isHydrating) const LinearProgressIndicator(minHeight: 2),
        MealDetailNutrimentsTable(
          product: meal,
          usesImperialUnits: _usesImperialUnits,
          servingQuantity: meal.servingQuantity,
          servingUnit: meal.servingUnit,
          showMicronutrients: _showMicronutrients,
        ),
        const SizedBox(height: 16),
        MealInfoButton(
          url: meal.url,
          source: meal.source,
          backendSource: meal.backendSource,
        ),
        if (meal.source == MealSourceEntity.off) const OffDisclaimer(),
        ?inlineActions,
      ],
    );
  }

  void onQuantityOrUnitChanged(String? quantityString, String? unit) {
    if (quantityString == null || unit == null) {
      return;
    }
    if (_applyingInitialSelection) {
      return;
    }
    _userChangedSelection = true;
    _mealDetailBloc.add(
      UpdateKcalEvent(
        meal: meal,
        totalQuantity: quantityString,
        selectedUnit: unit,
      ),
    );
  }
}

class MealDetailScreenArguments {
  final MealEntity mealEntity;
  final IntakeTypeEntity intakeTypeEntity;
  final DateTime day;
  final bool usesImperialUnits;

  /// The add-food screen's "To log" list. With one, the button adds the food
  /// to it and returns there instead of logging.
  final LogTray? logTray;

  MealDetailScreenArguments(
    this.mealEntity,
    this.intakeTypeEntity,
    this.day,
    this.usesImperialUnits, {
    this.logTray,
  });
}
