"""Compile and exercise the actual guest runner with UIKit, gesture, SwiftUI and recording fixtures."""
import json
import os
import pathlib
import plistlib
import shutil
import subprocess
import time

root = pathlib.Path(__file__).resolve().parent.parent
out = root / 'artifacts/automation-preview'
app = out / 'LCOSAutomationPreview.app'
app.mkdir(parents=True, exist_ok=True)
sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip()
subprocess.run(['xcrun', 'swiftc', '-typecheck', '-parse-as-library', '-swift-version', '5',
                '-target', 'arm64-apple-ios15.0-simulator', '-sdk', sdk,
                str(root / 'LiveContainer/LCOSAppIntents.swift')], check=True)
swift_object = out / 'SwiftUIFixture.o'
subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-emit-object', '-target', 'arm64-apple-ios16.0-simulator',
                '-sdk', sdk, str(root / 'Tests/AutomationPreview/SwiftUIFixture.swift'), '-o', str(swift_object)], check=True)
objects = [swift_object]
for source in ['Tests/AutomationPreview/Main.m', 'TweakLoader/LCOSAutomation.m']:
    object_file = out / (pathlib.Path(source).stem + '.o')
    subprocess.run(['xcrun', 'clang', '-c', '-fobjc-arc', '-fmodules', '-target', 'arm64-apple-ios16.0-simulator',
                    '-isysroot', sdk, '-I', str(root / 'LiveContainer'), str(root / source), '-o', str(object_file)], check=True)
    objects.append(object_file)
subprocess.run(['xcrun', 'swiftc', '-target', 'arm64-apple-ios16.0-simulator', '-sdk', sdk,
                *map(str, objects), '-framework', 'SwiftUI', '-framework', 'UIKit', '-framework', 'WebKit', '-framework', 'Foundation',
                '-o', str(app / 'LCOSAutomationPreview')], check=True)
bundle = 'org.example.lcosautomationpreview'
(app / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': bundle,
    'CFBundleExecutable': 'LCOSAutomationPreview', 'CFBundleName': 'Automation Runner', 'CFBundleVersion': '1',
    'CFBundleShortVersionString': '1.0', 'CFBundlePackageType': 'APPL', 'MinimumOSVersion': '16.0',
    'CFBundleSupportedPlatforms': ['iPhoneSimulator'], 'UIDeviceFamily': [1, 2], 'UILaunchScreen': {}}))
subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
sdk_version = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version'], text=True).strip()
runtimes = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'runtimes', '-j']))['runtimes']
runtime = next(item['identifier'] for item in runtimes if item['version'] == sdk_version and item['isAvailable'])
devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j']))['devices'][runtime]
template = next(item for item in devices if 'iPhone' in item['name'])
types = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devicetypes', '-j']))['devicetypes']
kind = next(item['identifier'] for item in types if item['name'] == template['name'])
device = subprocess.check_output(['xcrun', 'simctl', 'create', 'LCOS Automation Test', kind, runtime], text=True).strip()
try:
    subprocess.run(['xcrun', 'simctl', 'boot', device], check=True)
    subprocess.run(['xcrun', 'simctl', 'bootstatus', device, '-b'], check=True, timeout=240)
    subprocess.run(['xcrun', 'simctl', 'install', device, str(app)], check=True)
    subprocess.run(['xcrun', 'simctl', 'launch', device, bundle], check=True)
    container = pathlib.Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', device, bundle, 'data'], text=True).strip())
    evidence = container / 'Documents/automation-evidence.json'
    for _ in range(45):
        if evidence.exists():
            break
        time.sleep(1)
    shutil.copyfile(evidence, out / 'automation-evidence.json')
    result = json.loads(evidence.read_text())
    print(json.dumps(result, indent=2))
    shutil.copyfile(container / 'Documents/LCOSAutomations.json', out / 'saved-scenario.json')
    subprocess.run(['xcrun', 'simctl', 'io', device, 'screenshot', str(out / 'runner.png')], check=True)
    assert all(result[key] is True for key in ['actual_uikit_button_and_point', 'raw_touch_gesture', 'swiftui_point', 'recorded_profile_replay', 'recording_prompt_starts_capture', 'web_button_record_replay', 'background_cancellation', 'disabled_does_not_execute'])
finally:
    subprocess.run(['xcrun', 'simctl', 'shutdown', device], capture_output=True)
    subprocess.run(['xcrun', 'simctl', 'delete', device], capture_output=True)
