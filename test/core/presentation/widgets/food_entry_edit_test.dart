import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/food_quantity_dialog.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/presentation/log_tray.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/log_tray_widgets.dart';
import 'package:opennutritracker/generated/l10n.dart';

final meal = MealEntity(
  code: 'rice',
  name: '米饭',
  url: null,
  mealQuantity: '100',
  mealUnit: 'g',
  servingQuantity: null,
  servingUnit: 'g',
  servingSize: null,
  source: MealSourceEntity.custom,
  nutriments: const MealNutrimentsEntity(
    energyKcal100: 116,
    carbohydrates100: 25.9,
    fat100: 0.3,
    proteins100: 2.6,
    fiber100: 1,
    sugars100: null,
    saturatedFat100: null,
    potassium100: 62,
  ),
);
Finder id(String value) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.identifier == value,
);
Widget app(Widget child) => ChangeNotifierProvider(
  create: (_) => EnergyUnitProvider(),
  child: MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: const [
      S.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: S.supportedLocales,
    home: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('saved food edits nutrients without mutating the catalog food', (
    tester,
  ) async {
    LogTrayItem? result;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            child: const Text('Open'),
            onPressed: () async {
              result = await showFoodQuantitySheet(
                context: context,
                meal: meal,
                day: DateTime(2026, 11, 22),
                type: IntakeTypeEntity.lunch,
                usesImperialUnits: false,
                editingIntake: IntakeEntity(
                  id: 'saved',
                  unit: 'g',
                  amount: 150,
                  type: IntakeTypeEntity.lunch,
                  meal: meal,
                  dateTime: DateTime(2026, 11, 22),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(id('food-edit-nutrition'));
    await tester.pumpAndSettle();
    final energy = find.descendant(
      of: id('food-nutrient-0'),
      matching: find.byType(TextFormField),
    );
    await tester.ensureVisible(energy);
    await tester.enterText(energy, '200');
    await tester.pumpAndSettle();
    await tester.ensureVisible(id('meal-detail-add'));
    await tester.tap(id('meal-detail-add'));
    await tester.pumpAndSettle();
    expect(result!.amount, 150);
    expect(result!.kcal, 300);
    expect(result!.meal.nutriments.potassium100, 62);
    expect(meal.nutriments.energyKcal100, 116);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'tray editing starts at saved weight and preserves the selected meal',
    (tester) async {
      final tray = LogTray(defaultIntakeType: IntakeTypeEntity.lunch)
        ..add(
          LogTrayItem(
            meal: meal,
            unit: 'g',
            amount: 220,
            amountLabel: '220 克',
            intakeType: IntakeTypeEntity.dinner,
          ),
        );
      await tester.pumpWidget(
        app(
          ListenableBuilder(
            listenable: tray,
            builder: (context, _) => ListView(
              children: [LogTrayList(tray: tray, day: DateTime(2026, 11, 22))],
            ),
          ),
        ),
      );
      await tester.tap(id('add-meal-tray-edit'));
      await tester.pumpAndSettle();
      final quantity = find.byType(TextFormField);
      expect(tester.widget<TextFormField>(quantity).controller!.text, '220');
      await tester.enterText(quantity, '180');
      await tester.pumpAndSettle();
      await tester.ensureVisible(id('meal-detail-add'));
      await tester.tap(id('meal-detail-add'));
      await tester.pumpAndSettle();
      expect(tray.items.single.amount, 180);
      expect(tray.items.single.intakeType, IntakeTypeEntity.dinner);
      expect(tray.totalKcal, closeTo(208.8, .01));
      expect(tester.takeException(), isNull);
    },
  );
}
