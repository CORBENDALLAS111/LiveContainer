"""Read-only structural IPA verification. Does not claim device functionality or provisioning validity."""
import argparse
import hashlib
import json
import pathlib
import plistlib
import zipfile
from verify_sidebackup import verify_embedded_sidebackup

MACHO_MAGIC = [bytes.fromhex('cffaedfe'), bytes.fromhex('cafebabe'), bytes.fromhex('bebafeca')]


def verify_frameworks(archive):
    """Check every framework, including those nested inside the embedded store."""
    names = set(archive.namelist())
    frameworks = set()
    for name in names:
        parts = pathlib.PurePosixPath(name).parts
        for index, part in enumerate(parts):
            if part.endswith('.framework'):
                frameworks.add('/'.join(parts[:index + 1]) + '/')
    for framework in sorted(frameworks):
        plist = framework + 'Info.plist'
        if plist not in names:
            raise ValueError('Framework Info.plist missing: ' + framework)
        try:
            info = plistlib.loads(archive.read(plist))
        except (ValueError, plistlib.InvalidFileException) as error:
            raise ValueError('Invalid framework Info.plist: ' + framework) from error
        for key in ['CFBundleIdentifier', 'CFBundleExecutable', 'CFBundleVersion']:
            if not isinstance(info, dict) or not isinstance(info.get(key), str) or not info[key].strip():
                raise ValueError(f'Missing framework {key}: {framework}')
        executable = info['CFBundleExecutable']
        if executable in ['.', '..'] or '/' in executable or '\\' in executable:
            raise ValueError('Invalid framework executable name: ' + framework)
        binary = framework + executable
        if binary not in names:
            raise ValueError('Missing framework Mach-O executable: ' + binary)
        with archive.open(binary) as stream:
            if stream.read(4) not in MACHO_MAGIC:
                raise ValueError('Missing framework Mach-O executable: ' + binary)
    return len(frameworks)


def verify(path, integrated=False, source_commit=None, signing_injection=False, automations=False, builtin_jit=False):
    path = pathlib.Path(path)
    if not path.is_file() or path.stat().st_size == 0:
        raise ValueError('IPA is absent or empty')
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None:
            raise ValueError('Damaged ZIP entry')
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError('Duplicate ZIP entries')
        if any(name.startswith('/') or '..' in pathlib.PurePosixPath(name).parts for name in names):
            raise ValueError('Unsafe IPA entry path')
        roots = [name for name in names if name.count('/') == 2 and name.startswith('Payload/') and name.endswith('.app/Info.plist')]
        if len(roots) != 1:
            raise ValueError('Expected exactly one root application')
        root = roots[0][:-len('Info.plist')]
        info = plistlib.loads(archive.read(roots[0]))
        framework_count = verify_frameworks(archive)
        for key in ['CFBundleIdentifier', 'CFBundleExecutable', 'CFBundleVersion', 'MinimumOSVersion']:
            if not info.get(key):
                raise ValueError('Missing Info.plist value: ' + key)
        executable = root + info['CFBundleExecutable']
        touch_binary = root + 'Frameworks/TweakLoader.dylib'
        if touch_binary in names and b'IOHIDEventCreateDigitizerFingerEventWithQuality' in archive.read(touch_binary):
            for license_name in ['KIF-Apache-2.0.txt', 'KIF-NOTICE.txt']:
                if root + license_name not in names or not archive.read(root + license_name):
                    raise ValueError('Missing touch implementation license/notice: ' + license_name)
        if archive.read(executable)[:4] not in MACHO_MAGIC:
            raise ValueError('Missing Mach-O executable')
        for suffix in ['Frameworks/LiveContainerSwiftUI.framework/LiveContainerSwiftUI',
                       'Frameworks/CydiaSubstrate.framework/CydiaSubstrate', 'Frameworks/TweakLoader.dylib']:
            if root + suffix not in names:
                raise ValueError('Missing required component: ' + suffix)
        if integrated:
            for suffix in ['Frameworks/SideStoreApp.framework/SideStore',
                           'Frameworks/SideStoreApp.framework/Info.plist',
                           'Frameworks/SideStoreSupport.framework/SideStoreSupport',
                           'PlugIns/LiveWidgetExtension.appex/LiveWidgetExtension']:
                if root + suffix not in names:
                    raise ValueError('Missing integrated component: ' + suffix)
            if 'group.com.SideStore.SideStore' not in info.get('ALTAppGroups', []):
                raise ValueError('Missing SideStore app group declaration')
        if signing_injection:
            side = root + 'Frameworks/SideStoreApp.framework/'
            manifest = json.loads(archive.read(side + 'LCOSSigningIntegration.json'))
            if manifest.get('schema') != 1 or len(manifest.get('commit', '')) != 40 or not manifest.get('resign_operation_sha256'):
                raise ValueError('Missing SideStore signing overlay provenance')
            if b'LCOSInjected' not in archive.read(side + 'SideStore'):
                raise ValueError('SideStore binary lacks the signing injection implementation')
            if 'LCOSSigningInjectionUI.swift' not in manifest.get('overlay', {}) or not manifest.get('install_ui'):
                raise ValueError('Missing SideStore installation UI integration provenance')
            if not manifest.get('install_ui', {}).get('host_ui_only') or not manifest.get('install_ui', {}).get('pipeline_diagnostics') or not manifest.get('install_ui', {}).get('picker_owned_copy'):
                raise ValueError('SideStore must use host configuration and persistent pipeline diagnostics')
            if not manifest.get('extension_ids', {}).get('validate_before_signing') or 'SigningBundleIdentifiers.swift' not in manifest.get('overlay', {}):
                raise ValueError('Missing extension bundle ID correction provenance')
            verify_embedded_sidebackup(archive)
        if automations:
            metadata = json.loads(archive.read(root + 'Metadata.appintents/extract.actionsdata'))
            actions = metadata.get('actions', {})
            if any(intent not in actions for intent in ['LCLaunchGuestIntent', 'LCRunAutomationIntent']):
                raise ValueError('Main application lacks discoverable Shortcuts action metadata')
            if integrated and 'RefreshAllIntent' not in actions:
                raise ValueError('Integrated application lost SideStore refresh action metadata')
        if builtin_jit:
            helper = root + 'PlugIns/LifeJITHelper.appex/'
            helper_info = plistlib.loads(archive.read(helper + 'Info.plist'))
            if helper_info['CFBundleIdentifier'] != info['CFBundleIdentifier'] + '.LifeJITHelper':
                raise ValueError('JIT helper is outside the parent bundle namespace')
            if info['CFBundleDisplayName'] != 'LifeContainer+':
                raise ValueError('Incorrect LifeContainer+ display name')
            for suffix in ['PlugIns/LifeJITHelper.appex/LifeJITHelper', 'Frameworks/StikJIT.framework/StikJIT',
                           'Frameworks/StikJIT.framework/Info.plist',
                           'StikJIT-MPL-2.0.txt', 'idevice-MIT.txt', 'LifeJIT-SOURCE.json']:
                if root + suffix not in names or not archive.read(root + suffix):
                    raise ValueError('Missing built-in JIT component: ' + suffix)
            jit_info = plistlib.loads(archive.read(root + 'Frameworks/StikJIT.framework/Info.plist'))
            if (jit_info.get('CFBundlePackageType') != 'FMWK' or
                    jit_info.get('CFBundleIdentifier') != 'com.stik.StikJIT' or
                    jit_info.get('CFBundleSupportedPlatforms') != ['iPhoneOS']):
                raise ValueError('Invalid built-in JIT framework metadata or platform')
            provenance = json.loads(archive.read(root + 'LifeJIT-SOURCE.json'))
            if provenance.get('commit') != '32287268fa5824f9edce4cb359f5833ce0cf7b00' or not provenance.get('source_build'):
                raise ValueError('Unverified StikJIT source provenance')
        return {'file': path.name, 'bytes': path.stat().st_size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                'bundle': info['CFBundleIdentifier'], 'signing_injection': signing_injection, 'integrated': integrated, 'entries': len(names),
                'frameworks_checked': framework_count,
                'source_commit': source_commit, 'automation_metadata': automations,
                'verification': 'ZIP integrity and expected components only', 'device_tested': False}

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('ipa')
    parser.add_argument('--integrated', action='store_true')
    parser.add_argument('--signing-injection', action='store_true')
    parser.add_argument('--automations', action='store_true')
    parser.add_argument('--builtin-jit', action='store_true')
    parser.add_argument('--output')
    parser.add_argument('--source-commit')
    args = parser.parse_args()
    evidence = verify(args.ipa, args.integrated, args.source_commit, args.signing_injection, args.automations, args.builtin_jit)
    result = json.dumps(evidence, indent=2)
    if args.output:
        pathlib.Path(args.output).write_text(result + '\n', encoding='utf-8')
    print(result)
