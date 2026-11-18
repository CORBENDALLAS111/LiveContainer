"""LC+ host-only Extra Memory preparation: no Apple login or signing in these tests."""
import pathlib
import plistlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "scripts"))
from prepare_host_memory_request import prepare_host, MARKER, ENTITLEMENT


class HostExtraMemoryRequestTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        root = pathlib.Path(self.temporary.name)
        self.app = root / "Payload" / "LiveContainer.app"
        self.app.mkdir(parents=True)
        self.app.joinpath("LiveContainer").write_bytes(b"test executable")
        self.app.joinpath("Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "com.kdt.livecontainer",
            "CFBundleExecutable": "LiveContainer",
        }))
        self.entitlements = root / "entitlements.xml"
        self.entitlements.write_bytes(plistlib.dumps({ENTITLEMENT: True}))

    def test_host_request_matches_real_bundle(self):
        evidence = prepare_host(self.app, self.entitlements)
        payload = plistlib.loads((self.app / MARKER).read_bytes())
        self.assertEqual(payload, {
            "schema": 1, "requested": True,
            "bundleIdentifier": "com.kdt.livecontainer",
        })
        self.assertEqual(evidence["bundle"], payload["bundleIdentifier"])
        self.assertFalse(evidence["apple_profile_granted"])
        self.assertFalse(evidence["installed_signature_verified"])

    def test_declared_entitlement_is_required(self):
        self.entitlements.write_bytes(plistlib.dumps({}))
        with self.assertRaisesRegex(ValueError, "host entitlement"):
            prepare_host(self.app, self.entitlements)
        self.assertFalse((self.app / MARKER).exists())

    def test_does_not_write_to_wrong_host(self):
        self.app.joinpath("Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "com.example.other",
            "CFBundleExecutable": "OtherApp",
        }))
        with self.assertRaisesRegex(ValueError, "real LC"):
            prepare_host(self.app, self.entitlements)
        self.assertFalse((self.app / MARKER).exists())

    def test_rejects_malformed_bundle_identifier(self):
        self.app.joinpath("Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "../escape",
            "CFBundleExecutable": "LiveContainer",
        }))
        with self.assertRaisesRegex(ValueError, "bundle identifier"):
            prepare_host(self.app, self.entitlements)
        self.assertFalse((self.app / MARKER).exists())


if __name__ == "__main__":
    unittest.main()
