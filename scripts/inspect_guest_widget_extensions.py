#!/usr/bin/env python3
"""Read-only inventory of *original* guest WidgetKit extensions in an IPA.

This is NOT a widget launcher, a proxy widget, a signer, or a compatibility claim.
iOS discovers widget extensions as installed signed app extensions, not as files
placed in a guest application's sandbox after installation.
"""
import argparse
import json
import pathlib
import plistlib
import zipfile

MAX_INFO_BYTES = 1024 * 1024
MAX_ENTRIES = 50_000
WIDGETKIT_EXTENSION_POINT = "com.apple.widgetkit-extension"


def _plist(archive: zipfile.ZipFile, path: str) -> dict:
    try:
        entry = archive.getinfo(path)
    except KeyError as exc:
        raise ValueError("Missing Info.plist: " + path) from exc
    if entry.file_size > MAX_INFO_BYTES:
        raise ValueError("Oversized Info.plist: " + path)
    try:
        with archive.open(entry) as stream:
            value = plistlib.load(stream)
    except (plistlib.InvalidFileException, ValueError, TypeError) as exc:
        raise ValueError("Invalid Info.plist: " + path) from exc
    if not isinstance(value, dict):
        raise ValueError("Expected dictionary Info.plist: " + path)
    return value


def inspect_ipa(path: str | pathlib.Path) -> dict:
    """Inspect IPA metadata without extracting or executing untrusted contents."""
    path = pathlib.Path(path)
    if not path.is_file():
        raise ValueError("IPA file does not exist")
    try:
        archive = zipfile.ZipFile(path)
    except (zipfile.BadZipFile, OSError) as exc:
        raise ValueError("Invalid IPA archive") from exc
    with archive:
        entries = archive.namelist()
        if len(entries) > MAX_ENTRIES or len(entries) != len(set(entries)):
            raise ValueError("Too many or duplicate IPA archive entries")
        if any(name.startswith("/") or "\\" in name or ".." in pathlib.PurePosixPath(name).parts for name in entries):
            raise ValueError("Unsafe IPA archive path")
        names = set(entries)
        roots = [name for name in names if
                 len(name.split("/")) == 3 and
                 name.startswith("Payload/") and name.endswith(".app/Info.plist")]
        if len(roots) != 1:
            raise ValueError("IPA must contain exactly one root application")
        root_plist = roots[0]
        root = root_plist[:-len("Info.plist")]
        main_info = _plist(archive, root_plist)
        bundle_id = main_info.get("CFBundleIdentifier")
        if not isinstance(bundle_id, str) or not bundle_id:
            raise ValueError("Missing containing application's bundle identifier")

        prefix = root + "PlugIns/"
        extensions = []
        for name in sorted(names):
            if not name.startswith(prefix) or not name.endswith("/Info.plist"):
                continue
            relative = name[len(prefix):].split("/")
            if len(relative) != 2 or not relative[0].endswith(".appex"):
                continue
            info = _plist(archive, name)
            ns = info.get("NSExtension")
            point = ns.get("NSExtensionPointIdentifier") if isinstance(ns, dict) else None
            identifier = info.get("CFBundleIdentifier")
            executable = info.get("CFBundleExecutable")
            extension_root = name[:-len("Info.plist")]
            has_executable = (
                isinstance(executable, str) and bool(executable) and
                "/" not in executable and executable not in (".", "..") and
                extension_root + executable in names
            )
            extension = {
                "name": relative[0],
                "bundle_id": identifier if isinstance(identifier, str) else None,
                "extension_point": point if isinstance(point, str) else None,
                "is_original_widgetkit_extension": point == WIDGETKIT_EXTENSION_POINT,
                "has_executable": has_executable,
                "namespaced_under_containing_app": (
                    isinstance(identifier, str) and identifier.startswith(bundle_id + ".")
                ),
                "has_embedded_profile": extension_root + "embedded.mobileprovision" in names,
                "has_code_signature_files": extension_root + "_CodeSignature/CodeResources" in names,
            }
            extensions.append(extension)

        widgets = [extension for extension in extensions if extension["is_original_widgetkit_extension"]]
        return {
            "containing_bundle_id": bundle_id,
            "extension_count": len(extensions),
            "widgetkit_extension_count": len(widgets),
            "widgetkit_extensions": widgets,
            "other_extension_points": sorted({
                item["extension_point"] for item in extensions
                if not item["is_original_widgetkit_extension"] and item["extension_point"]
            }),
            "original_guest_widgets_installed_or_registered": False,
            "registration_method": "Requires an installed containing app with signed nested extension(s)",
            "required_before_a_device_trial": [
                "Package the actual original .appex into a newly installed application at build/install time",
                "Provision and sign each extension with its own valid App ID and permitted entitlements",
                "Sign and install the containing application and open it so WidgetKit can discover extensions",
                "Validate guest data access, app-group requirements, and widget timeline execution on device",
            ] if widgets else [],
            "status": "metadata_only_not_device_tested",
        }


def main() -> int:
    parser = argparse.ArgumentParser(description="Inventory real guest WidgetKit .appex files in an IPA (no install)")
    parser.add_argument("ipa", help="Path to an IPA you own or are authorized to inspect")
    args = parser.parse_args()
    try:
        print(json.dumps(inspect_ipa(args.ipa), indent=2, sort_keys=True, ensure_ascii=False))
    except (ValueError, OSError) as error:
        parser.error(str(error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
