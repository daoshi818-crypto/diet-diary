import json
from pathlib import Path
import tempfile
import unittest
import zipfile

from verify_android_apk import verify


class VerifyAndroidApkTest(unittest.TestCase):
    def test_current_catalog_and_arm64_are_required(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            catalog = root / 'catalog.json'
            catalog.write_text(json.dumps({'schema_version': 1, 'foods': [{'name': '鸡蛋'}]}), encoding='utf-8')

            def make_apk(name, *, stale=False, extra_abi=False, missing_runtime=False):
                path = root / name
                with zipfile.ZipFile(path, 'w') as apk:
                    apk.writestr('lib/arm64-v8a/libapp.so', b'app')
                    if not missing_runtime:
                        apk.writestr('lib/arm64-v8a/libflutter.so', b'flutter')
                    if extra_abi:
                        apk.writestr('lib/x86_64/plugin.so', b'plugin')
                    apk.writestr('assets/flutter_assets/assets/foods/catalog.json', b'old' if stale else catalog.read_bytes())
                return path

            result = verify(make_apk('valid.apk'), catalog)
            self.assertEqual(result['food_count'], 1)
            self.assertEqual(result['abis'], ['arm64-v8a'])
            with self.assertRaisesRegex(ValueError, 'differs'):
                verify(make_apk('stale.apk', stale=True), catalog)
            with self.assertRaisesRegex(ValueError, 'architectures'):
                verify(make_apk('wrong-abi.apk', extra_abi=True), catalog)
            with self.assertRaisesRegex(ValueError, 'runtime'):
                verify(make_apk('missing.apk', missing_runtime=True), catalog)


if __name__ == '__main__':
    unittest.main()
