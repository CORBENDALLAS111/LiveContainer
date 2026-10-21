#!/usr/bin/env python3
"""Create rootless and rootful Debian tweak archives on any platform."""
from __future__ import annotations
import argparse
import io
from pathlib import Path
import plistlib
import tarfile

PACKAGE = "com.chatgpt.usageoverlay"
VERSION = "1.0.2"

def tarball(files):
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode="w:gz", format=tarfile.GNU_FORMAT) as archive:
        for name, (content, mode) in files.items():
            info = tarfile.TarInfo(name)
            info.size = len(content)
            info.mode = mode
            info.uid = info.gid = 0
            info.uname = info.gname = "root"
            info.mtime = 0
            archive.addfile(info, io.BytesIO(content))
    return output.getvalue()

def ar_member(name, payload):
    if len(name) > 15:
        raise ValueError("ar name too long")
    header = (f"{name}/".ljust(16) + "0".ljust(12) + "0".ljust(6) + "0".ljust(6)
              + "100644".ljust(8) + str(len(payload)).ljust(10) + "\x60\n").encode("ascii")
    return header + payload + (b"\n" if len(payload) % 2 else b"")

def build(dylib, output, rootless):
    arch = "iphoneos-arm64" if rootless else "iphoneos-arm"
    location = ("var/jb/" if rootless else "") + "Library/MobileSubstrate/DynamicLibraries/"
    plist = plistlib.dumps({"Filter": {"Bundles": ["com.openai.chat"]}}, fmt=plistlib.FMT_XML)
    control = f"""Package: {PACKAGE}
Name: ChatGPT Usage Overlay
Version: {VERSION}
Architecture: {arch}
Maintainer: ChatGPTUsage Project
Section: Tweaks
Priority: optional
Description: Experimental ChatGPT manual usage overlay
 Shows manually entered counts; does not fetch server-side ChatGPT limits.
""".encode()
    content = (b"!<arch>\n" + ar_member("debian-binary", b"2.0\n")
               + ar_member("control.tar.gz", tarball({"./control": (control, 0o644)}))
               + ar_member("data.tar.gz", tarball({
                   "./" + location + "ChatGPTUsage.dylib": (dylib.read_bytes(), 0o755),
                   "./" + location + "ChatGPTUsage.plist": (plist, 0o644),
               })))
    result = output / f"ChatGPTUsage_{VERSION}_{arch}.deb"
    result.write_bytes(content)
    print(f"Created {result} ({len(content)} bytes)")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("dylib", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if not args.dylib.is_file():
        parser.error(f"File not found: {args.dylib}")
    output = args.output or args.dylib.parent
    output.mkdir(parents=True, exist_ok=True)
    for rootless in (True, False):
        build(args.dylib, output, rootless)

if __name__ == "__main__":
    main()
