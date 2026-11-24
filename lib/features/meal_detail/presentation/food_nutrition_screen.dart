import 'package:flutter/material.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/meal_detail/presentation/widgets/meal_detail_nutriments_table.dart';
import 'package:opennutritracker/generated/l10n.dart';

Future<void> showFoodNutritionDetails(
  BuildContext context, {
  required MealEntity meal,
  required double amount,
  required String amountLabel,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => FoodNutritionScreen(
      meal: meal,
      amount: amount,
      amountLabel: amountLabel,
    ),
  ),
);

class FoodNutritionScreen extends StatelessWidget {
  final MealEntity meal;
  final double amount;
  final String amountLabel;

  const FoodNutritionScreen({
    super.key,
    required this.meal,
    required this.amount,
    required this.amountLabel,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(S.of(context).nutritionInfoLabel)),
    body: SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                meal.name ?? '?',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (meal.brands?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 8),
                Text(meal.brands!),
              ],
              const SizedBox(height: 12),
              Text(amountLabel, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 24),
              MealDetailNutrimentsTable(
                product: meal,
                usesImperialUnits: false,
                referenceAmount: amount,
                referenceLabel: amountLabel,
                showMicronutrients: meal.nutriments.hasMicronutrientData,
              ),
              const SizedBox(height: 16),
              Semantics(
                identifier: 'food-nutrition-per-100',
                child: ExpansionTile(
                  title: Text(S.of(context).per100gmlLabel),
                  tilePadding: EdgeInsets.zero,
                  children: [
                    MealDetailNutrimentsTable(
                      product: meal,
                      usesImperialUnits: false,
                      showMicronutrients: meal.nutriments.hasMicronutrientData,
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
