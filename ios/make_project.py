#!/usr/bin/env python3
"""Writes ios/asmmesh.xcodeproj/project.pbxproj for the iPhone app.

The app shares the Mac's assembly core (../src/*.s, listed in CORE below) and adds
ios/asm/ios_ui.s plus the SwiftUI files in ios/asmmesh/. Run it again after adding
a file:  python3 ios/make_project.py
"""
import hashlib, os

HERE = os.path.dirname(os.path.abspath(__file__))

CORE = """mesh ident crypto util ble near home parse rules net hue st cloud lan udp weather
extras find sens_decode sensors spin spinui alerts voice services handoff bt limits guard web fm_html fm_pack fm_util fm_io files scan_core listed seek
bc_crypto bc_link bc_ble bc_packet bc_zlib bc_peer""".split()
SWIFT = ["App.swift", "Bridge.swift", "Mesh.swift", "RoomsView.swift", "PeopleView.swift",
         "NearbyView.swift", "SettingsView.swift", "SpinView.swift", "FindView.swift"]
FRAMEWORKS = ["CoreBluetooth", "Security", "CoreLocation", "Speech", "AVFoundation", "NearbyInteraction"]
BUNDLE_ID = "com.fbackman.asmmesh.ios"


def oid(*parts):
    return hashlib.md5("/".join(parts).encode()).hexdigest()[:24].upper()


objs = {}          # id -> text


def add(i, text):
    objs[i] = text


refs = []          # (fileref id, buildfile id, phase)

# --- file references ---
for f in SWIFT:
    fr, bf = oid("ref", f), oid("bf", f)
    add(fr, f'{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {f}; sourceTree = "<group>"; }}')
    add(bf, f'{{isa = PBXBuildFile; fileRef = {fr} /* {f} */; }}')
    refs.append((fr, bf, "src"))
iosui_fr, iosui_bf = oid("ref", "ios_ui.s"), oid("bf", "ios_ui.s")
add(iosui_fr, '{isa = PBXFileReference; lastKnownFileType = sourcecode.asm; path = ios_ui.s; sourceTree = "<group>"; }')
add(iosui_bf, f'{{isa = PBXBuildFile; fileRef = {iosui_fr} /* ios_ui.s */; }}')
core_refs = []
for c in CORE:
    f = c + ".s"
    fr, bf = oid("ref", "core", f), oid("bf", "core", f)
    add(fr, f'{{isa = PBXFileReference; lastKnownFileType = sourcecode.asm; path = {f}; sourceTree = "<group>"; }}')
    add(bf, f'{{isa = PBXBuildFile; fileRef = {fr} /* {f} */; }}')
    core_refs.append((fr, bf))
macros_fr = oid("ref", "core", "macros.inc")
add(macros_fr, '{isa = PBXFileReference; lastKnownFileType = text; path = macros.inc; sourceTree = "<group>"; }')
plist_fr = oid("ref", "Info.plist")
add(plist_fr, '{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }')
hdr_fr = oid("ref", "bridging")
add(hdr_fr, '{isa = PBXFileReference; lastKnownFileType = sourcecode.c.h; path = "asmmesh-Bridging-Header.h"; sourceTree = "<group>"; }')
assets_fr, assets_bf = oid("ref", "assets"), oid("bf", "assets")
add(assets_fr, '{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; }')
add(assets_bf, f'{{isa = PBXBuildFile; fileRef = {assets_fr} /* Assets.xcassets */; }}')
fw_refs = []
for fw in FRAMEWORKS:
    fr, bf = oid("ref", "fw", fw), oid("bf", "fw", fw)
    add(fr, f'{{isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = {fw}.framework; path = System/Library/Frameworks/{fw}.framework; sourceTree = SDKROOT; }}')
    add(bf, f'{{isa = PBXBuildFile; fileRef = {fr} /* {fw}.framework */; }}')
    fw_refs.append((fr, bf))
app_fr = oid("ref", "product")
add(app_fr, '{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = asmmesh.app; sourceTree = BUILT_PRODUCTS_DIR; }')

# --- groups ---
g_app, g_asm, g_core, g_fw, g_prod, g_main = (oid("group", n) for n in ("app", "asm", "core", "fw", "prod", "main"))
kids = lambda ids: "(" + "".join(f"{i}, " for i in ids) + ")"
add(g_app, f'{{isa = PBXGroup; children = {kids([r[0] for r in refs] + [hdr_fr, plist_fr, assets_fr])}; path = asmmesh; sourceTree = "<group>"; }}')
add(g_asm, f'{{isa = PBXGroup; children = {kids([iosui_fr])}; path = asm; sourceTree = "<group>"; }}')
add(g_core, f'{{isa = PBXGroup; children = {kids([macros_fr] + [r[0] for r in core_refs])}; name = "core (shared with the Mac)"; path = ../src; sourceTree = "<group>"; }}')
add(g_fw, f'{{isa = PBXGroup; children = {kids([r[0] for r in fw_refs])}; name = Frameworks; sourceTree = "<group>"; }}')
add(g_prod, f'{{isa = PBXGroup; children = {kids([app_fr])}; name = Products; sourceTree = "<group>"; }}')
add(g_main, f'{{isa = PBXGroup; children = {kids([g_app, g_asm, g_core, g_fw, g_prod])}; sourceTree = "<group>"; }}')

# --- build phases ---
ph_src, ph_fw, ph_res = oid("phase", "src"), oid("phase", "fw"), oid("phase", "res")
add(ph_src, f'{{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {kids([r[1] for r in refs] + [iosui_bf] + [r[1] for r in core_refs])}; runOnlyForDeploymentPostprocessing = 0; }}')
add(ph_fw, f'{{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = {kids([r[1] for r in fw_refs])}; runOnlyForDeploymentPostprocessing = 0; }}')
add(ph_res, f'{{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {kids([assets_bf])}; runOnlyForDeploymentPostprocessing = 0; }}')

# --- configurations ---
def settings(d):
    return "{" + "".join(f"{k} = {v}; " for k, v in d.items()) + "}"

proj_common = {
    "ALWAYS_SEARCH_USER_PATHS": "NO", "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "SDKROOT": "iphoneos", "SWIFT_VERSION": "5.0",
    "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
}
cfg_pd, cfg_pr = oid("cfg", "proj", "debug"), oid("cfg", "proj", "release")
add(cfg_pd, '{isa = XCBuildConfiguration; buildSettings = ' + settings({**proj_common, "DEBUG_INFORMATION_FORMAT": "dwarf", "ONLY_ACTIVE_ARCH": "YES", "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"', "GCC_OPTIMIZATION_LEVEL": "0", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG"}) + '; name = Debug; }')
add(cfg_pr, '{isa = XCBuildConfiguration; buildSettings = ' + settings({**proj_common, "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"', "SWIFT_COMPILATION_MODE": "wholemodule", "VALIDATE_PRODUCT": "YES"}) + '; name = Release; }')
target_common = {
    "PRODUCT_NAME": '"$(TARGET_NAME)"', "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
    "INFOPLIST_FILE": "asmmesh/Info.plist", "GENERATE_INFOPLIST_FILE": "NO",
    "SWIFT_OBJC_BRIDGING_HEADER": '"asmmesh/asmmesh-Bridging-Header.h"',
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "CODE_SIGN_STYLE": "Automatic", "DEVELOPMENT_TEAM": '""',
    "TARGETED_DEVICE_FAMILY": '"1,2"', "SUPPORTS_MACCATALYST": "NO",
    "HEADER_SEARCH_PATHS": '"$(SRCROOT)/../src"', "OTHER_CFLAGS": '"-I$(SRCROOT)/../src"',
    "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks"',
    "ENABLE_PREVIEWS": "NO", "OTHER_LDFLAGS": '"-lz"', "CURRENT_PROJECT_VERSION": "1", "MARKETING_VERSION": "0.8",
}
cfg_td, cfg_tr = oid("cfg", "target", "debug"), oid("cfg", "target", "release")
add(cfg_td, '{isa = XCBuildConfiguration; buildSettings = ' + settings(target_common) + '; name = Debug; }')
add(cfg_tr, '{isa = XCBuildConfiguration; buildSettings = ' + settings(target_common) + '; name = Release; }')
list_p, list_t = oid("list", "proj"), oid("list", "target")
add(list_p, f'{{isa = XCConfigurationList; buildConfigurations = ({cfg_pd}, {cfg_pr}, ); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }}')
add(list_t, f'{{isa = XCConfigurationList; buildConfigurations = ({cfg_td}, {cfg_tr}, ); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }}')

target, project = oid("target"), oid("project")
add(target, f'{{isa = PBXNativeTarget; buildConfigurationList = {list_t}; buildPhases = ({ph_src}, {ph_fw}, {ph_res}, ); buildRules = (); dependencies = (); name = asmmesh; productName = asmmesh; productReference = {app_fr}; productType = "com.apple.product-type.application"; }}')
add(project, f'{{isa = PBXProject; attributes = {{BuildIndependentTargetsInParallel = 1; LastSwiftUpdateCheck = 1600; LastUpgradeCheck = 1600; TargetAttributes = {{{target} = {{CreatedOnToolsVersion = 16.0; }}; }}; }}; buildConfigurationList = {list_p}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base, ); mainGroup = {g_main}; productRefGroup = {g_prod}; projectDirPath = ""; projectRoot = ""; targets = ({target}, ); }}')

out = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {", "\t};", "\tobjectVersion = 56;", "\tobjects = {"]
for k in sorted(objs):
    out.append(f"\t\t{k} = {objs[k]};")
out += ["\t};", f"\trootObject = {project};", "}", ""]
d = os.path.join(HERE, "asmmesh.xcodeproj")
os.makedirs(d, exist_ok=True)
open(os.path.join(d, "project.pbxproj"), "w").write("\n".join(out))
print("wrote", os.path.join(d, "project.pbxproj"), len(objs), "objects")
