#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
PBX="$ROOT/ios/Runner.xcodeproj/project.pbxproj"
PROFILE_FILE="$ROOT/ios/Flutter/Profile.xcconfig"

if [[ ! -f "$PBX" ]]; then
  echo "ERROR: Nie widzę $PBX. Odpal z root projektu (tam gdzie pubspec.yaml)."
  exit 1
fi

# Ensure Profile.xcconfig exists with proper includes
mkdir -p "$ROOT/ios/Flutter"
if [[ ! -f "$PROFILE_FILE" ]]; then
  cat > "$PROFILE_FILE" <<'EOF'
#include "Pods/Target Support Files/Pods-Runner/Pods-Runner.profile.xcconfig"
#include "Generated.xcconfig"
EOF
  echo "Created: ios/Flutter/Profile.xcconfig"
else
  # idempotent safety
  if ! grep -q 'Pods-Runner.profile.xcconfig' "$PROFILE_FILE"; then
    tmp="$(mktemp)"
    {
      echo '#include "Pods/Target Support Files/Pods-Runner/Pods-Runner.profile.xcconfig"'
      cat "$PROFILE_FILE"
    } > "$tmp"
    mv "$tmp" "$PROFILE_FILE"
    echo "Patched: Profile.xcconfig (added Pods include)"
  fi
  if ! grep -q 'Generated.xcconfig' "$PROFILE_FILE"; then
    echo '#include "Generated.xcconfig"' >> "$PROFILE_FILE"
    echo "Patched: Profile.xcconfig (added Generated include)"
  fi
fi

TS="$(date +"%Y%m%d_%H%M%S")"
cp -p "$PBX" "$PBX.bak.$TS"
echo "Backup: $PBX.bak.$TS"

python3 - <<'PY'
import re, random
from pathlib import Path

pbx_path = Path("ios/Runner.xcodeproj/project.pbxproj")
text = pbx_path.read_text(encoding="utf-8")

existing_ids = set(re.findall(r"\b[A-F0-9]{24}\b", text))

def gen_id():
    while True:
        s = "".join(random.choice("0123456789ABCDEF") for _ in range(24))
        if s not in existing_ids:
            existing_ids.add(s)
            return s

def ensure_pbxfileref(path: str, name: str) -> str:
    global text
    # already exists by path?
    m = re.search(
        rf"([A-F0-9]{{24}}) /\* .*? \*/ = \{{\s*isa = PBXFileReference;.*?\bpath = {re.escape(path)};.*?lastKnownFileType = text\.xcconfig;.*?\}};",
        text, re.S
    )
    if m:
        return m.group(1)

    # Insert into PBXFileReference section
    begin = text.find("/* Begin PBXFileReference section */")
    end = text.find("/* End PBXFileReference section */")
    if begin == -1 or end == -1 or end < begin:
        raise SystemExit("ERROR: Nie znalazłem sekcji PBXFileReference w project.pbxproj")

    insert_pos = text.find("\n", begin) + 1
    new_id = gen_id()
    entry = (
        f"\t\t{new_id} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; "
        f"name = {name}; path = {path}; sourceTree = \"<group>\"; }};\n"
    )
    text = text[:insert_pos] + entry + text[insert_pos:]
    return new_id

# Ensure file references exist for all three
debug_ref   = ensure_pbxfileref("Flutter/Debug.xcconfig",   "Debug.xcconfig")
release_ref = ensure_pbxfileref("Flutter/Release.xcconfig", "Release.xcconfig")
profile_ref = ensure_pbxfileref("Flutter/Profile.xcconfig", "Profile.xcconfig")

# Find Runner target
m = re.search(r"([A-F0-9]{24}) /\* Runner \*/ = \{\s*isa = PBXNativeTarget;.*?\bname = Runner;\b.*?\};", text, re.S)
if not m:
    raise SystemExit("ERROR: Nie znalazłem PBXNativeTarget o nazwie Runner.")
runner_target_id = m.group(1)

# Find buildConfigurationList id for Runner target
m = re.search(
    rf"{runner_target_id} /\* Runner \*/ = \{{.*?buildConfigurationList = ([A-F0-9]{{24}}) /\* Build configuration list for PBXNativeTarget \"Runner\" \*/;.*?\}};",
    text, re.S
)
if not m:
    raise SystemExit("ERROR: Nie mogę znaleźć buildConfigurationList dla targetu Runner.")
cfg_list_id = m.group(1)

# Extract Debug/Release/Profile XCBuildConfiguration ids from the configuration list
m = re.search(
    rf"{cfg_list_id} /\* Build configuration list for PBXNativeTarget \"Runner\" \*/ = \{{.*?buildConfigurations = \(\s*(.*?)\s*\);\s*defaultConfigurationIsVisible",
    text, re.S
)
if not m:
    raise SystemExit("ERROR: Nie mogę znaleźć XCConfigurationList dla Runnera.")
cfg_ids_block = m.group(1)

cfg_ids = dict(re.findall(r"([A-F0-9]{24}) /\* (Debug|Release|Profile) \*/", cfg_ids_block))
if not cfg_ids:
    raise SystemExit("ERROR: Runner nie ma Debug/Release/Profile w XCConfigurationList.")

desired = {
    "Debug":   (cfg_ids.get("Debug"),   debug_ref,   "Debug.xcconfig"),
    "Release": (cfg_ids.get("Release"), release_ref, "Release.xcconfig"),
    "Profile": (cfg_ids.get("Profile"), profile_ref, "Profile.xcconfig"),
}

def set_base_config(cfg_id: str, file_ref: str, comment: str):
    global text
    block_re = re.compile(rf"{cfg_id} /\* .*? \*/ = \{{\s*isa = XCBuildConfiguration;.*?\}};", re.S)
    m = block_re.search(text)
    if not m:
        raise SystemExit(f"ERROR: Nie znalazłem XCBuildConfiguration dla id {cfg_id}")
    block = m.group(0)

    # remove existing baseConfigurationReference
    block2 = re.sub(r"\s*baseConfigurationReference = [A-F0-9]{24} /\* .*? \*/;\n", "", block)

    insert_line = f"\t\t\tbaseConfigurationReference = {file_ref} /* {comment} */;\n"
    block2 = block2.replace("isa = XCBuildConfiguration;\n", "isa = XCBuildConfiguration;\n" + insert_line, 1)

    text = text[:m.start()] + block2 + text[m.end():]

for name, (cfg_id, ref_id, comment) in desired.items():
    if not cfg_id:
        raise SystemExit(f"ERROR: Brak konfiguracji {name} dla Runnera.")
    set_base_config(cfg_id, ref_id, comment)

pbx_path.write_text(text, encoding="utf-8")
print("OK: Added missing PBXFileReference(s) and patched Runner baseConfigurationReference (Debug/Release/Profile) to Flutter/*.xcconfig")
PY

echo ""
echo "Teraz odpal:"
echo "  cd ios && pod install && cd .."
echo "  flutter build ios --release"

