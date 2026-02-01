#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
PBX="$ROOT/ios/Runner.xcodeproj/project.pbxproj"
PROFILE_FILE="$ROOT/ios/Flutter/Profile.xcconfig"

if [[ ! -f "$PBX" ]]; then
  echo "ERROR: Nie widzę $PBX. Odpal z root projektu (tam gdzie pubspec.yaml)."
  exit 1
fi

# Ensure Profile.xcconfig exists and includes Pods + Generated
mkdir -p "$ROOT/ios/Flutter"
if [[ ! -f "$PROFILE_FILE" ]]; then
  cat > "$PROFILE_FILE" <<'EOF'
#include "Pods/Target Support Files/Pods-Runner/Pods-Runner.profile.xcconfig"
#include "Generated.xcconfig"
EOF
else
  if ! grep -q 'Pods-Runner.profile.xcconfig' "$PROFILE_FILE"; then
    tmp="$(mktemp)"
    { echo '#include "Pods/Target Support Files/Pods-Runner/Pods-Runner.profile.xcconfig"'; cat "$PROFILE_FILE"; } > "$tmp"
    mv "$tmp" "$PROFILE_FILE"
  fi
  if ! grep -q 'Generated.xcconfig' "$PROFILE_FILE"; then
    echo '#include "Generated.xcconfig"' >> "$PROFILE_FILE"
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

# ---- Find the application target "Runner" robustly ----
targets = []
for m in re.finditer(r"([A-F0-9]{24}) /\* (.*?) \*/ = \{\s*isa = PBXNativeTarget;.*?\};", text, re.S):
    tid = m.group(1)
    block = m.group(0)
    name_m = re.search(r"\bname = ([^;]+);", block)
    prodtype_m = re.search(r"\bproductType = ([^;]+);", block)
    bcl_m = re.search(r"\bbuildConfigurationList = ([A-F0-9]{24}) /\* .*? \*/;", block)
    name = (name_m.group(1).strip().strip('"') if name_m else "")
    productType = (prodtype_m.group(1).strip().strip('"') if prodtype_m else "")
    bcl = (bcl_m.group(1) if bcl_m else "")
    targets.append((tid, name, productType, bcl))

app_targets = [t for t in targets if "com.apple.product-type.application" in t[2]]
if not app_targets:
    raise SystemExit("ERROR: Nie znalazłem targetu aplikacyjnego (productType application).")

runner = None
for t in app_targets:
    if t[1] == "Runner":
        runner = t
        break
if not runner:
    runner = app_targets[0]

target_id, target_name, product_type, cfg_list_id = runner
print(f"Chosen target: name='{target_name}', productType='{product_type}'")

if not cfg_list_id:
    raise SystemExit("ERROR: Wybrany target nie ma buildConfigurationList.")

# ---- Get all config IDs from the target's XCConfigurationList ----
m = re.search(
    rf"{cfg_list_id} /\* .*? \*/ = \{{\s*isa = XCConfigurationList;.*?\bbuildConfigurations = \(\s*(.*?)\s*\);\s*defaultConfigurationIsVisible",
    text, re.S
)
if not m:
    raise SystemExit("ERROR: Nie mogę znaleźć XCConfigurationList dla wybranego targetu.")
cfg_block = m.group(1)

cfg_ids = re.findall(r"\b([A-F0-9]{24})\b", cfg_block)
cfg_ids = list(dict.fromkeys(cfg_ids))  # unique preserve order
if not cfg_ids:
    raise SystemExit("ERROR: Nie znalazłem żadnych ID konfiguracji w buildConfigurations.")

def cfg_name(cfg_id: str) -> str:
    mm = re.search(rf"{cfg_id} /\* .*? \*/ = \{{\s*isa = XCBuildConfiguration;.*?\bname = ([^;]+);.*?\}};", text, re.S)
    if not mm:
        return ""
    return mm.group(1).strip().strip('"')

cfgs = [(cid, cfg_name(cid)) for cid in cfg_ids]
print("Found configurations for target:")
for cid, name in cfgs:
    print(f" - {name} ({cid})")

# ---- Map to debug/release/profile by name heuristics ----
def pick(predicate):
    for cid, name in cfgs:
        if predicate(name.lower()):
            return cid
    return None

debug_id = pick(lambda n: "debug" in n)
release_id = pick(lambda n: "release" in n)
profile_id = pick(lambda n: "profile" in n)

if not debug_id or not release_id or not profile_id:
    raise SystemExit(
        "ERROR: Nie mogę jednoznacznie dopasować Debug/Release/Profile po nazwach. "
        "Upewnij się, że w konfiguracjach są słowa 'Debug', 'Release', 'Profile' (case-insensitive)."
    )

# Ensure PBXFileReferences exist for Flutter xcconfigs
debug_ref   = ensure_pbxfileref("Flutter/Debug.xcconfig",   "Debug.xcconfig")
release_ref = ensure_pbxfileref("Flutter/Release.xcconfig", "Release.xcconfig")
profile_ref = ensure_pbxfileref("Flutter/Profile.xcconfig", "Profile.xcconfig")

def set_base_config(cfg_id: str, file_ref: str, comment: str):
    global text
    block_re = re.compile(rf"{cfg_id} /\* .*? \*/ = \{{\s*isa = XCBuildConfiguration;.*?\}};", re.S)
    mm = block_re.search(text)
    if not mm:
        raise SystemExit(f"ERROR: Nie znalazłem XCBuildConfiguration dla id {cfg_id}")
    block = mm.group(0)

    block2 = re.sub(r"\s*baseConfigurationReference = [A-F0-9]{24} /\* .*? \*/;\n", "", block)
    insert_line = f"\t\t\tbaseConfigurationReference = {file_ref} /* {comment} */;\n"
    block2 = block2.replace("isa = XCBuildConfiguration;\n", "isa = XCBuildConfiguration;\n" + insert_line, 1)

    text = text[:mm.start()] + block2 + text[mm.end():]

set_base_config(debug_id,   debug_ref,   "Debug.xcconfig")
set_base_config(release_id, release_ref, "Release.xcconfig")
set_base_config(profile_id, profile_ref, "Profile.xcconfig")

pbx_path.write_text(text, encoding="utf-8")
print("OK: Patched baseConfigurationReference for Debug/Release/Profile to Flutter/*.xcconfig")
PY

echo ""
echo "Teraz odpal:"
echo "  cd ios && pod install && cd .."
echo "  flutter build ios --release"

