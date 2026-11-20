import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/add_item_bottom_sheet.dart';
import 'package:opennutritracker/core/presentation/widgets/floating_card_panel.dart';
import 'package:opennutritracker/core/presentation/widgets/food_quantity_dialog.dart';
import 'package:opennutritracker/core/presentation/widgets/intake_details_dialog.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/generated/l10n.dart';

final _meal = MealEntity(
  code: 'layout-food',
  name: '测试食物',
  url: null,
  mealQuantity: '100',
  mealUnit: 'g',
  servingQuantity: 30,
  servingUnit: 'g',
  servingSize: '30 g',
  nutriments: const MealNutrimentsEntity(
    energyKcal100: 200,
    carbohydrates100: 20,
    fat100: 10,
    proteins100: 5,
    sugars100: null,
    saturatedFat100: null,
    fiber100: null,
  ),
  source: MealSourceEntity.custom,
);

void main() {
  testWidgets('compact hub shows all five entrances on a 360x640 phone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: S.supportedLocales,
        theme: buildAppTheme(AppPalette.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => AddItemBottomSheet(day: DateTime(2026, 11, 20)),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    Finder id(String value) => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.identifier == value,
    );
    for (final value in [
      'logging-record-meal',
      'logging-record-water',
      'logging-food-library',
      'logging-ai-photo',
      'logging-ai-describe',
      'logging-hub-close',
    ]) {
      expect(id(value).hitTestable(), findsOneWidget);
    }
    expect(
      tester.getRect(id('logging-record-water')).top,
      tester.getRect(id('logging-food-library')).top,
    );
    expect(
      tester.getRect(id('logging-ai-photo')).top,
      tester.getRect(id('logging-ai-describe')).top,
    );
    expect(
      tester.getSize(find.byType(AddItemBottomSheet)).height,
      lessThan(520),
    );
    final card = find
        .descendant(
          of: find.byType(FloatingCardPanel),
          matching: find.byType(Material),
        )
        .first;
    final close = id('logging-hub-close');
    expect(
      tester.getRect(close).top - tester.getRect(card).bottom,
      greaterThanOrEqualTo(16),
    );
    expect(tester.getSize(close), const Size(56, 56));
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(375, 667), const Size(812, 375)]) {
    for (final dark in [false, true]) {
      for (final surface in ['hub', 'details', 'quantity']) {
        testWidgets('$surface fits $size, dark=$dark, large text', (
          tester,
        ) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            ChangeNotifierProvider(
              create: (_) => EnergyUnitProvider(),
              child: MaterialApp(
                locale: const Locale('zh'),
                localizationsDelegates: const [
                  S.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                ],
                supportedLocales: S.supportedLocales,
                theme: buildAppTheme(dark ? AppPalette.dark : AppPalette.light),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: const TextScaler.linear(2),
                    disableAnimations: true,
                  ),
                  child: child!,
                ),
                home: Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () {
                        final day = DateTime(2026, 11, 20);
                        if (surface == 'hub') {
                          showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) => AddItemBottomSheet(day: day),
                          );
                        } else {
                          showDialog<void>(
                            context: context,
                            builder: (_) => surface == 'details'
                                ? IntakeDetailsDialog(
                                    intake: IntakeEntity(
                                      id: 'intake',
                                      unit: 'g',
                                      amount: 150,
                                      type: IntakeTypeEntity.lunch,
                                      meal: _meal,
                                      dateTime: day,
                                    ),
                                    usesImperialUnits: false,
                                    onEditAmount: () {},
                                  )
                                : FoodQuantityDialog(
                                    meal: _meal,
                                    day: day,
                                    type: IntakeTypeEntity.lunch,
                                    usesImperialUnits: false,
                                  ),
                          );
                        }
                      },
                      child: const Text('Open'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (surface == 'details') {
            // The dialog must show this intake's 150g, not per-100g values.
            expect(find.text('300 卡路里'), findsOneWidget);
            expect(find.text('30.0 g'), findsOneWidget);
            expect(find.text('15.0 g'), findsOneWidget);
            expect(find.text('7.5 g'), findsOneWidget);
          }
          final close = surface == 'quantity'
              ? find.text('关闭')
              : find.byTooltip('关闭');
          await tester.ensureVisible(close);
          await tester.tap(close);
          await tester.pumpAndSettle();
          expect(close, findsNothing);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
