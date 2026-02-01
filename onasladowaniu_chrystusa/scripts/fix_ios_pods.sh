#!/usr/bin/env bash
set -euo pipefail

MIN_IOS="${MIN_IOS:-13.0}"

ROOT_DIR="$(pwd)"
IOS_DIR="$ROOT_DIR/ios"
PODFILE="$IOS_DIR/Podfile"

XC_DEBUG="$IOS_DIR/Flutter/Debug.xcconfig"
XC_PROFILE="$IOS_DIR/Flutter/Profile.xcconfig"
XC_RELEASE="$IOS_DIR/Flutter/Release.xcconfig"

timestamp() { date +"%Y%m%d_%H%M%S"; }

backup_file() {
  local f="$1"
  if [[ -f "$f" ]]; then
    local b="${f}.bak.$(timestamp)"
    cp -p "$f" "$b"
    echo "Backup: $b"
  fi
}

if [[ ! -d "$IOS_DIR" ]]; then
  echo "ERROR: Nie widzę katalogu ios/. Odpal skrypt z root projektu Flutter."
  exit 1
fi

if [[ ! -f "$PODFILE" ]]; then
  echo "ERROR: Nie widzę ios/Podfile."
  exit 1
fi

echo "==> Using MIN_IOS=$MIN_IOS"
echo "==> Patching Podfile and xcconfig files…"

backup_file "$PODFILE"
backup_file "$XC_DEBUG"
backup_file "$XC_PROFILE"
backup_file "$XC_RELEASE"

python3 - <<'PY'
import os, re, sys
from pathlib import Path

min_ios = os.environ.get("MIN_IOS", "13.0").strip()

root = Path.cwd()
ios_dir = root / "ios"
podfile = ios_dir / "Podfile"

xc_files = [
    (ios_dir / "Flutter" / "Debug.xcconfig",  "debug"),
    (ios_dir / "Flutter" / "Profile.xcconfig","profile"),
    (ios_dir / "Flutter" / "Release.xcconfig","release"),
]

def read_text(p: Path) -> str:
    return p.read_text(encoding="utf-8")

def write_text(p: Path, s: str):
    p.write_text(s, encoding="utf-8")

def ensure_podfile_platform():
    text = read_text(podfile)
    lines = text.splitlines(True)

    # If platform :ios exists -> replace version with min_ios (only if version is present)
    platform_re = re.compile(r"^\s*platform\s*:ios\s*,\s*['\"]([^'\"]+)['\"]\s*$")

    found = False
    for i, line in enumerate(lines):
        m = platform_re.match(line)
        if m:
            found = True
            current = m.group(1)
            if current != min_ios:
                lines[i] = re.sub(r"['\"][^'\"]+['\"]", f"'{min_ios}'", line)
            break

    if found:
        new_text = "".join(lines) + ("" if text.endswith("\n") else "\n")
        if new_text != text:
            write_text(podfile, new_text)
            print(f"Podfile: updated platform :ios to '{min_ios}'")
        else:
            print("Podfile: platform :ios already OK")
        return

    # Insert platform line near top:
    # - after initial comments/empty lines
    # - preferably after `source ...` if present early
    insert_at = 0
    for idx, line in enumerate(lines):
        if line.strip() == "" or line.lstrip().startswith("#"):
            continue
        # If first meaningful line is `source`, insert after it
        if re.match(r"^\s*source\s+['\"].+['\"]\s*$", line):
            insert_at = idx + 1
        else:
            # otherwise insert before first meaningful line
            insert_at = idx
        break

    platform_line = f"platform :ios, '{min_ios}'\n"
    lines.insert(insert_at, platform_line)

    new_text = "".join(lines) + ("" if text.endswith("\n") else "\n")
    write_text(podfile, new_text)
    print(f"Podfile: inserted platform :ios, '{min_ios}'")

def ensure_xcconfig_includes():
    for path, cfg in xc_files:
        if not path.exists():
            print(f"{path}: not found (skipping)")
            continue

        text = read_text(path)
        lines = text.splitlines(True)

        pods_include = f'#include "Pods/Target Support Files/Pods-Runner/Pods-Runner.{cfg}.xcconfig"\n'
        gen_include = '#include "Generated.xcconfig"\n'

        # Check if pods include already present (exact or with different slashes)
        if any(f"Pods-Runner.{cfg}.xcconfig" in ln for ln in lines):
            print(f"{path.name}: pods include already present")
            continue

        # Insert pods include just before Generated.xcconfig if present, else at top
        inserted = False
        for i, ln in enumerate(lines):
            if "Generated.xcconfig" in ln:
                lines.insert(i, pods_include)
                inserted = True
                break
        if not inserted:
            # Put at top, preserving BOM/empty first line isn’t needed typically
            lines.insert(0, pods_include)

        new_text = "".join(lines)
        # Ensure trailing newline
        if not new_text.endswith("\n"):
            new_text += "\n"
        write_text(path, new_text)
        print(f"{path.name}: inserted pods include for {cfg}")

ensure_podfile_platform()
ensure_xcconfig_includes()
PY

echo ""
echo "==> Done. Now run:"
echo "    flutter clean"
echo "    flutter pub get"
echo "    cd ios && pod install && cd .."
echo "    flutter build ios --release"

