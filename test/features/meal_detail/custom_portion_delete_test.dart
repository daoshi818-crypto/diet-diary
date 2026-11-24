import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/food_quantity_dialog.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_portion_entity.dart';
import 'package:opennutritracker/features/add_meal/presentation/log_tray.dart';
import 'package:opennutritracker/features/meal_detail/util/food_entry_preferences.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

class _Box extends Fake implements Box<String> {
  final _values = <dynamic, String>{};
  @override
  String? get(dynamic key, {String? defaultValue}) =>
      _values[key] ?? defaultValue;
  @override
  Future<void> put(dynamic key, String value) async => _values[key] = value;
  @override
  Future<void> delete(dynamic key) async => _values.remove(key);
}

class _DB extends Fake implements HiveDBProvider {
  @override
  final foodEntryBox = _Box();
  @override
  String get activeProfileId => 'test';
}

const _food = MealEntity(
  code: 'egg',
  name: '鸡蛋',
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: null,
  servingUnit: 'g',
  servingSize: null,
  nutriments: MealNutrimentsEntity(
    energyKcal100: 144,
    carbohydrates100: 2,
    proteins100: 13,
    fat100: 10,
    sugars100: null,
    saturatedFat100: null,
    fiber100: null,
  ),
  source: MealSourceEntity.custom,
  portions: [MealPortionEntity(label: '中个', gramWeight: 50, localized: true)],
);

void main() {
  late _DB db;
  late FoodEntryPreferences prefs;
  setUp(() {
    db = _DB();
    prefs = FoodEntryPreferences(db);
    GetIt.instance.registerSingleton(prefs);
  });
  tearDown(() => GetIt.instance.reset());

  for (final hasBuiltIn in [true, false]) {
    testWidgets(
      'deleting a personal portion preserves actual amount and existing snapshots (built-in: $hasBuiltIn)',
      (tester) async {
        final food = hasBuiltIn ? _food : _food.withPortions([]);
        await prefs.savePortion(food, '我的一份', 120);
        final snapshot = prefs.withCustomPortions(food);
        await prefs.remember(snapshot, hasBuiltIn ? 'serving#1' : 'serving#0');
        LogTrayItem? result;
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
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      result = await showFoodQuantitySheet(
                        context: context,
                        meal: food,
                        day: DateTime(2026, 11, 24),
                        type: IntakeTypeEntity.lunch,
                        usesImperialUnits: false,
                      );
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
        await tester.enterText(find.byType(TextFormField), '2');
        await tester.pumpAndSettle();
        final remove = find.bySemanticsIdentifier('food-delete-custom-portion');
        expect(remove, findsOneWidget);
        await tester.tap(remove);
        await tester.pumpAndSettle();
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(prefs.customPortions(food), {'我的一份': 120.0});
        await tester.tap(remove);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, '删除'));
        await tester.pumpAndSettle();
        expect(remove, findsNothing);
        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField))
              .controller!
              .text,
          '240',
        );
        final reloaded = FoodEntryPreferences(db);
        expect(reloaded.customPortions(food), isEmpty);
        expect(reloaded.lastUnit(reloaded.withCustomPortions(food)), isNull);
        expect(reloaded.withCustomPortions(food).portions, food.portions);
        expect(snapshot.portions, hasLength(hasBuiltIn ? 2 : 1));
        await tester.ensureVisible(
          find.bySemanticsIdentifier('meal-detail-add'),
        );
        await tester.tap(find.bySemanticsIdentifier('meal-detail-add'));
        await tester.pumpAndSettle();
        expect(result!.amount, 240);
        expect(result!.unit, 'g');
        expect(result!.kcal, closeTo(345.6, 0.001));
        expect(tester.takeException(), isNull);
      },
    );
  }

  test(
    'deleting an unknown or built-in portion never removes library portions',
    () async {
      await prefs.savePortion(_food, '我的一份', 120);
      await prefs.deletePortion(_food, '中个');
      expect(prefs.customPortions(_food), {'我的一份': 120});
      expect(
        prefs.withCustomPortions(_food).portions.first,
        _food.portions.first,
      );
    },
  );
}
