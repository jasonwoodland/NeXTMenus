#!/usr/bin/env python3
from pathlib import Path
import re
import sys

source_roots = [Path("Sources/NeXTMenus"), Path("Sources/NeXTMenusKit")]
source_files = sorted(
    path.name
    for root in source_roots
    for path in root.glob("*.swift")
)

pbxproj = Path("NeXTMenus.xcodeproj/project.pbxproj").read_text()
xcode_files = sorted(set(re.findall(r"/\* ([^*/]+\.swift) in Sources \*/", pbxproj)))

missing_in_xcode = sorted(set(source_files) - set(xcode_files))
stale_in_xcode = sorted(set(xcode_files) - set(source_files))

if missing_in_xcode or stale_in_xcode:
    if missing_in_xcode:
        print("Swift files missing from Xcode source phase:")
        for name in missing_in_xcode:
            print(f"  - {name}")
    if stale_in_xcode:
        print("Stale Xcode source phase entries:")
        for name in stale_in_xcode:
            print(f"  - {name}")
    sys.exit(1)

print(f"Xcode source phase matches {len(source_files)} Swift source files.")
