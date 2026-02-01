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
    m = re.search(
        rf"([A-F0-9]{{24}}) /\* .*? \*/ = \{{\s*isa = PBXFileReference;.*?\bpath = {re.escape(path)};.*?lastKnownFileType = text\.xcconfig;.*?\}};",
        text, re.S
    )
    if m:
        return m.group(1)

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

# ---- Find the application target automatically ----
targets = []
for m in re.finditer(r"([A-F0-9]{24}) /\* (.*?) \*/ = \{\s*isa = PBXNativeTarget;.*?\};", text, re.S):
    tid = m.group(1)
    tcomment = m.group(2)
    block = m.group(0)
    name_m = re.search(r"\bname = ([^;]+);", block)
    prodtype_m = re.search(r"\bproductType = ([^;]+);", block)
    prodname_m = re.search(r"\bproductName = ([^;]+);", block)
    bcl_m = re.search(r"\bbuildConfigurationList = ([A-F0-9]{24}) /\* .*? \*/;", block)

    name = (name_m.group(1).strip().strip('"') if name_m else tcomment)
    productType = (prodtype_m.group(1).strip().strip('"') if prodtype_m else "")
    productName = (prodname_m.group(1).strip().strip('"') if prodname_m else "")
    bcl = (bcl_m.group(1) if bcl_m else "")

    targets.append({
        "id": tid,
        "comment": tcomment,
        "name": name,
        "productType": productType,
        "productName": productName,
        "bcl": bcl,
    })

if not targets:
    raise SystemExit("ERROR: Nie znalazłem żadnych PBXNativeTarget w project.pbxproj")

# Prefer: application target, not tests
app_targets = [t for t in targets if "com.apple.product-type.application" in t["productType"]]
if not app_targets:
    # fallback: first target that isn't tests
    app_targets = [t for t in targets if "Tests" not in t["name"] and "test" not in t["productType"].lower()]
if not app_targets:
    app_targets = targets[:]

# Prefer a target with name or productName containing Runner
chosen = None
for t in app_targets:
    if t["name"] == "Runner" or t["productName"] == "Runner":
        chosen = t
        break
if not chosen:
    for t in app_targets:
        if "Runner" in t["name"] or "Runner" in t["productName"]:
            chosen = t
            break
if not chosen:
    chosen = app_targets[0]

if not chosen["bcl"]:
    raise SystemExit(f"ERROR: Wybrany target '{chosen['name']}' nie ma buildConfigurationList w pbxproj.")

print(f"Chosen target: name='{chosen['name']}', productName='{chosen['productName']}', productType='{chosen['productType']}'")

cfg_list_id = chosen["bcl"]

# Extract config IDs (Debug/Release/Profile) from XCConfigurationList for this target
m = re.search(
    rf"{cfg_list_id} /\* .*? \*/ = \{{\s*isa = XCConfigurationList;.*?\bbuildConfigurations = \(\s*(.*?)\s*\);\s*defaultConfigurationIsVisible",
    text, re.S
)
if not m:
    raise SystemExit("ERROR: Nie mogę znaleźć XCConfigurationList dla wybranego targetu.")

cfg_ids_block = m.group(1)
cfg_ids = dict(re.findall(r"([A-F0-9]{24}) /\* (Debug|Release|Profile) \*/", cfg_ids_block))
if not cfg_ids:
    raise SystemExit("ERROR: Nie znalazłem konfiguracji Debug/Release/Profile w XCConfigurationList (może są nazwane inaczej).")

# Ensure PBXFileReference exists for Flutter xcconfigs
debug_ref   = ensure_pbxfileref("Flutter/Debug.xcconfig",   "Debug.xcconfig")
release_ref = ensure_pbxfileref("Flutter/Release.xcconfig", "Release.xcconfig")
profile_ref = ensure_pbxfileref("Flutter/Profile.xcconfig", "Profile.xcconfig")

desired = {
    "Debug":   (cfg_ids.get("Debug"),   debug_ref,   "Debug.xcconfig"),
    "Release": (cfg_ids.get("Release"), release_ref, "Release.xcconfig"),
    "Profile": (cfg_ids.get("Profile"), profile_ref, "Profile.xcconfig"),
}

def set_base_config(cfg_id: str, file_ref: str, comment: str):
    global text
    block_re = re.compile(rf"{cfg_id} /\* .*? \*/ = \{{\s*isa = XCBuildConfiguration;.*?\}};", re.S)
    mm = block_re.search(text)
    if not mm:
        raise SystemExit(f"ERROR: Nie znalazłem XCBuildConfiguration dla id {cfg_id}")
    block = mm.group(0)

    # remove existing baseConfigurationReference
    block2 = re.sub(r"\s*baseConfigurationReference = [A-F0-9]{24} /\* .*? \*/;\n", "", block)

    insert_line = f"\t\t\tbaseConfigurationReference = {file_ref} /* {comment} */;\n"
    block2 = block2.replace("isa = XCBuildConfiguration;\n", "isa = XCBuildConfiguration;\n" + insert_line, 1)

    text = text[:mm.start()] + block2 + text[mm.end():]

for name, (cfg_id, ref_id, comment) in desired.items():
    if not cfg_id:
        raise SystemExit(f"ERROR: Brak konfiguracji {name} w XCConfigurationList dla wybranego targetu.")
    set_base_config(cfg_id, ref_id, comment)

pbx_path.write_text(text, encoding="utf-8")
print("OK: Patched baseConfigurationReference for Debug/Release/Profile to Flutter/*.xcconfig")
PY

echo ""
echo "Teraz odpal:"
echo "  cd ios && pod install && cd .."
echo "  flutter build ios --release"

