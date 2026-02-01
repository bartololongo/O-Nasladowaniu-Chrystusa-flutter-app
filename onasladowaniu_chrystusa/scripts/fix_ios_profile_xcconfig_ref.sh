#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
PBX="$ROOT/ios/Runner.xcodeproj/project.pbxproj"
PROFILE_FILE="$ROOT/ios/Flutter/Profile.xcconfig"

if [[ ! -f "$PBX" ]]; then
  echo "ERROR: Nie widzę $PBX. Odpal z root projektu (tam gdzie pubspec.yaml)."
  exit 1
fi

mkdir -p "$ROOT/ios/Flutter"
if [[ ! -f "$PROFILE_FILE" ]]; then
  cat > "$PROFILE_FILE" <<'EOF'
#include "Pods/Target Support Files/Pods-Runner/Pods-Runner.profile.xcconfig"
#include "Generated.xcconfig"
EOF
  echo "Created: ios/Flutter/Profile.xcconfig"
fi

TS="$(date +"%Y%m%d_%H%M%S")"
cp -p "$PBX" "$PBX.bak.$TS"
echo "Backup: $PBX.bak.$TS"

python3 - <<'PY'
import re
import os
import random
from pathlib import Path

pbx_path = Path("ios/Runner.xcodeproj/project.pbxproj")
text = pbx_path.read_text(encoding="utf-8")

def gen_id(existing: set[str]) -> str:
    # 24-hex uppercase, like Xcode IDs
    while True:
        s = "".join(random.choice("0123456789ABCDEF") for _ in range(24))
        if s not in existing:
            return s

existing_ids = set(re.findall(r"\b[A-F0-9]{24}\b", text))

# ---- 1) Ensure PBXFileReference exists for Flutter/Profile.xcconfig ----

def find_file_ref_by_path(path: str):
    m = re.search(rf"([A-F0-9]{{24}}) /\* .*? \*/ = \{{\s*isa = PBXFileReference;.*?\bpath = {re.escape(path)};.*?lastKnownFileType = text\.xcconfig;.*?\}};", text, re.S)
    return m.group(1) if m else None

profile_path = "Flutter/Profile.xcconfig"
profile_ref_id = find_file_ref_by_path(profile_path)

# Find Flutter group ID (PBXGroup /* Flutter */)
flutter_group_id = None
m = re.search(r"([A-F0-9]{24}) /\* Flutter \*/ = \{\s*isa = PBXGroup;.*?\bchildren = \(\s*(.*?)\s*\);\s*path = Flutter;\s*sourceTree = \"<group>\";\s*\};", text, re.S)
if m:
    flutter_group_id = m.group(1)
    flutter_children_block = m.group(2)
else:
    # Sometimes group is named differently; fallback: group with path = Flutter
    m2 = re.search(r"([A-F0-9]{24}) /\* .*? \*/ = \{\s*isa = PBXGroup;.*?\bchildren = \(\s*(.*?)\s*\);\s*path = Flutter;\s*sourceTree = \"<group>\";\s*\};", text, re.S)
    if m2:
        flutter_group_id = m2.group(1)
        flutter_children_block = m2.group(2)

if not flutter_group_id:
    raise SystemExit("ERROR: Nie znalazłem PBXGroup dla katalogu Flutter w project.pbxproj.")

def insert_into_pbxfilereference_section(new_entry: str):
    global text
    anchor = "/* Begin PBXFileReference section */"
    idx = text.find(anchor)
    if idx == -1:
        raise SystemExit("ERROR: Brak sekcji PBXFileReference w project.pbxproj.")
    # Insert right after anchor line
    insert_pos = text.find("\n", idx) + 1
    text = text[:insert_pos] + new_entry + text[insert_pos:]

def ensure_child_in_flutter_group(file_ref_id: str, comment: str):
    global text
    # Re-find group block to patch safely
    pattern = re.compile(rf"({flutter_group_id} /\* .*? \*/ = \{{\s*isa = PBXGroup;.*?\bchildren = \(\s*)(.*?)(\s*\);\s*path = Flutter;\s*sourceTree = \"<group>\";\s*\}};)", re.S)
    m = pattern.search(text)
    if not m:
        raise SystemExit("ERROR: Nie mogę zlokalizować bloku PBXGroup Flutter do edycji.")
    prefix, children, suffix = m.group(1), m.group(2), m.group(3)

    if re.search(rf"\b{re.escape(file_ref_id)}\b", children):
        return  # already in children

    # Add as last child with proper indentation
    new_children = children
    if not new_children.strip().endswith(",") and new_children.strip():
        # children lines already have commas; keep style safe by appending with comma
        pass
    new_children = new_children.rstrip() + f"\n\t\t\t\t{file_ref_id} /* {comment} */,"
    text = text[:m.start()] + prefix + new_children + suffix + text[m.end():]

if not profile_ref_id:
    profile_ref_id = gen_id(existing_ids)
    existing_ids.add(profile_ref_id)

    entry = (
        f"\t\t{profile_ref_id} /* Profile.xcconfig */ = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; "
        f"name = Profile.xcconfig; path = {profile_path}; sourceTree = \"<group>\"; }};\n"
    )
    insert_into_pbxfilereference_section(entry)
    ensure_child_in_flutter_group(profile_ref_id, "Profile.xcconfig")
    print("OK: Added PBXFileReference for Flutter/Profile.xcconfig and attached to Flutter group")
else:
    print("OK: PBXFileReference for Flutter/Profile.xcconfig already exists")

# ---- 2) Patch Runner target base configurations to Flutter/*.xcconfig ----

def find_runner_target_id():
    m = re.search(r"([A-F0-9]{24}) /\* Runner \*/ = \{\s*isa = PBXNativeTarget;.*?\bname = Runner;\b.*?\};", text, re.S)
    return m.group(1) if m else None

runner_target_id = find_runner_target_id()
if not runner_target_id:
    raise SystemExit("ERROR: Nie znalazłem PBXNativeTarget o nazwie Runner.")

m = re.search(rf"{runner_target_id} /\* Runner \*/ = \{{.*?buildConfigurationList = ([A-F0-9]{{24}}) /\* Build configuration list for PBXNativeTarget \"Runner\" \*/;.*?\}};", text, re.S)
if not m:
    raise SystemExit("ERROR: Nie mogę znaleźć buildConfigurationList dla targetu Runner.")
cfg_list_id = m.group(1)

m = re.search(rf"{cfg_list_id} /\* Build configuration list for PBXNativeTarget \"Runner\" \*/ = \{{.*?buildConfigurations = \(\s*(.*?)\s*\);\s*defaultConfigurationIsVisible", text, re.S)
if not m:
    raise SystemExit("ERROR: Nie mogę znaleźć XCConfigurationList dla Runnera.")
cfg_ids_block = m.group(1)
cfg_ids = dict(re.findall(r"([A-F0-9]{24}) /\* (Debug|Release|Profile) \*/", cfg_ids_block))
if not cfg_ids:
    raise SystemExit("ERROR: Runner nie ma Debug/Release/Profile w XCConfigurationList.")

def find_ref_id(path: str) -> str:
    mm = re.search(rf"([A-F0-9]{{24}}) /\* .*? \*/ = \{{\s*isa = PBXFileReference;.*?\bpath = {re.escape(path)};.*?lastKnownFileType = text\.xcconfig;.*?\}};", text, re.S)
    return mm.group(1) if mm else ""

# Debug/Release refs should already exist; find by path
debug_ref = find_ref_id("Flutter/Debug.xcconfig")
release_ref = find_ref_id("Flutter/Release.xcconfig")
profile_ref = profile_ref_id  # we ensured above

if not debug_ref or not release_ref:
    raise SystemExit("ERROR: Nie znalazłem PBXFileReference dla Flutter/Debug.xcconfig lub Flutter/Release.xcconfig.")

desired = {
    "Debug":  (cfg_ids.get("Debug"),  debug_ref,  "Debug.xcconfig"),
    "Release":(cfg_ids.get("Release"),release_ref,"Release.xcconfig"),
    "Profile":(cfg_ids.get("Profile"),profile_ref,"Profile.xcconfig"),
}

def set_base_config(cfg_id: str, file_ref: str, comment: str):
    global text
    # Find XCBuildConfiguration block by id
    block_re = re.compile(rf"{cfg_id} /\* .*? \*/ = \{{\s*isa = XCBuildConfiguration;.*?\}};", re.S)
    m = block_re.search(text)
    if not m:
        raise SystemExit(f"ERROR: Nie znalazłem XCBuildConfiguration dla id {cfg_id}")
    block = m.group(0)

    # Remove existing baseConfigurationReference line if present
    block2 = re.sub(r"\s*baseConfigurationReference = [A-F0-9]{24} /\* .*? \*/;\n", "", block)

    insert_line = f"\t\t\tbaseConfigurationReference = {file_ref} /* {comment} */;\n"
    if "isa = XCBuildConfiguration;" not in block2:
        raise SystemExit("ERROR: Nieoczekiwany format XCBuildConfiguration.")
    block2 = block2.replace("isa = XCBuildConfiguration;\n", "isa = XCBuildConfiguration;\n" + insert_line, 1)

    text = text[:m.start()] + block2 + text[m.end():]

for name, (cfg_id, ref_id, comment) in desired.items():
    if not cfg_id:
        raise SystemExit(f"ERROR: Brak konfiguracji {name} dla Runnera.")
    set_base_config(cfg_id, ref_id, comment)

pbx_path.write_text(text, encoding="utf-8")
print("OK: Patched Runner target baseConfigurationReference for Debug/Release/Profile to Flutter/*.xcconfig")
PY

echo ""
echo "Teraz odpal:"
echo "  cd ios && pod install && cd .."
echo "  flutter build ios --release"

