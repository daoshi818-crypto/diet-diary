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
        body: StatefulBuilder(
          builder: (context, refresh) => MealDetailBottomSheet(
            product: product,
            day: DateTime(2026, 9, 13),
            intakeTypeEntity: IntakeTypeEntity.breakfast,
            quantityTextController: quantityController,
            mealDetailBloc: _buildBloc(),
            selectedUnit: initialUnit,
            usesImperialUnits: usesImperialUnits,
            onQuantityOrUnitChanged: (q, u) {
              if (u != null) refresh(() => initialUnit = u);
              onChanged(q, u);
            },
            onSelectionConfirmed: onConfirm,
            confirmLabel: onConfirm == null ? null : 'Confirm amount',
          ),
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

Future<void> choosePortion(WidgetTester tester, String label) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining(label).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('pick a fifth specification and enter a fractional count', (
    tester,
  ) async {
    final controller = TextEditingController(text: '100');
    LogTrayItem? result;
    await _pumpSheet(
      tester,
      product: _riceWithPortions(),
      quantityController: controller,
      initialUnit: 'g',
      onChanged: (_, _) {},
      onConfirm: (item) async => result = item,
    );
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    await tester.tap(find.text('Portion'));
    await tester.pumpAndSettle();
    expect(controller.text, '1');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Quantity'),
      '1.5',
    );
    await tester.pumpAndSettle();
    await choosePortion(tester, '外卖盒');
    expect(controller.text, '1.5');
    await tester.tap(find.text('Confirm amount'));
    await tester.pumpAndSettle();
    expect(result!.amount, 375);
    expect(result!.selectionUnit, 'serving#4');
  });

  testWidgets('a solid food cannot switch to volume without a conversion', (
    tester,
  ) async {
    final changes = <String?>[];
    await _pumpSheet(
      tester,
      product: _solidWithServing(),
      quantityController: TextEditingController(text: '100'),
      initialUnit: 'g',
      onChanged: (_, unit) => changes.add(unit),
    );
    await tester.tap(find.text('Volume'));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
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
        initialUnit: 'serving',
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
      expect(
        dropdown.items!.where((item) => item.value == 'serving'),
        hasLength(1),
      );
      expect(
        dropdown.items!.where((item) => item.value == 'serving#1'),
        isEmpty,
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
      await tester.tap(find.text('Portion'));
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
    await tester.tap(find.text('Weight'));
    await tester.pumpAndSettle();
    expect(controller.text, '60');
    expect(changes, [('60', 'g')]);
  });

  testWidgets('plain weights do not appear in the portion menu', (
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
    await tester.tap(find.text('Portion'));
    await tester.pumpAndSettle();
    final menu = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>),
    );
    expect(menu.items!.map((item) => item.value), ['serving#1']);
  });
}
