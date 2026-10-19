"""Preserve host Shortcuts metadata when integrating SideStore's existing actions."""
import argparse
import json
import pathlib
import shutil


def merge(host, side):
    host, side = pathlib.Path(host), pathlib.Path(side)
    source = side / 'extract.actionsdata'
    target = host / source.name
    incoming = json.loads(source.read_text())
    # These implementations live in the existing bridge, not the embedded SideStore image.
    serialized = json.dumps(incoming).replace('9SideStore20RefreshAllAppsIntentV', '16SideStoreSupport20RefreshAllAppsIntentV')
    serialized = serialized.replace('9SideStore26RefreshAllAppsWidgetIntentV', '16SideStoreSupport26RefreshAllAppsWidgetIntentV')
    incoming = json.loads(serialized)
    if not target.exists():
        shutil.copytree(side, host, dirs_exist_ok=True)
        result = incoming
    else:
        result = json.loads(target.read_text())
        if result.get('version') != incoming.get('version'):
            raise ValueError('Cannot merge different App Intents metadata schema versions')
        for key, value in incoming.items():
            if key in ('actions', 'entities', 'queries'):
                destination = result.setdefault(key, {})
                for identifier, entry in value.items():
                    if identifier in destination and destination[identifier] != entry:
                        raise ValueError('Conflicting App Intents identifier: ' + identifier)
                    destination[identifier] = entry
            elif isinstance(value, list):
                destination = result.setdefault(key, [])
                for entry in value:
                    if entry not in destination:
                        destination.append(entry)
            elif key not in result:
                result[key] = value
        # The host's generated provider, version/generator and compiled NLU remain authoritative.
        # Copying an entire directory here nests Metadata.appintents and hides SideStore actions.
    target.write_text(json.dumps(result, separators=(',', ':')))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('host')
    parser.add_argument('sidestore')
    args = parser.parse_args()
    merge(args.host, args.sidestore)
