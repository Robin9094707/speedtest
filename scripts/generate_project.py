#!/usr/bin/env python3
"""Generate a deterministic Xcode project without third-party build dependencies."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
objects = {}


def uid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()


def add(key_name, isa, **properties):
    key = uid(key_name)
    objects[key] = dict(isa=isa, **properties)
    return key


def encode(value):
    if isinstance(value, dict):
        return "{ " + " ".join(f"{k} = {encode(v)};" for k, v in value.items()) + " }"
    if isinstance(value, list):
        return "( " + ", ".join(encode(v) for v in value) + ", )" if value else "()"
    return json.dumps(str(value), ensure_ascii=False)


def file_ref(path, file_type):
    return add("file:" + path, "PBXFileReference", lastKnownFileType=file_type, path=path, sourceTree="SOURCE_ROOT")


def phase(name, isa, refs):
    files = [add("build:" + name + ref, "PBXBuildFile", fileRef=ref) for ref in refs]
    return add(name, isa, buildActionMask="2147483647", files=files, runOnlyForDeploymentPostprocessing="0")


def configs(name, settings):
    items = []
    for mode in ["Debug", "Release"]:
        config = dict(settings)
        config.update(SWIFT_OPTIMIZATION_LEVEL="-Onone" if mode == "Debug" else "-O",
                      DEBUG_INFORMATION_FORMAT="dwarf" if mode == "Debug" else "dwarf-with-dsym")
        if mode == "Debug":
            config["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG"
            config["ENABLE_TESTABILITY"] = "YES"
        items.append(add(name + mode, "XCBuildConfiguration", name=mode, buildSettings=config))
    return add(name + "configs", "XCConfigurationList", buildConfigurations=items,
               defaultConfigurationIsVisible="0", defaultConfigurationName="Release")


all_refs = []
product_refs = []
targets = []
common = dict(SWIFT_VERSION="5.0", IPHONEOS_DEPLOYMENT_TARGET="17.0", SDKROOT="iphoneos",
              CLANG_ENABLE_MODULES="YES", CLANG_ENABLE_OBJC_ARC="YES", TARGETED_DEVICE_FAMILY="1,2",
              CODE_SIGN_STYLE="Automatic", SWIFT_STRICT_CONCURRENCY="targeted")

for name, folder, product_type, extension in [
    ("Speedtest", "Speedtest", "com.apple.product-type.application", "app"),
    ("SpeedtestTests", "Tests", "com.apple.product-type.bundle.unit-test", "xctest"),
    ("SpeedtestUITests", "UITests", "com.apple.product-type.bundle.ui-testing", "xctest"),
]:
    sources = [file_ref(str(p.relative_to(ROOT)), "sourcecode.swift") for p in sorted((ROOT / folder).rglob("*.swift"))]
    resources = []
    if name == "Speedtest":
        resources = [file_ref("Speedtest/Resources/Assets.xcassets", "folder.assetcatalog"),
                     file_ref("Speedtest/Resources/PrivacyInfo.xcprivacy", "text.xml")]
        all_refs += [file_ref("Speedtest/Resources/Info.plist", "text.plist.xml"),
                     file_ref("Speedtest/Resources/Speedtest.entitlements", "text.plist.entitlements")]
    all_refs += sources + resources
    product = add(name + "product", "PBXFileReference", explicitFileType="wrapper.application" if extension == "app" else "wrapper.cfbundle",
                  includeInIndex="0", path=f"{name}.{extension}", sourceTree="BUILT_PRODUCTS_DIR")
    product_refs.append(product)
    settings = dict(common, PRODUCT_NAME="$(TARGET_NAME)", PRODUCT_BUNDLE_IDENTIFIER="de.robinjuhas.speedtest" + ("" if name == "Speedtest" else "." + name),
                    CURRENT_PROJECT_VERSION="1", MARKETING_VERSION="2.0.0", GENERATE_INFOPLIST_FILE="YES",
                    LD_RUNPATH_SEARCH_PATHS=["$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks"])
    if name == "Speedtest":
        settings.update(INFOPLIST_FILE="Speedtest/Resources/Info.plist", GENERATE_INFOPLIST_FILE="NO",
                        ASSETCATALOG_COMPILER_APPICON_NAME="AppIcon", CODE_SIGN_ENTITLEMENTS="Speedtest/Resources/Speedtest.entitlements",
                        SUPPORTS_MACCATALYST="NO", SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD="NO", SUPPORTED_PLATFORMS="iphoneos iphonesimulator")
    elif name == "SpeedtestTests":
        settings.update(TEST_HOST="$(BUILT_PRODUCTS_DIR)/Speedtest.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Speedtest", BUNDLE_LOADER="$(TEST_HOST)")
    else:
        settings.update(TEST_TARGET_NAME="Speedtest")
    dependencies = []
    if name != "Speedtest":
        proxy = add(name + "proxy", "PBXContainerItemProxy", containerPortal=uid("project"), proxyType="1",
                    remoteGlobalIDString=uid("Speedtesttarget"), remoteInfo="Speedtest")
        dependencies = [add(name + "dependency", "PBXTargetDependency", target=uid("Speedtesttarget"), targetProxy=proxy)]
    target = add(name + "target", "PBXNativeTarget", name=name, productName=name,
                 productReference=product, productType=product_type, buildConfigurationList=configs(name, settings),
                 buildPhases=[phase(name + "sources", "PBXSourcesBuildPhase", sources),
                              phase(name + "frameworks", "PBXFrameworksBuildPhase", []),
                              phase(name + "resources", "PBXResourcesBuildPhase", resources)],
                 buildRules=[], dependencies=dependencies)
    targets.append(target)

products = add("products", "PBXGroup", children=product_refs, name="Products", sourceTree="<group>")
group = add("mainGroup", "PBXGroup", children=all_refs + [products], sourceTree="<group>")
add("project", "PBXProject", attributes={"BuildIndependentTargetsInParallel": "YES", "LastUpgradeCheck": "2600"},
    buildConfigurationList=configs("project", common), compatibilityVersion="Xcode 14.0", developmentRegion="de",
    hasScannedForEncodings="0", knownRegions=["de", "en", "Base"], mainGroup=group, productRefGroup=products,
    projectDirPath="", projectRoot="", targets=targets)
project = ROOT / "Speedtest.xcodeproj"
project.mkdir(exist_ok=True)
project.joinpath("project.pbxproj").write_text("// !$*UTF8*$!\n" + encode({
    "archiveVersion": "1", "classes": {}, "objectVersion": "56", "objects": objects, "rootObject": uid("project")
}) + "\n")
scheme_dir = project / "xcshareddata/xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)


def reference(name, ext):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid(name + "target")}" BuildableName="{name}.{ext}" BlueprintName="{name}" ReferencedContainer="container:Speedtest.xcodeproj"/>'


scheme_dir.joinpath("Speedtest.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
 <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference("Speedtest", "app")}</BuildActionEntry>
 </BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
 <Testables><TestableReference skipped="NO">{reference("SpeedtestTests", "xctest")}</TestableReference><TestableReference skipped="NO">{reference("SpeedtestUITests", "xctest")}</TestableReference></Testables>
 </TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference("Speedtest", "app")}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference("Speedtest", "app")}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/>
 <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print("Generated Speedtest.xcodeproj with app, unit tests and UI tests.")
