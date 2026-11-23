import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/features/add_meal/data/data_sources/chinese_food_data_source.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/generated/l10n.dart';

class FoodCategoryRail extends StatelessWidget {
  final List<FoodCategory> categories;
  final String? selected;
  final ValueChanged<String?> onSelected;
  const FoodCategoryRail({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    final accent = Theme.of(context).colorScheme.primary;
    final entries = [
      FoodCategory('', S.of(context).allItemsLabel),
      ...categories,
    ];
    return SizedBox(
      width: 76,
      child: ColoredBox(
        color: palette.surfaceMuted,
        child: Semantics(
          identifier: 'food-category-rail',
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final category = entries[index];
              final active = (selected ?? '') == category.id;
              return Semantics(
                selected: active,
                child: Material(
                  color: active ? palette.canvas : Colors.transparent,
                  child: InkWell(
                    onTap: () =>
                        onSelected(category.id.isEmpty ? null : category.id),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 48),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        border: BorderDirectional(
                          start: BorderSide(
                            color: active ? accent : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                      child: Text(
                        category.label,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: active ? accent : palette.textMuted,
                              fontWeight: active
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class CatalogFoodResults extends StatefulWidget {
  final ChineseFoodDataSource catalog;
  final String query;
  final String? categoryId;
  final Widget Function(MealEntity) itemBuilder;
  final List<MealEntity> personalMeals;
  const CatalogFoodResults({
    super.key,
    required this.catalog,
    required this.query,
    required this.categoryId,
    required this.itemBuilder,
    this.personalMeals = const [],
  });

  @override
  State<CatalogFoodResults> createState() => _CatalogFoodResultsState();
}

class _CatalogFoodResultsState extends State<CatalogFoodResults> {
  final _scroll = ScrollController();
  final _foods = <MealEntity>[];
  int _generation = 0;
  int _total = 0;
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    widget.catalog.addListener(_reset);
    _scroll.addListener(_nearEnd);
    _reset();
  }

  @override
  void didUpdateWidget(CatalogFoodResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.catalog != widget.catalog) {
      oldWidget.catalog.removeListener(_reset);
      widget.catalog.addListener(_reset);
    }
    if (oldWidget.query != widget.query ||
        oldWidget.categoryId != widget.categoryId ||
        oldWidget.catalog != widget.catalog) {
      _reset();
    }
  }

  void _reset() {
    _generation++;
    _foods.clear();
    _total = 0;
    _loading = false;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _load();
  }

  void _nearEnd() {
    if (_scroll.position.extentAfter < 300 &&
        _foods.length < _total &&
        !_failed) {
      _load();
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    final generation = _generation;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page = await widget.catalog.browse(
        widget.query,
        categoryId: widget.categoryId,
        offset: _foods.length,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _foods.addAll(page.foods);
        _total = page.total;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    widget.catalog.removeListener(_reset);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _foods.isEmpty && widget.personalMeals.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_failed && _foods.isEmpty && widget.personalMeals.isEmpty) {
      return Center(
        child: Semantics(
          identifier: 'food-category-retry',
          child: TextButton(
            onPressed: _load,
            child: Text(S.of(context).retryLabel),
          ),
        ),
      );
    }
    if (_foods.isEmpty && widget.personalMeals.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            S.of(context).foodCategoryEmpty,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final personal = widget.personalMeals;
    final personalCodes = personal
        .map((meal) => meal.code)
        .whereType<String>()
        .toSet();
    final visible = [
      ...personal,
      ..._foods.where((meal) => !personalCodes.contains(meal.code)),
    ];
    return Semantics(
      identifier: 'food-category-results',
      child: ListView.builder(
        controller: _scroll,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(10, 0, 12, 12),
        itemCount: visible.length + (_foods.length < _total ? 1 : 0),
        itemBuilder: (context, index) {
          if (index < visible.length) return widget.itemBuilder(visible[index]);
          return Center(
            child: _failed
                ? TextButton(
                    onPressed: _load,
                    child: Text(S.of(context).retryLabel),
                  )
                : const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(),
                  ),
          );
        },
      ),
    );
  }
}
