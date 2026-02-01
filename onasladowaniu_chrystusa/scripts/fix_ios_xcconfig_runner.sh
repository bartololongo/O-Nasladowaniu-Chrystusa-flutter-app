#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
PBXPROJ="$ROOT/ios/Runner.xcodeproj/project.pbxproj"
PROFILE_XC="$ROOT/ios/Flutter/Profile.xcconfig"

if [[ ! -f "$PBXPROJ" ]]; then
  echo "ERROR: Nie widzę $PBXPROJ. Odpal z root projektu Flutter (tam gdzie pubspec.yaml)."
  exit 1
fi

# 1) Ensure Profile.xcconfig exists and contains proper includes
mkdir -p "$ROOT/ios/Flutter"
if [[ ! -f "$PROFILE_XC" ]]; then
  cat > "$PROFILE_XC" <<'EOF'
#include "Pods/Target Support Files/Pods-Runner/Pods-Runner.profile.xcconfig"
#include "Generated.xcconfig"
EOF
  echo "Created: ios/Flutter/Profile.xcconfig"
else
  # Ensure required includes exist (idempotent)
  if ! grep -q 'Pods-Runner.profile.xcconfig' "$PROFILE_XC"; then
    tmp="$(mktemp)"
    {
      echo '#include "Pods/Target Support Files/Pods-Runner/Pods-Runner.profile.xcconfig"'
      cat "$PROFILE_XC"
    } > "$tmp"
    mv "$tmp" "$PROFILE_XC"
    echo "Patched: ios/Flutter/Profile.xcconfig (added Pods include)"
  fi
  if ! grep -q 'Generated.xcconfig' "$PROFILE_XC"; then
    echo '#include "Generated.xcconfig"' >> "$PROFILE_XC"
    echo "Patched: ios/Flutter/Profile.xcconfig (added Generated include)"
  fi
fi

# 2) Backup pbxproj
TS="$(date +"%Y%m%d_%H%M%S")"
cp -p "$PBXPROJ" "$PBXPROJ.bak.$TS"
echo "Backup: $PBXPROJ.bak.$TS"

# 3) Patch pbxproj: set Runner target baseConfigurationReference for Debug/Release/Profile
python3 - <<'PY'
import re
from pathlib import Path

pbx_path = Path("ios/Runner.xcodeproj/project.pbxproj")
text = pbx_path.read_text(encoding="utf-8")

def find_section(name: str):
    m = re.search(rf"/\* Begin {re.escape(name)} section \*/", text)
    n = re.search(rf"/\* End {re.escape(name)} section \*/", text)
    if not m or not n:
        return None, None
    return m.start(), n.end()

# Helper: find PBXNativeTarget id for name "Runner"
runner_target_id = None
for m in re.finditer(r"([A-F0-9]{24}) /\* Runner \*/ = \{\s*isa = PBXNativeTarget;.*?name = Runner;.*?\};", text, re.S):
    runner_target_id = m.group(1)
    break

if not runner_target_id:
    raise SystemExit("ERROR: Nie znalazłem PBXNativeTarget o nazwie Runner w project.pbxproj")

# Extract buildConfigurationList for Runner target
m = re.search(rf"{runner_target_id} /\* Runner \*/ = \{{.*?buildConfigurationList = ([A-F0-9]{{24}}) /\* Build configuration list for PBXNativeTarget \"Runner\" \*/;.*?\}};", text, re.S)
if not m:
    raise SystemExit("ERROR: Nie mogę znaleźć buildConfigurationList dla targetu Runner")
cfg_list_id = m.group(1)

# From XCConfigurationList, extract build configuration IDs for that list
m = re.search(rf"{cfg_list_id} /\* Build configuration list for PBXNativeTarget \"Runner\" \*/ = \{{.*?buildConfigurations = \(\s*(.*?)\s*\);.*?\}};", text, re.S)
if not m:
    raise SystemExit("ERROR: Nie mogę znaleźć XCConfigurationList dla Runnera")
cfg_ids_block = m.group(1)

cfg_ids = re.findall(r"([A-F0-9]{24}) /\* (Debug|Release|Profile) \*/", cfg_ids_block)
if not cfg_ids:
    raise SystemExit("ERROR: Nie znalazłem ID konfiguracji Debug/Release/Profile dla Runnera")

cfg_id_by_name = {name: cid for cid, name in cfg_ids}

# Find PBXFileReference IDs for the desired xcconfigs.
# Prefer paths with Flutter/..., otherwise we patch existing refs.
def find_file_ref_id_for_path(path_suffix: str):
    # path = Flutter/Debug.xcconfig;
    m = re.search(rf"([A-F0-9]{{24}}) /\* .*? \*/ = \{{\s*isa = PBXFileReference;.*?\bpath = {re.escape(path_suffix)};.*?lastKnownFileType = text\.xcconfig;.*?\}};", text, re.S)
    return m.group(1) if m else None

def find_file_ref_id_for_name(name: str):
    # name = Debug.xcconfig;
    m = re.search(rf"([A-F0-9]{{24}}) /\* {re.escape(name)} \*/ = \{{\s*isa = PBXFileReference;.*?\b(lastKnownFileType = text\.xcconfig;).*?\}};", text, re.S)
    return m.group(1) if m else None

desired = {
    "Debug":  "Flutter/Debug.xcconfig",
    "Release":"Flutter/Release.xcconfig",
    "Profile":"Flutter/Profile.xcconfig",
}

file_ref_id = {}
for cfg_name, path in desired.items():
    fid = find_file_ref_id_for_path(path)
    if not fid:
        # Try to locate by the plain filename and patch its path to Flutter/...
        plain = path.split("/")[-1]
        fid2 = find_file_ref_id_for_name(plain)
        if fid2:
            # Patch that file reference block's path line to the Flutter/ path
            # Replace `path = Debug.xcconfig;` with `path = Flutter/Debug.xcconfig;`
            text_before = text
            text = re.sub(
                rf"({fid2} /\* {re.escape(plain)} \*/ = \{{\s*isa = PBXFileReference;.*?\bpath = )[^;]+(;)",
                rf"\1{path}\2",
                text,
                flags=re.S
            )
            if text == text_before:
                # Maybe file ref has different comment; try a more general patch by id.
                text = re.sub(
                    rf"({fid2} /\* .*? \*/ = \{{\s*isa = PBXFileReference;.*?\bpath = )[^;]+(;)",
                    rf"\1{path}\2",
                    text,
                    flags=re.S
                )
            fid = fid2
    if not fid:
        raise SystemExit(f"ERROR: Nie znalazłem PBXFileReference dla {path}. Plik istnieje na dysku, ale nie ma referencji w project.pbxproj.")
    file_ref_id[cfg_name] = fid

# Patch XCBuildConfiguration blocks: set baseConfigurationReference for each Runner config
def set_base_config(cfg_id: str, file_ref: str):
    global text
    # Locate XCBuildConfiguration block by id
    block_re = re.compile(rf"{cfg_id} /\* .*? \*/ = \{{\s*isa = XCBuildConfiguration;.*?\}};", re.S)
    m = block_re.search(text)
    if not m:
        raise SystemExit(f"ERROR: Nie znalazłem XCBuildConfiguration dla id {cfg_id}")
    block = m.group(0)

    # Remove existing baseConfigurationReference if present
    block2 = re.sub(r"\s*baseConfigurationReference = [A-F0-9]{24} /\* .*? \*/;\n", "", block)

    # Insert baseConfigurationReference near top (after isa line)
    insert = f"\t\t\tbaseConfigurationReference = {file_ref} /* {desired_name_map[cfg_name].split('/')[-1]} */;\n"
    block2 = re.sub(r"(isa = XCBuildConfiguration;\n)", r"\1" + insert, block2, count=1)

    # Replace original block
    text = text[:m.start()] + block2 + text[m.end():]

desired_name_map = desired  # alias

for cfg_name in ["Debug", "Release", "Profile"]:
    cfg_id = cfg_id_by_name.get(cfg_name)
    if not cfg_id:
        raise SystemExit(f"ERROR: Runner nie ma konfiguracji {cfg_name} w XCConfigurationList.")
    set_base_config(cfg_id, file_ref_id[cfg_name])

pbx_path.write_text(text, encoding="utf-8")
print("OK: Patched Runner target base configurations (Debug/Release/Profile) to Flutter/*.xcconfig")
PY

echo ""
echo "Teraz odpal:"
echo "  cd ios && pod install && cd .."
echo "  flutter build ios --release"

