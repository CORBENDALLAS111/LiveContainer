"""Build the pinned MPL StikJIT source and our separate debugger extension."""
import hashlib, json, pathlib, plistlib, shutil, subprocess, sys, urllib.request

root = pathlib.Path(__file__).resolve().parent.parent
app = pathlib.Path(sys.argv[1]).resolve()
work = root / 'artifacts/builtin-jit'
work.mkdir(parents=True, exist_ok=True)
source = work / 'StikJIT'
commit = '32287268fa5824f9edce4cb359f5833ce0cf7b00'
if not source.exists():
    subprocess.run(['git', 'clone', '--depth', '1', '--branch', '1.9.0', 'https://github.com/StikDebug/StikJIT.git', str(source)], check=True)
assert subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip() == commit
subprocess.run(['xcodegen', 'generate'], cwd=source, check=True)
subprocess.run(['xcodebuild', 'archive', '-project', str(source / 'StikJIT.xcodeproj'), '-scheme', 'StikJIT',
    '-destination', 'generic/platform=iOS', '-archivePath', str(work / 'StikJIT'),
    'CODE_SIGNING_ALLOWED=NO', 'ARCHS=arm64', 'SKIP_INSTALL=NO', 'BUILD_LIBRARY_FOR_DISTRIBUTION=YES'], check=True)
framework = work / 'StikJIT.xcarchive/Products/Library/Frameworks/StikJIT.framework'
destination = app / 'Frameworks/StikJIT.framework'
shutil.copytree(framework, destination, dirs_exist_ok=True)
info = plistlib.loads((app / 'Info.plist').read_bytes())
helper = app / 'PlugIns/LifeJITHelper.appex'
helper.mkdir(parents=True, exist_ok=True)
sdk = subprocess.check_output(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'], text=True).strip()
subprocess.run(['xcrun', 'swiftc', '-O', '-parse-as-library', '-application-extension', '-target', 'arm64-apple-ios17.4',
    '-sdk', sdk, '-F', str(framework.parent), '-framework', 'StikJIT', '-framework', 'Foundation',
    '-Xlinker', '-e', '-Xlinker', '_NSExtensionMain', '-Xlinker', '-rpath', '-Xlinker', '@executable_path/../../Frameworks',
    str(root / 'LifeJITHelper/Handler.swift'), '-o', str(helper / 'LifeJITHelper')], check=True)
(helper / 'Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': info['CFBundleIdentifier'] + '.LifeJITHelper', 'CFBundleExecutable': 'LifeJITHelper',
    'CFBundleName': 'LifeJITHelper', 'CFBundleDisplayName': 'LifeContainer+ JIT', 'CFBundlePackageType': 'XPC!',
    'CFBundleInfoDictionaryVersion': '6.0', 'CFBundleSupportedPlatforms': ['iPhoneOS'],
    'DTPlatformName': 'iphoneos', 'LSRequiresIPhoneOS': True,
    'CFBundleShortVersionString': info['CFBundleShortVersionString'], 'CFBundleVersion': info['CFBundleVersion'],
    'MinimumOSVersion': '17.4', 'UIDeviceFamily': [1, 2],
    'NSExtension': {'NSExtensionPointIdentifier': 'com.apple.ar.viewer', 'NSExtensionPrincipalClass': 'LifeJITHandler',
        'NSExtensionAttributes': {'NSExtensionActivationRule': 'FALSEPREDICATE'},
        'NSExtensionContextClass': 'NSExtensionContext', 'NSExtensionContextHostClass': 'NSExtensionContext'},
    'XPCService': {'ServiceType': 'Application', '_MultipleInstances': True, '_ProcessType': 'App'}
}))
shutil.copyfile(source / 'LICENSE', app / 'StikJIT-MPL-2.0.txt')
# idevice is linked into the upstream framework; preserve its original license.
shutil.copyfile(root / 'LifeJITHelper/idevice-MIT.txt', app / 'idevice-MIT.txt')
(app / 'LifeJIT-SOURCE.json').write_text(json.dumps({'repository': 'https://github.com/StikDebug/StikJIT',
    'commit': commit, 'license': 'MPL-2.0', 'source_build': True,
    'helper': 'LifeJITHelper/Handler.swift', 'physical_device_tested': False}, indent=2), encoding='utf-8')
for code in [destination, helper]:
    subprocess.run(['codesign', '--force', '--sign', '-', str(code)], check=True)
print('Built and embedded the separate LifeContainer+ JIT helper from pinned StikJIT source.')
