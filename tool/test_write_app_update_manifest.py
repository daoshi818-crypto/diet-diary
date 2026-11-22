import hashlib
from pathlib import Path
import tempfile
import unittest
from write_app_update_manifest import manifest, PACKAGE

class UpdateManifestTest(unittest.TestCase):
    def test_uses_actual_apk_version_and_hash(self):
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / 'app.apk'
            apk.write_bytes(b'signed-apk')
            badging = "package: name='" + PACKAGE + "' versionCode='1013' versionName='2.8.1'"
            data = manifest(apk, badging, '2.8.1', 1013)
            self.assertEqual(data['sha256'], hashlib.sha256(b'signed-apk').hexdigest())
            self.assertEqual(data['bytes'], 10)
            self.assertEqual(data['versionCode'], 1013)
            for output in [badging.replace('2.8.1', '2.8.0'),
                           badging.replace('1013', '1012'),
                           badging.replace(PACKAGE, 'other.app'), 'broken']:
                with self.assertRaises(ValueError):
                    manifest(apk, output, '2.8.1', 1013)

if __name__ == '__main__':
    unittest.main()
