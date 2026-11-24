import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/recipes/presentation/widgets/ingredient_quantity_dialog.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_portion_entity.dart';
import 'package:provider/provider.dart';

MealEntity _solidMeal({String unit = 'g'}) => MealEntity(
      code: 'flour',
      name: 'Flour',
      url: null,
      mealQuantity: null,
  mealUnit: unit,
      servingQuantity: null,
      servingUnit: null,
      servingSize: null,
      nutriments: MealNutrimentsEntity.empty(),
      source: MealSourceEntity.off,
    );

Widget _wrap({required Widget child}) {
  return ChangeNotifierProvider(
    create: (_) => EnergyUnitProvider(),
    child: MaterialApp(
    localizationsDelegates: const [S.delegate],
    supportedLocales: S.supportedLocales,
    home: child,
    ),
  );
}

void main() {
  testWidgets('returns selection on confirm', (tester) async {
    IngredientQuantitySelection? captured;

    await tester.pumpWidget(_wrap(
      child: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                captured = await showIngredientQuantityDialog(
                  context,
                  meal: _solidMeal(),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Default amount is 0; type 150 and confirm with the Add button.
    await tester.enterText(find.byType(TextFormField).first, '150');
    await tester.pumpAndSettle();
    // The confirm button label is the localized addLabel ("Add").
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.amount, 150);
    // Default unit for a solid meal without serving values is 'g'.
    expect(captured!.unit, 'g');
  });

  testWidgets('returns null when amount is invalid', (tester) async {
    IngredientQuantitySelection? captured;

    await tester.pumpWidget(_wrap(
      child: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                captured = await showIngredientQuantityDialog(
                  context,
                  meal: _solidMeal(),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Add'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.bySemanticsIdentifier('food-quantity-close'));
    await tester.pumpAndSettle();

    expect(captured, isNull);
  });

  testWidgets(
    'recipe uses named portions and returns its exact specification',
    (tester) async {
      IngredientQuantitySelection? result;
      final egg = _solidMeal().withPortions(const [
        MealPortionEntity(label: '小个', gramWeight: 40, localized: true),
        MealPortionEntity(label: '中个', gramWeight: 50, localized: true),
      ]);
      await tester.pumpWidget(
        _wrap(
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showIngredientQuantityDialog(
                    context,
                    meal: egg,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Weight'), findsWidgets);
      expect(find.text('Volume'), findsOneWidget);
      expect(find.bySemanticsIdentifier('food-detail-meal-type'), findsNothing);
      await tester.tap(find.text('Portion'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('中个').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '3');
      await tester.pumpAndSettle();
      expect(find.text('= 150 g'), findsOneWidget);
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(result!.amount, 3);
      expect(result!.unit, 'serving#1');
      expect(result!.meal.portions[1].gramWeight, 50);
    },
  );

  for (final (baseUnit, initialUnit, amount, expected) in [
    ('g', 'kg', 1.25, 1250.0),
    ('ml', 'l', 0.25, 250.0),
    ('ml', 'ml', 125.0, 125.0),
  ]) {
    testWidgets('editing $initialUnit preserves its quantity in $baseUnit', (
      tester,
    ) async {
      IngredientQuantitySelection? result;
      await tester.pumpWidget(
        _wrap(
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showIngredientQuantityDialog(
                    context,
                    meal: _solidMeal(unit: baseUnit),
                    initialAmount: amount,
                    initialUnit: initialUnit,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        double.parse(
          tester
              .widget<TextFormField>(find.byType(TextFormField))
              .controller!
              .text,
        ),
        expected,
      );
      await tester.tap(find.bySemanticsIdentifier('meal-detail-add'));
      await tester.pumpAndSettle();
      expect(result!.amount, expected);
      expect(result!.unit, baseUnit);
    });
  }

  // Edge-to-edge draws the navigation bar over the sheet; its buttons must
  // sit above the bar, not under it.
  testWidgets('keeps the Add button above the navigation bar', (tester) async {
    // A phone's height, so the whole sheet fits above the bar.
    tester.view.physicalSize = const Size(1080, 2400);
    // As a device reports a 48 dp bar, at 3x.
    tester.view.padding = const FakeViewPadding(bottom: 144);
    tester.view.viewPadding = const FakeViewPadding(bottom: 144);
    addTearDown(tester.view.reset);
    final navigationBar = 144 / tester.view.devicePixelRatio;

    await tester.pumpWidget(_wrap(
      child: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () =>
                  showIngredientQuantityDialog(context, meal: _solidMeal()),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(
      tester.getBottomLeft(find.text('Add')).dy,
      lessThanOrEqualTo(screenHeight - navigationBar),
    );
  });
}
