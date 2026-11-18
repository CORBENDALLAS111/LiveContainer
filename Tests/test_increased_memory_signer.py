"""Validate fail-closed signing changes without contacting Apple or signing apps."""
import pathlib
import sys
import tempfile
import unittest
from unittest.mock import patch as mock_patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "scripts"))
from patch_sidestore_memory_signer import patch, PINNED_SIDESIGN  # noqa: E402

# Exact structural anchors from pinned SideSign CodeSignerAPI.swift.
SIGNER_FIXTURE = '''
func prepare(_ app: AppBundle) throws {
    let matchedProfile = profile(for: app)!
            let applicationEntitlements = app.entitlements

            for (key, _) in filteredEntitlements {
                if let applicationValue = applicationEntitlements[key] {
                } else if key != "application-identifier"               &&
                          key != "com.apple.developer.team-identifier"  &&
                          key != "get-task-allow"
                {
                    filteredEntitlements.removeValue(forKey: key)
                }
            }
}
'''.replace('key != "get-task-allow"' + chr(10), 'key != "get-task-allow" ' + chr(10))


class IncreasedMemorySignerTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.repo = pathlib.Path(self.directory.name)
        self.signer = self.repo / "Sources/CodeSigning/CodeSignerAPI.swift"
        self.signer.parent.mkdir(parents=True)
        self.signer.write_text(SIGNER_FIXTURE, encoding="utf-8")

    def test_approved_request_keeps_only_the_one_entitlement(self):
        with mock_patch("patch_sidestore_memory_signer.subprocess.check_output",
                        return_value=PINNED_SIDESIGN + "\n"):
            metadata = patch(self.repo)
        result = self.signer.read_text()
        self.assertEqual(metadata["submodule"], PINNED_SIDESIGN)
        self.assertIn("LCOSIncreasedMemoryRequest.plist", result)
        self.assertIn('profile.entitlements[memoryKey] as? Bool == true', result.replace("matchedProfile", "profile"))
        self.assertIn('!(key == memoryKey && increasedMemoryRequested)', result)
        self.assertIn('if !app.isExtension && FileManager.default.fileExists', result)
        self.assertIn('requestBundle + "." + matchedProfile.teamIdentifier', result)

    def test_reject_changed_source(self):
        self.signer.write_text("unexpected source", encoding="utf-8")
        with mock_patch("patch_sidestore_memory_signer.subprocess.check_output",
                        return_value=PINNED_SIDESIGN + "\n"):
            with self.assertRaisesRegex(ValueError, "anchor changed"):
                patch(self.repo)

    def test_reject_unpinned_signer(self):
        with mock_patch("patch_sidestore_memory_signer.subprocess.check_output",
                        return_value="new-unreviewed-sha\n"):
            with self.assertRaisesRegex(ValueError, "revision changed"):
                patch(self.repo)

    def test_reject_reapplying_patch(self):
        with mock_patch("patch_sidestore_memory_signer.subprocess.check_output",
                        return_value=PINNED_SIDESIGN + "\n"):
            patch(self.repo)
            with self.assertRaises(ValueError):
                patch(self.repo)


if __name__ == "__main__":
    unittest.main()
