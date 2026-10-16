// Native preview resource fixture. profile-preview.py compiles it with the
// current core and the original preview class from the requested baseline commit.
// This measures preview visibility, not USB capture or whole-app resource use.
import AppKit
import CameraLiveCore
import CoreImage
import MetalKit
import VirtualCameraShared

final class Counter {
 let lock = NSLock(); var value = 0
 func increment() { lock.lock(); value += 1; lock.unlock() }
 func read() -> Int { lock.lock(); defer { lock.unlock() }; return value }
}
@main struct Review {
 static func main() throws {
  let app = NSApplication.shared
  app.setActivationPolicy(.regular)
  let frames = PreviewFrames(), presented = Counter(), rendered = Counter(), produced = Counter()
  let view: MTKView
  if CommandLine.arguments.contains("--baseline") {
   let preview = try BaselineCameraPreviewView(frames: frames)
   preview.framing = VideoFraming(canvas: .hd1080, zoom: 1.4)
   preview.didPresent = { if $0 > 0 { presented.increment() } }
   preview.inspectDrawable = { _, buffer in buffer.addCompletedHandler { _ in rendered.increment() } }
   view = preview
  } else {
   let preview = try CameraPreviewView(frames: frames)
   preview.framing = VideoFraming(canvas: .hd1080, zoom: 1.4)
   preview.didPresent = { if $0 > 0 { presented.increment() } }
   preview.inspectDrawable = { _, buffer in buffer.addCompletedHandler { _ in rendered.increment() } }
   view = preview
  }
  let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 960, height: 640), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false; window.level = .floating
  window.title = "Camera Live — preview resource check"
  window.contentView = view; window.makeKeyAndOrderFront(nil)
  app.finishLaunching(); app.activate(ignoringOtherApps: true)
  let bitmap = CGContext(data: nil, width: 1056, height: 704, bitsPerComponent: 8, bytesPerRow: 1056*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
  bitmap.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); bitmap.fill(CGRect(x: 0,y: 0,width: 1056,height: 704))
  var marker = 0
  let feeder = DispatchSource.makeTimerSource(queue: DispatchQueue(label:"preview-input"))
  feeder.schedule(deadline:.now(),repeating:.nanoseconds(1_000_000_000/30))
  feeder.setEventHandler {
   autoreleasepool {
    bitmap.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); bitmap.fill(CGRect(x: 0,y: 0,width: 1056,height: 704))
    bitmap.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1)); bitmap.fill(CGRect(x: 0,y: 352,width: 1056,height: 352))
    bitmap.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1)); bitmap.fill(CGRect(x: marker % 1024,y: 320,width: 32,height: 64))
    frames.submit(bitmap.makeImage()!); marker += 8; produced.increment()
   }
  }
  feeder.resume()
  var hiddenRenderCount = 0, restoredPresentationCount = 0
  var finished = false
  func phase(_ name: String) {
   let data = try! JSONSerialization.data(withJSONObject: ["phase":name,"uptime_seconds":ProcessInfo.processInfo.systemUptime,"renders":rendered.read(),"presentations":presented.read(),"produced":produced.read()],options:[.sortedKeys])
   FileHandle.standardOutput.write(data + Data([10]))
  }
  func require(_ value: Bool, _ message: String) {
   if !value { FileHandle.standardError.write(Data((message + "\n").utf8)); exit(1) }
  }
  phase("visible")
  DispatchQueue.main.asyncAfter(deadline:.now()+12) {
   require(presented.read() > 300,"Initial stream: produced=\(produced.read()), rendered=\(rendered.read()), presented=\(presented.read())")
   window.orderOut(nil); phase("hidden-warm")
  }
  DispatchQueue.main.asyncAfter(deadline:.now()+18) {
   require(!window.occlusionState.contains(.visible),"Window is still visible")
   hiddenRenderCount = rendered.read(); phase("hidden")
  }
  DispatchQueue.main.asyncAfter(deadline:.now()+26) {
   if !CommandLine.arguments.contains("--baseline") { require(rendered.read() == hiddenRenderCount,"Hidden preview submitted work") }
   restoredPresentationCount = presented.read()
   window.makeKeyAndOrderFront(nil); phase("restored")
  }
  DispatchQueue.main.asyncAfter(deadline:.now()+38) {
   require(presented.read()-restoredPresentationCount > 300,"Restored stream: rendered=\(rendered.read()), presented=\(presented.read()-restoredPresentationCount)")
   feeder.cancel(); frames.close()
   if let preview = view as? CameraPreviewView { preview.stopDisplaying() }
   else { view.isPaused = true }
   phase("stopped")
  }
  DispatchQueue.main.asyncAfter(deadline:.now()+46) {
   print("PASS: visible/restored stream presentation; hidden rendering " +
    (CommandLine.arguments.contains("--baseline") ? "recorded for original preview" : "suppressed for optimized preview"))
   finished = true
  }
  let deadline = Date().addingTimeInterval(55)
  while !finished && Date() < deadline {
   autoreleasepool {
    if let event = app.nextEvent(matching:.any,until:Date().addingTimeInterval(0.02),inMode:.default,dequeue:true) { app.sendEvent(event) }
    app.updateWindows()
   }
  }
  require(finished,"Visibility diagnostic timed out")
  window.close()
 }
}
