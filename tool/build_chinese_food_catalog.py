"""Build a private, offline Chinese food library from the user's CSV exports.

Standard library only. Never edits inputs or infers missing serving weights.
Run: python tool/build_chinese_food_catalog.py --source-root D:\\吃有数
"""
from __future__ import annotations

import argparse
import copy
import csv
import hashlib
import html
import io
import json
import math
import re
import sqlite3
import sys
import unicodedata
from collections import Counter, defaultdict
from pathlib import Path

from food_weight_basis import (
    name_with_basis, portion_basis_error, preparation_basis,
    preparation_nutrition_error,
)

ROOT = Path(__file__).resolve().parents[1]
CORE = ('energy_kcal', 'protein_g', 'carbohydrate_g', 'fat_g')
BRANDS = {'麦当劳', '肯德基', '星巴克', '瑞幸咖啡', '瑞幸', '蜜雪冰城',
          '喜茶', '奈雪的茶', 'CoCo都可', '茶百道', '古茗', '一点点',
          '霸王茶姬', '沪上阿姨', '茶颜悦色', '汉堡王', '必胜客', '赛百味',
          '塔斯汀', '华莱士', '德克士', '库迪咖啡', '库迪'}
SOURCE_PRIORITY = {'cn_fct': 0, 'calshot': 1, 'fatsecret': 2}


def normalized(text):
    return re.sub(r'\s+', '', unicodedata.normalize('NFKC', text or '')).casefold()


def clean_text(text):
    text = html.unescape(unicodedata.normalize('NFKC', text or ''))
    text = re.sub(r'[\x00-\x1f\x7f\u200b-\u200f\ufeff]', '', text)
    return re.sub(r'\s+', ' ', text).strip()


def balanced_name(text):
    stack, pairs = [], {')': '(', ']': '[', '}': '{'}
    for char in text:
        if char in '([{':
            stack.append(char)
        elif char in pairs:
            if not stack or stack.pop() != pairs[char]:
                return False
    return not stack


def clean_food_name(text):
    text = clean_text(text)
    if '\ufffd' in text:
        raise ValueError('名称含乱码替代字符，无法确认原名')
    if not balanced_name(text):
        raise ValueError('名称括号截断或不配对，无法确认完整名称')
    if re.search(r'\(者\)', text):
        raise ValueError('名称疑似OCR错误“者”，无法确认食物做法')
    def clean_description(match):
        tokens = re.split(r'[,，、;；]', match[1])
        tokens = [token.strip() for token in tokens
                  if token.strip() not in {'代表值', '平均值', '均值'}]
        description = ','.join(tokens)
        description = re.sub(r'\bfat\s*(\d+(?:\.\d+)?)\s*g\b',
                             r'脂肪\1克', description, flags=re.I)
        return f'({description})' if description else ''
    text = re.sub(r'\(([^()]*)\)', clean_description, text).strip()
    # Only explicit equivalent descriptions; retain varieties and cooking states.
    text = {'鸡蛋(整个)': '鸡蛋', '鸡蛋(全蛋)': '鸡蛋',
            '水煮鸡蛋': '煮鸡蛋'}.get(text, text)
    cooked = re.fullmatch(r'(.+)\((煮|水煮|蒸|炒|煎|炸|烤)\)', text)
    if cooked:
        text = ('煮' if cooked[2] == '水煮' else cooked[2]) + cooked[1]
    return text.translate(str.maketrans({'(': '（', ')': '）'}))


def clean_portions(portions, unit='g'):
    unique = {}
    for portion in portions:
        grams = number(portion.get('grams'))
        label = clean_text(portion.get('label'))
        if not grams or not label or '\ufffd' in label or not balanced_name(label):
            continue
        label = re.sub(r'\s*([()])\s*', r'\1', label)
        suffix = r'(?:ml|毫升)' if unit == 'ml' else r'(?:g|克)'
        mass = re.fullmatch(r'(\d+(?:\.\d+)?)\s*' + suffix, label, re.I)
        if mass:
            label = f'{float(mass[1]):g}' + ('毫升' if unit == 'ml' else '克')
        label = re.sub(r'^1\s*(份|个)$', r'一\1', label)
        label = {
            '一个中等大小鸡蛋': '中个', '一个中等鸡蛋': '中个',
            '一个大鸡蛋': '大个', '一个小鸡蛋': '小个',
            '半颗鸡蛋': '半个',
        }.get(normalized(label), label)
        label = label.translate(str.maketrans({'(': '（', ')': '）'}))
        unique.setdefault((normalized(label), round(grams, 6)),
                          {'label': label, 'grams': grams})
    by_weight = {}
    for (_, weight), portion in unique.items():
        previous = by_weight.get(weight)
        mass_label = r'\d+(?:\.\d+)?(?:克|毫升)'
        previous_is_mass = previous is not None and re.fullmatch(mass_label, previous['label'])
        current_is_mass = re.fullmatch(mass_label, portion['label'])
        if previous is None or (previous_is_mass and not current_is_mass):
            by_weight[weight] = portion
    unique = {(normalized(p['label']), w): p for w, p in by_weight.items()}
    counts = Counter(label for label, _ in unique)
    result = []
    for (key, _), portion in unique.items():
        if counts[key] > 1:
            portion['label'] += f'（{portion["grams"]:g}' + ('毫升）' if unit == 'ml' else '克）')
        result.append(portion)
    return result


def number(value):
    if value is None or str(value).strip() in {'', '-', '—', 'Tr', 'tr'}:
        return None
    try:
        value = float(value)
        return value if math.isfinite(value) and value >= 0 else None
    except (ValueError, TypeError):
        return None


def close_nutrition(a, b):
    # Compatibility only permits filling missing fields; never average values.
    return all(abs(a[k] - b[k]) <= max(1 if k == 'energy_kcal' else .2,
                                     .01 * max(a[k], b[k])) for k in CORE)


def read_csv(path, manifest):
    content = path.read_bytes()  # Consistent snapshot even if crawler continues.
    rows = list(csv.DictReader(io.StringIO(content.decode('utf-8-sig'))))
    manifest.append({'file': path.name, 'sha256': hashlib.sha256(content).hexdigest(),
                     'rows': len(rows)})
    return rows


def metric_quantity(text):
    text = clean_text(text)
    matches = re.findall(r'(\d+(?:\.\d+)?)\s*(毫升|ml|克|g)\b', text, re.I)
    # Chinese unit boundaries need not be word boundaries, e.g. “每100毫升装”.
    if not matches:
        matches = re.findall(r'(\d+(?:\.\d+)?)\s*(毫升|克)', text)
    units = {(float(n), 'ml' if u.lower() in {'ml', '毫升'} else 'g') for n, u in matches}
    if len(units) != 1:
        return None
    amount, unit = units.pop()
    return (amount, unit) if amount > 0 else None


def fatsecret_values(row):
    basis = metric_quantity(row.get('计量基准', ''))
    derived = row.get('基准来源') == 'derived'
    if derived and basis is None:
        raise ValueError('份量重量为能量反推，缺少明示计量基准')
    unit = basis[1] if basis else 'g'
    raw_keys = dict(zip(CORE, ['热量kcal', '蛋白g', '碳水g', '脂肪g']))
    raw = {key: number(row.get(value)) for key, value in raw_keys.items()}
    if basis and all(value is not None for value in raw.values()):
        nutrients = {key: value * 100 / basis[0] for key, value in raw.items()}
    elif unit == 'g':
        nutrients = {key: number(row.get(value)) for key, value in zip(
            CORE, ['每100g_热量', '每100g_蛋白', '每100g_碳水', '每100g_脂肪'])}
    else:
        raise ValueError('每毫升营养缺失，不能使用每克字段或假定密度')
    serving = []
    amount = basis[0] if basis else number(row.get('基准克重'))
    if amount and not derived:
        serving.append({'label': row.get('计量基准', '').removeprefix('每'), 'grams': amount})
    try:
        alternatives = json.loads(row.get('其他份量') or '[]')
    except (ValueError, TypeError):
        alternatives = []
    for portion in alternatives if isinstance(alternatives, list) else []:
        if not isinstance(portion, dict):
            continue
        label = portion.get('name', '')
        metric = metric_quantity(label)
        if metric and metric[1] != unit:
            continue
        quantity = metric[0] if metric else number(portion.get('grams')) if unit == 'g' else None
        if quantity:
            serving.append({'label': label, 'grams': quantity})
    return nutrients, unit, serving


def fatsecret_rows(source_root, updates, manifest, rejected, refresh_audit):
    batches = [read_csv(source_root / 'fatsecret' / '有效数据.csv', manifest)]
    for folder in updates:
        original = read_csv(folder / '全量原始.csv', manifest)
        current = read_csv(folder / '有效数据.csv', manifest)
        raw_by_key = {row['key']: row for row in original}
        valid_by_key = {row['key']: row for row in current}
        if len(raw_by_key) != len(original) or len(valid_by_key) != len(current):
            raise ValueError('更新快照的原始 key 不唯一')
        if any(raw_by_key.get(key) != row for key, row in valid_by_key.items()):
            raise ValueError('有效数据与全量原始不属于同一快照')
        superseded = [row for batch in batches for row in batch if row['key'] in raw_by_key]
        batches = [[row for row in batch if row['key'] not in raw_by_key] for batch in batches]
        invalid = [row for row in original if row['key'] not in valid_by_key]
        for row in invalid:
            rejected.append({'source': 'fatsecret', 'source_id': row['key'],
                             'name': row['名称'], 'reason': '本次抓取有效表未收录，隔离且不回退旧快照',
                             'original': row})
        refresh_audit.append({'snapshot': folder.name, 'raw_rows': len(original),
                              'valid_rows': len(current), 'superseded_rows': len(superseded),
                              'excluded_rows': len(invalid)})
        batches.append(current)
    return [row for batch in batches for row in batch]


def reference_energy(row):
    kcal, kj = number(row.get('能量(kcal)')), number(row.get('能量(kJ)'))
    swapped = (kcal is not None and kj is not None and kcal > kj > 0 and
               abs(kcal / 4.184 - kj) <= max(2, .02 * kj))
    return (kj if swapped else kcal), swapped


def build(source_root, output=ROOT, fatsecret_updates=()):
    manifest, rejected, candidates = [], [], []
    name_corrections, preparation_audit = [], []
    portions = defaultdict(list)
    refresh_audit = []
    energy_corrections = []
    report = source_root / 'report'
    for row in read_csv(next(report.glob('08_*.csv')), manifest):
        grams = number(row['份量克重'])
        if grams and row['份量描述']:
            portions[row['food_id']].append({'label': row['份量描述'], 'grams': grams})

    def add(source, source_id, name, brand, category, nutrients, serving=None,
            aliases=(), provenance=None, unit='g'):
        original_name = name
        reason = None
        basis = None
        try:
            name = clean_food_name(name)
        except ValueError as error:
            reason = str(error)
        brand = clean_text(brand)
        if reason:
            pass
        elif not name or not re.search(r'[\u3400-\u9fff]', name):
            reason = '无中文名称'
        elif any(nutrients.get(k) is None for k in CORE):
            reason = '缺少可归一的热量或三大营养素'
        elif nutrients['energy_kcal'] > 1000 or any(nutrients[k] > (100 if unit == 'g' else 250) for k in CORE[1:]):
            reason = '超出每100克或毫升合理上限'
        elif unit == 'g' and sum(nutrients[k] for k in CORE[1:]) > 105:
            reason = '三大营养素合计超过105克'
        if reason:
            rejected.append({'source': source, 'source_id': str(source_id),
                             'name': original_name, 'reason': reason,
                             'original': provenance or nutrients})
            return
        try:
            basis = preparation_basis(name, source, source_id, category,
                                      nutrients, provenance or {})
            error = preparation_nutrition_error(name, basis, nutrients)
            if error:
                raise ValueError(error)
        except ValueError as error:
            rejected.append({'source': source, 'source_id': str(source_id),
                             'name': original_name, 'reason': str(error),
                             'original': provenance or nutrients})
            return
        safe_portions = []
        for portion in serving or []:
            error = portion_basis_error(name, basis, portion.get('label', ''))
            if error:
                preparation_audit.append({'source': source, 'source_id': str(source_id),
                    'name': original_name, 'weight_basis': basis,
                    'portion': portion, 'reason': error})
            else:
                safe_portions.append(portion)
        name = name_with_basis(name, basis)
        # Crawled exports may repeat an id with a revised name or recipe.
        # Include its actual identity/values so retained conflicts stay unique.
        key = json.dumps([source, str(source_id), normalized(original_name), normalized(brand),
                          [nutrients[k] for k in CORE]], ensure_ascii=False)
        if name != original_name:
            name_corrections.append({'source': source, 'source_id': str(source_id),
                                     'original': original_name, 'cleaned': name})
        aliases = set(a for a in aliases if a)
        if name != original_name:
            aliases.add(original_name)
        candidates.append({'id': 'cn-' + hashlib.sha256(key.encode()).hexdigest()[:20],
                           'name': name.strip(), 'brand': brand.strip(), 'unit': unit,
                           'category': category, 'aliases': sorted(aliases - {name}),
                           'nutrients': {k: round(v, 6) for k, v in nutrients.items() if v is not None},
                           'portions': safe_portions, 'weight_basis': basis,
                           'sources': [{'source': source, 'id': str(source_id)}],
                           '_representative': bool(re.search(r'代表值|平均值|均值', original_name))})

    # Parse references and both export sources; select one default per identity
    # below using explicit source priority, not the input's incidental ordering.
    for row in read_csv(next(report.glob('13_*.csv')), manifest):
        mappings = {'energy_kcal': '能量(kcal)', 'protein_g': '蛋白质(g)',
                    'carbohydrate_g': '碳水化合物(g)', 'fat_g': '脂肪(g)',
                    'cholesterol_mg': '胆固醇(mg)', 'sodium_mg': '钠(mg)',
                    'calcium_mg': '钙(mg)', 'iron_mg': '铁(mg)',
                    'potassium_mg': '钾(mg)', 'magnesium_mg': '镁(mg)',
                    'zinc_mg': '锌(mg)', 'phosphorus_mg': '磷(mg)',
                    'vitamin_a_ug': '总维生素A(μgRAE)', 'vitamin_c_mg': '维生素C(mg)',
                    'niacin_mg': '烟酸(mg)'}
        nutrients = {k: number(row.get(v)) for k, v in mappings.items()}
        nutrients['energy_kcal'], swapped = reference_energy(row)
        if swapped:
            energy_corrections.append({'source': 'cn_fct', 'source_id': row['食物编码'],
                                       'name': row['食物名称'], 'original_kcal': number(row['能量(kcal)']),
                                       'corrected_kcal': nutrients['energy_kcal'],
                                       'reason': '源表kcal/kJ列反置，按两列4.184换算关系纠正'})
        # Insoluble fibre is not interchangeable with total dietary fibre.
        nutrients['insoluble_fiber_g'] = number(row.get('不溶性膳食纤维(g)'))
        add('cn_fct', row['食物编码'], row['食物名称'], '', row['一级分类'],
            nutrients, aliases=[row['原名称']], provenance=row)

    for row in read_csv(next(report.glob('07_*.csv')), manifest):
        nutrients = {k: number(row[v]) for k, v in {
            'energy_kcal': '卡路里(kcal/100g)', 'protein_g': '蛋白质(g/100g)',
            'carbohydrate_g': '碳水(g/100g)', 'fat_g': '脂肪(g/100g)',
            'fiber_g': '膳食纤维(g/100g)', 'sugars_g': '糖(g/100g)',
            'sodium_mg': '钠(mg/100g)'}.items()}
        serving = portions[row['id']]
        grams = number(row['常用份量克重(g)'])
        if grams and not serving:
            serving = [{'label': row['常用份量描述'] or '一份', 'grams': grams}]
        # Export explicitly specifies g even for drinks. Do not assume density=1.
        add('calshot', row['id'], row['名称'],
            row['分类'] if row['分类'] in BRANDS else '', row['分类'], nutrients,
            serving=serving, aliases=[row['英文名']], provenance=row)

    for row in fatsecret_rows(source_root, fatsecret_updates, manifest, rejected, refresh_audit):
        try:
            nutrients, unit, serving = fatsecret_values(row)
        except ValueError as error:
            rejected.append({'source': 'fatsecret', 'source_id': row['key'],
                             'name': row['名称'], 'reason': str(error), 'original': row})
            continue
        add('fatsecret', row['key'], row['名称'], row['品牌'], row['类型'],
            nutrients, serving=serving, provenance=row, unit=unit)

    groups = defaultdict(list)
    for item in candidates:
        n = normalized(item['name'])
        brand = normalized(item['brand'])
        if brand and n.startswith(brand):
            n = n[len(brand):]
        key = (n, brand, item['unit'], item['weight_basis'])
        groups[key].append(item)

    def selection_rank(food):
        source = food['sources'][0]['source']
        return (SOURCE_PRIORITY[source], not food['_representative'],
                -len(food['nutrients']), food['id'])

    foods, conflicts = [], []
    for group in groups.values():
        group.sort(key=selection_rank)
        target = copy.deepcopy(group[0])
        target['nutrition_source'] = dict(target['sources'][0])
        alternatives = []
        for item in group[1:]:
            compatible = close_nutrition(target['nutrients'], item['nutrients'])
            if not compatible:
                alternatives.append({k: v for k, v in item.items() if not k.startswith('_')})
            else:
                # Do not fabricate a hybrid nutrition profile from conflicting rows.
                for k, v in item['nutrients'].items():
                    target['nutrients'].setdefault(k, v)
            target['sources'].extend(s for s in item['sources'] if s not in target['sources'])
            target['aliases'] = sorted(set(target['aliases'] + item['aliases'] + [item['name']]) - {target['name']})
            target['portions'].extend(item['portions'])
        if alternatives:
            conflicts.append({'selected_id': target['id'], 'name': target['name'],
                              'brand': target['brand'], 'nutrition_source': target['nutrition_source'],
                              'selected_nutrients': target['nutrients'], 'alternatives': alternatives})
        target.pop('_representative')
        target['portions'] = clean_portions(target['portions'], target['unit'])
        foods.append(target)
    foods.sort(key=lambda x: x['id'])
    merged_count = len(candidates) - len(foods)
    summary = {'schema_version': 1, 'inputs': manifest,
               'candidate_rows': len(candidates), 'food_count': len(foods),
               'merged_duplicates': merged_count, 'rejected_rows': len(rejected),
               'cleaning_version': 5,
               'refresh_snapshots': refresh_audit,
               'energy_unit_corrections': len(energy_corrections),
               'preparation_portions_removed': len(preparation_audit),
               'weight_basis_coverage': dict(Counter(f['weight_basis'] or 'unspecified' for f in foods)),
               'conflict_groups_resolved': len(conflicts),
               'conflict_rows_archived': sum(len(c['alternatives']) for c in conflicts),
               'name_corrections': len(name_corrections),
               'source_coverage': dict(Counter(s['source'] for f in foods for s in f['sources'])),
               'serving_count': sum(len(f['portions']) for f in foods),
               'normalization': '每100克可食部或每100毫升；kcal/g/mg/µg；不推测份量克重或饮品密度',
               'deduplication': '清洗后名称+品牌+单位+生熟干湿状态唯一；中国食物成分表>吃有数>FatSecret；同源优先代表值及完整营养，数值不平均，冲突进审计不重复展示',
               'distribution': '私人本地数据；来源许可未授权公开再分发，不得上传公共仓库'}
    asset = output / 'assets' / 'foods'
    data = output / 'data' / 'private_food_catalog'
    asset.mkdir(parents=True, exist_ok=True)
    data.mkdir(parents=True, exist_ok=True)
    (asset / 'catalog.json').write_text(json.dumps({'schema_version': 1, 'foods': foods},
        ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
    (data / 'catalog_manifest.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding='utf-8')
    (data / 'food_rejected.json').write_text(json.dumps(rejected, ensure_ascii=False, indent=2), encoding='utf-8')
    (data / 'food_conflicts.json').write_text(json.dumps(conflicts, ensure_ascii=False, indent=2), encoding='utf-8')
    (data / 'food_preparation_audit.json').write_text(json.dumps(preparation_audit, ensure_ascii=False, indent=2), encoding='utf-8')
    (data / 'food_name_corrections.json').write_text(json.dumps(name_corrections, ensure_ascii=False, indent=2), encoding='utf-8')
    (data / 'food_energy_corrections.json').write_text(json.dumps(energy_corrections, ensure_ascii=False, indent=2), encoding='utf-8')
    csv_fields = ['id', 'name', 'brand', 'unit', *CORE, 'sources']
    with (data / 'food_library.csv').open('w', encoding='utf-8-sig', newline='') as fp:
        writer = csv.DictWriter(fp, fieldnames=csv_fields)
        writer.writeheader()
        for f in foods:
            writer.writerow({**{k: f[k] for k in ['id', 'name', 'brand', 'unit']},
                             **{k: f['nutrients'][k] for k in CORE},
                             'sources': json.dumps(f['sources'], ensure_ascii=False)})
    dbpath = data / 'food_library.sqlite'
    connection = sqlite3.connect(dbpath)
    with connection:
        connection.execute('CREATE TABLE IF NOT EXISTS foods(id TEXT PRIMARY KEY,name TEXT NOT NULL,brand TEXT,unit TEXT,nutrition_json TEXT,payload_json TEXT)')
        connection.execute('DELETE FROM foods')
        connection.executemany('INSERT INTO foods VALUES(?,?,?,?,?,?)',
            [(f['id'], f['name'], f['brand'], f['unit'], json.dumps(f['nutrients']),
              json.dumps(f, ensure_ascii=False)) for f in foods])
        connection.execute('CREATE INDEX IF NOT EXISTS foods_name ON foods(name)')
    connection.close()
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return summary


if __name__ == '__main__':
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root', required=True, type=Path)
    parser.add_argument('--output', type=Path, default=ROOT)
    parser.add_argument('--fatsecret-update', action='append', type=Path, default=[],
                        help='Additional snapshot folder containing 全量原始.csv and 有效数据.csv; newest last')
    args = parser.parse_args()
    build(args.source_root, args.output, args.fatsecret_update)
