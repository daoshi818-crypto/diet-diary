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
)


class FoodCatalogueTest(unittest.TestCase):
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
