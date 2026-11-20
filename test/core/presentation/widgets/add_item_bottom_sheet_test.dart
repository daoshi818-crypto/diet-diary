import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/add_item_bottom_sheet.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_activity/presentation/add_activity_screen.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_screen.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/features/add_meal/presentation/screens/bulk_add_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';
import '../../../helpers/test_l10n.dart';

Finder _id(String id) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.identifier == id,
);

Future<void> _open(
  WidgetTester tester, {
  bool activity = true,
  void Function(RouteSettings)? onRoute,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [S.delegate],
      supportedLocales: S.supportedLocales,
      onGenerateRoute: (settings) {
        onRoute?.call(settings);
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const Scaffold(body: Text('Destination')),
        );
      },
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => AddItemBottomSheet(
                day: DateTime(2026, 11, 19),
                showActivityTracking: activity,
                suggestedType: IntakeTypeEntity.lunch,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'hub presents five card entrances and close; meal choices stay together',
    (tester) async {
      await _open(tester);
      for (final id in [
        'logging-record-meal',
        'logging-record-water',
        'logging-food-library',
        'logging-ai-photo',
        'logging-ai-describe',
        'logging-hub-close',
      ]) {
        expect(_id(id), findsOneWidget);
      }
      expect(find.byType(ChoiceChip), findsNWidgets(4));
      await tester.tap(_id('logging-hub-close'));
      await tester.pumpAndSettle();
      expect(_id('logging-record-meal'), findsNothing);
    },
  );

  testWidgets(
    'meal selection follows into the library with the selected date',
    (tester) async {
      AddMealScreenArguments? args;
      await _open(
        tester,
        onRoute: (settings) {
          if (settings.name == NavigationOptions.addMealRoute) {
            args = settings.arguments as AddMealScreenArguments;
          }
        },
      );
      await tester.tap(_id('logging-meal-snack'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(_id('logging-food-library'));
      await tester.tap(_id('logging-food-library'));
      await tester.pumpAndSettle();
      expect(args!.mealType, AddMealType.snackType);
      expect(args!.day, DateTime(2026, 11, 19));
      expect(args!.isFoodLibrary, isTrue);
    },
  );

  testWidgets(
    'AI photo card opens the original photo flow with selected meal',
    (tester) async {
      BulkAddScreenArguments? args;
      await _open(
        tester,
        onRoute: (settings) {
          if (settings.name == NavigationOptions.bulkAddRoute) {
            args = settings.arguments as BulkAddScreenArguments;
          }
        },
      );
      await tester.ensureVisible(_id('logging-ai-photo'));
      await tester.tap(_id('logging-ai-photo'));
      await tester.pumpAndSettle();
      expect(args!.startWithPhoto, isTrue);
      expect(args!.intakeTypeEntity, IntakeTypeEntity.lunch);
    },
  );

  testWidgets('activity hub entry preserves the selected day', (tester) async {
    AddActivityScreenArguments? args;
    await _open(
      tester,
      onRoute: (settings) {
        if (settings.name == NavigationOptions.addActivityRoute) {
          args = settings.arguments as AddActivityScreenArguments;
        }
      },
    );
    final entry = find.text(l10nEn.activityLabel);
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(args?.day, DateTime(2026, 11, 19));
  });

  testWidgets('activity preference is respected by the consolidated hub', (
    tester,
  ) async {
    await _open(tester, activity: false);
    expect(find.text(l10nEn.activityLabel), findsNothing);
    expect(_id('logging-record-meal'), findsOneWidget);
  });
}
