#!/usr/bin/env python3
"""Writes Pasr.xcodeproj/project.pbxproj (Xcode 16+ format with synchronized folders).

Folders App/, Shared/ and Watch/ are synchronized groups: every file you add in Xcode or on disk
is picked up automatically, so this script only needs to run again when targets or settings change.
"""
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def oid(name: str) -> str:
    return hashlib.md5(name.encode()).hexdigest()[:24].upper()


def q(value) -> str:
    s = str(value)
    if s and all(c.isalnum() or c in "._/" for c in s) and not s[0].isdigit():
        return s
    return '"' + s.replace('"', '\\"') + '"'


def settings_block(d: dict, indent: str) -> str:
    lines = []
    for key in sorted(d):
        value = d[key]
        if isinstance(value, list):
            inner = "".join(f"{indent}\t\t{q(v)},\n" for v in value)
            lines.append(f"{indent}\t{q(key)} = (\n{inner}{indent}\t);")
        else:
            lines.append(f"{indent}\t{q(key)} = {q(value)};")
    return "\n".join(lines)


PROJECT_BASE = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
    "CLANG_ANALYZER_NONNULL": "YES",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "COPY_PHASE_STRIP": "NO",
    "DEVELOPMENT_TEAM": "EU3UY476T6",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "IPHONEOS_DEPLOYMENT_TARGET": "26.0",
    "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
    "DEVELOPMENT_LANGUAGE": "nl",
    "MACOSX_DEPLOYMENT_TARGET": "26.0",
    "MTL_FAST_MATH": "YES",
    "STRING_CATALOG_GENERATE_SYMBOLS": "YES",
    "SWIFT_VERSION": "5.0",
    "WATCHOS_DEPLOYMENT_TARGET": "26.0",
}
PROJECT_DEBUG = {**PROJECT_BASE, "DEBUG_INFORMATION_FORMAT": "dwarf", "ENABLE_TESTABILITY": "YES",
                 "GCC_OPTIMIZATION_LEVEL": "0", "ONLY_ACTIVE_ARCH": "YES",
                 "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)",
                 "SWIFT_OPTIMIZATION_LEVEL": "-Onone", "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE"}
PROJECT_RELEASE = {**PROJECT_BASE, "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym", "ENABLE_NS_ASSERTIONS": "NO",
                   "SWIFT_COMPILATION_MODE": "wholemodule", "VALIDATE_PRODUCT": "YES", "MTL_ENABLE_DEBUG_INFO": "NO"}

APP = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_ENTITLEMENTS": "Config/Pasr.entitlements",
    "CODE_SIGN_ENTITLEMENTS[sdk=macosx*]": "Config/Pasr-macOS.entitlements",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "4",
    "ENABLE_HARDENED_RUNTIME": "YES",
    "ENABLE_PREVIEWS": "YES",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_FILE": "Config/Pasr-Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName": "Pasr",
    "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.lifestyle",
    "INFOPLIST_KEY_NSFaceIDUsageDescription": "Pasr gebruikt Face ID om je kaarten te beschermen.",
    "INFOPLIST_KEY_NSCameraUsageDescription": "Pasr gebruikt de camera om de barcode op je kaart te scannen.",
    "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": "UIInterfaceOrientationPortrait",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
    "LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]": ["$(inherited)", "@executable_path/../Frameworks"],
    "MARKETING_VERSION": "1.0.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "nl.lrvdlinden.pasr",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SDKROOT": "auto",
    "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator macosx",
    "SUPPORTS_MACCATALYST": "NO",
    "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "SWIFT_EMIT_LOC_STRINGS": "NO",
    "TARGETED_DEVICE_FAMILY": "1,2",
}
WIDGETS = {
    "APPLICATION_EXTENSION_API_ONLY": "YES",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_ENTITLEMENTS": "Config/PasrWidgets.entitlements",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "4",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_FILE": "Config/PasrWidgets-Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName": "Pasr",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"],
    "MARKETING_VERSION": "1.0.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "nl.lrvdlinden.pasr.widgets",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SDKROOT": "iphoneos",
    "SKIP_INSTALL": "YES",
    "SWIFT_EMIT_LOC_STRINGS": "NO",
    "TARGETED_DEVICE_FAMILY": "1,2",
}

WATCH = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_ENTITLEMENTS": "Config/PasrWatch.entitlements",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "4",
    "ENABLE_PREVIEWS": "YES",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_KEY_CFBundleDisplayName": "Pasr",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown",
    "INFOPLIST_KEY_WKCompanionAppBundleIdentifier": "nl.lrvdlinden.pasr",
    "INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp": "NO",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
    "MARKETING_VERSION": "1.0.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "nl.lrvdlinden.pasr.watchkitapp",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SDKROOT": "watchos",
    "SKIP_INSTALL": "YES",
    "SWIFT_EMIT_LOC_STRINGS": "NO",
    "TARGETED_DEVICE_FAMILY": "4",
}


def build():
    I = {k: oid(k) for k in [
        "project", "main", "products", "g.app", "g.shared", "g.watch", "p.app", "p.watch",
        "t.app", "t.watch", "app.sources", "app.frameworks", "app.resources", "app.embed",
        "watch.sources", "watch.frameworks", "watch.resources", "bf.embedwatch", "dep.watch", "proxy.watch",
        "cl.project", "cl.app", "cl.watch", "c.project.debug", "c.project.release",
        "c.app.debug", "c.app.release", "c.watch.debug", "c.watch.release",
        "g.widgets", "p.widgets", "t.widgets", "widgets.sources", "widgets.frameworks", "widgets.resources",
        "app.embedext", "bf.embedwidgets", "dep.widgets", "proxy.widgets", "cl.widgets",
        "c.widgets.debug", "c.widgets.release"]}

    def phase(isa, key):
        return f"""\t\t{I[key]} = {{
\t\t\tisa = {isa};
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
"""

    def config(key, name, d):
        return f"""\t\t{I[key]} /* {name} */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
{settings_block(d, chr(9) * 3)}
\t\t\t}};
\t\t\tname = {name};
\t\t}};
"""

    def config_list(key, debug, release, comment):
        return f"""\t\t{I[key]} /* {comment} */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{I[debug]} /* Debug */,
\t\t\t\t{I[release]} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
"""

    def sync(key, path):
        return f"""\t\t{I[key]} /* {path} */ = {{
\t\t\tisa = PBXFileSystemSynchronizedRootGroup;
\t\t\tpath = {path};
\t\t\tsourceTree = "<group>";
\t\t}};
"""

    return f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 77;
\tobjects = {{

/* Begin PBXBuildFile section */
\t\t{I['bf.embedwatch']} /* PasrWatch.app in Embed Watch Content */ = {{isa = PBXBuildFile; fileRef = {I['p.watch']} /* PasrWatch.app */; platformFilter = ios; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};
\t\t{I['bf.embedwidgets']} /* PasrWidgets.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {I['p.widgets']} /* PasrWidgets.appex */; platformFilter = ios; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
\t\t{I['proxy.watch']} /* PBXContainerItemProxy */ = {{
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = {I['project']} /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = {I['t.watch']};
\t\t\tremoteInfo = PasrWatch;
\t\t}};
\t\t{I['proxy.widgets']} /* PBXContainerItemProxy */ = {{
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = {I['project']} /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = {I['t.widgets']};
\t\t\tremoteInfo = PasrWidgets;
\t\t}};
/* End PBXContainerItemProxy section */

/* Begin PBXCopyFilesBuildPhase section */
\t\t{I['app.embed']} /* Embed Watch Content */ = {{
\t\t\tisa = PBXCopyFilesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tdstPath = "$(CONTENTS_FOLDER_PATH)/Watch";
\t\t\tdstSubfolderSpec = 16;
\t\t\tfiles = (
\t\t\t\t{I['bf.embedwatch']} /* PasrWatch.app in Embed Watch Content */,
\t\t\t);
\t\t\tname = "Embed Watch Content";
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{I['app.embedext']} /* Embed Foundation Extensions */ = {{
\t\t\tisa = PBXCopyFilesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tdstPath = "";
\t\t\tdstSubfolderSpec = 13;
\t\t\tfiles = (
\t\t\t\t{I['bf.embedwidgets']} /* PasrWidgets.appex in Embed Foundation Extensions */,
\t\t\t);
\t\t\tname = "Embed Foundation Extensions";
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFileReference section */
\t\t{I['p.app']} /* Pasr.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Pasr.app; sourceTree = BUILT_PRODUCTS_DIR; }};
\t\t{I['p.watch']} /* PasrWatch.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = PasrWatch.app; sourceTree = BUILT_PRODUCTS_DIR; }};
\t\t{I['p.widgets']} /* PasrWidgets.appex */ = {{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = PasrWidgets.appex; sourceTree = BUILT_PRODUCTS_DIR; }};
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
{sync('g.app', 'App')}{sync('g.shared', 'Shared')}{sync('g.watch', 'Watch')}{sync('g.widgets', 'Widgets')}/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
{phase('PBXFrameworksBuildPhase', 'app.frameworks')}{phase('PBXFrameworksBuildPhase', 'watch.frameworks')}{phase('PBXFrameworksBuildPhase', 'widgets.frameworks')}/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{I['main']} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{I['g.app']} /* App */,
\t\t\t\t{I['g.shared']} /* Shared */,
\t\t\t\t{I['g.watch']} /* Watch */,
\t\t\t\t{I['g.widgets']} /* Widgets */,
\t\t\t\t{I['products']} /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{I['products']} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{I['p.app']} /* Pasr.app */,
\t\t\t\t{I['p.watch']} /* PasrWatch.app */,
\t\t\t\t{I['p.widgets']} /* PasrWidgets.appex */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{I['t.app']} /* Pasr */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {I['cl.app']} /* Build configuration list for PBXNativeTarget "Pasr" */;
\t\t\tbuildPhases = (
\t\t\t\t{I['app.sources']} /* Sources */,
\t\t\t\t{I['app.frameworks']} /* Frameworks */,
\t\t\t\t{I['app.resources']} /* Resources */,
\t\t\t\t{I['app.embed']} /* Embed Watch Content */,
\t\t\t\t{I['app.embedext']} /* Embed Foundation Extensions */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t\t{I['dep.watch']} /* PBXTargetDependency */,
\t\t\t\t{I['dep.widgets']} /* PBXTargetDependency */,
\t\t\t);
\t\t\tfileSystemSynchronizedGroups = (
\t\t\t\t{I['g.app']} /* App */,
\t\t\t\t{I['g.shared']} /* Shared */,
\t\t\t);
\t\t\tname = Pasr;
\t\t\tpackageProductDependencies = (
\t\t\t);
\t\t\tproductName = Pasr;
\t\t\tproductReference = {I['p.app']} /* Pasr.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
\t\t{I['t.watch']} /* PasrWatch */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {I['cl.watch']} /* Build configuration list for PBXNativeTarget "PasrWatch" */;
\t\t\tbuildPhases = (
\t\t\t\t{I['watch.sources']} /* Sources */,
\t\t\t\t{I['watch.frameworks']} /* Frameworks */,
\t\t\t\t{I['watch.resources']} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tfileSystemSynchronizedGroups = (
\t\t\t\t{I['g.shared']} /* Shared */,
\t\t\t\t{I['g.watch']} /* Watch */,
\t\t\t);
\t\t\tname = PasrWatch;
\t\t\tpackageProductDependencies = (
\t\t\t);
\t\t\tproductName = PasrWatch;
\t\t\tproductReference = {I['p.watch']} /* PasrWatch.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
\t\t{I['t.widgets']} /* PasrWidgets */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {I['cl.widgets']} /* Build configuration list for PBXNativeTarget "PasrWidgets" */;
\t\t\tbuildPhases = (
\t\t\t\t{I['widgets.sources']} /* Sources */,
\t\t\t\t{I['widgets.frameworks']} /* Frameworks */,
\t\t\t\t{I['widgets.resources']} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tfileSystemSynchronizedGroups = (
\t\t\t\t{I['g.shared']} /* Shared */,
\t\t\t\t{I['g.widgets']} /* Widgets */,
\t\t\t);
\t\t\tname = PasrWidgets;
\t\t\tpackageProductDependencies = (
\t\t\t);
\t\t\tproductName = PasrWidgets;
\t\t\tproductReference = {I['p.widgets']} /* PasrWidgets.appex */;
\t\t\tproductType = "com.apple.product-type.app-extension";
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
\t\t\t\t\t{I['t.app']} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;
\t\t\t\t\t}};
\t\t\t\t\t{I['t.watch']} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;
\t\t\t\t\t}};
\t\t\t\t\t{I['t.widgets']} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {I['cl.project']} /* Build configuration list for PBXProject "Pasr" */;
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
\t\t\t\t{I['t.app']} /* Pasr */,
\t\t\t\t{I['t.watch']} /* PasrWatch */,
\t\t\t\t{I['t.widgets']} /* PasrWidgets */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
{phase('PBXResourcesBuildPhase', 'app.resources')}{phase('PBXResourcesBuildPhase', 'watch.resources')}{phase('PBXResourcesBuildPhase', 'widgets.resources')}/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
{phase('PBXSourcesBuildPhase', 'app.sources')}{phase('PBXSourcesBuildPhase', 'watch.sources')}{phase('PBXSourcesBuildPhase', 'widgets.sources')}/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
\t\t{I['dep.watch']} /* PBXTargetDependency */ = {{
\t\t\tisa = PBXTargetDependency;
\t\t\tplatformFilter = ios;
\t\t\ttarget = {I['t.watch']} /* PasrWatch */;
\t\t\ttargetProxy = {I['proxy.watch']} /* PBXContainerItemProxy */;
\t\t}};
\t\t{I['dep.widgets']} /* PBXTargetDependency */ = {{
\t\t\tisa = PBXTargetDependency;
\t\t\tplatformFilter = ios;
\t\t\ttarget = {I['t.widgets']} /* PasrWidgets */;
\t\t\ttargetProxy = {I['proxy.widgets']} /* PBXContainerItemProxy */;
\t\t}};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
{config('c.project.debug', 'Debug', PROJECT_DEBUG)}{config('c.project.release', 'Release', PROJECT_RELEASE)}{config('c.app.debug', 'Debug', APP)}{config('c.app.release', 'Release', APP)}{config('c.watch.debug', 'Debug', WATCH)}{config('c.watch.release', 'Release', WATCH)}{config('c.widgets.debug', 'Debug', WIDGETS)}{config('c.widgets.release', 'Release', WIDGETS)}/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
{config_list('cl.project', 'c.project.debug', 'c.project.release', 'Build configuration list for PBXProject "Pasr"')}{config_list('cl.app', 'c.app.debug', 'c.app.release', 'Build configuration list for PBXNativeTarget "Pasr"')}{config_list('cl.watch', 'c.watch.debug', 'c.watch.release', 'Build configuration list for PBXNativeTarget "PasrWatch"')}{config_list('cl.widgets', 'c.widgets.debug', 'c.widgets.release', 'Build configuration list for PBXNativeTarget "PasrWidgets"')}/* End XCConfigurationList section */
\t}};
\trootObject = {I['project']} /* Project object */;
}}
"""


if __name__ == "__main__":
    out = ROOT / "Pasr.xcodeproj" / "project.pbxproj"
    out.parent.mkdir(exist_ok=True)
    out.write_text(build())
    print(f"Wrote {out}")
