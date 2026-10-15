import CoreMediaIO
import Foundation
import VirtualCameraShared

protocol VirtualCameraTransport: AnyObject {
    func start() throws
    func enqueue(_ sample: CMSampleBuffer) -> Bool
    func stop()
}

/// All methods are called on the publisher's serial queue. CMIO owns and releases
/// each retained sample after a successful enqueue; failed enqueues release here.
final class CMIOVirtualCameraTransport: VirtualCameraTransport {
    private var device: CMIODeviceID = 0
    private var stream: CMIOStreamID = 0
    private var buffers: CMSimpleQueue?

    static func isAvailable() -> Bool { deviceID() != nil }
    private static func ids(_ object: CMIOObjectID, selector: UInt32, scope: UInt32 = UInt32(kCMIOObjectPropertyScopeGlobal)) -> [CMIOObjectID] {
        var address = CMIOObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: UInt32(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr,
              size > 0, size % UInt32(MemoryLayout<CMIOObjectID>.stride) == 0 else { return [] }
        var result = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.stride)
        let status = result.withUnsafeMutableBytes { CMIOObjectGetPropertyData(object, &address, 0, nil, size, &size, $0.baseAddress) }
        return status == noErr ? Array(result.prefix(Int(size) / MemoryLayout<CMIOObjectID>.stride)) : []
    }
    private static func deviceID() -> CMIODeviceID? {
        ids(CMIOObjectID(kCMIOObjectSystemObject), selector: UInt32(kCMIOHardwarePropertyDevices)).first { device in
            var address = CMIOObjectPropertyAddress(mSelector: UInt32(kCMIODevicePropertyDeviceUID),
                mScope: UInt32(kCMIOObjectPropertyScopeGlobal), mElement: UInt32(kCMIOObjectPropertyElementMain))
            var uid: Unmanaged<CFString>?
            var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard CMIOObjectGetPropertyData(device, &address, 0, nil, size, &size, &uid) == noErr,
                  let uid else { return false }
            return (uid.takeRetainedValue() as String).caseInsensitiveCompare(VirtualCameraFormat.deviceID.uuidString) == .orderedSame
        }
    }

    func start() throws {
        stop()
        guard let device = Self.deviceID(), let stream = Self.ids(device, selector: UInt32(kCMIODevicePropertyStreams),
            scope: UInt32(kCMIODevicePropertyScopeOutput)).first else { throw VirtualCameraError.notInstalled }
        var queue: Unmanaged<CMSimpleQueue>?
        let queueStatus = CMIOStreamCopyBufferQueue(stream, nil, nil, &queue)
        guard queueStatus == noErr, let queue else { throw VirtualCameraError.operation("Open virtual-camera input", queueStatus) }
        let buffers = queue.takeRetainedValue()
        let status = CMIODeviceStartStream(device, stream)
        guard status == noErr else { throw VirtualCameraError.operation("Start virtual camera", status) }
        self.device = device; self.stream = stream; self.buffers = buffers
    }
    func enqueue(_ sample: CMSampleBuffer) -> Bool {
        guard let buffers, CMSimpleQueueGetCount(buffers) < CMSimpleQueueGetCapacity(buffers) else { return false }
        let retained = Unmanaged.passRetained(sample)
        let result = CMSimpleQueueEnqueue(buffers, element: retained.toOpaque())
        if result != noErr { retained.release() }
        return result == noErr
    }
    func stop() {
        if device != 0, stream != 0 { _ = CMIODeviceStopStream(device, stream) }
        // StopStream synchronizes the stream before any remaining owned samples
        // are drained. Do not reuse old queues after restart or removal.
        if let buffers {
            while let pointer = CMSimpleQueueDequeue(buffers) {
                Unmanaged<CMSampleBuffer>.fromOpaque(pointer).release()
            }
        }
        buffers = nil; device = 0; stream = 0
    }
    deinit { stop() }
}
