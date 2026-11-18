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
    if hashlib.sha256((root / 'scripts/prepare_sidestore_source.py').read_bytes()).hexdigest() != manifest.get('integration_script_sha256'):
        raise ValueError('Rebuild SideStore: pipeline integration script changed')
    files = {name: root / 'Integrations/SideStore' / name for name in ['LCOSSigningInjection.swift', 'LCOSSigningInjectionUI.swift']}
    files.update({name: root / 'LiveContainerSwiftUI/PackageManager/Core' / name for name in
                  ['SigningMachO.swift', 'SigningInjectionPreset.swift', 'SigningBundleIdentifiers.swift', 'PackageSHA256.swift', 'SigningDiagnostics.swift', 'SigningIncreasedMemory.swift']})
    for name, file in files.items():
        if hashlib.sha256(file.read_bytes()).hexdigest() != manifest.get('overlay', {}).get(name):
            raise ValueError('Rebuild SideStore: changed overlay source ' + name)
    memory = manifest.get('memory_capability')
    if not isinstance(memory, dict) or memory.get('entitlement') != 'com.apple.developer.kernel.increased-memory-limit':
        raise ValueError('Rebuild SideStore: Increased Memory Limit signing metadata is missing')
    patch = root / 'scripts/patch_sidestore_memory_signer.py'
    if hashlib.sha256(patch.read_bytes()).hexdigest() != memory.get('sidesign_patch_script_sha256'):
        raise ValueError('Rebuild SideStore: Increased Memory Limit signer patch changed')
    if memory.get('sidesign', {}).get('submodule') != '752d1ef602aa792a432ffa1e71646dc1ecf7363c':
        raise ValueError('Rebuild SideStore: unexpected SideSign revision')
    if not memory.get('signature_requires_profile') or not memory.get('profile_operation_sha256'):
        raise ValueError('Rebuild SideStore: Apple profile grant verification not recorded')
    print('Pinned SideStore revision and all overlay sources match this checkout.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('manifest')
    verify(parser.parse_args().manifest)
