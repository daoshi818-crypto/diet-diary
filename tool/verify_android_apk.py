"""Verify that the APK contains the exact checked-in catalog and only ARM64."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile


def verify(apk_path, catalog_path):
    expected = catalog_path.read_bytes()
    with zipfile.ZipFile(apk_path) as apk:
        entries = apk.namelist()
        names = set(entries)
        if len(entries) != len(names):
            raise ValueError('APK contains duplicate archive paths')
        abis = {name.split('/')[1] for name in names
                if name.startswith('lib/') and name.endswith('.so')}
        if abis != {'arm64-v8a'}:
            raise ValueError(f'Unexpected APK architectures: {sorted(abis)}')
        for library in ('libapp.so', 'libflutter.so'):
            if f'lib/arm64-v8a/{library}' not in names:
                raise ValueError(f'Missing ARM64 runtime library: {library}')
        packaged = apk.read('assets/flutter_assets/assets/foods/catalog.json')
        if packaged != expected:
            raise ValueError('Packaged food catalog differs from the checked-in snapshot')
    catalog = json.loads(expected)
    if catalog.get('schema_version') != 1 or not catalog.get('foods'):
        raise ValueError('Food catalog is empty or unsupported')
    return {
        'apk_sha256': hashlib.sha256(apk_path.read_bytes()).hexdigest(),
        'catalog_sha256': hashlib.sha256(expected).hexdigest(),
        'food_count': len(catalog['foods']),
        'abis': sorted(abis),
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('--catalog', type=Path, default=Path('assets/foods/catalog.json'))
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    result = verify(args.apk, args.catalog)
    text = json.dumps(result, ensure_ascii=False, indent=2)
    if args.report:
        args.report.write_text(text + '\n', encoding='utf-8')
    print(text)
