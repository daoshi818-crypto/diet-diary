"""Keep dry/raw ingredients separate from hydrated and prepared foods."""
import re

RAW_GRAINS = {
    '大米', '稻米', '粳米', '籼米', '糙米', '糯米', '黑米', '紫米',
    '小米', '高粱米', '薏米', '藜麦', '青稞', '小麦', '大麦', '燕麦',
    '荞麦', '荞麦米', '黍米', '黄米', '糜子米',
}
BEANS = {
    '黄豆', '黑豆', '青豆', '绿豆', '红豆', '赤小豆', '鹰嘴豆',
    '芸豆', '白芸豆', '红芸豆', '花芸豆', '扁豆', '刀豆', '四季豆',
    '地豆', '架豆', '甜豆', '眉豆', '菜豆', '荷兰豆', '豌豆', '蚕豆',
}
HYDRATION_FOODS = {
    '河粉', '米粉', '米线', '粉丝', '粉条', '荞麦面', '红薯粉',
    '木耳', '银耳', '香菇', '海带', '紫菜', '豆腐皮', '虾仁',
}
# Reviewed exports: the expected energy guards against reused crawler IDs.
CALSHOT_BASIS = {
    '545': ('cooked', 132), '547': ('wet', 125),
    '549': ('wet', 138), '550': ('wet', 135), '551': ('wet', 125),
    '1327': ('dry', 337), '178': ('rehydrated', 27),
    '597': ('rehydrated', 20), '587': ('fresh', 19), '177': ('fresh', 34),
    '608': ('rehydrated', 12), '328': ('fresh', 43),
    '607': ('fresh', 35), '329': ('fresh', 35),
    '324981': ('fresh', 180),
    '833': ('fresh', 104), '834': ('fresh', 81), '835': ('fresh', 81),
}
BASIS_TAGS = {'raw': '生', 'cooked': '熟', 'dry': '干', 'wet': '湿',
              'fresh': '鲜', 'rehydrated': '泡发'}


def explicit_basis(text):
    if re.search(r'泡发|水发|复水|[（(,，]浸(?:泡)?[）),，]', text):
        return 'rehydrated'
    if re.search(r'干重|干品|脱水|[（(,，]干(?:制)?[）),，]|干(?:面条|切面|挂面|意大利面|荞麦面|米线|米粉|粉丝|粉条|红薯粉|木耳|银耳|香菇|海带|紫菜|黄豆|绿豆|红豆|芸豆|菜豆|刀豆|花芸豆|黄花菜)|(?:鱼|虾|贝|肉)干(?:[（(]|$)', text):
        return 'dry'
    if re.search(r'熟|煮好|煮后|煮熟|蒸熟|蒸好', text):
        return 'cooked'
    if re.search(r'[（(,，]湿(?:重)?[）),，]|鲜湿', text):
        return 'wet'
    if re.search(r'生重|[（(,，]生[）),，]', text):
        return 'raw'
    if re.search(r'新鲜|鲜重|[（(,，]鲜[）),，]|鲜(?:香菇|木耳|海带)', text):
        return 'fresh'
    return None


def preparation_basis(name, source, source_id, category, nutrients, original):
    base = re.split(r'[（(\[]', name)[0]
    if source == 'calshot' and str(source_id) in CALSHOT_BASIS:
        basis, expected = CALSHOT_BASIS[str(source_id)]
        if abs(nutrients['energy_kcal'] - expected) > .01:
            raise ValueError('已审核食物记录的营养值改变，需重新确认生熟或干湿状态')
        return basis
    explicit = explicit_basis(name)
    if explicit:
        return explicit
    if re.search(r'米饭|粥|[（(,，](?:煮|蒸|炒|煎|炸|烤)[）),，]|^(?:水煮|清蒸|煮|蒸|炒|煎|炸|烤)', name):
        return 'cooked'
    if base in RAW_GRAINS:
        return 'raw'
    water = original.get('水分(g)') if original else None
    try:
        water = float(water) if water not in (None, '') else None
    except (TypeError, ValueError):
        water = None
    if base in BEANS:
        if '干豆' in category or category == '豆制品':
            return 'dry'
        if '蔬菜' in category:
            return 'fresh'
    if base in HYDRATION_FOODS and source == 'cn_fct' and water is not None:
        if water < 30:
            return 'dry'
        if water > 65:
            return 'fresh'
    return None


def name_with_basis(name, basis):
    if not basis or explicit_basis(name) == basis:
        return name
    if basis == 'cooked' and re.search(
            r'米饭|粥|[（(,，](?:煮|蒸|炒|煎|炸|烤)[）),，]|^(?:水煮|清蒸|煮|蒸|炒|煎|炸|烤)', name):
        return name
    if name.endswith('）'):
        return f'{name[:-1]},{BASIS_TAGS[basis]}）'
    return f'{name}（{BASIS_TAGS[basis]}）'


def portion_basis_error(name, basis, label):
    if not basis:
        return None
    if re.search(r'带壳|带荚', label):
        return '含壳或荚重量不能直接计入每100克可食部'
    portion_basis = explicit_basis(label)
    incompatible = {
        'raw': {'cooked', 'wet', 'rehydrated'},
        'dry': {'cooked', 'wet', 'rehydrated', 'fresh'},
        'cooked': {'raw', 'dry', 'fresh'},
        'wet': {'dry'},
        'fresh': {'dry', 'cooked', 'rehydrated'},
        'rehydrated': {'dry', 'fresh'},
    }
    if portion_basis in incompatible[basis]:
        return '份量的生熟或干湿状态与营养基准不符'
    for method in ('干炒', '清炒', '凉拌', '红烧', '油炸', '煎', '烤', '盐渍', '即食', '汤河粉'):
        if method in label and method not in name:
            return '份量描述属于另一种加工做法'
    if basis in {'raw', 'dry', 'fresh'} and re.search(r'煮|蒸|炒|煎|炸|烤|汤用|煮汤|汤河粉', label):
        return '份量描述为烹调后成品'
    if basis in {'cooked', 'wet', 'rehydrated'} and not portion_basis and re.search(r'把|扎|朵', label):
        return '无法确认手抓份量的干湿状态'
    return None


def preparation_nutrition_error(name, basis, nutrients):
    base = re.split(r'[（(\[]', name)[0]
    if base in BEANS and basis == 'dry' and nutrients['energy_kcal'] < 200:
        return '干豆分类与营养浓度冲突，需人工核对'
    if base in RAW_GRAINS and basis == 'raw' and nutrients['energy_kcal'] < 200:
        return '生谷物名称与营养浓度冲突，需人工核对'
    if (base in {'米饭', '白米饭', '蒸米饭', '糙米饭', '粉丝', '米线', '荞麦面', '方便米饭'}
            and basis in {'cooked', 'wet'} and nutrients['carbohydrate_g'] > 55):
        return '湿重或熟重主食混入干品营养值，需人工核对'
    return None
