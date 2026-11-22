import 'package:opennutritracker/core/utils/id_generator.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';

class NutritionLabelDraft {
  final String name;
  final String brand;
  final double? basisQuantity;
  final String basisUnit;
  final double? energy;
  final String energyUnit;
  final double? protein;
  final double? fat;
  final double? carbs;
  final double? fiber;
  final double? sodiumMg;
  final String notes;

  const NutritionLabelDraft({
    this.name = '',
    this.brand = '',
    this.basisQuantity,
    this.basisUnit = 'g',
    this.energy,
    this.energyUnit = 'kcal',
    this.protein,
    this.fat,
    this.carbs,
    this.fiber,
    this.sodiumMg,
    this.notes = '',
  });

  factory NutritionLabelDraft.fromJson(Map<String, dynamic> json) {
    double? number(String key) {
      final value = json[key];
      if (value == null) return null;
      final n = value is num
          ? value.toDouble()
          : value is String
          ? double.tryParse(value)
          : null;
      if (n == null || !n.isFinite || n < 0) {
        throw FormatException('Invalid label field: $key');
      }
      return n;
    }

    String text(String key) =>
        json[key] is String ? (json[key] as String).trim() : '';
    final unit = text('basisUnit');
    final energyUnit = text('energyUnit');
    if (!['g', 'ml'].contains(unit) || !['kcal', 'kJ'].contains(energyUnit)) {
      throw const FormatException('Unsupported nutrition label units');
    }
    return NutritionLabelDraft(
      name: text('name'),
      brand: text('brand'),
      basisQuantity: number('basisQuantity'),
      basisUnit: unit,
      energy: number('energy'),
      energyUnit: energyUnit,
      protein: number('protein'),
      fat: number('fat'),
      carbs: number('carbs'),
      fiber: number('fiber'),
      sodiumMg: number('sodiumMg'),
      notes: text('notes'),
    );
  }

  bool get canSave {
    final basis = basisQuantity;
    if (name.isEmpty ||
        basis == null ||
        !basis.isFinite ||
        basis <= 0 ||
        basis > 10000 ||
        !['g', 'ml'].contains(basisUnit) ||
        !['kcal', 'kJ'].contains(energyUnit)) {
      return false;
    }
    final required = [energy, protein, fat, carbs];
    if (required.any((n) => n == null || !n.isFinite || n < 0)) return false;
    if ([fiber, sodiumMg].any((n) => n != null && (!n.isFinite || n < 0))) {
      return false;
    }
    final scale = 100 / basis;
    return energy! * scale / (energyUnit == 'kJ' ? 4.184 : 1) <= 1000 &&
        [protein!, fat!, carbs!, ?fiber].every((n) => n * scale <= 100) &&
        (sodiumMg == null || sodiumMg! * scale <= 100000);
  }

  MealEntity toMeal() {
    if (!canSave) throw const FormatException('Review required label values');
    final scale = 100 / basisQuantity!;
    return MealEntity(
      code: IdGenerator.getUniqueID(),
      name: name,
      brands: brand.isEmpty ? null : brand,
      url: null,
      mealQuantity: null,
      mealUnit: basisUnit,
      servingQuantity: null,
      servingUnit: null,
      servingSize: null,
      source: MealSourceEntity.custom,
      nutriments: MealNutrimentsEntity(
        energyKcal100: energy! * scale / (energyUnit == 'kJ' ? 4.184 : 1),
        carbohydrates100: carbs! * scale,
        fat100: fat! * scale,
        proteins100: protein! * scale,
        fiber100: fiber == null ? null : fiber! * scale,
        sodium100: sodiumMg == null ? null : sodiumMg! * scale,
        sugars100: null,
        saturatedFat100: null,
      ),
    );
  }
}
