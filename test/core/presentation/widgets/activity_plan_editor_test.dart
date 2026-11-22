import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/activity_plan.dart';
import 'package:opennutritracker/core/presentation/widgets/activity_plan_editor.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';

Finder _id(String id) => find.bySemanticsIdentifier(id);

Future<void> _show(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      180,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String id, String value) async {
  final field = find.descendant(
    of: _id(id),
    matching: find.byType(TextFormField),
  );
  await _show(tester, field);
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
}

void main() {
  for (final palette in [AppPalette.light, AppPalette.dark]) {
    testWidgets(
      'selected activity stays readable in ${palette.brightness.name}',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: const [
              S.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: S.supportedLocales,
            theme: buildAppTheme(palette),
            home: Scaffold(
              body: SingleChildScrollView(
                child: ActivityPlanEditor(
                  value: const ActivityPlan(),
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final title = tester.widget<Text>(find.textContaining('· ×1.2'));
        final foreground = title.style!.color!;
        final background = palette.colorScheme.primaryContainer;
        final a = foreground.computeLuminance();
        final b = background.computeLuminance();
        final contrast = a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
        expect(contrast, greaterThanOrEqualTo(4.5));
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'weekly exercise adds, edits and deletes at 320px scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var value = const ActivityPlan();
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: const [
              S.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: S.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: ActivityPlanEditor(
                    value: value,
                    weightKg: 68,
                    onChanged: (plan) => setState(() => value = plan),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _show(tester, _id('activity-plan-add-exercise'));
        await tester.tap(_id('activity-plan-add-exercise'));
        await tester.pumpAndSettle();
        final fields = tester
            .widgetList<TextFormField>(find.byType(TextFormField))
            .toList();
        expect(
          fields.where((f) => f.controller?.text.isNotEmpty ?? false),
          isEmpty,
          reason: 'workout frequency and duration must come from the user',
        );
        await tester.tap(_id('exercise-save'));
        await tester.pumpAndSettle();
        expect(value.exercises, isEmpty);
        await _type(tester, 'exercise-sessions', '3');
        await _type(tester, 'exercise-minutes', '35');
        await _show(tester, _id('exercise-type'));
        await tester.tap(_id('exercise-type'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('有氧运动').last);
        await tester.pumpAndSettle();
        await _show(tester, _id('exercise-energy-source'));
        await tester.tap(_id('exercise-energy-source'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('填写活动热量').last);
        await tester.pumpAndSettle();
        await _type(tester, 'exercise-calories', '250');
        tester.testTextInput.hide();
        await tester.tap(_id('exercise-save'));
        await tester.pumpAndSettle();
        expect(value.exercises.single.type, PlannedExerciseType.cardio);
        expect(value.exercises.single.sessionsPerWeek, 3);
        expect(value.exercises.single.minutesPerSession, 35);
        expect(
          value.exercises.single.energySource,
          ExerciseEnergySource.activeCalories,
        );
        expect(value.weeklyActiveCalories(68), 750);
        await _show(tester, _id('activity-plan-edit-0'));
        await tester.tap(_id('activity-plan-edit-0'));
        await tester.pumpAndSettle();
        await _type(tester, 'exercise-calories', '300');
        tester.testTextInput.hide();
        await tester.tap(_id('exercise-save'));
        await tester.pumpAndSettle();
        expect(value.weeklyActiveCalories(68), 900);
        await _show(tester, _id('activity-plan-delete-0'));
        await tester.tap(_id('activity-plan-delete-0'));
        await tester.pumpAndSettle();
        expect(value.exercises, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
