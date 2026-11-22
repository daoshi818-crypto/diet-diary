import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opennutritracker/features/add_meal/data/food_catalog_updater.dart';
import 'package:opennutritracker/features/add_meal/data/data_sources/chinese_food_data_source.dart';

String food(double energy) => jsonEncode({
  'schema_version': 1,
  'foods': [
    {
      'id': 'cn-stable-food',
      'name': '熟米饭',
      'brand': '',
      'unit': 'g',
      'category': '',
      'aliases': [],
      'portions': [
        {'label': '小碗', 'grams': 100},
      ],
      'nutrients': {
        'energy_kcal': energy,
        'protein_g': 2.6,
        'fat_g': .3,
        'carbohydrate_g': 25.9,
      },
      'sources': [
        {'source': 'cn_fct', 'id': 'rice'},
      ],
    },
  ],
});
Map<String, Object?> manifest(int seq, String text) => {
  'manifest_version': 1,
  'dataset_id': 'chiyoushu-cn-foods',
  'release_seq': seq,
  'catalog_version': 'test.$seq',
  'catalog_schema_version': 1,
  'published_at': '2026-11-22T00:00:00Z',
  'source_commit': 'a' * 40,
  'file': {
    'path': 'dist/catalog.json',
    'sha256': sha256.convert(utf8.encode(text)).toString(),
    'bytes': utf8.encode(text).length,
    'food_count': 1,
  },
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUp(
    () async =>
        temp = await Directory.systemTemp.createTemp('food-update-test-'),
  );
  tearDown(() async => temp.delete(recursive: true));

  test(
    'two updates and higher-sequence rollback refresh search and preserve history',
    () async {
      var seq = 1;
      var text = food(116);
      var now = DateTime.utc(2026, 11, 22);
      final source = ChineseFoodDataSource(read: () async => food(110));
      final history = (await source.search('米饭')).single;
      final updater = FoodCatalogUpdater(
        directory: () async => temp,
        clock: () => now,
        activate: source.activate,
        client: MockClient((request) async {
          expect(request.url.scheme, 'https');
          if (request.url.path.endsWith('manifest.json')) {
            return http.Response(jsonEncode(manifest(seq, text)), 200);
          }
          expect(request.url.host, 'cdn.jsdelivr.net');
          expect(request.url.toString(), contains('@${'a' * 40}'));
          return http.Response.bytes(utf8.encode(text), 200);
        }),
      );
      await updater.check(manual: true);
      expect(updater.phase, FoodCatalogUpdatePhase.updated);
      expect((await source.search('米饭')).single.code, history.code);
      expect((await source.search('米饭')).single.nutriments.energyKcal100, 116);
      now = now.add(const Duration(seconds: 11));
      seq = 2;
      text = food(120);
      await updater.check(manual: true);
      expect((await source.search('米饭')).single.nutriments.energyKcal100, 120);
      now = now.add(const Duration(seconds: 11));
      seq = 3;
      text = food(116);
      await updater.check(manual: true);
      expect(updater.current!.sequence, 3);
      expect((await source.search('米饭')).single.nutriments.energyKcal100, 116);
      expect(history.nutriments.energyKcal100, 110);
      expect(await Directory('${temp.path}/versions/1').exists(), isFalse);
      expect(await Directory('${temp.path}/versions/2').exists(), isTrue);
      final restarted = FoodCatalogUpdater(
        directory: () async => temp,
        activate: source.activate,
        client: MockClient((_) async => http.Response('', 503)),
      );
      expect(await restarted.readInstalledCatalog(), text);
      expect(restarted.current!.sequence, 3);
      updater.dispose();
      restarted.dispose();
    },
  );

  test(
    'bad hash, older release and conflicting sequence retain active snapshot',
    () async {
      var seq = 1;
      var text = food(116);
      var corrupt = false;
      var now = DateTime.utc(2026, 11, 22);
      final source = ChineseFoodDataSource(read: () async => food(110));
      final updater = FoodCatalogUpdater(
        directory: () async => temp,
        activate: source.activate,
        clock: () => now,
        client: MockClient(
          (r) async => r.url.path.endsWith('manifest.json')
              ? http.Response(jsonEncode(manifest(seq, text)), 200)
              : http.Response.bytes(
                  utf8.encode(corrupt ? food(999) : text),
                  200,
                ),
        ),
      );
      await updater.check(manual: true);
      seq = 2;
      text = food(120);
      corrupt = true;
      now = now.add(const Duration(seconds: 11));
      await updater.check(manual: true);
      expect(updater.phase, FoodCatalogUpdatePhase.failed);
      expect(updater.current!.sequence, 1);
      expect((await source.search('米饭')).single.nutriments.energyKcal100, 116);
      seq = 1;
      corrupt = false;
      now = now.add(const Duration(seconds: 11));
      await updater.check(manual: true);
      expect(updater.phase, FoodCatalogUpdatePhase.failed);
      expect(updater.current!.sequence, 1);
      updater.dispose();
    },
  );

  test(
    'corrupt installed catalogue falls back to previous valid version',
    () async {
      var seq = 1;
      var text = food(116);
      var now = DateTime.utc(2026, 11, 22);
      final source = ChineseFoodDataSource(read: () async => food(110));
      final client = MockClient(
        (r) async => r.url.path.endsWith('manifest.json')
            ? http.Response(jsonEncode(manifest(seq, text)), 200)
            : http.Response.bytes(utf8.encode(text), 200),
      );
      final updater = FoodCatalogUpdater(
        directory: () async => temp,
        activate: source.activate,
        clock: () => now,
        client: client,
      );
      await updater.check(manual: true);
      seq = 2;
      text = food(120);
      now = now.add(const Duration(seconds: 11));
      await updater.check(manual: true);
      await File(
        '${temp.path}/versions/2/catalog.json',
      ).writeAsString('broken');
      final restarted = FoodCatalogUpdater(
        directory: () async => temp,
        activate: source.activate,
        client: client,
      );
      expect(await restarted.readInstalledCatalog(), food(116));
      expect(restarted.current!.sequence, 1);
      updater.dispose();
      restarted.dispose();
    },
  );

  test(
    'concurrent checks share one download and offline failure keeps food usable',
    () async {
      var calls = 0;
      final source = ChineseFoodDataSource(read: () async => food(116));
      final updater = FoodCatalogUpdater(
        directory: () async => temp,
        activate: source.activate,
        client: MockClient((_) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return http.Response('', 503);
        }),
      );
      await Future.wait([updater.check(), updater.check(manual: true)]);
      expect(calls, 1);
      expect(updater.phase, FoodCatalogUpdatePhase.failed);
      expect(await source.count(), 1);
      updater.dispose();
    },
  );

  test(
    'manifest and catalogue reject incompatible shape, duplicate IDs and portions',
    () async {
      final m = manifest(1, food(116));
      expect(
        () => FoodCatalogManifest.parse(
          jsonEncode({...m, 'dataset_id': 'other'}),
        ),
        throwsFormatException,
      );
      expect(
        () => FoodCatalogManifest.parse(
          jsonEncode({...m, 'catalog_schema_version': 2}),
        ),
        throwsFormatException,
      );
      final j = jsonDecode(food(116)) as Map;
      (j['foods'] as List).add(j['foods'][0]);
      await expectLater(
        ChineseFoodDataSource.validateCatalog(jsonEncode(j)),
        throwsFormatException,
      );
      final p = jsonDecode(food(116)) as Map;
      p['foods'][0]['portions'].add({'label': '重复', 'grams': 100});
      await expectLater(
        ChineseFoodDataSource.validateCatalog(jsonEncode(p)),
        throwsFormatException,
      );
    },
  );
}
