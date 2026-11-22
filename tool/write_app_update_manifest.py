"""Build update metadata from the signed APK's actual Android manifest."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

PACKAGE = 'com.opennutritracker.ont.opennutritracker'

def manifest(apk, badging, expected_version, expected_build):
    package = re.search(r"package: name='([^']+)' versionCode='([0-9]+)' versionName='([^']+)'", badging)
    if not package:
        raise ValueError('APK package information missing')
    name, code, version = package.groups()
    if name != PACKAGE or version != expected_version or int(code) != expected_build:
        raise ValueError('APK identity/version differs from build configuration')
    digest = hashlib.sha256()
    with apk.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return {'schemaVersion': 1, 'packageName': name, 'version': version,
            'versionCode': int(code), 'bytes': apk.stat().st_size,
            'sha256': digest.hexdigest()}

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('--aapt', required=True)
    parser.add_argument('--build', type=int, required=True)
    parser.add_argument('--pubspec', type=Path, default=Path('pubspec.yaml'))
    parser.add_argument('--output', type=Path, default=Path('dist/UPDATE.json'))
    args = parser.parse_args()
    version = re.search(r'^version: ([0-9]+\.[0-9]+\.[0-9]+)\+',
                        args.pubspec.read_text(encoding='utf-8'), re.M).group(1)
    badging = subprocess.run([args.aapt, 'dump', 'badging', str(args.apk)],
                            check=True, capture_output=True, text=True).stdout
    result = manifest(args.apk, badging, version, args.build)
    args.output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result))
