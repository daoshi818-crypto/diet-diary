import 'package:opennutritracker/core/data/data_source/recipe_data_source.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/utils/energy_display.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:opennutritracker/core/domain/entity/recipe_ingredient_entity.dart';
import 'package:opennutritracker/features/recipes/presentation/screens/recipe_builder_screen.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/presentation/widgets/food_quantity_dialog.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/presentation/widgets/empty_hint.dart';
import 'package:opennutritracker/core/presentation/widgets/error_dialog.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/data/data_source/remote_search_cache_data_source.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/core/utils/navigation_predicates.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/local_batch_matcher.dart';
import 'package:opennutritracker/features/meal_detail/util/food_entry_preferences.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/data/data_sources/chinese_food_data_source.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/add_meal_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/screens/bulk_add_screen.dart';
import 'package:opennutritracker/features/add_meal/presentation/screens/local_batch_screen.dart';
import 'package:opennutritracker/features/add_meal/presentation/screens/nutrition_label_screen.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/favourite_meal_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/food_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/recent_meal_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/search_debounce.dart';
import 'package:opennutritracker/features/add_meal/presentation/log_tray.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/log_tray_widgets.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/add_food_methods.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/food_category_browser.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/default_results_widget.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/meal_search_bar.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/no_results_widget.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/meal_item_card.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/partial_results_notice.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/quick_add_bottom_sheet.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/products_bloc.dart';
import 'package:opennutritracker/features/add_meal/util/meal_relevance_ranker.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/edit_meal/presentation/edit_meal_screen.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/features/meal_detail/util/hydrate_off_meal.dart';
import 'package:opennutritracker/features/scanner/scanner_screen.dart';
import 'package:opennutritracker/features/scanner/util/barcode_check_digit.dart';
import 'package:opennutritracker/generated/l10n.dart';

class AddMealScreen extends StatefulWidget {
  const AddMealScreen({super.key});

  @override
  State<AddMealScreen> createState() => _AddMealScreenState();
}

class _AddMealScreenState extends State<AddMealScreen> {
  final _log = Logger('AddMealScreen');
  final ValueNotifier<String> _searchStringListener = ValueNotifier('');

  late AddMealType _mealType;
  late DateTime _day;
  bool _isFoodLibrary = false;
  bool _argumentsLoaded = false;
  late final _customMealDataSource = locator<CustomMealDataSource>();
  late final _customFoodChanges = _customMealDataSource.watch();
  late final _recipeChanges = locator.isRegistered<RecipeDataSource>()
      ? locator<RecipeDataSource>().watch()
      : const Stream<void>.empty();

  late ProductsBloc _productsBloc;
  late FoodBloc _foodBloc;
  late RecentMealBloc _recentMealBloc;
  late FavouriteMealBloc _favouriteMealBloc;
  late AddMealBloc _addMealBloc;

  /// Whether the user hid the AI features (#1518): no Snap meal tile, and
  /// Describe without its AI badge, since the offline parser reads it then.
  /// Starts from the value read at app start, so the tile does not show for
  /// a frame and vanish.
  bool _aiHidden = false;

  /// What every entry method on this screen adds to, and the one button at
  /// the bottom logs. Handed to the screens this one opens.
  final _logTray = LogTray();
  bool _logging = false;

  /// Codes whose + is still fetching the full record.
  final _quickAdding = <String>{};

  _SearchSource _source = _SearchSource.recent;

  // #576: once the user explicitly taps the Recent chip, typing should keep
  // filtering Recent instead of silently jumping to All (the default-Recent
  // case still upgrades to All on first keystroke, matching existing
  // behavior for someone who never touched the chips).
  bool _stickOnRecent = false;
  ChineseFoodDataSource? _catalog;
  List<FoodCategory> _categories = const [];
  String? _categoryId;
  bool _trayExpanded = false;
  bool _fullTray = false;

  @override
  void initState() {
    _productsBloc = locator<ProductsBloc>();
    _foodBloc = locator<FoodBloc>();
    _recentMealBloc = locator<RecentMealBloc>();
    _favouriteMealBloc = locator<FavouriteMealBloc>();
    // Held, not looked up where it is read: a factory registration hands out
    // a fresh instance per lookup, whose state would always be initial.
    _addMealBloc = locator<AddMealBloc>()..add(InitializeAddMealEvent());
    super.initState();
    if (locator.isRegistered<ChineseFoodDataSource>()) {
      _catalog = locator<ChineseFoodDataSource>();
      _source = _SearchSource.all;
      _catalog!.addListener(_reloadCategories);
      _reloadCategories();
    }
    _refreshAiHidden();
  }

  Future<void> _reloadCategories() async {
    try {
      final categories = await _catalog!.categories();
      if (!mounted) return;
      setState(() {
        _categories = categories;
        if (!_categories.any((category) => category.id == _categoryId)) {
          _categoryId = null;
        }
      });
    } catch (error) {
      _log.warning('Reading food categories failed', error);
    }
  }

  List<MealEntity> _categoryMeals(List<MealEntity> meals) => _categoryId == null
      ? meals
      : meals
            .where((meal) => _catalog?.categoryFor(meal) == _categoryId)
            .toList();

  /// Absent in tests that register no AI store, where nothing is hidden.
  Future<void> _refreshAiHidden() async {
    if (!locator.isRegistered<AiCredentialStorage>()) return;
    final storage = locator<AiCredentialStorage>();
    final known = storage.hiddenIfKnown;
    if (known != null) _aiHidden = known;
    final hidden = await storage.isHidden();
    if (mounted && hidden != _aiHidden) setState(() => _aiHidden = hidden);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_argumentsLoaded) {
      final args =
          ModalRoute.of(context)?.settings.arguments as AddMealScreenArguments;
      _mealType = args.mealType;
      _logTray.defaultIntakeType = _mealType.getIntakeType();
      _day = args.day;
      _isFoodLibrary = args.isFoodLibrary;
      _argumentsLoaded = true;
      if (args.initialItems.isNotEmpty) _logTray.addAll(args.initialItems);
      if (args.initialMeal case final meal?) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _addInitialMeal(meal),
        );
      }
    }
  }

  Future<void> _addInitialMeal(MealEntity meal) async {
    final current = _addMealBloc.state;
    final loaded = current is AddMealLoadedState
        ? current
        : await _addMealBloc.stream.firstWhere(
            (state) => state is AddMealLoadedState,
            orElse: () => AddMealInitialState(),
          );
    if (mounted && loaded is AddMealLoadedState) {
      await _onQuickAddToTray(meal, loaded.usesImperialUnits);
    }
  }

  @override
  void dispose() {
    _catalog?.removeListener(_reloadCategories);
    _searchStringListener.dispose();
    _favouriteMealBloc.close();
    _addMealBloc.close();
    _logTray.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    return ListenableBuilder(
      listenable: _logTray,
      builder: (context, _) => PopScope(
        // Leaving with items on the list would drop them without a word.
        canPop: !_fullTray && _logTray.isEmpty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !_logging) {
            if (_fullTray) {
              setState(() => _fullTray = false);
            } else {
              _confirmDiscardTray();
            }
          }
        },
        // Nothing on the screen takes input while the list is being
        // written: an item added or removed mid-write would be dropped by
        // the return to the day, or logged after being removed.
        child: AbsorbPointer(
          absorbing: _logging,
          child: _buildScaffold(context, palette),
        ),
      ),
    );
  }

  Widget _buildScaffold(BuildContext context, AppPalette palette) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
        systemNavigationBarIconBrightness: palette.brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: Text(
            _fullTray
                ? S.of(context).foodTrayReview
                : S.of(context).loggingFoodLibrary,
          ),
          actions: [
            if (!_fullTray)
              Semantics(
                identifier: 'add-meal-quick-add',
                child: TextButton(
                  onPressed: _onQuickAddPressed,
                  child: Text(
                    S.of(context).quickAddCardLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            if (!_fullTray)
              BlocBuilder<AddMealBloc, AddMealState>(
                bloc: _addMealBloc,
                builder: (BuildContext context, AddMealState state) {
                  if (state is AddMealLoadedState) {
                    return Semantics(
                      identifier: 'add-meal-custom-add',
                      child: IconButton(
                        onPressed: () =>
                            _onCustomAddButtonPressed(state.usesImperialUnits),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    );
                  }
                  return const SizedBox();
                },
              ),
          ],
        ),
        bottomNavigationBar: _catalog == null && _logTray.isEmpty
            ? null
            : Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: _buildTrayFooter(),
              ),
        body: _fullTray
            ? _buildFullTray()
            : SafeArea(
                top: false,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 840),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = MediaQuery.sizeOf(context).width < 600;
                        return Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Column(
                                children: [
                                  const SizedBox(height: 4),
                                  AddFoodMethodTiles(
                                    onBarcodePressed: _onBarcodeIconPressed,
                                    onSnapMealPressed: () =>
                                        _openBulkAdd(startWithPhoto: true),
                                    onDescribePressed: () => _openBulkAdd(),
                                    onLocalBatchPressed: _openLocalBatch,
                                    describeOpen: false,
                                    showAi: !_aiHidden,
                                    compact: compact,
                                    singleRow: constraints.maxHeight < 250,
                                    onNutritionLabelPressed:
                                        _openNutritionLabel,
                                  ),
                                  SizedBox(height: compact ? 4 : 8),
                                  MealSearchBar(
                                    searchStringListener: _searchStringListener,
                                    onSearchSubmit: _onSearchSubmit,
                                    onSearchChanged: _onSearchChanged,
                                    onBarcodePressed: null,
                                    compact: compact,
                                  ),
                                  SizedBox(height: compact ? 4 : 8),
                                  _buildSourceChips(
                                    context,
                                    palette,
                                    compact: compact,
                                  ),
                                  SizedBox(height: compact ? 4 : 8),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (_catalog != null)
                                    FoodCategoryRail(
                                      categories: _categories,
                                      selected: _categoryId,
                                      onSelected: (id) => setState(() {
                                        _categoryId = id;
                                        _source = _SearchSource.all;
                                      }),
                                    ),
                                  Expanded(
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: _catalog == null ? 16 : 0,
                                      ),
                                      child: ValueListenableBuilder<String>(
                                        valueListenable: _searchStringListener,
                                        builder: (context, query, _) =>
                                            _buildResults(
                                              context,
                                              palette,
                                              query,
                                            ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  bool get _usesImperialUnits =>
      _addMealBloc.state is AddMealLoadedState &&
      (_addMealBloc.state as AddMealLoadedState).usesImperialUnits;

  Widget _trayList({int? maxItems, bool showHeader = true}) => LogTrayList(
    tray: _logTray,
    day: _day,
    usesImperialUnits: _usesImperialUnits,
    maxItems: maxItems,
    showHeader: showHeader,
    compact: true,
  );

  Widget _buildTrayFooter() {
    final s = S.of(context);
    final showItems =
        _trayExpanded &&
        !_fullTray &&
        !_logTray.isEmpty &&
        MediaQuery.viewInsetsOf(context).bottom == 0;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showItems) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.foodTrayReview,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    Semantics(
                      identifier: 'food-tray-collapse',
                      child: TextButton(
                        onPressed: () => setState(() => _trayExpanded = false),
                        child: Text(s.foodTrayCollapse),
                      ),
                    ),
                  ],
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.34,
                  ),
                  child: SingleChildScrollView(
                    key: const ValueKey('food-tray-inline-scroll'),
                    child: _trayList(showHeader: false),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        identifier: 'food-tray-save-recipe',
                        child: TextButton.icon(
                          onPressed: _saveTrayAsRecipe,
                          icon: const Icon(Icons.menu_book_outlined, size: 18),
                          label: Text(s.saveAsMealLabel),
                        ),
                      ),
                    ),
                    if (_logTray.length > 2)
                      Semantics(
                        identifier: 'food-tray-view-all',
                        child: TextButton(
                          onPressed: () => setState(() => _fullTray = true),
                          child: Text(s.foodTrayViewAll(_logTray.length)),
                        ),
                      ),
                  ],
                ),
                const Divider(height: 1),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      identifier: 'add-meal-review-tray',
                      child: InkWell(
                        onTap: _fullTray ? null : _reviewLogTray,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Badge(
                                isLabelVisible: !_logTray.isEmpty,
                                label: Text(_logTray.length.toString()),
                                child: const Icon(
                                  Icons.receipt_long_rounded,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      s.foodTrayShortTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelLarge,
                                    ),
                                    Text(
                                      _logTray.isEmpty
                                          ? '—'
                                          : EnergyDisplay.formatSumWithUnit(
                                              context,
                                              _logTray.items.map(
                                                (item) => item.kcal,
                                              ),
                                            ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              if (!_fullTray)
                                Icon(
                                  showItems
                                      ? Icons.expand_more
                                      : Icons.expand_less,
                                  size: 18,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _logTray.isEmpty
                        ? FilledButton(
                            onPressed: null,
                            child: Text(s.foodTrayRecord),
                          )
                        : LogTrayLogButton(
                            tray: _logTray,
                            compact: true,
                            onPressed: _logging || _quickAdding.isNotEmpty
                                ? null
                                : _logAll,
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _reviewLogTray() {
    if (_logTray.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      if (MediaQuery.sizeOf(context).height /
              MediaQuery.textScalerOf(context).scale(1) <
          450) {
        _fullTray = true;
      } else {
        _trayExpanded = !_trayExpanded;
      }
    });
  }

  Widget _buildFullTray() => SafeArea(
    top: false,
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            identifier: 'food-tray-back-to-library',
            child: TextButton.icon(
              onPressed: () => setState(() => _fullTray = false),
              icon: const Icon(Icons.arrow_back),
              label: Text(S.of(context).loggingFoodLibrary),
            ),
          ),
          _trayList(),
          const SizedBox(height: 12),
          Semantics(
            identifier: 'food-tray-save-recipe',
            child: OutlinedButton.icon(
              onPressed: _logTray.isEmpty ? null : _saveTrayAsRecipe,
              icon: const Icon(Icons.menu_book_outlined),
              label: Text(S.of(context).saveAsMealLabel),
            ),
          ),
        ],
      ),
    ),
  );

  void _saveTrayAsRecipe() {
    final ingredients = [
      for (final item in _logTray.items)
        RecipeIngredientEntity(
          snapshotMeal: item.meal,
          amount: item.amount,
          unit: item.meal.isLiquid ? 'ml' : 'g',
          convertedAmountG: item.amount,
        ),
    ];
    Navigator.of(context).pushNamed(
      NavigationOptions.recipeBuilderRoute,
      arguments: RecipeBuilderArguments(initialIngredients: ingredients),
    );
  }

  void _onProductsRefreshButtonPressed() {
    _productsBloc.add(const RefreshProductsEvent());
  }

  void _onFoodRefreshButtonPressed() {
    _foodBloc.add(const RefreshFoodEvent());
  }

  void _onAllSourcesRefreshButtonPressed() {
    _onProductsRefreshButtonPressed();
    _onFoodRefreshButtonPressed();
  }

  void _onRecentMealsRefreshButtonPressed() {
    _recentMealBloc.add(const LoadRecentMealEvent(searchString: ""));
  }

  void _onFavouritesRefreshButtonPressed() {
    _favouriteMealBloc.add(
      LoadFavouriteMealEvent(searchString: _searchStringListener.value),
    );
  }

  /// Resolves the source to search for a query: an empty query always returns
  /// to Recent; a non-empty query searches Products by default, unless the user
  /// has explicitly chosen Food. Keeps the chip selection and the results in sync.
  /// Favourites is the exception — a chosen list the query filters, so typing
  /// or clearing the field keeps the user on it.
  _SearchSource _resolveSource(String trimmed) {
    if (_source == _SearchSource.favourites) return _SearchSource.favourites;
    if (_source == _SearchSource.custom) return _SearchSource.custom;
    if (trimmed.isEmpty) {
      return _catalog != null ? _source : _SearchSource.recent;
    }
    if (_source == _SearchSource.recent) {
      // Typing searches every source at once (All) by default — unless the
      // user explicitly chose the Recent chip, in which case it stays put
      // and filters recent history instead (#576).
      return _stickOnRecent ? _SearchSource.recent : _SearchSource.all;
    }
    // An explicit Products / Food choice narrows that merged list.
    return _source;
  }

  bool _searchesProducts(_SearchSource s) =>
      s == _SearchSource.all || s == _SearchSource.products;
  bool _searchesFood(_SearchSource s) =>
      s == _SearchSource.all || s == _SearchSource.food;

  void _onSearchSubmit(String inputText) {
    final trimmed = inputText.trim();
    final source = _resolveSource(trimmed);
    if (source != _source) setState(() => _source = source);
    // A scannable barcode jumps straight to the scanner (product sources only).
    if (_searchesProducts(source) && isValidBarcodeCheckDigit(trimmed)) {
      Navigator.of(context).pushNamed(
        NavigationOptions.scannerRoute,
        arguments: ScannerScreenArguments(
          _day,
          _mealType.getIntakeType(),
          initialBarcode: trimmed,
          logTray: _logTray,
        ),
      );
      return;
    }
    if (_searchesProducts(source)) {
      _productsBloc.add(LoadProductsEvent(searchString: inputText));
    }
    if (_searchesFood(source)) {
      _foodBloc.add(LoadFoodEvent(searchString: inputText));
    }
    if (source == _SearchSource.recent) {
      _recentMealBloc.add(LoadRecentMealEvent(searchString: inputText));
    }
    if (source == _SearchSource.favourites) {
      _favouriteMealBloc.add(LoadFavouriteMealEvent(searchString: inputText));
    }
  }

  /// Debounced search-as-you-type. Recent filters local intake history; the
  /// remote sources debounce via their own *InputChanged events. "All" searches
  /// products and food together into one merged list.
  void _onSearchChanged(String inputText) {
    final trimmed = inputText.trim();
    final source = _resolveSource(trimmed);
    if (source != _source) setState(() => _source = source);
    if (_searchesProducts(source)) {
      _productsBloc.add(SearchInputChangedEvent(searchString: inputText));
    }
    if (_searchesFood(source)) {
      _foodBloc.add(SearchFoodInputChangedEvent(searchString: inputText));
    }
    if (source == _SearchSource.recent) {
      // Filters the history already in memory rather than re-reading the
      // whole intake box on every keystroke.
      _recentMealBloc.add(
        RecentMealSearchChangedEvent(searchString: inputText),
      );
    }
    if (source == _SearchSource.favourites) {
      _favouriteMealBloc.add(LoadFavouriteMealEvent(searchString: inputText));
    }
  }

  void _selectSource(_SearchSource source) {
    setState(() {
      _source = source;
      if (source == _SearchSource.custom) _categoryId = null;
      _stickOnRecent = source == _SearchSource.recent;
    });
    final query = _searchStringListener.value;
    if (_searchesProducts(source)) {
      _productsBloc.add(LoadProductsEvent(searchString: query));
    }
    if (_searchesFood(source)) {
      _foodBloc.add(LoadFoodEvent(searchString: query));
    }
    if (source == _SearchSource.recent) {
      _recentMealBloc.add(LoadRecentMealEvent(searchString: query));
    }
    if (source == _SearchSource.favourites) {
      _favouriteMealBloc.add(LoadFavouriteMealEvent(searchString: query));
    }
  }

  // #576: "Search all" CTA on an empty filtered-Recent result — switches to
  // the All chip without the user having to find and tap it themselves.
  void _onSearchAllPressed() => _selectSource(_SearchSource.all);

  Widget _buildSourceChips(
    BuildContext context,
    AppPalette palette, {
    bool compact = false,
  }) {
    Widget chip(_SearchSource source, String label) => Padding(
      padding: const EdgeInsets.only(right: Dimens.spacing8),
      child: ChoiceChip(
        visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
        label: Text(label),
        selected: _source == source,
        showCheckmark: false,
        onSelected: (_) => _selectSource(source),
      ),
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            chip(_SearchSource.recent, S.of(context).recentlyAddedLabel),
            Semantics(
              identifier: 'add-meal-source-favourites',
              child: chip(
                _SearchSource.favourites,
                S.of(context).favouritesLabel,
              ),
            ),
            Semantics(
              identifier: 'add-meal-source-custom',
              child: chip(
                _SearchSource.custom,
                S.of(context).loggingCustomFoods,
              ),
            ),
            chip(_SearchSource.all, S.of(context).allItemsLabel),
            if (!locator.isRegistered<ChineseFoodDataSource>()) ...[
              chip(_SearchSource.products, S.of(context).searchProductsPage),
              chip(_SearchSource.food, S.of(context).searchFoodPage),
            ],
          ],
        ),
      ),
    );
  }

  Widget _resultsHeader(BuildContext context, AppPalette palette) => Container(
    padding: const EdgeInsets.symmetric(vertical: Dimens.spacing4),
    alignment: Alignment.centerLeft,
    child: Text(
      S.of(context).searchResultsLabel,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: palette.textMuted,
      ),
    ),
  );

  /// True while the results carried by [state] lag behind [query]: the
  /// search for the current input is still debouncing or in flight. Empty
  /// views show a spinner in that window instead of a premature "no
  /// results". Sub-threshold input never searches, so it is never pending;
  /// failed states return false so the error stays visible.
  static bool _productsPending(ProductsState state, String query) {
    if (state is ProductsLoadingState) return true;
    if (!isSearchQueryLongEnough(query)) return false;
    if (state is ProductsInitial) return true;
    if (state is ProductsLoadedState) return state.query != query;
    return false;
  }

  static bool _foodPending(FoodState state, String query) {
    if (state is FoodLoadingState) return true;
    if (!isSearchQueryLongEnough(query)) return false;
    if (state is FoodInitial) return true;
    if (state is FoodLoadedState) return state.query != query;
    return false;
  }

  // Fixed-size and top-aligned: the "All" view returns this inside an
  // Expanded, whose tight constraints would otherwise stretch the
  // indicator across the whole results area.
  static const _pendingSpinner = Align(
    alignment: Alignment.topCenter,
    child: Padding(
      padding: EdgeInsets.only(top: 32),
      child: SizedBox(
        width: 36,
        height: 36,
        child: CircularProgressIndicator(),
      ),
    ),
  );

  List<MealEntity> _personalMeals(String query) {
    if (_categoryId != null) return const [];
    final terms = query.trim().toLowerCase().split(RegExp(r'\s+'));
    final meals =
        [
          ..._customMealDataSource.getAllCustomMeals().map(
            MealEntity.fromMealDBO,
          ),
          if (locator.isRegistered<RecipeDataSource>())
            ...locator<RecipeDataSource>().getAllRecipes().map(
              (recipe) => RecipeEntity.fromDBO(recipe).toMealEntity(),
            ),
        ].where((meal) {
          final text = '${meal.name ?? ''} ${meal.brands ?? ''}'.toLowerCase();
          return terms.every(text.contains);
        }).toList();
    return rankMealsByRelevance(meals, query);
  }

  Widget _buildResults(BuildContext context, AppPalette palette, String query) {
    if (_catalog != null && _source == _SearchSource.all) {
      return BlocBuilder<AddMealBloc, AddMealState>(
        bloc: _addMealBloc,
        builder: (context, state) => StreamBuilder<void>(
          stream: _customFoodChanges,
          builder: (context, _) => StreamBuilder<void>(
            stream: _recipeChanges,
            builder: (context, _) => CatalogFoodResults(
              catalog: _catalog!,
              query: query,
              categoryId: _categoryId,
              personalMeals: _personalMeals(query),
              itemBuilder: (meal) => _mealCard(
                meal,
                state is AddMealLoadedState && state.usesImperialUnits,
              ),
            ),
          ),
        ),
      );
    }
    switch (_source) {
      case _SearchSource.custom:
        return _buildCustomResults(context, query);
      case _SearchSource.all:
        // One merged list across product sources; each card already shows its
        // own brand/source, so provenance stays clear.
        return Column(
          children: [
            _resultsHeader(context, palette),
            Expanded(
              child: BlocBuilder<ProductsBloc, ProductsState>(
                bloc: _productsBloc,
                builder: (context, ps) {
                  return BlocBuilder<FoodBloc, FoodState>(
                    bloc: _foodBloc,
                    builder: (context, fs) {
                      // Wait for BOTH sources (OFF and the Supabase backend)
                      // before rendering the merged list — showing whichever
                      // lands first would make results pop in and shift when
                      // the second source arrives. A failed source counts as
                      // answered so one outage doesn't block the other's
                      // results, but it is tracked separately from a genuine
                      // zero-result answer so the two never look the same.
                      if (_productsPending(ps, query) ||
                          _foodPending(fs, query)) {
                        return _pendingSpinner;
                      }
                      // A provider timeout or rate limit doesn't fail the
                      // bloc: the use case falls back to local matches and
                      // flags the gap on the loaded state instead.
                      final productsFailed =
                          ps is ProductsFailedState ||
                          (ps is ProductsLoadedState && ps.remoteSourceFailed);
                      final foodFailed =
                          fs is FoodFailedState ||
                          (fs is FoodLoadedState && fs.remoteSourceFailed);
                      final VoidCallback retryFailed =
                          productsFailed && foodFailed
                          ? _onAllSourcesRefreshButtonPressed
                          : (productsFailed
                                ? _onProductsRefreshButtonPressed
                                : _onFoodRefreshButtonPressed);
                      final products = ps is ProductsLoadedState
                          ? ps.products
                          : const <MealEntity>[];
                      final foods = fs is FoodLoadedState
                          ? fs.food
                          : const <MealEntity>[];
                      final merged = mergeAndRankMeals(products, foods, query);
                      final imperial = ps is ProductsLoadedState
                          ? ps.usesImperialUnits
                          : (fs is FoodLoadedState
                                ? fs.usesImperialUnits
                                : false);
                      if (merged.isEmpty) {
                        if (ps is ProductsInitial && fs is FoodInitial) {
                          return const DefaultsResultsWidget();
                        }
                        if (productsFailed && foodFailed) {
                          // Scrollable for the same reason as the partial
                          // branch below: on a landscape phone the space
                          // left in this Expanded is shorter than the error,
                          // which would overflow and push Retry off screen.
                          return SingleChildScrollView(
                            child: ErrorDialog(
                              errorText: S.of(context).errorFetchingProductData,
                              onRefreshPressed:
                                  _onAllSourcesRefreshButtonPressed,
                              retryIdentifier: 'search-all-retry',
                            ),
                          );
                        }
                        // Exactly one source failed: the other genuinely has
                        // zero matches, so this is not a hard error, but it
                        // is not a confirmed "no results" from both sources
                        // either — say so instead of only offering the
                        // scan/create actions a real zero-result state gets.
                        if (productsFailed || foodFailed) {
                          // SingleChildScrollView, not a plain Column: this
                          // sits directly inside the Expanded above, and
                          // NoResultsWidget alone already relies on its own
                          // internal scroll view to stay overflow-safe on a
                          // short viewport (see the landscape overflow this
                          // screen hit in #165). Stacking a second widget on
                          // top of it without that same protection would
                          // reintroduce that overflow.
                          return SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                PartialResultsNotice(onRetry: retryFailed),
                                NoResultsWidget(
                                  onScanBarcode: _onBarcodeIconPressed,
                                  onCreateCustomFood: () =>
                                      _onCustomAddButtonPressed(imperial),
                                ),
                              ],
                            ),
                          );
                        }
                        return NoResultsWidget(
                          onScanBarcode: _onBarcodeIconPressed,
                          onCreateCustomFood: () =>
                              _onCustomAddButtonPressed(imperial),
                        );
                      }
                      return Column(
                        children: [
                          // Both down with local matches left: say nothing
                          // online answered, not that one source is missing.
                          if (productsFailed || foodFailed)
                            PartialResultsNotice(
                              onRetry: retryFailed,
                              allSourcesDown: productsFailed && foodFailed,
                            ),
                          Expanded(
                            child: Semantics(
                              identifier: 'add-meal-all-list',
                              container: true,
                              child: ListView.builder(
                                itemCount: merged.length,
                                itemBuilder: (context, index) =>
                                    _mealCard(merged[index], imperial),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      case _SearchSource.products:
        return Column(
          children: [
            _resultsHeader(context, palette),
            BlocBuilder<ProductsBloc, ProductsState>(
              bloc: _productsBloc,
              builder: (context, state) {
                if (state is ProductsInitial) {
                  return _productsPending(state, query)
                      ? _pendingSpinner
                      : const DefaultsResultsWidget();
                } else if (state is ProductsLoadingState) {
                  return _pendingSpinner;
                } else if (state is ProductsLoadedState) {
                  if (state.products.isEmpty) {
                    return Flexible(
                      child: _productsPending(state, query)
                          ? _pendingSpinner
                          : NoResultsWidget(
                              onScanBarcode: _onBarcodeIconPressed,
                              onCreateCustomFood: () =>
                                  _onCustomAddButtonPressed(
                                    state.usesImperialUnits,
                                  ),
                            ),
                    );
                  }
                  return Flexible(
                    child: Semantics(
                      identifier: 'add-meal-products-list',
                      container: true,
                      child: ListView.builder(
                        itemCount:
                            state.products.length +
                            (state.remoteSourceEmpty ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == state.products.length) {
                            return const NoResultsWidget();
                          }
                          return _mealCard(
                            state.products[index],
                            state.usesImperialUnits,
                          );
                        },
                      ),
                    ),
                  );
                } else if (state is ProductsFailedState) {
                  return ErrorDialog(
                    errorText: S.of(context).errorFetchingProductData,
                    onRefreshPressed: _onProductsRefreshButtonPressed,
                  );
                }
                return const SizedBox();
              },
            ),
          ],
        );
      case _SearchSource.food:
        return Column(
          children: [
            _resultsHeader(context, palette),
            BlocBuilder<FoodBloc, FoodState>(
              bloc: _foodBloc,
              builder: (context, state) {
                if (state is FoodInitial) {
                  return _foodPending(state, query)
                      ? _pendingSpinner
                      : const DefaultsResultsWidget();
                } else if (state is FoodLoadingState) {
                  return _pendingSpinner;
                } else if (state is FoodLoadedState) {
                  if (state.food.isEmpty) {
                    return Flexible(
                      child: _foodPending(state, query)
                          ? _pendingSpinner
                          : NoResultsWidget(
                              onScanBarcode: _onBarcodeIconPressed,
                              onCreateCustomFood: () =>
                                  _onCustomAddButtonPressed(
                                    state.usesImperialUnits,
                                  ),
                            ),
                    );
                  }
                  return Flexible(
                    child: Semantics(
                      identifier: 'add-meal-food-list',
                      container: true,
                      child: ListView.builder(
                        itemCount:
                            state.food.length +
                            (state.remoteSourceEmpty ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == state.food.length) {
                            return const NoResultsWidget();
                          }
                          return _mealCard(
                            state.food[index],
                            state.usesImperialUnits,
                          );
                        },
                      ),
                    ),
                  );
                } else if (state is FoodFailedState) {
                  return ErrorDialog(
                    errorText: S.of(context).errorFetchingProductData,
                    onRefreshPressed: _onFoodRefreshButtonPressed,
                  );
                }
                return const SizedBox();
              },
            ),
          ],
        );
      case _SearchSource.favourites:
        return _buildFavouriteResults(context, query);
      case _SearchSource.recent:
        return BlocBuilder<RecentMealBloc, RecentMealState>(
          bloc: _recentMealBloc,
          builder: (context, state) {
            if (state is RecentMealInitial) {
              _recentMealBloc.add(const LoadRecentMealEvent(searchString: ""));
              return const SizedBox();
            } else if (state is RecentMealLoadingState) {
              return const Padding(
                padding: EdgeInsets.only(top: 32),
                child: CircularProgressIndicator(),
              );
            } else if (state is RecentMealLoadedState) {
              final meals = _categoryMeals(state.recentMeals);
              if (meals.isNotEmpty) {
                return Semantics(
                  identifier: 'add-meal-recent-list',
                  container: true,
                  child: ListView.builder(
                    itemCount: meals.length,
                    itemBuilder: (context, index) {
                      return _mealCard(meals[index], state.usesImperialUnits);
                    },
                  ),
                );
              }
              if (query.trim().isEmpty) {
                // Scrollable: the entry tiles above leave a landscape phone
                // less height here than the hint needs (#165).
                return SingleChildScrollView(
                  child: EmptyHint(
                    icon: Icons.history_rounded,
                    title: S.of(context).noMealsRecentlyAddedLabel,
                  ),
                );
              }
              return NoResultsWidget(
                onScanBarcode: _onBarcodeIconPressed,
                onCreateCustomFood: () =>
                    _onCustomAddButtonPressed(state.usesImperialUnits),
                // All skips queries below minQueryLength, so only offer it
                // once the query is long enough to actually search.
                onSearchAll: _stickOnRecent && isSearchQueryLongEnough(query)
                    ? _onSearchAllPressed
                    : null,
              );
            } else if (state is RecentMealFailedState) {
              return ErrorDialog(
                errorText: S.of(context).noMealsRecentlyAddedLabel,
                onRefreshPressed: _onRecentMealsRefreshButtonPressed,
              );
            }
            return const SizedBox();
          },
        );
    }
  }

  Widget _buildFavouriteResults(BuildContext context, String query) {
    return BlocBuilder<FavouriteMealBloc, FavouriteMealState>(
      bloc: _favouriteMealBloc,
      builder: (context, state) {
        if (state is FavouriteMealInitial) {
          _favouriteMealBloc.add(LoadFavouriteMealEvent(searchString: query));
          return const SizedBox();
        } else if (state is FavouriteMealLoadingState) {
          return const Padding(
            padding: EdgeInsets.only(top: 32),
            child: CircularProgressIndicator(),
          );
        } else if (state is FavouriteMealLoadedState) {
          final meals = _categoryMeals(state.favourites);
          if (meals.isNotEmpty) {
            return Semantics(
              identifier: 'add-meal-favourites-list',
              container: true,
              child: ListView.builder(
                itemCount: meals.length,
                itemBuilder: (context, index) =>
                    _mealCard(meals[index], state.usesImperialUnits),
              ),
            );
          }
          if (query.trim().isEmpty) {
            // Scrollable for the same reason as the empty Recent hint.
            return SingleChildScrollView(
              child: EmptyHint(
                icon: Icons.star_outline_rounded,
                title: S.of(context).favouritesEmptyTitle,
                subtitle: S.of(context).favouritesEmptySubtitle,
              ),
            );
          }
          return NoResultsWidget(
            onScanBarcode: _onBarcodeIconPressed,
            onCreateCustomFood: () =>
                _onCustomAddButtonPressed(state.usesImperialUnits),
          );
        } else if (state is FavouriteMealFailedState) {
          return ErrorDialog(
            errorText: S.of(context).errorLoadingFavourites,
            onRefreshPressed: _onFavouritesRefreshButtonPressed,
            retryIdentifier: 'add-meal-favourites-retry',
          );
        }
        return const SizedBox();
      },
    );
  }

  Widget _buildCustomResults(BuildContext context, String query) =>
      BlocBuilder<AddMealBloc, AddMealState>(
        bloc: _addMealBloc,
        builder: (context, state) {
          if (state is! AddMealLoadedState) return _pendingSpinner;
          return StreamBuilder<void>(
            stream: _customFoodChanges,
            builder: (context, snapshot) {
              List<MealEntity> meals;
              try {
                if (snapshot.hasError) throw snapshot.error!;
                final terms = query.trim().toLowerCase().split(RegExp(r'\s+'));
                meals = _customMealDataSource
                    .getAllCustomMeals()
                    .map(MealEntity.fromMealDBO)
                    .where((meal) {
                      final text = '${meal.name ?? ''} ${meal.brands ?? ''}'
                          .toLowerCase();
                      return terms.every(text.contains);
                    })
                    .toList();
                if (query.trim().isNotEmpty) {
                  meals = rankMealsByRelevance(meals, query);
                }
              } catch (error, stackTrace) {
                _log.warning('Reading custom foods failed', error, stackTrace);
                return ErrorDialog(
                  errorText: S.of(context).errorFetchingProductData,
                  onRefreshPressed: () => setState(() {}),
                );
              }
              if (meals.isEmpty) {
                return SingleChildScrollView(
                  child: Column(
                    children: [
                      EmptyHint(
                        icon: Icons.edit_note_rounded,
                        title: query.trim().isEmpty
                            ? S.of(context).customMealsEmptyLabel
                            : S.of(context).noResultsFound,
                      ),
                      Semantics(
                        identifier: 'food-library-create-custom',
                        child: TextButton.icon(
                          onPressed: () => _onCustomAddButtonPressed(
                            state.usesImperialUnits,
                          ),
                          icon: const Icon(Icons.add_rounded),
                          label: Text(S.of(context).noResultsCreateCustomFood),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return Semantics(
                identifier: 'add-meal-custom-list',
                container: true,
                child: ListView.builder(
                  itemCount: meals.length,
                  itemBuilder: (context, index) =>
                      _mealCard(meals[index], state.usesImperialUnits),
                ),
              );
            },
          );
        },
      );

  void _onBarcodeIconPressed() {
    Navigator.of(context).pushNamed(
      NavigationOptions.scannerRoute,
      arguments: ScannerScreenArguments(
        _day,
        _mealType.getIntakeType(),
        logTray: _logTray,
      ),
    );
  }

  Future<void> _openNutritionLabel() async {
    final meal = await Navigator.of(context).push<MealEntity>(
      MaterialPageRoute(builder: (_) => const NutritionLabelScreen()),
    );
    if (!mounted || meal == null) return;
    if (_isFoodLibrary) {
      setState(() {
        _source = _SearchSource.custom;
        _categoryId = null;
      });
      return;
    }
    final state = _addMealBloc.state;
    if (state is AddMealLoadedState) {
      await _onQuickAddToTray(meal, state.usesImperialUnits);
    }
  }

  /// A search result, wired to this screen's list: opening it adds there,
  /// and its + asks for an explicit amount before adding to the list.
  Widget _mealCard(MealEntity meal, bool usesImperialUnits) => MealItemCard(
    day: _day,
    mealEntity: meal,
    compact: _catalog != null,
    addMealType: _mealType,
    usesImperialUnits: usesImperialUnits,
    logTray: _logTray,
    onQuickAdd: () => _onQuickAddToTray(meal, usesImperialUnits),
  );

  Future<void> _onQuickAddToTray(
    MealEntity meal,
    bool usesImperialUnits,
  ) async {
    final code = meal.code ?? '';
    // A second tap while the first is still fetching would add it twice.
    if (_quickAdding.contains(code)) return;
    // Through setState: the log button waits for these (see build).
    setState(() => _quickAdding.add(code));
    // So a sheet open meanwhile adds to the list rather than logging on its
    // own and leaving before this food arrives (LogTray.collects).
    _logTray.beginPending();
    try {
      meal = await _detailedForQuickAdd(meal);
    } finally {
      // Not once the screen has gone: it disposes the list with it, and a
      // disposed notifier must not be told anything.
      if (mounted) {
        _logTray.endPending();
        setState(() => _quickAdding.remove(code));
      }
    }
    if (!mounted) return;
    final item = await showFoodQuantitySheet(
      context: context,
      meal: meal,
      day: _day,
      type: _mealType.getIntakeType(),
      usesImperialUnits: usesImperialUnits,
    );
    if (!mounted || item == null) return;
    // No snackbar: the count on the log button is the confirmation, and a
    // snackbar would sit over the next result someone is about to tap.
    _logTray.add(item);
  }

  /// The full record behind a thin Open Food Facts search hit, so the +
  /// picks the serving the detail screen would pick. Falls back to the thin
  /// record when the fetch fails, as the detail screen does.
  Future<MealEntity> _detailedForQuickAdd(MealEntity meal) async {
    try {
      return await fetchDetailedOffMeal(
            meal,
            locator<RemoteSearchCacheDataSource>(),
            locator<ProductsRepository>(),
          ) ??
          meal;
    } catch (e, stackTrace) {
      _log.warning('Quick-add hydration failed', e, stackTrace);
      return meal;
    }
  }

  /// Writes the whole list, then returns to the day it was logged to.
  Future<void> _logAll() async {
    if (_logging || _quickAdding.isNotEmpty || _logTray.isEmpty) return;
    // The screen ignores input until this returns (see build), so the list
    // cannot change under the writes below.
    setState(() => _logging = true);
    final mealDetailBloc = locator<MealDetailBloc>();
    final type = _mealType.getIntakeType();
    final written = <LogTrayItem>[];
    try {
      // Sequential, not concurrent: the tracked-day totals are a
      // read-modify-write, and overlapping writes would lose updates.
      for (final item in _logTray.items) {
        if (!mounted) return;
        await mealDetailBloc.addIntake(
          context,
          item.unit,
          item.amount.toString(),
          item.intakeType ?? type,
          item.meal,
          _day,
        );
        written.add(item);
        if (item.batchMatchQuery case final query?) {
          final identity = LocalBatchMatcher.foodIdentity(item.meal);
          if (identity != null) {
            try {
              await FoodEntryPreferences.current?.rememberBatchMatch(
                batchFoodKey(query),
                identity,
              );
            } catch (error) {
              _log.warning('Saving confirmed batch preference failed', error);
            }
          }
        }
      }
    } catch (e, stackTrace) {
      _log.severe('Logging the to-log list failed', e, stackTrace);
      if (!mounted) return;
      // What was written stays written; only the rest waits for a retry,
      // so trying again cannot log anything twice.
      _logTray.removeAll(written);
      setState(() => _logging = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).logTrayLogFailedLabel)),
      );
      return;
    } finally {
      _refreshLoggedDays(written.length);
    }
    if (!mounted) return;
    _logTray.clear();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(S.of(context).infoAddedIntakeLabel)));
    Navigator.of(
      context,
    ).popUntil(namedRouteOrFirst(NavigationOptions.mainRoute));
  }

  void _refreshLoggedDays(int written) {
    if (written == 0) return;
    locator<HomeBloc>().add(const LoadItemsEvent());
    locator<DiaryBloc>().add(const LoadDiaryYearEvent());
    locator<CalendarDayBloc>().add(const RefreshCalendarDayEvent());
  }

  Future<void> _confirmDiscardTray() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.of(dialogContext).discardChangesTitle),
        content: Text(S.of(dialogContext).discardChangesContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(S.of(dialogContext).dialogCancelLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(S.of(dialogContext).discardChangesConfirmLabel),
          ),
        ],
      ),
    );
    if (discard != true || !mounted) return;
    _logTray.clear();
    Navigator.of(context).pop();
  }

  Future<void> _openLocalBatch() async {
    final state = _addMealBloc.state;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => LocalBatchScreen(
          logTray: _logTray,
          day: _day,
          type: _mealType.getIntakeType(),
          usesImperialUnits:
              state is AddMealLoadedState && state.usesImperialUnits,
        ),
      ),
    );
  }

  /// Snap meal and Describe both end on the review screen: a photo or a
  /// description becomes rows the user checks before anything is logged.
  Future<void> _openBulkAdd({
    String? initialText,
    bool startWithPhoto = false,
  }) async {
    final state = _addMealBloc.state;
    await Navigator.of(context).pushNamed(
      NavigationOptions.bulkAddRoute,
      arguments: BulkAddScreenArguments(
        _mealType.getIntakeType(),
        _day,
        state is AddMealLoadedState && state.usesImperialUnits,
        initialText: initialText,
        startWithPhoto: startWithPhoto,
        logTray: _logTray,
      ),
    );
    // The review screen can open the AI settings, where the features can be
    // hidden or shown again.
    await _refreshAiHidden();
  }

  void _onQuickAddPressed() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => QuickAddBottomSheet(
        intakeType: _mealType.getIntakeType(),
        day: _day,
        logTray: _logTray,
      ),
    );
  }

  void _onCustomAddButtonPressed(bool usesImperialUnits) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(S.of(context).createCustomDialogTitle),
          content: Text(S.of(context).createCustomDialogContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(), // close dialog
              child: Text(S.of(context).dialogCancelLabel),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                _openEditMealScreen(usesImperialUnits);
              },
              child: Text(S.of(context).buttonYesLabel),
            ),
          ],
        );
      },
    );
  }

  void _openEditMealScreen(bool usesImperialUnits) {
    Navigator.of(context).pushNamed(
      NavigationOptions.editMealRoute,
      arguments: EditMealScreenArguments(
        _day,
        MealEntity.empty(),
        _mealType.getIntakeType(),
        usesImperialUnits,
        logTray: _logTray,
      ),
    );
  }
}

class AddMealScreenArguments {
  final AddMealType mealType;
  final DateTime day;

  final bool isFoodLibrary;
  final MealEntity? initialMeal;
  final List<LogTrayItem> initialItems;

  AddMealScreenArguments(
    this.mealType,
    this.day, {
    this.isFoodLibrary = false,
    this.initialMeal,
    this.initialItems = const [],
  });
}

enum _SearchSource { recent, favourites, custom, all, products, food }
