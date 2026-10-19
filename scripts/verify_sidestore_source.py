"""Reject a reused SideStore artifact if its pinned source or overlay differs from this checkout."""
import argparse
import hashlib
import json
import pathlib


def verify(path):
    root = pathlib.Path(__file__).resolve().parent.parent
    manifest = json.loads(pathlib.Path(path).read_text())
    if manifest.get('schema') != 1 or manifest.get('commit') != 'ee3cc16a67f9fed766f79a0ed70938f0f8ad5a07':
        raise ValueError('SideStore artifact does not match the pinned source revision')
    files = {name: root / 'Integrations/SideStore' / name for name in ['LCOSSigningInjection.swift', 'LCOSSigningInjectionUI.swift']}
    files.update({name: root / 'LiveContainerSwiftUI/PackageManager/Core' / name for name in
                  ['SigningMachO.swift', 'SigningInjectionPreset.swift', 'SigningBundleIdentifiers.swift', 'PackageSHA256.swift']})
    for name, file in files.items():
        if hashlib.sha256(file.read_bytes()).hexdigest() != manifest.get('overlay', {}).get(name):
            raise ValueError('Rebuild SideStore: changed overlay source ' + name)
    print('Pinned SideStore revision and all six overlay sources match this checkout.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('manifest')
    verify(parser.parse_args().manifest)
