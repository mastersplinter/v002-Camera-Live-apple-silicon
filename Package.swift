// swift-tools-version: 6.0
import PackageDescription
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let dependencies = root + "/.dependencies/usr"
let minimumMacOS = "26.0"
// The CLT Swift driver can stamp the deployment target as the SDK version,
// opting native controls into old compatibility behaviour. The build wrapper
// supplies the actual selected SDK; pass both versions explicitly at link time.
let platformLinkerSettings: [LinkerSetting] = ProcessInfo.processInfo.environment["CAMERALIVE_MACOS_SDK_VERSION"].map {
    [.unsafeFlags(["-Xlinker", "-platform_version", "-Xlinker", "macos",
                   "-Xlinker", minimumMacOS, "-Xlinker", $0])]
} ?? []
let package = Package(
    name: "CameraLive",
    platforms: [.macOS(minimumMacOS)],
    products: [
        .library(name: "CameraLiveCore", targets: ["CameraLiveCore"]),
        .executable(name: "CameraLive", targets: ["CameraLiveApp"]),
        .executable(name: "camera-live-diagnostics", targets: ["CameraLiveDiagnostics"]),
        .executable(name: "CameraLiveCameraExtension", targets: ["CameraLiveCameraExtension"])
    ],
    targets: [
        .target(name: "CameraLiveNative", publicHeadersPath: "include",
                cSettings: [.unsafeFlags(["-I" + dependencies + "/include", "-F" + dependencies + "/Frameworks", "-fobjc-arc"])],
                linkerSettings: [.unsafeFlags(["-L" + dependencies + "/lib", "-F" + dependencies + "/Frameworks",
                    "-Xlinker", "-rpath", "-Xlinker", dependencies + "/lib",
                    "-Xlinker", "-rpath", "-Xlinker", dependencies + "/Frameworks",
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
                    .linkedLibrary("gphoto2"), .linkedLibrary("gphoto2_port"), .linkedFramework("Syphon")]),
        .target(name: "CameraLiveCore", dependencies: ["CameraLiveNative", "VirtualCameraShared"],
                linkerSettings: [.linkedFramework("Metal"), .linkedFramework("MetalKit"), .linkedFramework("CoreImage"),
                                 .linkedFramework("ImageIO"), .linkedFramework("IOKit")]),
        .target(name: "VirtualCameraShared", linkerSettings: platformLinkerSettings + [.linkedFramework("CoreMedia"), .linkedFramework("CoreVideo"), .linkedFramework("CoreText"), .linkedFramework("CoreImage"), .linkedFramework("Metal")]),
        .target(name: "CameraLiveVirtualCamera", dependencies: ["CameraLiveCore", "VirtualCameraShared"],
                linkerSettings: [.linkedFramework("CoreMediaIO"), .linkedFramework("SystemExtensions")]),
        .executableTarget(name: "CameraLiveCameraExtension", dependencies: ["VirtualCameraShared"],
                linkerSettings: [.linkedFramework("CoreMediaIO"), .linkedFramework("Security")]),
        .executableTarget(name: "CameraLiveApp", dependencies: ["CameraLiveCore", "CameraLiveVirtualCamera", "VirtualCameraShared"]),
        .executableTarget(name: "CameraLiveDiagnostics", dependencies: ["CameraLiveCore", "CameraLiveNative", "CameraLiveVirtualCamera", "VirtualCameraShared"]),
        .testTarget(name: "CameraLiveCoreTests", dependencies: ["CameraLiveCore", "CameraLiveNative", "CameraLiveVirtualCamera", "VirtualCameraShared"])
    ],
    swiftLanguageModes: [.v5]
)
