import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
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
final _capture = GlobalKey();

Future<void> _open(
  WidgetTester tester, {
  bool activity = true,
  bool dark = false,
  double scale = 1,
  Locale locale = const Locale('en'),
  void Function(RouteSettings)? onRoute,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildAppTheme(dark ? AppPalette.dark : AppPalette.light),
      supportedLocales: S.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child: RepaintBoundary(key: _capture, child: child!),
      ),
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
              useSafeArea: true,
              backgroundColor: Colors.transparent,
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
  setUpAll(() async {
    if (!const bool.fromEnvironment('GENERATE_GOAL_PREVIEW')) return;
    await (FontLoader('Nunito')..addFont(
          File(
            'C:/Windows/Fonts/msyh.ttc',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
    final icons = Platform.environment['FOOD_PREVIEW_ICON_FONT'];
    if (icons != null) {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(File(icons).readAsBytes().then(ByteData.sublistView))).load();
    }
  });
  testWidgets(
    'hub presents entrances and close without duplicate meal choices',
    (tester) async {
      await _open(tester);
      for (final id in [
        'logging-record-meal',
        'logging-record-water',
        'logging-food-library',
        'logging-ai-photo',
        'logging-ai-describe',
        'logging-nutrition-label',
        'logging-hub-close',
      ]) {
        expect(_id(id), findsOneWidget);
      }
      expect(find.byType(ChoiceChip), findsNothing);
      await tester.tap(_id('logging-hub-close'));
      await tester.pumpAndSettle();
      expect(_id('logging-record-meal'), findsNothing);
    },
  );

  testWidgets(
    'library keeps the suggested meal and selected date without a selector',
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
      await tester.ensureVisible(_id('logging-food-library'));
      await tester.tap(_id('logging-food-library'));
      await tester.pumpAndSettle();
      expect(args!.mealType, AddMealType.lunchType);
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

  for (final size in [const Size(375, 667), const Size(812, 375)]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'hub uses available height with a separate close $size dark=$dark scale=$scale',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            tester.view.padding = const FakeViewPadding(bottom: 24);
            addTearDown(tester.view.reset);
            await _open(
              tester,
              dark: dark,
              scale: scale,
              locale: const Locale('zh'),
            );
            final panel = tester.getRect(
              find.byKey(const ValueKey('logging-hub-panel')),
            );
            final close = tester.getRect(_id('logging-hub-close'));
            expect(panel.top, greaterThanOrEqualTo(0));
            expect(panel.bottom, lessThanOrEqualTo(close.top - 8));
            expect(close.bottom, lessThanOrEqualTo(size.height - 24));
            expect(tester.takeException(), isNull);
            if (const bool.fromEnvironment('GENERATE_GOAL_PREVIEW')) {
              await tester.runAsync(() async {
                final folder = Directory(
                  const String.fromEnvironment('GOAL_PREVIEW_DIR'),
                );
                await folder.create(recursive: true);
                final boundary =
                    _capture.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary;
                final img = await boundary.toImage(pixelRatio: 1.5);
                final data = await img.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await File(
                  '${folder.path}/hub-${size.width.toInt()}-$dark-$scale.png',
                ).writeAsBytes(data!.buffer.asUint8List());
                img.dispose();
              });
            }
            for (final id in [
              'logging-record-meal',
              'logging-record-water',
              'logging-nutrition-label',
              'logging-food-library',
              'logging-ai-photo',
              'logging-ai-describe',
              'add-item-recipes',
            ]) {
              await tester.ensureVisible(_id(id));
              await tester.pumpAndSettle();
              expect(_id(id).hitTestable(), findsOneWidget);
              expect(tester.getSize(_id(id)).height, greaterThanOrEqualTo(48));
            }
            await tester.tap(_id('logging-hub-close'));
            await tester.pumpAndSettle();
            expect(find.byType(AddItemBottomSheet), findsNothing);
          },
        );
      }
    }
  }
}
