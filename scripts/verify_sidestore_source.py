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
    memory = manifest.get('increased_memory_limit', {})
    if (memory.get('sidesign_base') != '752d1ef602aa792a432ffa1e71646dc1ecf7363c'
        or memory.get('sidesign_capability_patch') != '9d89dac1d391c934e5c69be1fadbb090d9a7f944'
        or memory.get('feature') != 'INCREASED_MEMORY_LIMIT'
        or memory.get('entitlement') != 'com.apple.developer.kernel.increased-memory-limit'
        or memory.get('profile_validation') is not True
        or memory.get('signer_requires_profile') is not True
        or memory.get('host_opt_in_only') is not True
        or any(len(memory.get(key, '')) != 64 for key in [
            'developer_portal_source_sha256', 'profile_operation_sha256', 'signer_sha256'])):
        raise ValueError('Rebuild SideStore: missing verified Increased Memory Limit capability integration')
    files = {name: root / 'Integrations/SideStore' / name for name in ['LCOSSigningInjection.swift', 'LCOSSigningInjectionUI.swift']}
    files.update({name: root / 'LiveContainerSwiftUI/PackageManager/Core' / name for name in
                  ['SigningMachO.swift', 'SigningInjectionPreset.swift', 'SigningBundleIdentifiers.swift', 'PackageSHA256.swift', 'SigningDiagnostics.swift']})
    for name, file in files.items():
        if hashlib.sha256(file.read_bytes()).hexdigest() != manifest.get('overlay', {}).get(name):
            raise ValueError('Rebuild SideStore: changed overlay source ' + name)
    print('Pinned SideStore revision and all overlay sources match this checkout.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('manifest')
    verify(parser.parse_args().manifest)
