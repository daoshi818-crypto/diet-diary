import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/ai_food_draft.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/presentation/log_tray.dart';
import 'package:opennutritracker/features/add_meal/presentation/screens/ai_food_analysis_screen.dart';
import 'package:opennutritracker/features/add_meal/presentation/screens/bulk_add_screen.dart';
import 'package:opennutritracker/features/recipes/presentation/screens/recipe_builder_screen.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/ai_assist_dialog.dart';
import 'package:opennutritracker/generated/l10n.dart';

class _MemoryStorage extends FlutterSecureStorage {
  final values = <String, String>{};
  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];
  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}

AiFoodDraft _draft(String name, double amount, double kcal) =>
    AiFoodDraft.fromJson({
      'name': name,
      'amount': amount,
      'basisUnit': 'g',
      'amountEstimated': false,
      'energy': kcal,
      'protein': 10,
      'fat': 2,
      'carbs': 15,
    });
final _drafts = [
  _draft('金枪鱼', 60, 110),
  _draft('熟米饭', 220, 116),
  _draft('玉米粒', 40, 106),
];
final _capture = GlobalKey();
RecipeBuilderArguments? _recipeArgs;
late AiCredentialStorage _storage;

Finder _id(String id) => find.bySemanticsIdentifier(id);
Future<void> _see(WidgetTester tester, String id) async {
  final finder = _id(id);
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 60,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _open(
  WidgetTester tester, {
  Future<List<AiFoodDraft>> Function(String, MealPhoto?, AiSelection)? reader,
  Future<MealPhoto?> Function(ImageSource, AiSelection?)? photoPicker,
  Future<void> Function(MealEntity)? save,
  LogTray? tray,
  String? initialText,
  bool startPhoto = false,
  bool dark = false,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => EnergyUnitProvider(),
      child: MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: S.supportedLocales,
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: buildAppTheme(dark ? AppPalette.dark : AppPalette.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(key: _capture, child: child!),
        ),
        onGenerateRoute: (settings) {
          if (settings.name == NavigationOptions.recipeBuilderRoute) {
            _recipeArgs = settings.arguments as RecipeBuilderArguments;
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => const Scaffold(body: Text('recipe editor')),
            );
          }
          return null;
        },
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('open'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  settings: RouteSettings(
                    arguments: BulkAddScreenArguments(
                      IntakeTypeEntity.lunch,
                      DateTime(2026, 11, 22),
                      false,
                      initialText: initialText,
                      startWithPhoto: startPhoto,
                      logTray: tray,
                    ),
                  ),
                  builder: (_) => AiFoodAnalysisScreen(
                    reader: reader ?? (text, photo, selection) async => _drafts,
                    search: (_) async => [],
                    photoPicker: photoPicker,
                    onSaveCustom: save,
                  ),
                ),
              ),
            ),
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
  setUp(() async {
    await locator.reset();
    _recipeArgs = null;
    _storage = AiCredentialStorage(_MemoryStorage());
    await _storage.setTermsAccepted(true);
    await _storage.setActiveProvider(AiProvider.ownServer);
    await _storage.writeOwnServerConfiguration(
      endpoint: 'https://relay.example/v1',
      model: 'saved-model',
    );
    await _storage.writeApiKey('saved-key');
    locator.registerSingleton<AiCredentialStorage>(_storage);
  });
  tearDown(() => locator.reset());

  testWidgets(
    'unknown probe uses saved configuration repeatedly without opening settings',
    (tester) async {
      var calls = 0;
      await _open(
        tester,
        reader: (text, photo, selection) async {
          calls++;
          expect(text, '金枪鱼60g 熟米饭220g');
          expect(selection.modelId, 'saved-model');
          expect(selection.apiKey, 'saved-key');
          return _drafts;
        },
      );
      expect((await _storage.readProbe()).photo, AiCapability.unknown);
      expect(_id('ai-food-match-ingredients'), findsOneWidget);
      for (var i = 0; i < 2; i++) {
        await _see(tester, 'ai-food-description');
        await tester.enterText(
          find.descendant(
            of: _id('ai-food-description'),
            matching: find.byType(TextField),
          ),
          '金枪鱼60g 熟米饭220g',
        );
        await _see(tester, 'ai-food-analyze');
        await tester.tap(_id('ai-food-analyze'));
        await tester.pumpAndSettle();
        expect(find.byType(AiAssistDialog), findsNothing);
        expect(tester.takeException(), isNull);
      }
      expect(calls, 2);
    },
  );
  testWidgets(
    'corrected grams add each food and scaled nutrition to the tray',
    (tester) async {
      final tray = LogTray();
      addTearDown(tray.dispose);
      await _open(tester, tray: tray, initialText: '金枪鱼60g 熟米饭220g 玉米粒40g');
      await _see(tester, 'ai-food-amount-0');
      await tester.enterText(
        find.descendant(
          of: _id('ai-food-amount-0'),
          matching: find.byType(TextField),
        ),
        '120',
      );
      await _see(tester, 'ai-food-add');
      await tester.tap(_id('ai-food-add'));
      await tester.pumpAndSettle();
      expect(tray.items.map((i) => i.amount), [120, 220, 40]);
      expect(tray.items.every((i) => i.unit == 'g'), true);
      expect(tray.totalKcal, closeTo(429.6, .001));
      expect(find.byType(AiFoodAnalysisScreen), findsNothing);
    },
  );
  testWidgets(
    'save as a meal passes all ingredients and weights to recipe editor',
    (tester) async {
      await _open(tester, initialText: '金枪鱼60g 熟米饭220g 玉米粒40g');
      await _see(tester, 'ai-food-save-recipe');
      await tester.tap(_id('ai-food-save-recipe'));
      await tester.pumpAndSettle();
      expect(_recipeArgs!.existing, isNull);
      expect(_recipeArgs!.initialIngredients.map((i) => i.convertedAmountG), [
        60,
        220,
        40,
      ]);
      expect(_recipeArgs!.initialIngredients.map((i) => i.snapshotMeal.name), [
        '金枪鱼',
        '熟米饭',
        '玉米粒',
      ]);
    },
  );
  testWidgets('custom-food save ignores repeated taps while saving', (
    tester,
  ) async {
    final gate = Completer<void>();
    var writes = 0;
    await _open(
      tester,
      initialText: '金枪鱼60g',
      save: (meal) async {
        writes++;
        expect(meal.nutriments.energyKcal100, 110);
        await gate.future;
      },
    );
    await _see(tester, 'ai-food-custom-0');
    await tester.tap(_id('ai-food-custom-0'));
    await tester.pump();
    await tester.tap(_id('ai-food-custom-0'));
    await tester.pump();
    expect(writes, 1);
    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('photo entry uses the same unprobed provider and selected model', (
    tester,
  ) async {
    var calls = 0;
    final photo = MealPhoto(
      bytes: base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aG9sAAAAASUVORK5CYII=',
      ),
      mediaType: 'image/png',
    );
    await _open(
      tester,
      startPhoto: true,
      photoPicker: (source, selection) async {
        expect(selection!.modelId, 'saved-model');
        return photo;
      },
      reader: (text, image, selection) async {
        calls++;
        expect(image, photo);
        return [_drafts.first];
      },
    );
    await tester.tap(_id('ai-food-gallery'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.byType(AiAssistDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('removing a photo lets the next request analyze text alone', (
    tester,
  ) async {
    final photos = <MealPhoto?>[];
    final photo = MealPhoto(
      bytes: base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aG9sAAAAASUVORK5CYII=',
      ),
      mediaType: 'image/png',
    );
    await _open(
      tester,
      startPhoto: true,
      photoPicker: (_, _) async => photo,
      reader: (text, image, selection) async {
        photos.add(image);
        return [_drafts.first];
      },
    );
    await tester.tap(_id('ai-food-gallery'));
    await tester.pumpAndSettle();
    await _see(tester, 'ai-food-remove-photo');
    await tester.tap(_id('ai-food-remove-photo'));
    await tester.pumpAndSettle();
    await _see(tester, 'ai-food-description');
    await tester.enterText(
      find.descendant(
        of: _id('ai-food-description'),
        matching: find.byType(TextField),
      ),
      '金枪鱼60g',
    );
    await _see(tester, 'ai-food-analyze');
    await tester.tap(_id('ai-food-analyze'));
    await tester.pumpAndSettle();
    expect(photos, [photo, null]);
    expect(_id('ai-food-remove-photo'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'image picker failure remains on the page with a readable error',
    (tester) async {
      await _open(
        tester,
        startPhoto: true,
        photoPicker: (_, selection) async =>
            throw StateError('picker unavailable'),
      );
      await tester.tap(_id('ai-food-gallery'));
      await tester.pumpAndSettle();
      expect(find.byType(AiFoodAnalysisScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final size in [const Size(360, 640), const Size(812, 375)]) {
    for (final dark in [false, true]) {
      testWidgets(
        'AI review and editor fit $size dark=$dark at 200% with keyboard',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await _open(tester, initialText: '熟米饭220g', dark: dark, scale: 2);
          await _see(tester, 'ai-food-amount-0');
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
                '${dir.path}/ai-review-${size.width.toInt()}-$dark.png',
              ).writeAsBytes(data!.buffer.asUint8List());
              img.dispose();
            });
          }
          await _see(tester, 'ai-food-edit-0');
          await tester.tap(_id('ai-food-edit-0'));
          await tester.pumpAndSettle();
          tester.view.viewInsets = FakeViewPadding(
            bottom: size.height > 400 ? 260 : 140,
          );
          await tester.pumpAndSettle();
          final close = _id('ai-food-edit-close');
          expect(
            tester.getRect(close).bottom,
            lessThanOrEqualTo(size.height - (size.height > 400 ? 260 : 140)),
          );
          expect(tester.takeException(), isNull);
          await tester.tap(close);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
