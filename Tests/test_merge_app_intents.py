import importlib.util
import json
import pathlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('merge_app_intents', pathlib.Path(__file__).parents[1] / 'scripts/merge_app_intents.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class MetadataMergeTests(unittest.TestCase):
    def test_preserves_host_provider_and_both_actions_without_nested_directories(self):
        with tempfile.TemporaryDirectory() as directory:
            host, side = pathlib.Path(directory) / 'host', pathlib.Path(directory) / 'side'
            host.mkdir(); side.mkdir()
            target = host / 'extract.actionsdata'
            target.write_text(json.dumps({'version': 1, 'actions': {'LCLaunchGuestIntent': {}}, 'autoShortcutProviderMangledName': 'HostProvider', 'autoShortcuts': ['host']}))
            (side / target.name).write_text(json.dumps({'version': 1, 'actions': {'RefreshAllIntent': {'mangledTypeName': '9SideStore20RefreshAllAppsIntentV'}}, 'autoShortcutProviderMangledName': 'SideProvider', 'autoShortcuts': ['side']}))
            (host / 'version.json').write_text('host version')
            module.merge(host, side)
            result = json.loads(target.read_text())
            self.assertEqual(set(result['actions']), {'LCLaunchGuestIntent', 'RefreshAllIntent'})
            self.assertEqual(result['actions']['RefreshAllIntent']['mangledTypeName'], '16SideStoreSupport20RefreshAllAppsIntentV')
            self.assertEqual(result['autoShortcutProviderMangledName'], 'HostProvider')
            self.assertEqual(result['autoShortcuts'], ['host', 'side'])
            self.assertEqual((host / 'version.json').read_text(), 'host version')
            self.assertFalse((host / 'Metadata.appintents').exists())
            module.merge(host, side)
            self.assertEqual(json.loads(target.read_text()), result)

    def test_conflicting_action_does_not_overwrite_host(self):
        with tempfile.TemporaryDirectory() as directory:
            host, side = pathlib.Path(directory) / 'host', pathlib.Path(directory) / 'side'
            host.mkdir(); side.mkdir()
            original = json.dumps({'version': 1, 'actions': {'Existing': {'type': 'Host'}}})
            (host / 'extract.actionsdata').write_text(original)
            (side / 'extract.actionsdata').write_text(json.dumps({'version': 1, 'actions': {'Existing': {'type': 'Other'}}}))
            with self.assertRaises(ValueError):
                module.merge(host, side)
            self.assertEqual((host / 'extract.actionsdata').read_text(), original)


if __name__ == '__main__':
    unittest.main()
