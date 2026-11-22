"""Offline importer regression tests using synthetic CSVs only."""
import contextlib
import csv
import io
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path

from build_chinese_food_catalog import (
    build, clean_food_name, clean_portions, close_nutrition, number,
    fatsecret_values, metric_quantity, reference_energy,
)


class FoodCatalogueTest(unittest.TestCase):
    def test_reference_energy_only_repairs_explicit_reversed_kcal_kj_columns(self):
        self.assertEqual(reference_energy({'能量(kcal)': '221', '能量(kJ)': '53'}), (53, True))
        self.assertEqual(reference_energy({'能量(kcal)': '116', '能量(kJ)': '486'}), (116, False))
        self.assertEqual(reference_energy({'能量(kcal)': '200'}), (200, False))
        self.assertEqual(reference_energy({'能量(kcal)': '500', '能量(kJ)': '50'}), (500, False))

    def test_explicit_millilitres_never_use_or_infer_gram_density(self):
        row = {'计量基准': '每1盒 (250毫升)', '基准来源': 'derived',
               '基准克重': '275', '热量kcal': '120', '蛋白g': '5',
               '碳水g': '16', '脂肪g': '4', '每100g_热量': '999',
               '其他份量': '[{"name":"1瓶 (500毫升)","grams":550},{"name":"100克","grams":100}]'}
        nutrients, unit, portions = fatsecret_values(row)
        self.assertEqual(unit, 'ml')
        self.assertEqual(nutrients['energy_kcal'], 48)
        self.assertEqual(nutrients['protein_g'], 2)
        self.assertEqual(portions, [{'label': '1瓶 (500毫升)', 'grams': 500}])
        row['基准来源'] = 'stated'
        self.assertEqual(fatsecret_values(row)[2][0]['grams'], 250)

    def test_unknown_serving_weights_are_not_inferred_from_energy(self):
        with self.assertRaisesRegex(ValueError, '反推'):
            fatsecret_values({'计量基准': '每1杯', '基准克重': '244',
                              '基准来源': 'derived', '每100g_热量': '50'})
        self.assertEqual(metric_quantity('每1份 (15毫升)'), (15, 'ml'))
        self.assertEqual(metric_quantity('每100 ml'), (100, 'ml'))
        self.assertEqual(metric_quantity('每1份 (60克)'), (60, 'g'))
        self.assertIsNone(metric_quantity('1块 (30厘米直径)'))
        self.assertIsNone(metric_quantity('100克 / 200毫升'))

    def test_volume_portions_deduplicate_without_gram_labels(self):
        self.assertEqual(clean_portions([
            {'label': '250 ml', 'grams': 250},
            {'label': '一盒', 'grams': 250},
            {'label': '250毫升', 'grams': 250},
        ], 'ml'), [{'label': '一盒', 'grams': 250}])

    def test_new_snapshot_supersedes_old_keys_and_never_restores_excluded_rows(self):
        with tempfile.TemporaryDirectory(prefix='refresh_catalogue_') as temp:
            root = Path(temp)
            for name in ['report', 'fatsecret', 'new']:
                (root / name).mkdir()

            def write(path, template, rows):
                with path.open('w', encoding='utf-8-sig', newline='') as stream:
                    writer = csv.DictWriter(stream, fieldnames=list(template))
                    writer.writeheader()
                    writer.writerows(dict(template, **row) for row in rows)

            write(root / 'report/13_reference.csv', {'食物编码': ''}, [])
            write(root / 'report/07_foods.csv', {'id': ''}, [])
            write(root / 'report/08_portions.csv', {'food_id': ''}, [])
            template = {'key': '', '名称': '', '品牌': '', '类型': 'brand',
                        '每100g_热量': '100', '每100g_蛋白': '2', '每100g_碳水': '14',
                        '每100g_脂肪': '4', '基准克重': '100', '计量基准': '每100克',
                        '其他份量': '[]'}
            write(root / 'fatsecret/有效数据.csv', template, [
                {'key': 'updated', '名称': '旧奶片'},
                {'key': 'retained', '名称': '保留奶片'},
                {'key': 'excluded', '名称': '异常奶片'},
            ])
            incoming = [{'key': 'updated', '名称': '新奶片', '每100g_热量': '110'},
                        {'key': 'excluded', '名称': '异常奶片'}]
            write(root / 'new/全量原始.csv', template, incoming)
            write(root / 'new/有效数据.csv', template, incoming[:1])
            originals = {p: p.read_bytes() for p in root.rglob('*.csv')}
            with contextlib.redirect_stdout(io.StringIO()):
                summary = build(root, root / 'out', [root / 'new'])
            foods = json.loads((root / 'out/assets/foods/catalog.json').read_text(encoding='utf-8'))['foods']
            self.assertEqual({food['name'] for food in foods}, {'新奶片', '保留奶片'})
            self.assertEqual(summary['refresh_snapshots'][0]['superseded_rows'], 2)
            self.assertEqual(summary['refresh_snapshots'][0]['excluded_rows'], 1)
            self.assertEqual(summary['rejected_rows'], 1)
            before = (root / 'out/assets/foods/catalog.json').read_bytes()
            with contextlib.redirect_stdout(io.StringIO()):
                build(root, root / 'out', [root / 'new'])
            self.assertEqual((root / 'out/assets/foods/catalog.json').read_bytes(), before)
            for path, content in originals.items():
                self.assertEqual(path.read_bytes(), content)

    def test_dry_and_hydrated_profiles_remain_separate_with_safe_portions(self):
        with tempfile.TemporaryDirectory(prefix='preparation_catalogue_') as temp:
            root = Path(temp)
            (root / 'report').mkdir()
            (root / 'fatsecret').mkdir()

            def write(path, template, entries):
                with path.open('w', encoding='utf-8-sig', newline='') as stream:
                    writer = csv.DictWriter(stream, fieldnames=list(template))
                    writer.writeheader()
                    writer.writerows(dict(template, **entry) for entry in entries)

            write(root / 'report/13_reference.csv', {
                '食物编码': '', '食物名称': '', '原名称': '', '一级分类': '谷类及制品',
                '水分(g)': '15', '能量(kcal)': '338', '蛋白质(g)': '.8',
                '碳水化合物(g)': '83.7', '脂肪(g)': '.2',
            }, [{'食物编码': '22201', '食物名称': '粉丝', '原名称': '粉丝'}])
            write(root / 'report/07_foods.csv', {
                'id': '', '名称': '', '英文名': '', '分类': '主食',
                '卡路里(kcal/100g)': '125', '蛋白质(g/100g)': '2.8',
                '碳水(g/100g)': '28', '脂肪(g/100g)': '.2',
                '膳食纤维(g/100g)': '', '糖(g/100g)': '', '钠(mg/100g)': '',
                '常用份量克重(g)': '50', '常用份量描述': '一把干粉丝',
            }, [{'id': '551', '名称': '粉丝'}])
            write(root / 'report/08_portions.csv', {
                'food_id': '551', '份量描述': '', '份量克重': '',
            }, [
                {'份量描述': '一把干粉丝', '份量克重': '50'},
                {'份量描述': '一碗粉丝', '份量克重': '150'},
                {'份量描述': '一份凉拌粉丝', '份量克重': '200'},
            ])
            write(root / 'fatsecret/有效数据.csv', {
                'key': '', '名称': '', '品牌': '', '类型': '',
                '每100g_热量': '', '每100g_蛋白': '', '每100g_碳水': '', '每100g_脂肪': '',
                '基准克重': '', '计量基准': '', '其他份量': '',
            }, [])
            with contextlib.redirect_stdout(io.StringIO()):
                summary = build(root, root / 'out')
            foods = json.loads((root / 'out/assets/foods/catalog.json').read_text(encoding='utf-8'))['foods']
            self.assertEqual(len(foods), 2)
            dry = next(f for f in foods if f['name'] == '粉丝（干）')
            wet = next(f for f in foods if f['name'] == '粉丝（湿）')
            self.assertEqual(dry['nutrients']['energy_kcal'], 338)
            self.assertEqual(wet['nutrients']['energy_kcal'], 125)
            self.assertEqual(wet['portions'], [{'label': '一碗粉丝', 'grams': 150}])
            self.assertEqual(summary['preparation_portions_removed'], 2)
            self.assertNotEqual(dry['id'], wet['id'])

    def test_portions_do_not_cross_raw_cooked_or_dry_wet_bases(self):
        from food_weight_basis import portion_basis_error, explicit_basis
        for basis, label in [
            ('raw', '一碗熟米饭'), ('dry', '一碗煮好的荞麦面'),
            ('cooked', '一小把干荞麦面'), ('rehydrated', '一朵干木耳'),
            ('fresh', '一把干海带'), ('fresh', '一盘清炒芸豆'),
            ('wet', '一碗汤河粉'), ('fresh', '一把带荚青豆'),
        ]:
            self.assertIsNotNone(portion_basis_error('食物', basis, label))
        self.assertIsNone(portion_basis_error('米饭', 'cooked', '一小碗'))
        self.assertIsNone(portion_basis_error('木耳', 'rehydrated', '一碗泡发木耳'))
        self.assertEqual(explicit_basis('海带（浸）'), 'rehydrated')
        self.assertIsNone(explicit_basis('豆腐干'))
        self.assertIsNone(explicit_basis('一份干炒河粉'))

    def test_bean_categories_do_not_override_reviewed_fresh_records(self):
        from food_weight_basis import preparation_basis, preparation_nutrition_error
        for source_id, name, kcal in [('833', '蚕豆', 104), ('834', '青豆', 81), ('835', '豌豆', 81)]:
            self.assertEqual(preparation_basis(name, 'calshot', source_id, '豆制品',
                                             {'energy_kcal': kcal}, {}), 'fresh')
        self.assertEqual(preparation_basis('蚕豆（炸）[开花豆]', 'cn_fct', '35202',
                         '干豆类及制品', {'energy_kcal': 447}, {}), 'cooked')
        self.assertIsNotNone(preparation_nutrition_error('青豆', 'dry', {'energy_kcal': 81}))
        self.assertIsNotNone(preparation_nutrition_error('方便米饭', 'cooked',
                             {'energy_kcal': 354, 'carbohydrate_g': 76}))

    def test_numeric_inputs_do_not_turn_unknown_or_invalid_into_zero(self):
        for raw in ['', '-', 'Tr', 'NaN', 'inf', '-1', None]:
            self.assertIsNone(number(raw))
        self.assertEqual(number('0'), 0)

    def test_nutrition_compatibility_controls_only_safe_field_supplementation(self):
        a = dict(energy_kcal=144, protein_g=13, carbohydrate_g=1.1, fat_g=9.5)
        self.assertTrue(close_nutrition(a, dict(a, energy_kcal=144.5)))
        self.assertFalse(close_nutrition(a, dict(a, protein_g=25)))

    def test_names_clean_equivalents_but_preserve_variety_and_preparation(self):
        self.assertEqual(clean_food_name(' 鸡蛋（代表值） '), '鸡蛋')
        self.assertEqual(clean_food_name('鸡蛋(整个)'), '鸡蛋')
        self.assertEqual(clean_food_name('鸡蛋（煮）'), '煮鸡蛋')
        self.assertEqual(clean_food_name('水煮鸡蛋'), '煮鸡蛋')
        for name in ['鸡蛋（白皮）', '鸡蛋（红皮）', '煎鸡蛋', '鸡蛋白']:
            self.assertEqual(clean_food_name(name), name)
        for name in ['鸡蛋（者）', '松花蛋（鸡蛋', '手作八宝粘豆包�']:
            with self.assertRaises(ValueError):
                clean_food_name(name)
        self.assertEqual(clean_food_name('墨西哥玉米片（Nachos)加奶酪'),
                         '墨西哥玉米片（Nachos）加奶酪')

    def test_metadata_tokens_are_removed_inside_mixed_descriptions(self):
        for original, cleaned in [
            ('米饭（蒸,代表值）', '蒸米饭'),
            ('纯牛奶（代表值,全脂）', '纯牛奶（全脂）'),
            ('牛肉（平均值、瘦、fat 3g）', '牛肉（瘦,脂肪3克）'),
            ('面条（生，均值）', '面条（生）'),
        ]:
            self.assertEqual(clean_food_name(original), cleaned)
        self.assertEqual(clean_food_name('平均值牌酸奶'), '平均值牌酸奶')

    def test_portions_merge_equivalent_labels_and_disambiguate_weights(self):
        result = clean_portions([
            {'label': '100 g', 'grams': 100},
            {'label': '100 克', 'grams': 100},
            {'label': '1份', 'grams': 200},
            {'label': '一份', 'grams': 300},
            {'label': '小个', 'grams': 40},
            {'label': '一个小鸡蛋', 'grams': 40},
            {'label': '40克', 'grams': 40},
            {'label': '100克', 'grams': 100},
            {'label': '一碗', 'grams': 100},
        ])
        self.assertEqual(result, [
            {'label': '一碗', 'grams': 100},
            {'label': '一份（200克）', 'grams': 200},
            {'label': '一份（300克）', 'grams': 300},
            {'label': '小个', 'grams': 40},
        ])

    def test_import_resolves_same_food_conflicts_and_quarantines_bad_names(self):
        with tempfile.TemporaryDirectory(prefix='diet_catalogue_') as temp:
            root = Path(temp)
            report, fs = root / 'report', root / 'fatsecret'
            report.mkdir()
            fs.mkdir()

            def write(path, rows):
                with path.open('w', encoding='utf-8-sig', newline='') as stream:
                    writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
                    writer.writeheader()
                    writer.writerows(rows)

            write(report / '08_portions.csv', [
                {'food_id': 'c1', '份量描述': '一个', '份量克重': '50'},
            ])
            write(report / '13_reference.csv', [
                {'食物编码': 'r1', '食物名称': '鸡蛋（代表值）', '原名称': '鸡卵',
                 '一级分类': '蛋类', '能量(kcal)': '144', '蛋白质(g)': '13',
                 '碳水化合物(g)': '1.1', '脂肪(g)': '9.5',
                 '钠(mg)': '142', '不溶性膳食纤维(g)': '0'},
            ])
            write(report / '07_foods.csv', [
                {'id': 'c1', '名称': '鸡蛋', '分类': '蛋类', '英文名': 'Egg',
                 '卡路里(kcal/100g)': '180', '蛋白质(g/100g)': '13',
                 '碳水(g/100g)': '1.1', '脂肪(g/100g)': '9.5',
                 '膳食纤维(g/100g)': '', '糖(g/100g)': '30', '钠(mg/100g)': '',
                 '常用份量克重(g)': '50', '常用份量描述': '一个'},
            ])
            base = {'key': 'f1', '名称': '鸡蛋', '品牌': '', '类型': '蛋类',
                    '每100g_热量': '144', '每100g_蛋白': '13',
                    '每100g_碳水': '1.1', '每100g_脂肪': '9.5',
                    '基准克重': '100', '计量基准': '每100克',
                    '其他份量': '[{"name":"半个","grams":25}]'}
            write(fs / '有效数据.csv', [
                base,
                dict(base, 每100g_热量='180'),  # Archive conflict; one search row.
                dict(base, key='whole', 名称='鸡蛋（整个）'),
                dict(base, key='boiled', 名称='煮鸡蛋'),
                dict(base, key='branded', 品牌='旦六福'),
                dict(base, key='ocr', 名称='鸡蛋（者）'),
                dict(base, key='truncated', 名称='鸡蛋（乌鸡蛋，绿皮'),
                dict(base, key='garbled', 名称='手作八宝粘豆包�'),
                dict(base, key='f2', 名称='Egg'),  # No Chinese display name.
                dict(base, key='f3', 名称='异常鸡蛋', 每100g_热量=''),
            ])
            original = {str(p): p.read_bytes() for p in root.rglob('*.csv')}
            output = root / 'out'
            with contextlib.redirect_stdout(io.StringIO()):
                summary = build(root, output)
            self.assertEqual(summary['food_count'], 3)
            self.assertEqual(summary['merged_duplicates'], 4)
            self.assertEqual(summary['rejected_rows'], 5)
            self.assertEqual(summary['conflict_groups_resolved'], 1)
            rows = json.loads((output / 'assets/foods/catalog.json').read_text(encoding='utf-8'))['foods']
            self.assertEqual(len({f['id'] for f in rows}), 3)
            egg = next(f for f in rows if f['name'] == '鸡蛋' and not f['brand'])
            self.assertEqual(egg['nutrition_source'], {'source': 'cn_fct', 'id': 'r1'})
            self.assertEqual(len(egg['sources']), 4)
            self.assertEqual({s['source'] for s in egg['sources']}, {'cn_fct', 'calshot', 'fatsecret'})
            self.assertEqual(egg['nutrients']['sodium_mg'], 142)
            self.assertNotIn('fiber_g', egg['nutrients'])
            self.assertNotIn('sugars_g', egg['nutrients'])
            self.assertIn({'label': '一个', 'grams': 50}, egg['portions'])
            self.assertIn({'label': '半个', 'grams': 25}, egg['portions'])
            self.assertEqual(len([f for f in rows if f['name'] == '鸡蛋' and not f['brand']]), 1)
            self.assertTrue(any(f['name'] == '煮鸡蛋' for f in rows))
            self.assertTrue(any(f['brand'] == '旦六福' for f in rows))
            conflicts = json.loads((output / 'data/private_food_catalog/food_conflicts.json').read_text(encoding='utf-8'))
            self.assertEqual(conflicts[0]['selected_id'], egg['id'])
            self.assertTrue(any(f['nutrients']['energy_kcal'] == 180 for f in conflicts[0]['alternatives']))
            for path, content in original.items():
                self.assertEqual(Path(path).read_bytes(), content)
            with contextlib.closing(sqlite3.connect(output / 'data/private_food_catalog/food_library.sqlite')) as db:
                self.assertEqual(db.execute('select count(*) from foods').fetchone()[0], 3)
            # Repeating the import must not append duplicate records.
            before = (output / 'assets/foods/catalog.json').read_bytes()
            with contextlib.redirect_stdout(io.StringIO()):
                build(root, output)
            self.assertEqual((output / 'assets/foods/catalog.json').read_bytes(), before)


if __name__ == '__main__':
    unittest.main()
