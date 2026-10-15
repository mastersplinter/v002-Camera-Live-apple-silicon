// swift-tools-version: 6.0
import PackageDescription
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let dependencies = root + "/.dependencies/usr"
let package = Package(
    name: "CameraLive",
    platforms: [.macOS(.v13)],
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
        .target(name: "CameraLiveCore", dependencies: ["CameraLiveNative"],
                linkerSettings: [.linkedFramework("Metal"), .linkedFramework("MetalKit"), .linkedFramework("CoreImage"),
                                 .linkedFramework("ImageIO"), .linkedFramework("IOKit")]),
        .target(name: "VirtualCameraShared", linkerSettings: [.linkedFramework("CoreMedia"), .linkedFramework("CoreVideo"), .linkedFramework("CoreText")]),
        .target(name: "CameraLiveVirtualCamera", dependencies: ["CameraLiveCore", "VirtualCameraShared"],
                linkerSettings: [.linkedFramework("CoreMediaIO"), .linkedFramework("SystemExtensions")]),
        .executableTarget(name: "CameraLiveCameraExtension", dependencies: ["VirtualCameraShared"],
                linkerSettings: [.linkedFramework("CoreMediaIO")]),
        .executableTarget(name: "CameraLiveApp", dependencies: ["CameraLiveCore", "CameraLiveVirtualCamera"]),
        .executableTarget(name: "CameraLiveDiagnostics", dependencies: ["CameraLiveCore", "CameraLiveNative", "CameraLiveVirtualCamera", "VirtualCameraShared"]),
        .testTarget(name: "CameraLiveCoreTests", dependencies: ["CameraLiveCore", "CameraLiveNative", "CameraLiveVirtualCamera", "VirtualCameraShared"])
    ],
    swiftLanguageModes: [.v5]
)
