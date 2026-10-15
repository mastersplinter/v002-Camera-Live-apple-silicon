import CoreMediaIO
import Foundation
import OSLog
import Security
import VirtualCameraShared

final class CameraProviderSource: NSObject, CMIOExtensionProviderSource {
    private(set) var provider: CMIOExtensionProvider!
    private let camera: CameraDeviceSource
    init(queue: DispatchQueue = DispatchQueue(label: "info.v002.CameraLive.extension", qos: .userInitiated)) throws {
        camera = try CameraDeviceSource(queue: queue)
        super.init()
        provider = CMIOExtensionProvider(source: self, clientQueue: queue)
        try provider.addDevice(camera.device)
    }
    var availableProperties: Set<CMIOExtensionProperty> { [.providerName, .providerManufacturer] }
    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let result = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerName) { result.name = VirtualCameraFormat.name }
        if properties.contains(.providerManufacturer) { result.manufacturer = "Camera Live" }
        return result
    }
    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {}
    func connect(to client: CMIOExtensionClient) throws {}
    func disconnect(from client: CMIOExtensionClient) { camera.disconnect(client) }
}

final class CameraDeviceSource: NSObject, CMIOExtensionDeviceSource {
    private(set) var device: CMIOExtensionDevice!
    private(set) var output: CameraStreamSource!
    private(set) var input: CameraStreamSource!
    private let queue: DispatchQueue
    private let relay = VirtualCameraFrameRelay()
    private let standby: CVPixelBuffer
    private var timer: DispatchSourceTimer?
    private var sourceClients = 0
    private var producer: CMIOExtensionClient?
    private var authorizedProducer: CMIOExtensionClient?
    private var consuming = false
    private var generation = 0
    private var wasLive = false
    private let senderVerifier = CameraSenderVerifier()
    private let logger = Logger(subsystem: VirtualCameraFormat.extensionIdentifier, category: "Sender")
    private var reportedClients: Set<UUID> = []

    init(queue: DispatchQueue) throws {
        self.queue = queue
        standby = try VirtualCameraFormat.placeholder()
        super.init()
        device = CMIOExtensionDevice(localizedName: VirtualCameraFormat.name,
            deviceID: VirtualCameraFormat.deviceID, legacyDeviceID: nil, source: self)
        output = try CameraStreamSource(owner: self, direction: .source)
        input = try CameraStreamSource(owner: self, direction: .sink)
        try device.addStream(output.stream)
        try device.addStream(input.stream)
    }

    var availableProperties: Set<CMIOExtensionProperty> { [.deviceModel, .deviceTransportType] }
    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let result = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceModel) { result.model = "Camera Live Virtual Camera" }
        if properties.contains(.deviceTransportType) { result.transportType = 0x76697274 /* virt */ }
        return result
    }
    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {}

    func authorize(_ client: CMIOExtensionClient, direction: CMIOExtensionStream.Direction) -> Bool {
        guard direction == .sink else { return true } // macOS enforces camera consent for viewers.
        let signatureStatus = senderVerifier.status(for: client.pid)
        let available = producer == nil || producer?.clientID == client.clientID
        if reportedClients.insert(client.clientID).inserted {
            logger.notice("Sender pid=\(client.pid) reportedSigningID=\(client.signingID ?? "missing", privacy: .public) signatureStatus=\(signatureStatus) available=\(available)")
        }
        guard signatureStatus == errSecSuccess, available else { return false }
        authorizedProducer = client
        return true
    }

    func start(_ direction: CMIOExtensionStream.Direction) throws {
        if direction == .source { sourceClients += 1 }
        else {
            guard let authorizedProducer else { throw VirtualCameraError.invalidFrame }
            producer = authorizedProducer
            generation += 1
        }
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .nanoseconds(1_000_000_000 / Int(VirtualCameraFormat.framesPerSecond)), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer
        timer.resume()
    }

    func stop(_ direction: CMIOExtensionStream.Direction) {
        if direction == .source { sourceClients = max(0, sourceClients - 1) }
        else {
            generation += 1
            producer = nil; authorizedProducer = nil; consuming = false
            relay.clear()
        }
        if sourceClients == 0, producer == nil { timer?.cancel(); timer = nil }
    }

    func disconnect(_ client: CMIOExtensionClient) {
        reportedClients.remove(client.clientID)
        if producer?.clientID == client.clientID { stop(.sink) }
        if authorizedProducer?.clientID == client.clientID { authorizedProducer = nil }
    }

    private func tick() {
        if producer != nil, !consuming { consume(remaining: VirtualCameraFormat.queueSize) }
        guard sourceClients > 0 else { return }
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        let image = relay.frame(at: ProcessInfo.processInfo.systemUptime)
        let live = image != nil
        do {
            let sample = try VirtualCameraFormat.sample(image ?? standby, at: now)
            output.stream.send(sample, discontinuity: live != wasLive ? .time : [],
                hostTimeInNanoseconds: UInt64(CMTimeConvertScale(now, timescale: 1_000_000_000, method: .default).value))
            wasLive = live
        } catch { NSLog("Camera Live output error: %@", error.localizedDescription) }
    }

    private func consume(remaining: Int) {
        guard let producer, remaining > 0 else { return }
        consuming = true
        let token = generation
        input.stream.consumeSampleBuffer(from: producer) { [weak self] sample, sequence, _, more, error in
            guard let self else { return }
            self.queue.async {
                guard token == self.generation else { return }
                self.consuming = false
                if error == nil, let sample, let image = CMSampleBufferGetImageBuffer(sample) {
                    self.relay.receive(image, at: ProcessInfo.processInfo.systemUptime)
                }
                if sample != nil {
                    let now = CMClockGetTime(CMClockGetHostTimeClock())
                    self.input.stream.notifyScheduledOutputChanged(CMIOExtensionScheduledOutput(sequenceNumber: sequence,
                        hostTimeInNanoseconds: UInt64(CMTimeConvertScale(now, timescale: 1_000_000_000, method: .default).value)))
                }
                if more, error == nil { self.consume(remaining: remaining - 1) }
            }
        }
    }
}

final class CameraStreamSource: NSObject, CMIOExtensionStreamSource {
    private(set) var stream: CMIOExtensionStream!
    let formats: [CMIOExtensionStreamFormat]
    private weak var owner: CameraDeviceSource?
    private let direction: CMIOExtensionStream.Direction
    init(owner: CameraDeviceSource, direction: CMIOExtensionStream.Direction) throws {
        self.owner = owner; self.direction = direction
        formats = [CMIOExtensionStreamFormat(formatDescription: try VirtualCameraFormat.description(),
            maxFrameDuration: VirtualCameraFormat.frameDuration, minFrameDuration: VirtualCameraFormat.frameDuration, validFrameDurations: nil)]
        super.init()
        stream = CMIOExtensionStream(localizedName: direction == .source ? "Camera Live Video" : "Camera Live Input",
            streamID: direction == .source ? VirtualCameraFormat.sourceID : VirtualCameraFormat.sinkID,
            direction: direction, clockType: .hostTime, source: self)
    }
    var availableProperties: Set<CMIOExtensionProperty> {
        var properties: Set<CMIOExtensionProperty> = [.streamActiveFormatIndex, .streamFrameDuration]
        if direction == .sink { properties.formUnion([.streamSinkBufferQueueSize, .streamSinkBuffersRequiredForStartup, .streamSinkEndOfData]) }
        return properties
    }
    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let result = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) { result.activeFormatIndex = 0 }
        if properties.contains(.streamFrameDuration) { result.frameDuration = VirtualCameraFormat.frameDuration }
        if properties.contains(.streamSinkBufferQueueSize) { result.sinkBufferQueueSize = VirtualCameraFormat.queueSize }
        if properties.contains(.streamSinkBuffersRequiredForStartup) { result.sinkBuffersRequiredForStartup = 1 }
        if properties.contains(.streamSinkEndOfData) { result.sinkEndOfData = 0 }
        return result
    }
    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
        if let format = streamProperties.activeFormatIndex, format != 0 { throw VirtualCameraError.invalidFrame }
        if let duration = streamProperties.frameDuration, CMTimeCompare(duration, VirtualCameraFormat.frameDuration) != 0 {
            throw VirtualCameraError.invalidFrame
        }
    }
    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool { owner?.authorize(client, direction: direction) ?? false }
    func startStream() throws { try owner?.start(direction) }
    func stopStream() throws { owner?.stop(direction) }
}
