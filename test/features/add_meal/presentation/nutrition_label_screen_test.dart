import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/nutrition_label_draft.dart';
import 'package:opennutritracker/features/add_meal/presentation/screens/nutrition_label_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';

const _draft = NutritionLabelDraft(
  name: '燕麦片',
  brand: '测试品牌',
  basisQuantity: 30,
  energy: 450,
  energyUnit: 'kJ',
  protein: 3,
  fat: 2,
  carbs: 20,
);
final _capture = GlobalKey();

Finder _field(String id) => find.descendant(
  of: find.bySemanticsIdentifier('nutrition-label-$id'),
  matching: find.byType(TextFormField),
);

Future<void> _open(
  WidgetTester tester, {
  required Future<void> Function(MealEntity) save,
  void Function(MealEntity?)? returned,
  bool dark = false,
  double scale = 1,
}) async {
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
      theme: buildAppTheme(dark ? AppPalette.dark : AppPalette.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: RepaintBoundary(key: _capture, child: child!),
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            child: const Text('open'),
            onPressed: () async {
              final result = await Navigator.of(context).push<MealEntity>(
                MaterialPageRoute(
                  builder: (_) =>
                      NutritionLabelScreen(initialDraft: _draft, onSave: save),
                ),
              );
              returned?.call(result);
            },
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('GENERATE_GOAL_PREVIEW')) return;
    final file = File('C:/Windows/Fonts/msyh.ttc');
    if (file.existsSync()) {
      await (FontLoader(
        'Nunito',
      )..addFont(file.readAsBytes().then(ByteData.sublistView))).load();
    }
    final icons = Platform.environment['FOOD_PREVIEW_ICON_FONT'];
    if (icons != null) {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(File(icons).readAsBytes().then(ByteData.sublistView))).load();
    }
  });

  testWidgets('corrected label saves a custom food once and returns it', (
    tester,
  ) async {
    final gate = Completer<void>();
    final meals = <MealEntity>[];
    MealEntity? returned;
    await _open(
      tester,
      save: (meal) async {
        meals.add(meal);
        await gate.future;
      },
      returned: (meal) => returned = meal,
    );
    await tester.ensureVisible(_field('name'));
    await tester.enterText(_field('name'), '原味燕麦片');
    final save = find.bySemanticsIdentifier('nutrition-label-save');
    await tester.tap(save);
    await tester.pump();
    await tester.tap(save);
    await tester.pump();
    expect(meals, hasLength(1));
    expect(meals.single.name, '原味燕麦片');
    expect(meals.single.nutriments.energyKcal100, closeTo(1500 / 4.184, .001));
    expect(meals.single.nutriments.sodium100, isNull);
    gate.complete();
    await tester.pumpAndSettle();
    expect(returned, meals.single);
  });

  testWidgets('save failure preserves all corrected values for retry', (
    tester,
  ) async {
    var calls = 0;
    await _open(
      tester,
      save: (_) async {
        calls++;
        throw StateError('disk');
      },
    );
    await tester.tap(find.bySemanticsIdentifier('nutrition-label-save'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(
      tester.widget<TextFormField>(_field('energy')).controller!.text,
      '450',
    );
    await tester.tap(find.bySemanticsIdentifier('nutrition-label-save'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.byType(NutritionLabelScreen), findsOneWidget);
  });

  testWidgets('missing required values cannot silently save as zero', (
    tester,
  ) async {
    var writes = 0;
    await _open(tester, save: (_) async => writes++);
    await tester.ensureVisible(_field('energy'));
    await tester.enterText(_field('energy'), '');
    await tester.tap(find.bySemanticsIdentifier('nutrition-label-save'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(find.byType(NutritionLabelScreen), findsOneWidget);
  });

  for (final size in [const Size(360, 640), const Size(812, 375)]) {
    for (final dark in [false, true]) {
      testWidgets('label review fits $size dark=$dark at 200% with keyboard', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await _open(tester, save: (_) async {}, dark: dark, scale: 2);
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('GENERATE_GOAL_PREVIEW')) {
          await tester.runAsync(() async {
            final dir = Directory(
              const String.fromEnvironment('GOAL_PREVIEW_DIR'),
            );
            await dir.create(recursive: true);
            final boundary =
                _capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final img = await boundary.toImage(pixelRatio: 1.5);
            final data = await img.toByteData(format: ui.ImageByteFormat.png);
            await File(
              '${dir.path}/label-${size.width.toInt()}-$dark.png',
            ).writeAsBytes(data!.buffer.asUint8List());
            img.dispose();
          });
        }
        tester.view.viewInsets = FakeViewPadding(
          bottom: size.height > 400 ? 260 : 140,
        );
        await tester.pumpAndSettle();
        if (_field('energy').evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            _field('energy'),
            120,
            scrollable: find.byType(Scrollable).first,
          );
        }
        await tester.ensureVisible(_field('energy'));
        await tester.enterText(_field('energy'), '451');
        await tester.pumpAndSettle();
        final button = tester.getRect(
          find.bySemanticsIdentifier('nutrition-label-save'),
        );
        expect(
          button.bottom,
          lessThanOrEqualTo(size.height - (size.height > 400 ? 260 : 140)),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
