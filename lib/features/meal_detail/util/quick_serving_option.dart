import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/util/portion_unit.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/features/meal_detail/util/portion_display.dart';

/// One preset a user can tap in the meal-detail sheet to jump the
/// quantity + unit inputs to a common portion without typing.
///
/// [id] is a stable ASCII slug for building `Semantics(identifier: ...)`
/// values; [label] is the visible chip text and moves with the locale.
class QuickServingOption {
  final String id;
  final double quantity;
  final String unit;
  final String label;

  const QuickServingOption({
    required this.id,
    required this.quantity,
    required this.unit,
    required this.label,
  });
}

/// Presets for [product]. Returns an empty list when the food carries no
/// serving metadata and is not measured by mass or volume, so the sheet
/// can hide the row entirely rather than show a chip that rounds to
/// nothing meaningful.
///
/// [gramUnitLabel] is passed in so this helper stays context-free.
List<QuickServingOption> quickServingOptionsFor(
  MealEntity product,
  String gramUnitLabel, {
  bool includeWeightPresets = false,
}) {
  final servingUnit = UnitDropdownItem.serving.toString();
  final gramUnit = UnitDropdownItem.g.toString();
  final options = <QuickServingOption>[];

  if (product.portions.isNotEmpty) {
    for (final i in visiblePortionIndices(product)) {
      final portion = product.portions[i];
      options.add(
        QuickServingOption(
          id: 'portion-$i',
          quantity: 1,
          unit: portionUnit(i),
          label: portionDisplayLabel(portion, gramUnitLabel),
        ),
      );
    }
  } else if (product.scalableServingQuantity != null) {
    options.addAll([
      QuickServingOption(
        id: 'half-serving',
        quantity: 0.5,
        unit: servingUnit,
        label: '½×',
      ),
      QuickServingOption(
        id: 'one-serving',
        quantity: 1,
        unit: servingUnit,
        label: '1×',
      ),
      QuickServingOption(
        id: 'double-serving',
        quantity: 2,
        unit: servingUnit,
        label: '2×',
      ),
    ]);
  }
  // Mirror the unit dropdown's gate at meal_detail_bottom_sheet.dart:167-170,
  // so quick-add custom meals (mealUnit == 'g/ml') and liquids with no
  // serving still get the 100 g shortcut.
  if (product.isSolid || (!product.isLiquid && !product.isSolid)) {
    if (includeWeightPresets) {
      for (final grams in [50, 100, 150, 200]) {
        options.add(
          QuickServingOption(
            id: '${grams}g',
            quantity: grams.toDouble(),
            unit: gramUnit,
            label: '$grams $gramUnitLabel',
          ),
        );
      }
    } else {
      options.add(
        QuickServingOption(
          id: '100g',
          quantity: 100,
          unit: gramUnit,
          label: '100 $gramUnitLabel',
        ),
      );
    }
  }
  final weights = <int>{};
  return options.where((option) {
    double? grams;
    if (option.unit == gramUnit) {
      grams = option.quantity;
    } else if (isPortionUnit(option.unit)) {
      final index = effectivePortionIndex(option.unit);
      final base = product.portions.isNotEmpty
          ? product.portions[index].gramWeight
          : product.scalableServingQuantity;
      if (base != null) grams = base * option.quantity;
    }
    return grams == null || weights.add((grams * 1000000).round());
  }).toList();
}
