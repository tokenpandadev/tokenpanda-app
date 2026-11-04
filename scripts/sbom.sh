#!/bin/sh
# SPDX-FileCopyrightText: 2026 tokenpanda
# SPDX-License-Identifier: MIT
# Writes the software bill of materials of a release as CycloneDX 1.6 JSON: build/tokenpanda-<version>.cdx.json.
# It reads the package from `swift package dump-package` (Package.swift) and Package.resolved when there is one,
# lists the app's own modules and the macOS frameworks it links, and records the zip's SHA-256 when the zip is built.
# Every third party package pinned in Package.resolved becomes a component; today there are none, and the file says so.
# No network. Run it after scripts/build-app.sh, which calls it.
#   scripts/sbom.sh [version]
set -eu
cd "$(dirname "$0")/.."
# the version given, else the one scripts/build-app.sh builds by default, so the two never disagree
VERSION="${1:-$(sed -n 's/^VERSION="\${1:-\([0-9][0-9.]*\)}"$/\1/p' scripts/build-app.sh)}"
[ -n "$VERSION" ] || { echo "sbom.sh: no version given and none found in scripts/build-app.sh" >&2; exit 2; }
BUILD="build"
OUT="$BUILD/tokenpanda-$VERSION.cdx.json"
mkdir -p "$BUILD"

DUMP="$(mktemp -t tokenpanda-sbom)"
trap 'rm -f "$DUMP"' EXIT
swift package dump-package > "$DUMP"

# the tag's commit when the version is tagged, else the current commit; its time is the SBOM's time, so a rerun gives the same file
if git rev-parse -q --verify "refs/tags/v$VERSION^{commit}" >/dev/null; then
  COMMIT="$(git rev-parse "v$VERSION^{commit}")"
else
  COMMIT="$(git rev-parse HEAD)"
fi
STAMP="$(TZ=UTC git log -1 --date=format-local:%Y-%m-%dT%H:%M:%SZ --format=%cd "$COMMIT")"
ZIP="$BUILD/tokenpanda-$VERSION.zip"
ZIPSHA=""
[ -f "$ZIP" ] && ZIPSHA="$(shasum -a 256 "$ZIP" | cut -d ' ' -f 1)"
RESOLVED=""
[ -f Package.resolved ] && RESOLVED="Package.resolved"
# the libraries the built binary links, read from the binary itself when build/ holds this version
LINKED="$(mktemp -t tokenpanda-sbom-linked)"
trap 'rm -f "$DUMP" "$LINKED"' EXIT
APPBIN="$BUILD/tokenpanda.app/Contents/MacOS/tokenpanda"
if [ -x "$APPBIN" ] && [ "$(defaults read "$PWD/$BUILD/tokenpanda.app/Contents/Info" CFBundleShortVersionString 2>/dev/null)" = "$VERSION" ]; then
  otool -L "$APPBIN" | tail -n +2 | sed -E 's/^[[:space:]]+//; s/ \(compatibility.*$//' > "$LINKED"
fi

python3 -I - "$DUMP" "$VERSION" "$COMMIT" "$STAMP" "$ZIPSHA" "$RESOLVED" "$OUT" "$LINKED" <<'PY'
import json, sys, uuid
dump, version, commit, stamp, zipsha, resolved, out, linked = sys.argv[1:9]
pkg = json.load(open(dump))
repo = "https://github.com/tokenpandadev/tokenpanda-app"
app_ref = "pkg:swift/github.com/tokenpandadev/tokenpanda-app@" + version
mit = [{"license": {"id": "MIT"}}]

# third party packages: declared in Package.swift, pinned in Package.resolved
declared = pkg.get("dependencies", [])
pins = []
if resolved:
    r = json.load(open(resolved))
    pins = r.get("pins") or r.get("object", {}).get("pins", [])
third = []
for p in pins:
    loc = p.get("location") or p.get("repositoryURL", "")
    st = p.get("state", {})
    ver = st.get("version") or st.get("revision", "")
    name = p.get("identity") or p.get("package", loc)
    host = loc.removeprefix("https://").removesuffix(".git")
    c = {"type": "library", "bom-ref": "pkg:swift/%s@%s" % (host, ver), "name": name, "version": ver,
         "purl": "pkg:swift/%s@%s" % (host, ver), "scope": "required",
         "externalReferences": [{"type": "vcs", "url": loc}]}
    if st.get("revision"):
        c["properties"] = [{"name": "swiftpm:revision", "value": st["revision"]}]
    third.append(c)
if declared and not pins:
    sys.exit("Package.swift declares dependencies but there is no Package.resolved; run swift package resolve first")

# the app's own modules, shipped inside the one binary; the test target is not shipped
targets = [t for t in pkg["targets"] if t.get("type") != "test"]
modules = []
for t in targets:
    if t["name"] == "tokenpanda":
        continue
    modules.append({"type": "library", "bom-ref": "tokenpanda-module:" + t["name"], "name": t["name"], "version": version,
                    "group": "tokenpanda", "licenses": mit, "scope": "required",
                    "description": "Module of tokenpanda, compiled into the app's one binary"})

# what the binary links: read from the built binary (otool -L) when build/ holds this version, else the frameworks Package.swift names.
# Everything must come from the operating system (/System or /usr/lib); anything else stops the script, since it would be shipped code.
paths = [l.strip() for l in open(linked) if l.strip()] if linked else []
if paths:
    source = "otool -L of the built binary"
    bad = [p for p in paths if not (p.startswith("/System/Library/") or p.startswith("/usr/lib/"))]
    if bad:
        sys.exit("the binary links libraries outside macOS, list them by hand: " + ", ".join(bad))
    def short(p):
        if ".framework/" in p:
            return p.split("/")[-1].split(".framework")[0] if p.endswith(".framework") else p.split(".framework/")[0].split("/")[-1]
        return p.split("/")[-1]
    names = sorted({short(p) for p in paths})
else:
    source = "the linkerSettings of Package.swift (no built binary of this version in build/)"
    names = sorted({s["kind"]["linkedFramework"]["_0"] for t in targets for s in t.get("settings", [])
                    if "linkedFramework" in s.get("kind", {})})
apple = [{"type": "framework" if not n.endswith(".dylib") else "library", "bom-ref": "macos:" + n, "name": n,
          "supplier": {"name": "Apple Inc."}, "scope": "required",
          "description": "Part of macOS, linked at run time, not shipped in the release zip",
          "properties": [{"name": "tokenpanda:shipped", "value": "false"}]} for n in names]
runtime = []

app = {"type": "application", "bom-ref": app_ref, "name": "tokenpanda", "version": version,
       "description": "macOS menu bar app that reads Claude Code's status line feed and the Mac's own figures",
       "licenses": mit, "purl": app_ref,
       "externalReferences": [{"type": "vcs", "url": repo + ".git"},
                              {"type": "distribution", "url": "%s/releases/tag/v%s" % (repo, version)},
                              {"type": "security-contact", "url": repo + "/security/advisories/new"}],
       "properties": [{"name": "git:commit", "value": commit},
                      {"name": "tokenpanda:third-party-packages", "value": str(len(third))},
                      {"name": "tokenpanda:system-libraries-from", "value": source}]}
if zipsha:
    app["hashes"] = [{"alg": "SHA-256", "content": zipsha}]
    app["properties"].append({"name": "tokenpanda:hashed-file", "value": "tokenpanda-%s.zip" % version})

note = ("No third party packages: Package.swift declares no dependencies and there is no Package.resolved. "
        "The release holds tokenpanda's own code only, built against macOS frameworks that are part of the operating system.") \
    if not third else ("%d third party package(s), as pinned in Package.resolved." % len(third))

components = modules + third + apple + runtime
bom = {
    "bomFormat": "CycloneDX", "specVersion": "1.6",
    "serialNumber": "urn:uuid:" + str(uuid.uuid5(uuid.NAMESPACE_URL, "%s/sbom/%s/%s" % (repo, version, commit))),
    "version": 1,
    "metadata": {"timestamp": stamp,
                 "tools": {"components": [{"type": "application", "name": "scripts/sbom.sh", "version": version}]},
                 "component": app,
                 "supplier": {"name": "tokenpanda", "url": ["https://tokenpanda.dev"]},
                 "licenses": mit},
    "components": components,
    "dependencies": [{"ref": app_ref, "dependsOn": [c["bom-ref"] for c in components]}] +
                    [{"ref": c["bom-ref"], "dependsOn": []} for c in components],
    "compositions": [{"aggregate": "complete", "assemblies": [app_ref],
                      "dependencies": [app_ref]}],
    "annotations": [{"subjects": [app_ref], "annotator": {"component": {"type": "application", "name": "scripts/sbom.sh"}},
                     "timestamp": stamp, "text": note}],
}
with open(out, "w") as f:
    json.dump(bom, f, indent=2)
    f.write("\n")
print("wrote %s: %d components, %d third party" % (out, len(components), len(third)))
PY
