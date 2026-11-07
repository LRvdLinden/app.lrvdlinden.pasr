#!/usr/bin/env python3
"""Writes PasrBeheer.xcodeproj (Xcode 16+ format, synchronized folder PasrBeheer/).

One multiplatform target: iPhone, iPad and native Mac (no Catalyst). Files added to PasrBeheer/ are picked up
automatically; run this again only when settings change (e.g. the build number below).
"""
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent
BUILD = "9"
VERSION = "1.0.0"


def oid(name):
    return hashlib.md5(("beheer." + name).encode()).hexdigest()[:24].upper()


def q(v):
    s = str(v)
    if s and all(c.isalnum() or c in "._/" for c in s) and not s[0].isdigit():
        return s
    return '"' + s.replace('"', '\\"') + '"'


def block(d, ind):
    out = []
    for k in sorted(d):
        v = d[k]
        if isinstance(v, list):
            inner = "".join(f"{ind}\t\t{q(x)},\n" for x in v)
            out.append(f"{ind}\t{q(k)} = (\n{inner}{ind}\t);")
        else:
            out.append(f"{ind}\t{q(k)} = {q(v)};")
    return "\n".join(out)


PROJECT = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "DEVELOPMENT_TEAM": "EU3UY476T6",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
    "MACOSX_DEPLOYMENT_TARGET": "14.0",
    "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
    "SWIFT_VERSION": "5.0",
}
DEBUG = {**PROJECT, "DEBUG_INFORMATION_FORMAT": "dwarf", "ENABLE_TESTABILITY": "YES", "GCC_OPTIMIZATION_LEVEL": "0",
         "ONLY_ACTIVE_ARCH": "YES", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)", "SWIFT_OPTIMIZATION_LEVEL": "-Onone"}
RELEASE = {**PROJECT, "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym", "ENABLE_NS_ASSERTIONS": "NO",
           "SWIFT_COMPILATION_MODE": "wholemodule", "VALIDATE_PRODUCT": "YES"}
APP = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_ENTITLEMENTS": "Config/PasrBeheer-iOS.entitlements",
    "CODE_SIGN_ENTITLEMENTS[sdk=macosx*]": "Config/PasrBeheer-macOS.entitlements",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": BUILD,
    "ENABLE_HARDENED_RUNTIME[sdk=macosx*]": "YES",
    "ENABLE_PREVIEWS": "YES",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_FILE": "Config/Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName": "PasrBeheer",
    "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.business",
    "INFOPLIST_KEY_NSFaceIDUsageDescription": "PasrBeheer gebruikt Face ID om het beheer af te schermen.",
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation[sdk=iphone*]": "YES",
    "INFOPLIST_KEY_UILaunchScreen_Generation[sdk=iphone*]": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
    "INFOPLIST_KEY_UIUserInterfaceStyle": "Dark",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
    "LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]": ["$(inherited)", "@executable_path/../Frameworks"],
    "MARKETING_VERSION": VERSION,
    "PRODUCT_BUNDLE_IDENTIFIER": "nl.lrvdlinden.pasr.beheer",
    "PRODUCT_NAME": "PasrBeheer",
    "SDKROOT": "auto",
    "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator macosx",
    "SUPPORTS_MACCATALYST": "NO",
    "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "SWIFT_EMIT_LOC_STRINGS": "NO",
    "TARGETED_DEVICE_FAMILY": "1,2",
}


def build():
    I = {k: oid(k) for k in ["project", "main", "products", "group", "config", "product", "target", "sources",
                              "frameworks", "resources", "cl.project", "cl.target", "pd", "pr", "td", "tr",
                              "f.info", "f.ios", "f.mac"]}

    def phase(isa, key):
        return f"\t\t{I[key]} = {{\n\t\t\tisa = {isa};\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n"

    def cfg(key, name, d):
        return f"\t\t{I[key]} /* {name} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{\n{block(d, chr(9) * 3)}\n\t\t\t}};\n\t\t\tname = {name};\n\t\t}};\n"

    def cl(key, d, r, comment):
        return (f"\t\t{I[key]} /* {comment} */ = {{\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n"
                f"\t\t\t\t{I[d]} /* Debug */,\n\t\t\t\t{I[r]} /* Release */,\n\t\t\t);\n"
                f"\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t}};\n")

    return f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 77;
\tobjects = {{

/* Begin PBXFileReference section */
\t\t{I['product']} /* PasrBeheer.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "PasrBeheer.app"; sourceTree = BUILT_PRODUCTS_DIR; }};
\t\t{I['f.info']} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};
\t\t{I['f.ios']} /* PasrBeheer-iOS.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = "PasrBeheer-iOS.entitlements"; sourceTree = "<group>"; }};
\t\t{I['f.mac']} /* PasrBeheer-macOS.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = "PasrBeheer-macOS.entitlements"; sourceTree = "<group>"; }};
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
\t\t{I['group']} /* PasrBeheer */ = {{
\t\t\tisa = PBXFileSystemSynchronizedRootGroup;
\t\t\tpath = PasrBeheer;
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
{phase('PBXFrameworksBuildPhase', 'frameworks')}/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{I['main']} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{I['group']} /* PasrBeheer */,
\t\t\t\t{I['config']} /* Config */,
\t\t\t\t{I['products']} /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{I['config']} /* Config */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{I['f.info']} /* Info.plist */,
\t\t\t\t{I['f.ios']} /* PasrBeheer-iOS.entitlements */,
\t\t\t\t{I['f.mac']} /* PasrBeheer-macOS.entitlements */,
\t\t\t);
\t\t\tpath = Config;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{I['products']} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{I['product']} /* PasrBeheer.app */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{I['target']} /* PasrBeheer */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {I['cl.target']} /* Build configuration list for PBXNativeTarget "PasrBeheer" */;
\t\t\tbuildPhases = (
\t\t\t\t{I['sources']} /* Sources */,
\t\t\t\t{I['frameworks']} /* Frameworks */,
\t\t\t\t{I['resources']} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tfileSystemSynchronizedGroups = (
\t\t\t\t{I['group']} /* PasrBeheer */,
\t\t\t);
\t\t\tname = PasrBeheer;
\t\t\tpackageProductDependencies = (
\t\t\t);
\t\t\tproductName = PasrBeheer;
\t\t\tproductReference = {I['product']} /* PasrBeheer.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{I['project']} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 2600;
\t\t\t\tLastUpgradeCheck = 2600;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{I['target']} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {I['cl.project']} /* Build configuration list for PBXProject "PasrBeheer" */;
\t\t\tdevelopmentRegion = nl;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\tnl,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {I['main']};
\t\t\tminimizedProjectReferenceProxies = 1;
\t\t\tpreferredProjectObjectVersion = 77;
\t\t\tproductRefGroup = {I['products']} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{I['target']} /* PasrBeheer */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
{phase('PBXResourcesBuildPhase', 'resources')}/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
{phase('PBXSourcesBuildPhase', 'sources')}/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
{cfg('pd', 'Debug', DEBUG)}{cfg('pr', 'Release', RELEASE)}{cfg('td', 'Debug', APP)}{cfg('tr', 'Release', APP)}/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
{cl('cl.project', 'pd', 'pr', 'Build configuration list for PBXProject "PasrBeheer"')}{cl('cl.target', 'td', 'tr', 'Build configuration list for PBXNativeTarget "PasrBeheer"')}/* End XCConfigurationList section */
\t}};
\trootObject = {I['project']} /* Project object */;
}}
"""


SCHEME = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "2600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{target}" BuildableName = "PasrBeheer.app" BlueprintName = "PasrBeheer" ReferencedContainer = "container:PasrBeheer.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{target}" BuildableName = "PasrBeheer.app" BlueprintName = "PasrBeheer" ReferencedContainer = "container:PasrBeheer.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""

if __name__ == "__main__":
    proj = ROOT / "PasrBeheer.xcodeproj"
    (proj / "xcshareddata" / "xcschemes").mkdir(parents=True, exist_ok=True)
    (proj / "project.pbxproj").write_text(build())
    (proj / "xcshareddata" / "xcschemes" / "PasrBeheer.xcscheme").write_text(SCHEME.replace("{target}", oid("target")))
    print("Wrote", proj)
