"""Synthetic, read-only checks for original guest WidgetKit extension discovery."""
import pathlib
import plistlib
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "scripts"))
from inspect_guest_widget_extensions import inspect_ipa  # noqa: E402


class GuestWidgetProbeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.ipa = pathlib.Path(self.temp.name) / "test.ipa"

    def write_fixture(self, extensions=(), malformed=False, duplicate=False):
        with zipfile.ZipFile(self.ipa, "w") as archive:
            main = "Payload/Example.app/"
            info = {"CFBundleIdentifier": "com.example.app", "CFBundleExecutable": "Example"}
            archive.writestr(main + "Info.plist", plistlib.dumps(info))
            if duplicate:
                archive.writestr(main + "Info.plist", plistlib.dumps(info))
            for name, point in extensions:
                base = main + "PlugIns/" + name + ".appex/"
                extension_info = {
                    "CFBundleIdentifier": "com.example.app." + name,
                    "CFBundleExecutable": name,
                    "NSExtension": {"NSExtensionPointIdentifier": point},
                }
                archive.writestr(base + "Info.plist",
                                 b"not-a-plist" if malformed else plistlib.dumps(extension_info))
                archive.writestr(base + name, b"dummy executable: never run")
        return self.ipa

    def test_original_widget_is_identified_without_claiming_it_runs(self):
        path = self.write_fixture([
            ("OriginalWidget", "com.apple.widgetkit-extension"),
            ("Share", "com.apple.share-services"),
        ])
        result = inspect_ipa(path)
        self.assertEqual(result["widgetkit_extension_count"], 1)
        self.assertEqual(result["extension_count"], 2)
        self.assertFalse(result["original_guest_widgets_installed_or_registered"])
        self.assertEqual(result["widgetkit_extensions"][0]["bundle_id"], "com.example.app.OriginalWidget")
        self.assertTrue(result["widgetkit_extensions"][0]["has_executable"])
        self.assertEqual(result["other_extension_points"], ["com.apple.share-services"])
        self.assertTrue(result["required_before_a_device_trial"])

    def test_no_widget_does_not_offer_a_fake_proxy(self):
        result = inspect_ipa(self.write_fixture([("Share", "com.apple.share-services")]))
        self.assertEqual(result["widgetkit_extension_count"], 0)
        self.assertEqual(result["widgetkit_extensions"], [])
        self.assertEqual(result["required_before_a_device_trial"], [])

    def test_bad_plist_rejected(self):
        with self.assertRaisesRegex(ValueError, "Invalid Info.plist"):
            inspect_ipa(self.write_fixture([("Widget", "com.apple.widgetkit-extension")], malformed=True))

    def test_duplicate_entries_rejected(self):
        with self.assertRaisesRegex(ValueError, "duplicate"):
            inspect_ipa(self.write_fixture(duplicate=True))

    def test_traversal_entry_rejected(self):
        self.write_fixture()
        with zipfile.ZipFile(self.ipa, "a") as archive:
            archive.writestr("../escape.txt", b"unsafe")
        with self.assertRaisesRegex(ValueError, "Unsafe"):
            inspect_ipa(self.ipa)

    def test_missing_nested_executable_is_reported(self):
        path = self.write_fixture([("Widget", "com.apple.widgetkit-extension")])
        with zipfile.ZipFile(path, "r") as source:
            payload = [(item.filename, source.read(item.filename))
                       for item in source.infolist() if not item.filename.endswith("/Widget")]
        with zipfile.ZipFile(path, "w") as destination:
            for name, data in payload:
                destination.writestr(name, data)
        result = inspect_ipa(path)
        self.assertFalse(result["widgetkit_extensions"][0]["has_executable"])


if __name__ == "__main__":
    unittest.main()
