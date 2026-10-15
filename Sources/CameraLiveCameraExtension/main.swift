import CoreMediaIO
import Foundation

do {
    let source = try CameraProviderSource()
    CMIOExtensionProvider.startService(provider: source.provider)
    withExtendedLifetime(source) { dispatchMain() }
} catch {
    NSLog("Camera Live extension could not start: %@", error.localizedDescription)
    exit(EXIT_FAILURE)
}
