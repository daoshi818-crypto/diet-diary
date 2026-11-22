import 'package:flutter/material.dart';
import 'package:opennutritracker/features/add_meal/presentation/log_tray.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_portion_entity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/data_source/remote_search_cache_data_source.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_macro_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/features/meal_detail/presentation/widgets/meal_detail_bottom_sheet.dart';
import 'package:opennutritracker/generated/l10n.dart';

class _FakeAddIntakeUsecase extends Fake implements AddIntakeUsecase {}

class _FakeAddTrackedDayUsecase extends Fake implements AddTrackedDayUsecase {}

class _FakeGetKcalGoalUsecase extends Fake implements GetKcalGoalUsecase {}

class _FakeGetMacroGoalUsecase extends Fake implements GetMacroGoalUsecase {}

class _FakeGetTrackedDayUsecase extends Fake implements GetTrackedDayUsecase {}

class _FakeProductsRepository extends Fake implements ProductsRepository {
  @override
  bool get usesLocalFoods => false;
}

class _FakeRemoteSearchCacheDataSource extends Fake
    implements RemoteSearchCacheDataSource {}

MealDetailBloc _buildBloc() => MealDetailBloc(
  _FakeAddIntakeUsecase(),
  _FakeAddTrackedDayUsecase(),
  _FakeGetKcalGoalUsecase(),
  _FakeGetMacroGoalUsecase(),
  _FakeGetTrackedDayUsecase(),
  _FakeProductsRepository(),
  _FakeRemoteSearchCacheDataSource(),
);

const _nutriments = MealNutrimentsEntity(
  energyKcal100: 100,
  carbohydrates100: 10,
  fat100: 5,
  proteins100: 5,
  sugars100: 2,
  saturatedFat100: 1,
  fiber100: 1,
);

MealEntity _solidWithServing({List<MealPortionEntity> portions = const []}) =>
    MealEntity(
      portions: portions,
      code: 'preset-widget-test',
      name: 'Test product',
      url: null,
      mealQuantity: null,
      mealUnit: 'g',
      servingQuantity: 30,
      servingUnit: 'g',
      servingSize: '30 g',
      nutriments: _nutriments,
      source: MealSourceEntity.off,
    );

Future<void> _pumpSheet(
  WidgetTester tester, {
  required MealEntity product,
  required TextEditingController quantityController,
  required void Function(String?, String?) onChanged,
  String initialUnit = 'serving',
  bool usesImperialUnits = false,
  Future<void> Function(LogTrayItem)? onConfirm,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [S.delegate],
      supportedLocales: S.supportedLocales,
      home: Scaffold(
        body: MealDetailBottomSheet(
          product: product,
          day: DateTime(2026, 9, 13),
          intakeTypeEntity: IntakeTypeEntity.breakfast,
          quantityTextController: quantityController,
          mealDetailBloc: _buildBloc(),
          selectedUnit: initialUnit,
          usesImperialUnits: usesImperialUnits,
          onQuantityOrUnitChanged: onChanged,
          onSelectionConfirmed: onConfirm,
          confirmLabel: onConfirm == null ? null : 'Confirm amount',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

MealEntity _riceWithPortions() => MealEntity(
  code: 'rice',
  name: '米饭',
  url: null,
  mealQuantity: '100',
  mealUnit: 'g',
  servingQuantity: 150,
  servingUnit: 'g',
  servingSize: '小碗',
  nutriments: _nutriments,
  source: MealSourceEntity.fdc,
  backendSource: 'local_calshot',
  portions: const [
    MealPortionEntity(label: '小碗', gramWeight: 150, localized: true),
    MealPortionEntity(label: '中碗', gramWeight: 200, localized: true),
    MealPortionEntity(label: '大碗', gramWeight: 300, localized: true),
    MealPortionEntity(label: '半碗', gramWeight: 100, localized: true),
    MealPortionEntity(label: '外卖盒', gramWeight: 250, localized: true),
  ],
);

Future<void> choosePortion(WidgetTester tester, String id) async {
  await tester.tap(find.bySemanticsIdentifier('meal-detail-more-portions'));
  await tester.pumpAndSettle();
  final option = find.byKey(ValueKey('portion-option-$id'));
  await tester.ensureVisible(option);
  await tester.tap(option);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a household portion fills grams and confirms that weight', (
    tester,
  ) async {
    final controller = TextEditingController(text: '100');
    final changes = <(String?, String?)>[];
    LogTrayItem? selected;
    await _pumpSheet(
      tester,
      product: _riceWithPortions(),
      quantityController: controller,
      initialUnit: 'g',
      onChanged: (q, u) => changes.add((q, u)),
      onConfirm: (item) async => selected = item,
    );
    final menu = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>),
    );
    expect(menu.items!.map((i) => i.value), ['g', 'oz']);
    await choosePortion(tester, 'portion-0');
    expect(controller.text, '150');
    expect(changes, [('150', 'g')]);
    await tester.tap(find.text('Confirm amount'));
    await tester.pumpAndSettle();
    expect(selected!.amount, 150);
    expect(selected!.unit, 'g');
  });

  testWidgets('the portion picker reaches presets beyond the first four', (
    tester,
  ) async {
    final controller = TextEditingController(text: '100');
    final changes = <(String?, String?)>[];
    await _pumpSheet(
      tester,
      product: _riceWithPortions(),
      quantityController: controller,
      initialUnit: 'g',
      onChanged: (q, u) => changes.add((q, u)),
    );
    await tester.tap(find.bySemanticsIdentifier('meal-detail-more-portions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('外卖盒 · 250 g'));
    await tester.pumpAndSettle();
    expect(controller.text, '250');
    expect(changes, [('250', 'g')]);
    expect(
      find.bySemanticsIdentifier('meal-detail-portion-options'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'one portion button opens all presets without duplicate presets',
    (tester) async {
      await _pumpSheet(
        tester,
        product: _solidWithServing(),
        quantityController: TextEditingController(text: '1'),
        onChanged: (_, _) {},
      );
      expect(find.byType(ChoiceChip), findsNothing);
      expect(
        find.bySemanticsIdentifier('meal-detail-more-portions'),
        findsOneWidget,
      );
      await tester.tap(find.bySemanticsIdentifier('meal-detail-more-portions'));
      await tester.pumpAndSettle();
      for (final id in [
        'half-serving',
        'one-serving',
        'double-serving',
        '100g',
      ]) {
        expect(find.byKey(ValueKey('portion-option-$id')), findsOneWidget);
      }
    },
  );

  testWidgets(
    'tapping the 100 g preset writes 100 into the quantity field and fires the '
    'callback with unit=g',
    (tester) async {
      final quantityController = TextEditingController(text: '1');
      String? cbQuantity;
      String? cbUnit;

      await _pumpSheet(
        tester,
        product: _solidWithServing(),
        quantityController: quantityController,
        onChanged: (q, u) {
          cbQuantity = q;
          cbUnit = u;
        },
      );

      await choosePortion(tester, '100g');

      expect(quantityController.text, '100');
      expect(cbQuantity, '100');
      expect(cbUnit, 'g');
    },
  );

  testWidgets(
    'tapping the 1× preset writes 1 into the quantity field and fires the '
    'callback with unit=serving',
    (tester) async {
      final quantityController = TextEditingController(text: '30');
      String? cbQuantity;
      String? cbUnit;

      await _pumpSheet(
        tester,
        product: _solidWithServing(),
        quantityController: quantityController,
        onChanged: (q, u) {
          cbQuantity = q;
          cbUnit = u;
        },
        initialUnit: 'g',
      );

      await choosePortion(tester, 'one-serving');

      expect(quantityController.text, '1');
      expect(cbQuantity, '1');
      expect(cbUnit, 'serving');
    },
  );

  testWidgets(
    'tapping the 0.5× preset writes 0.5 (not 1 or 0) into the quantity field',
    (tester) async {
      final quantityController = TextEditingController(text: '1');
      String? cbQuantity;
      String? cbUnit;

      await _pumpSheet(
        tester,
        product: _solidWithServing(),
        quantityController: quantityController,
        onChanged: (q, u) {
          cbQuantity = q;
          cbUnit = u;
        },
      );

      await choosePortion(tester, 'half-serving');

      expect(quantityController.text, '0.5');
      expect(cbQuantity, '0.5');
      expect(cbUnit, 'serving');
    },
  );
  testWidgets('with imperial food units the serving entry reads in oz '
      '(#1368)', (tester) async {
    await _pumpSheet(
      tester,
      product: _solidWithServing(),
      quantityController: TextEditingController(text: '1'),
      onChanged: (_, _) {},
      usesImperialUnits: true,
    );

    expect(find.text('1.06 oz'), findsOneWidget);
    expect(find.text('30 g'), findsNothing);
  });
  testWidgets('confirming two servings returns 60g without writing an intake', (
    tester,
  ) async {
    LogTrayItem? result;
    await _pumpSheet(
      tester,
      product: _solidWithServing(),
      quantityController: TextEditingController(text: '2'),
      onChanged: (_, _) {},
      onConfirm: (item) async => result = item,
    );
    expect(result, isNull);
    await tester.tap(find.text('Confirm amount'));
    await tester.pumpAndSettle();
    expect(result!.amount, 60);
    expect(result!.kcal, 60);
  });

  testWidgets(
    'named second portion scales by its own weight before confirmation',
    (tester) async {
      LogTrayItem? result;
      await _pumpSheet(
        tester,
        product: _solidWithServing(
          portions: const [
            MealPortionEntity(
              label: '1 slice',
              gramWeight: 30,
              localized: true,
            ),
            MealPortionEntity(
              label: '1 bowl',
              gramWeight: 180,
              localized: true,
            ),
          ],
        ),
        quantityController: TextEditingController(text: '2'),
        initialUnit: 'serving#1',
        onChanged: (_, _) {},
        onConfirm: (item) async => result = item,
      );
      await tester.tap(find.text('Confirm amount'));
      await tester.pumpAndSettle();
      expect(result!.amount, 360);
      expect(result!.unit, 'serving');
    },
  );

  testWidgets('zero amount cannot be confirmed', (tester) async {
    LogTrayItem? result;
    await _pumpSheet(
      tester,
      product: _solidWithServing(),
      quantityController: TextEditingController(text: '0'),
      onChanged: (_, _) {},
      onConfirm: (item) async => result = item,
    );
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirm amount'),
    );
    expect(button.onPressed, isNull);
    expect(result, isNull);
  });

  testWidgets(
    'duplicate weights stay unique and preserve the selected portion',
    (tester) async {
      LogTrayItem? result;
      await _pumpSheet(
        tester,
        product: _solidWithServing(
          portions: const [
            MealPortionEntity(label: '小个', gramWeight: 50, localized: true),
            MealPortionEntity(label: '50克', gramWeight: 50, localized: true),
          ],
        ),
        quantityController: TextEditingController(text: '2'),
        initialUnit: 'serving#1',
        onChanged: (_, _) {},
        onConfirm: (item) async => result = item,
      );
      expect(
        find.bySemanticsIdentifier('meal-detail-preset-50g'),
        findsNothing,
      );
      expect(
        find.bySemanticsIdentifier('meal-detail-preset-portion-1'),
        findsNothing,
      );
      final dropdown = tester.widget<DropdownButton<String>>(
        find.byType(DropdownButton<String>),
      );
      expect(dropdown.items!.where((item) => item.value == 'serving'), isEmpty);
      expect(
        dropdown.items!.where((item) => item.value == 'serving#1'),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Confirm amount'));
      await tester.pumpAndSettle();
      expect(result!.amount, 100);
    },
  );
  testWidgets(
    'changing grams to a serving selects one serving without a stale callback',
    (tester) async {
      final controller = TextEditingController(text: '100');
      final changes = <(String?, String?)>[];
      await _pumpSheet(
        tester,
        product: _solidWithServing(),
        quantityController: controller,
        initialUnit: 'g',
        onChanged: (q, u) => changes.add((q, u)),
      );
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .onChanged!('serving');
      await tester.pumpAndSettle();
      expect(controller.text, '1');
      expect(changes, [('1', 'serving')]);
    },
  );

  testWidgets('changing servings to grams keeps the actual weight', (
    tester,
  ) async {
    final controller = TextEditingController(text: '2');
    final changes = <(String?, String?)>[];
    await _pumpSheet(
      tester,
      product: _solidWithServing(),
      quantityController: controller,
      onChanged: (q, u) => changes.add((q, u)),
    );
    tester
        .widget<DropdownButtonFormField<String>>(
          find.byType(DropdownButtonFormField<String>),
        )
        .onChanged!('g');
    await tester.pumpAndSettle();
    expect(controller.text, '60');
    expect(changes, [('60', 'g')]);
  });

  testWidgets('plain weights are presets rather than serving units', (
    tester,
  ) async {
    await _pumpSheet(
      tester,
      product: _solidWithServing(
        portions: const [
          MealPortionEntity(label: '100克', gramWeight: 100, localized: true),
          MealPortionEntity(label: '小个', gramWeight: 50, localized: true),
        ],
      ),
      quantityController: TextEditingController(text: '100'),
      initialUnit: 'g',
      onChanged: (_, _) {},
    );
    final menu = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>),
    );
    expect(menu.items!.where((item) => item.value == 'serving'), isEmpty);
    expect(menu.items!.where((item) => item.value == 'serving#1'), isEmpty);
    await choosePortion(tester, 'portion-1');
  });
}
