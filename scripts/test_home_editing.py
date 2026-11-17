"""Native XCUITest regression: mini blank/gap holds, badges, Done and context menus."""
import json
import os
import pathlib
import subprocess

root = pathlib.Path(__file__).resolve().parent.parent
out = root / 'artifacts/home-editing-tests'
out.mkdir(parents=True, exist_ok=True)
sources = ['Tests/HomeScreenPreview/PreviewHost.swift', 'LiveContainerSwiftUI/HomeScreen/Core',
           'LiveContainerSwiftUI/HomeScreen/LCHomeIconArtwork.swift', 'LiveContainerSwiftUI/HomeScreen/LCHomeGlass.swift',
           'LiveContainerSwiftUI/HomeScreen/LCHomeDragSource.swift', 'LiveContainerSwiftUI/HomeScreen/LCHomeScreenView.swift']
spec = {'name': 'HomeEditing', 'options': {'deploymentTarget': {'iOS': '16.0'}}, 'targets': {
    'HomeEditingHost': {'type': 'application', 'platform': 'iOS', 'sources': [str(root / p) for p in sources],
        'settings': {'base': {'PRODUCT_BUNDLE_IDENTIFIER': 'org.example.homeediting', 'GENERATE_INFOPLIST_FILE': 'YES',
                             'SWIFT_ACTIVE_COMPILATION_CONDITIONS': 'DEBUG', 'TARGETED_DEVICE_FAMILY': '1,2',
                             'INFOPLIST_KEY_UILaunchScreen_Generation': 'YES',
                             'INFOPLIST_KEY_UISupportedInterfaceOrientations': 'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight'}},},
    'HomeEditingUITests': {'type': 'bundle.ui-testing', 'platform': 'iOS',
        'sources': [str(root / 'Tests/HomeScreenPreview/HomeEditingUITests.swift')],
        'dependencies': [{'target': 'HomeEditingHost'}],
        'settings': {'base': {'PRODUCT_BUNDLE_IDENTIFIER': 'org.example.homeediting.tests', 'GENERATE_INFOPLIST_FILE': 'YES',
                             'TEST_TARGET_NAME': 'HomeEditingHost'}}}},
    'schemes': {'HomeEditing': {'build': {'targets': {'HomeEditingHost': 'all', 'HomeEditingUITests': ['test']}},
                              'test': {'targets': ['HomeEditingUITests']}}}}
(out / 'project.json').write_text(json.dumps(spec), encoding='utf-8')
subprocess.run(['xcodegen', 'generate', '--spec', str(out / 'project.json')], check=True)
devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j']))['devices']
sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version'], text=True).strip()
runtimes = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'runtimes', '-j']))['runtimes']
runtime = next(r['identifier'] for r in runtimes if r['version'] == sdk and r['isAvailable'])
requested = os.environ.get('LCOS_TEST_DEVICE', 'mini')
if requested not in ('mini', 'iphone'):
    raise ValueError('LCOS_TEST_DEVICE must be mini or iphone')
device_name = 'iPad mini' if requested == 'mini' else 'iPhone'
device = next(d for d in devices[runtime] if device_name in d['name'])
report_name = 'MiniEditing' if requested == 'mini' else 'iPhoneContinuous'
print('Testing on', device['name'], runtime, flush=True)
# Warm the selected device before XCTest installs its runner. Cold automatic
# boot can stall before the first test on shared macOS runners.
if device['state'] != 'Booted':
    subprocess.run(['xcrun', 'simctl', 'boot', device['udid']], check=True, timeout=120)
subprocess.run(['open', '-a', 'Simulator', '--args', '-CurrentDeviceUDID', device['udid']], check=True, timeout=60)
subprocess.run(['xcrun', 'simctl', 'bootstatus', device['udid'], '-b'], check=True, timeout=300)
try:
    command = ['xcodebuild', '-project', str(out / 'HomeEditing.xcodeproj'), '-scheme', 'HomeEditing',
               '-destination', 'platform=iOS Simulator,id=' + device['udid'], '-parallel-testing-enabled', 'NO',
               '-resultBundlePath', str(out / (report_name + '.xcresult')), 'test']
    if requested == 'iphone':
        command.append('-only-testing:HomeEditingUITests/HomeEditingUITests/testOneContinuousGridScrollsFromFirstTo128thApp')
    subprocess.run(command, check=True, timeout=900)

finally:
    result = out / (report_name + '.xcresult')
    if result.exists():
        attachment_dir = 'attachments' if requested == 'mini' else 'attachments-iphone'
        subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(result),
                        '--output-path', str(out / attachment_dir)], timeout=90)
