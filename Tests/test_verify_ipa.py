import io
import pathlib
import plistlib
import sys
import unittest
import zipfile

sys.path.insert(0, str(pathlib.Path(__file__).parents[1] / 'scripts'))
from verify_ipa import verify_frameworks


class EmbeddedFrameworkTests(unittest.TestCase):
    def archive(self, entries):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, 'w') as archive:
            for name, data in entries.items():
                archive.writestr(name, data)
        buffer.seek(0)
        return zipfile.ZipFile(buffer)

    def framework(self, folder, **overrides):
        info = {'CFBundleIdentifier': 'org.example.framework',
                'CFBundleExecutable': 'Runtime', 'CFBundleVersion': '1'}
        info.update(overrides)
        # Header-only test data exercises structural verification, not signing.
        return {folder + 'Info.plist': plistlib.dumps(info),
                folder + 'Runtime': bytes.fromhex('cffaedfe')}

    def test_missing_stikjit_plist_reproduces_install_failure(self):
        folder = 'Payload/App.app/Frameworks/StikJIT.framework/'
        with self.archive({folder + 'StikJIT': bytes.fromhex('cffaedfe')}) as archive:
            with self.assertRaisesRegex(ValueError, 'Framework Info.plist missing:.*StikJIT.framework'):
                verify_frameworks(archive)

    def test_checks_frameworks_nested_inside_embedded_store(self):
        outer = 'Payload/App.app/Frameworks/SideStoreApp.framework/'
        entries = self.framework(outer, CFBundlePackageType='APPL')
        inner = outer + 'Frameworks/OpenSSL.framework/'
        entries.update(self.framework(inner))
        with self.archive(entries) as archive:
            self.assertEqual(verify_frameworks(archive), 2)
        del entries[inner + 'Info.plist']
        with self.archive(entries) as archive:
            with self.assertRaisesRegex(ValueError, 'OpenSSL.framework'):
                verify_frameworks(archive)

    def test_rejects_invalid_or_missing_bundle_metadata(self):
        folder = 'Payload/App.app/Frameworks/Test.framework/'
        for invalid in [b'not a plist', plistlib.dumps([]),
                        plistlib.dumps({'CFBundleExecutable': 'Runtime'})]:
            entries = self.framework(folder)
            entries[folder + 'Info.plist'] = invalid
            with self.subTest(invalid=invalid), self.archive(entries) as archive:
                with self.assertRaises(ValueError):
                    verify_frameworks(archive)

    def test_rejects_missing_non_macho_or_escaping_executable(self):
        folder = 'Payload/App.app/Frameworks/Test.framework/'
        entries = self.framework(folder)
        del entries[folder + 'Runtime']
        with self.archive(entries) as archive:
            with self.assertRaisesRegex(ValueError, 'Mach-O'):
                verify_frameworks(archive)
        entries[folder + 'Runtime'] = b'not executable'
        with self.archive(entries) as archive:
            with self.assertRaisesRegex(ValueError, 'Mach-O'):
                verify_frameworks(archive)
        with self.archive(self.framework(folder, CFBundleExecutable='../Runtime')) as archive:
            with self.assertRaisesRegex(ValueError, 'executable name'):
                verify_frameworks(archive)


if __name__ == '__main__':
    unittest.main()
