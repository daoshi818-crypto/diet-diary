import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/data/data_sources/chinese_food_data_source.dart';

Map<String, dynamic> catalog({bool changed = false}) => {
  'schema_version': 1,
  'categories': changed
      ? [
          {'id': 'new-group', 'label': '云端新分类'},
          {'id': 'staples', 'label': '谷薯'},
        ]
      : [
          {'id': 'staples', 'label': '主食'},
          {'id': 'vegetables', 'label': '蔬菜'},
        ],
  'foods': List.generate(
    81,
    (i) => {
      'id': 'food-$i',
      'name': i == 80 ? '西麦纯燕麦片' : '食物$i',
      'brand': '',
      'category': '',
      'category_id': changed
          ? 'new-group'
          : (i == 80 ? 'staples' : 'vegetables'),
      'unit': 'g',
      'aliases': [],
      'sources': [
        {'source': 'cn_fct', 'id': '$i'},
      ],
      'nutrients': {'energy_kcal': 100},
      'portions': [],
    },
  ),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'categories filter before pagination and support multi-word search',
    () async {
      final source = ChineseFoodDataSource(
        read: () async => jsonEncode(catalog()),
      );
      expect((await source.categories()).map((c) => c.label), ['主食', '蔬菜']);
      final page = await source.browse('', categoryId: 'staples', limit: 1);
      expect(page.total, 1);
      expect(page.foods.single.code, 'food-80');
      expect((await source.browse('西麦 麦片', categoryId: 'staples')).total, 1);
      expect((await source.browse('西麦 麦片', categoryId: 'vegetables')).total, 0);
      final first = await source.browse('', categoryId: 'vegetables');
      final second = await source.browse(
        '',
        categoryId: 'vegetables',
        offset: 60,
      );
      expect(first.total, 80);
      expect(first.foods.length, 60);
      expect(second.foods.length, 20);
      expect(
        {
          ...first.foods.map((f) => f.code),
          ...second.foods.map((f) => f.code),
        }.length,
        80,
      );
    },
  );

  test(
    'activation updates labels order membership and preserves food identity',
    () async {
      final source = ChineseFoodDataSource(
        read: () async => jsonEncode(catalog()),
      );
      final old = (await source.browse('', categoryId: 'staples')).foods.single;
      var notifications = 0;
      source.addListener(() => notifications++);
      await source.activate(jsonEncode(catalog(changed: true)));
      expect((await source.categories()).map((c) => c.id), [
        'new-group',
        'staples',
      ]);
      expect((await source.categories()).first.label, '云端新分类');
      expect(source.categoryFor(old), 'new-group');
      expect((await source.byCatalogId(old.code!))!.nutriments, old.nutriments);
      expect((await source.browse('', categoryId: 'new-group')).total, 81);
      expect(notifications, 1);
    },
  );

  test(
    'invalid categories cannot replace a working catalog; legacy data works',
    () async {
      final source = ChineseFoodDataSource(
        read: () async => jsonEncode(catalog()),
      );
      await source.categories();
      for (final invalid in [
        catalog()
          ..['categories'] = [
            {'id': 'staples', 'label': '主食'},
            {'id': 'staples', 'label': '重复'},
          ],
        catalog()
          ..['categories'] = [
            {'id': 'other', 'label': '其他'},
          ],
        catalog()
          ..['categories'] = [
            {'id': '../bad', 'label': '无效'},
          ],
      ]) {
        await expectLater(
          source.activate(jsonEncode(invalid)),
          throwsFormatException,
        );
        expect((await source.categories()).first.label, '主食');
        expect(await source.count(), 81);
      }
      final legacy = catalog()..remove('categories');
      for (final row in legacy['foods'] as List) {
        (row as Map).remove('category_id');
      }
      await source.activate(jsonEncode(legacy));
      expect(await source.categories(), isEmpty);
      expect(await source.count(), 81);
    },
  );
}
