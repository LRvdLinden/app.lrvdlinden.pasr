#!/usr/bin/env python3
"""Writes PasrZakelijk.xcodeproj (Xcode 16+ format, synchronized folders).

Pasr Zakelijk: de app voor ondernemers (stempels zetten, kaarten, medewerkers). Vier targets, één versie en build:

- PasrZakelijk            iPhone en iPad (iOS 17+), mappen PasrZakelijk/ en Shared/, met de widgets ingebed
- PasrZakelijkWidgets     widgets voor iOS (Vandaag, Komend event, Te doen), mappen Widgets/ en Shared/
- PasrZakelijkMac         native Mac-app (macOS 14+, SwiftUI, geen Catalyst), mappen PasrZakelijk/, Shared/ en Mac/
- PasrZakelijkMacWidgets  dezelfde widgets voor macOS, mappen Widgets/ en Shared/

iOS en Mac hebben hetzelfde bundle-id (app.lrvdlinden.pasrzakelijk): één app in App Store Connect (universal purchase).
Bestanden in de mappen komen er vanzelf in; draai dit alleen opnieuw als instellingen veranderen
(bijv. het buildnummer hieronder).
"""
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent
BUILD = "21"
VERSION = "1.0.4"


def oid(name):
    return hashlib.md5(("zakelijk." + name).encode()).hexdigest()[:24].upper()


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
    "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
    "MACOSX_DEPLOYMENT_TARGET": "14.0",
    "SWIFT_VERSION": "5.0",
}
DEBUG = {**PROJECT, "DEBUG_INFORMATION_FORMAT": "dwarf", "ENABLE_TESTABILITY": "YES", "GCC_OPTIMIZATION_LEVEL": "0",
         "ONLY_ACTIVE_ARCH": "YES", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)", "SWIFT_OPTIMIZATION_LEVEL": "-Onone"}
RELEASE = {**PROJECT, "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym", "ENABLE_NS_ASSERTIONS": "NO",
           "SWIFT_COMPILATION_MODE": "wholemodule", "VALIDATE_PRODUCT": "YES"}
APP = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_ENTITLEMENTS": "Config/PasrZakelijk.entitlements",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": BUILD,
    "DEVELOPMENT_TEAM": "EU3UY476T6",
    "ENABLE_PREVIEWS": "YES",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_FILE": "Config/Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName": "Pasr Zakelijk",
    "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption": "NO",
    "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.business",
    "INFOPLIST_KEY_NSCameraUsageDescription": "Pasr Zakelijk gebruikt de camera om stempelkaarten, tickets, klantenkaarten, kortingsbonnen en codes van je klanten te scannen.",
    "INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription": "Pasr Zakelijk bewaart gemaakte promotieafbeeldingen in je Foto’s-bibliotheek.",
    "INFOPLIST_KEY_NSFaceIDUsageDescription": "Pasr Zakelijk gebruikt Face ID om de app te vergrendelen, zodat alleen jij stempels kunt zetten.",
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": "UIInterfaceOrientationPortrait",
    "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
    "MARKETING_VERSION": VERSION,
    "PRODUCT_BUNDLE_IDENTIFIER": "app.lrvdlinden.pasrzakelijk",
    "PRODUCT_NAME": "PasrZakelijk",
    "SDKROOT": "iphoneos",
    "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
    "SUPPORTS_MACCATALYST": "NO",
    "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "TARGETED_DEVICE_FAMILY": "1,2",
}
WIDGETS = {
    "APPLICATION_EXTENSION_API_ONLY": "YES",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_ENTITLEMENTS": "Config/PasrZakelijkWidgets.entitlements",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": BUILD,
    "DEVELOPMENT_TEAM": "EU3UY476T6",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_FILE": "Config/PasrZakelijkWidgets-Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName": "Pasr Zakelijk",
    "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"],
    "MARKETING_VERSION": VERSION,
    "PRODUCT_BUNDLE_IDENTIFIER": "app.lrvdlinden.pasrzakelijk.widgets",
    "PRODUCT_NAME": "PasrZakelijkWidgets",
    "SDKROOT": "iphoneos",
    "SKIP_INSTALL": "YES",
    "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "TARGETED_DEVICE_FAMILY": "1,2",
}
MAC = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_ENTITLEMENTS": "Config/PasrZakelijkMac.entitlements",
    "CODE_SIGN_STYLE": "Automatic",
    "COMBINE_HIDPI_IMAGES": "YES",
    "CURRENT_PROJECT_VERSION": BUILD,
    "DEVELOPMENT_TEAM": "EU3UY476T6",
    "ENABLE_APP_SANDBOX": "YES",
    "ENABLE_HARDENED_RUNTIME": "YES",
    "ENABLE_PREVIEWS": "YES",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_FILE": "Config/Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName": "Pasr Zakelijk",
    "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption": "NO",
    "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.business",
    "INFOPLIST_KEY_NSCameraUsageDescription": "Pasr Zakelijk gebruikt de camera om stempelkaarten, tickets, klantenkaarten, kortingsbonnen en codes van je klanten te scannen.",
    "INFOPLIST_KEY_NSHumanReadableCopyright": "© LRvdLinden",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/../Frameworks"],
    "MACOSX_DEPLOYMENT_TARGET": "14.0",
    "MARKETING_VERSION": VERSION,
    "PRODUCT_BUNDLE_IDENTIFIER": "app.lrvdlinden.pasrzakelijk",
    "PRODUCT_MODULE_NAME": "PasrZakelijk",
    "PRODUCT_NAME": "Pasr Zakelijk",
    "SDKROOT": "macosx",
    "SUPPORTED_PLATFORMS": "macosx",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
}
MAC_WIDGETS = {
    "APPLICATION_EXTENSION_API_ONLY": "YES",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_ENTITLEMENTS": "Config/PasrZakelijkMacWidgets.entitlements",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": BUILD,
    "DEVELOPMENT_TEAM": "EU3UY476T6",
    "ENABLE_APP_SANDBOX": "YES",
    "ENABLE_HARDENED_RUNTIME": "YES",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_FILE": "Config/PasrZakelijkWidgets-Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName": "Pasr Zakelijk",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/../Frameworks", "@executable_path/../../../../Frameworks"],
    "MACOSX_DEPLOYMENT_TARGET": "14.0",
    "MARKETING_VERSION": VERSION,
    "PRODUCT_BUNDLE_IDENTIFIER": "app.lrvdlinden.pasrzakelijk.widgets",
    "PRODUCT_NAME": "PasrZakelijkMacWidgets",
    "SDKROOT": "macosx",
    "SKIP_INSTALL": "YES",
    "SUPPORTED_PLATFORMS": "macosx",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
}


def build():
    I = {k: oid(k) for k in [
        "project", "main", "products", "group", "config", "product", "target", "sources",
        "frameworks", "resources", "cl.project", "cl.target", "pd", "pr", "td", "tr",
        "f.info", "f.ent",
        # gedeelde code, widgets en Mac
        "g.shared", "g.widgets", "g.mac",
        "f.wentinfo", "f.went", "f.ment", "f.mwent",
        "p.widgets", "t.widgets", "widgets.sources", "widgets.frameworks", "widgets.resources", "cl.widgets", "wd", "wr",
        "p.mac", "t.mac", "mac.sources", "mac.frameworks", "mac.resources", "cl.mac", "md", "mr",
        "p.macwidgets", "t.macwidgets", "macwidgets.sources", "macwidgets.frameworks", "macwidgets.resources",
        "cl.macwidgets", "mwd", "mwr",
        "app.embedext", "bf.embedwidgets", "dep.widgets", "proxy.widgets",
        "mac.embedext", "bf.embedmacwidgets", "dep.macwidgets", "proxy.macwidgets"]}

    def phase(isa, key):
        return f"\t\t{I[key]} = {{\n\t\t\tisa = {isa};\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n"

    def cfg(key, name, d):
        return f"\t\t{I[key]} /* {name} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{\n{block(d, chr(9) * 3)}\n\t\t\t}};\n\t\t\tname = {name};\n\t\t}};\n"

    def cl(key, d, r, comment):
        return (f"\t\t{I[key]} /* {comment} */ = {{\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n"
                f"\t\t\t\t{I[d]} /* Debug */,\n\t\t\t\t{I[r]} /* Release */,\n\t\t\t);\n"
                f"\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t}};\n")

    def sync(key, path):
        return f"\t\t{I[key]} /* {path} */ = {{\n\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n\t\t\tpath = {path};\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n"

    def proxy(key, target, name):
        return (f"\t\t{I[key]} /* PBXContainerItemProxy */ = {{\n\t\t\tisa = PBXContainerItemProxy;\n"
                f"\t\t\tcontainerPortal = {I['project']} /* Project object */;\n\t\t\tproxyType = 1;\n"
                f"\t\t\tremoteGlobalIDString = {I[target]};\n\t\t\tremoteInfo = {name};\n\t\t}};\n")

    def dep(key, target, prox, name):
        return (f"\t\t{I[key]} /* PBXTargetDependency */ = {{\n\t\t\tisa = PBXTargetDependency;\n"
                f"\t\t\ttarget = {I[target]} /* {name} */;\n\t\t\ttargetProxy = {I[prox]} /* PBXContainerItemProxy */;\n\t\t}};\n")

    def embed(key, bf, name):
        return (f"\t\t{I[key]} /* Embed Foundation Extensions */ = {{\n\t\t\tisa = PBXCopyFilesBuildPhase;\n"
                f"\t\t\tbuildActionMask = 2147483647;\n\t\t\tdstPath = \"\";\n\t\t\tdstSubfolderSpec = 13;\n\t\t\tfiles = (\n"
                f"\t\t\t\t{I[bf]} /* {name} in Embed Foundation Extensions */,\n\t\t\t);\n"
                f"\t\t\tname = \"Embed Foundation Extensions\";\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")

    def target(key, name, cl_key, phases, deps, groups, product, product_file, ptype):
        ph = "".join(f"\t\t\t\t{I[k]} /* {c} */,\n" for k, c in phases)
        dp = "".join(f"\t\t\t\t{I[k]} /* PBXTargetDependency */,\n" for k in deps)
        gr = "".join(f"\t\t\t\t{I[k]} /* {c} */,\n" for k, c in groups)
        return (f"\t\t{I[key]} /* {name} */ = {{\n\t\t\tisa = PBXNativeTarget;\n"
                f"\t\t\tbuildConfigurationList = {I[cl_key]} /* Build configuration list for PBXNativeTarget \"{name}\" */;\n"
                f"\t\t\tbuildPhases = (\n{ph}\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n"
                f"\t\t\tdependencies = (\n{dp}\t\t\t);\n"
                f"\t\t\tfileSystemSynchronizedGroups = (\n{gr}\t\t\t);\n"
                f"\t\t\tname = {name};\n\t\t\tpackageProductDependencies = (\n\t\t\t);\n\t\t\tproductName = {name};\n"
                f"\t\t\tproductReference = {I[product]} /* {product_file} */;\n"
                f"\t\t\tproductType = \"{ptype}\";\n\t\t}};\n")

    APP_T = "com.apple.product-type.application"
    EXT_T = "com.apple.product-type.app-extension"

    return f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 77;
\tobjects = {{

/* Begin PBXBuildFile section */
\t\t{I['bf.embedwidgets']} /* PasrZakelijkWidgets.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {I['p.widgets']} /* PasrZakelijkWidgets.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};
\t\t{I['bf.embedmacwidgets']} /* PasrZakelijkMacWidgets.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {I['p.macwidgets']} /* PasrZakelijkMacWidgets.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
{proxy('proxy.widgets', 't.widgets', 'PasrZakelijkWidgets')}{proxy('proxy.macwidgets', 't.macwidgets', 'PasrZakelijkMacWidgets')}/* End PBXContainerItemProxy section */

/* Begin PBXCopyFilesBuildPhase section */
{embed('app.embedext', 'bf.embedwidgets', 'PasrZakelijkWidgets.appex')}{embed('mac.embedext', 'bf.embedmacwidgets', 'PasrZakelijkMacWidgets.appex')}/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFileReference section */
\t\t{I['product']} /* PasrZakelijk.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "PasrZakelijk.app"; sourceTree = BUILT_PRODUCTS_DIR; }};
\t\t{I['p.widgets']} /* PasrZakelijkWidgets.appex */ = {{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = "PasrZakelijkWidgets.appex"; sourceTree = BUILT_PRODUCTS_DIR; }};
\t\t{I['p.mac']} /* Pasr Zakelijk.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "Pasr Zakelijk.app"; sourceTree = BUILT_PRODUCTS_DIR; }};
\t\t{I['p.macwidgets']} /* PasrZakelijkMacWidgets.appex */ = {{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = "PasrZakelijkMacWidgets.appex"; sourceTree = BUILT_PRODUCTS_DIR; }};
\t\t{I['f.info']} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};
\t\t{I['f.ent']} /* PasrZakelijk.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = "PasrZakelijk.entitlements"; sourceTree = "<group>"; }};
\t\t{I['f.wentinfo']} /* PasrZakelijkWidgets-Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = "PasrZakelijkWidgets-Info.plist"; sourceTree = "<group>"; }};
\t\t{I['f.went']} /* PasrZakelijkWidgets.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = "PasrZakelijkWidgets.entitlements"; sourceTree = "<group>"; }};
\t\t{I['f.ment']} /* PasrZakelijkMac.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = "PasrZakelijkMac.entitlements"; sourceTree = "<group>"; }};
\t\t{I['f.mwent']} /* PasrZakelijkMacWidgets.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = "PasrZakelijkMacWidgets.entitlements"; sourceTree = "<group>"; }};
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
{sync('group', 'PasrZakelijk')}{sync('g.shared', 'Shared')}{sync('g.widgets', 'Widgets')}{sync('g.mac', 'Mac')}/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
{phase('PBXFrameworksBuildPhase', 'frameworks')}{phase('PBXFrameworksBuildPhase', 'widgets.frameworks')}{phase('PBXFrameworksBuildPhase', 'mac.frameworks')}{phase('PBXFrameworksBuildPhase', 'macwidgets.frameworks')}/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{I['main']} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{I['group']} /* PasrZakelijk */,
\t\t\t\t{I['g.shared']} /* Shared */,
\t\t\t\t{I['g.widgets']} /* Widgets */,
\t\t\t\t{I['g.mac']} /* Mac */,
\t\t\t\t{I['config']} /* Config */,
\t\t\t\t{I['products']} /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{I['config']} /* Config */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{I['f.info']} /* Info.plist */,
\t\t\t\t{I['f.ent']} /* PasrZakelijk.entitlements */,
\t\t\t\t{I['f.wentinfo']} /* PasrZakelijkWidgets-Info.plist */,
\t\t\t\t{I['f.went']} /* PasrZakelijkWidgets.entitlements */,
\t\t\t\t{I['f.ment']} /* PasrZakelijkMac.entitlements */,
\t\t\t\t{I['f.mwent']} /* PasrZakelijkMacWidgets.entitlements */,
\t\t\t);
\t\t\tpath = Config;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{I['products']} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{I['product']} /* PasrZakelijk.app */,
\t\t\t\t{I['p.widgets']} /* PasrZakelijkWidgets.appex */,
\t\t\t\t{I['p.mac']} /* Pasr Zakelijk.app */,
\t\t\t\t{I['p.macwidgets']} /* PasrZakelijkMacWidgets.appex */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
{target('target', 'PasrZakelijk', 'cl.target',
        [('sources', 'Sources'), ('frameworks', 'Frameworks'), ('resources', 'Resources'), ('app.embedext', 'Embed Foundation Extensions')],
        ['dep.widgets'], [('group', 'PasrZakelijk'), ('g.shared', 'Shared')], 'product', 'PasrZakelijk.app', APP_T)}{target('t.widgets', 'PasrZakelijkWidgets', 'cl.widgets',
        [('widgets.sources', 'Sources'), ('widgets.frameworks', 'Frameworks'), ('widgets.resources', 'Resources')],
        [], [('g.widgets', 'Widgets'), ('g.shared', 'Shared')], 'p.widgets', 'PasrZakelijkWidgets.appex', EXT_T)}{target('t.mac', 'PasrZakelijkMac', 'cl.mac',
        [('mac.sources', 'Sources'), ('mac.frameworks', 'Frameworks'), ('mac.resources', 'Resources'), ('mac.embedext', 'Embed Foundation Extensions')],
        ['dep.macwidgets'], [('group', 'PasrZakelijk'), ('g.shared', 'Shared'), ('g.mac', 'Mac')], 'p.mac', 'Pasr Zakelijk.app', APP_T)}{target('t.macwidgets', 'PasrZakelijkMacWidgets', 'cl.macwidgets',
        [('macwidgets.sources', 'Sources'), ('macwidgets.frameworks', 'Frameworks'), ('macwidgets.resources', 'Resources')],
        [], [('g.widgets', 'Widgets'), ('g.shared', 'Shared')], 'p.macwidgets', 'PasrZakelijkMacWidgets.appex', EXT_T)}/* End PBXNativeTarget section */

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
\t\t\t\t\t{I['t.widgets']} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;
\t\t\t\t\t}};
\t\t\t\t\t{I['t.mac']} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;
\t\t\t\t\t}};
\t\t\t\t\t{I['t.macwidgets']} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {I['cl.project']} /* Build configuration list for PBXProject "PasrZakelijk" */;
\t\t\tdevelopmentRegion = nl;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\tnl,
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {I['main']};
\t\t\tminimizedProjectReferenceProxies = 1;
\t\t\tpreferredProjectObjectVersion = 77;
\t\t\tproductRefGroup = {I['products']} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{I['target']} /* PasrZakelijk */,
\t\t\t\t{I['t.widgets']} /* PasrZakelijkWidgets */,
\t\t\t\t{I['t.mac']} /* PasrZakelijkMac */,
\t\t\t\t{I['t.macwidgets']} /* PasrZakelijkMacWidgets */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
{phase('PBXResourcesBuildPhase', 'resources')}{phase('PBXResourcesBuildPhase', 'widgets.resources')}{phase('PBXResourcesBuildPhase', 'mac.resources')}{phase('PBXResourcesBuildPhase', 'macwidgets.resources')}/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
{phase('PBXSourcesBuildPhase', 'sources')}{phase('PBXSourcesBuildPhase', 'widgets.sources')}{phase('PBXSourcesBuildPhase', 'mac.sources')}{phase('PBXSourcesBuildPhase', 'macwidgets.sources')}/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
{dep('dep.widgets', 't.widgets', 'proxy.widgets', 'PasrZakelijkWidgets')}{dep('dep.macwidgets', 't.macwidgets', 'proxy.macwidgets', 'PasrZakelijkMacWidgets')}/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
{cfg('pd', 'Debug', DEBUG)}{cfg('pr', 'Release', RELEASE)}{cfg('td', 'Debug', APP)}{cfg('tr', 'Release', APP)}{cfg('wd', 'Debug', WIDGETS)}{cfg('wr', 'Release', WIDGETS)}{cfg('md', 'Debug', MAC)}{cfg('mr', 'Release', MAC)}{cfg('mwd', 'Debug', MAC_WIDGETS)}{cfg('mwr', 'Release', MAC_WIDGETS)}/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
{cl('cl.project', 'pd', 'pr', 'Build configuration list for PBXProject "PasrZakelijk"')}{cl('cl.target', 'td', 'tr', 'Build configuration list for PBXNativeTarget "PasrZakelijk"')}{cl('cl.widgets', 'wd', 'wr', 'Build configuration list for PBXNativeTarget "PasrZakelijkWidgets"')}{cl('cl.mac', 'md', 'mr', 'Build configuration list for PBXNativeTarget "PasrZakelijkMac"')}{cl('cl.macwidgets', 'mwd', 'mwr', 'Build configuration list for PBXNativeTarget "PasrZakelijkMacWidgets"')}/* End XCConfigurationList section */
\t}};
\trootObject = {I['project']} /* Project object */;
}}
"""


SCHEME = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "2600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{target}" BuildableName = "PasrZakelijk.app" BlueprintName = "PasrZakelijk" ReferencedContainer = "container:PasrZakelijk.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{target}" BuildableName = "PasrZakelijk.app" BlueprintName = "PasrZakelijk" ReferencedContainer = "container:PasrZakelijk.xcodeproj">
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


def scheme(target_key, product, name):
    return (SCHEME.replace("{target}", oid(target_key)).replace("PasrZakelijk.app", product)
            .replace('BlueprintName = "PasrZakelijk"', f'BlueprintName = "{name}"'))


if __name__ == "__main__":
    proj = ROOT / "PasrZakelijk.xcodeproj"
    schemes = proj / "xcshareddata" / "xcschemes"
    schemes.mkdir(parents=True, exist_ok=True)
    (proj / "project.pbxproj").write_text(build())
    (schemes / "PasrZakelijk.xcscheme").write_text(SCHEME.replace("{target}", oid("target")))
    (schemes / "PasrZakelijkMac.xcscheme").write_text(scheme("t.mac", "Pasr Zakelijk.app", "PasrZakelijkMac"))
    print("Wrote", proj)
