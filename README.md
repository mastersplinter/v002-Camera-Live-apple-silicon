# Camera Live for Apple Silicon

A native arm64 rewrite of v002 Camera Live. It turns a USB DSLR's live view into a **Syphon Metal video feed** for compatible creative/video applications. The target camera is the **Canon EOS 550D / Rebel T2i / Kiss X4**.

The app and reusable `CameraLiveCore` Swift library replace the original Objective-C application, Canon EDSDK integration, Intel libjpeg-turbo dependency, and OpenGL video pipeline. Camera access uses a locally built arm64 libgphoto2; JPEG decoding uses ImageIO; Core Image and Metal render into shared IOSurface-backed textures for Syphon. Rosetta and Homebrew are not required to run the built app.

## Requirements

- Apple Silicon Mac, macOS 13 or newer.
- Swift 6.0 or newer, Python 3, and Apple's Command Line Tools (or Xcode) to build.
- Internet access for the first dependency build. Source downloads are pinned by version/revision and SHA-256.
- A USB PTP camera with libgphoto2 live-view support. See [camera support](CAMERAS.md).

## Build and run

From this repository:

```sh
python3 scripts/build-app.py
open "dist/Camera Live.app"
```

The first build compiles libusb, libltdl, libgphoto2 and Syphon locally. Subsequent builds reuse them. The Swift wrapper also avoids stale manifest interfaces on some upgraded Command Line Tools installations without changing system files. Detailed dependency build logs are in `.dependencies/logs`. Everything is contained in the checkout; no system packages are installed. Use a checkout path without spaces for the Autotools dependency build.

The result is a relocatable, ad-hoc-signed application at `dist/Camera Live.app`, with camera drivers and all third-party libraries embedded. It can be copied to Applications after testing. A Developer ID signature and notarization are separate release steps.

## Use with the Canon 550D

1. Connect the camera's USB port directly to the Mac with a data-capable cable and turn the camera on.
2. Quit EOS Utility, Photos, Image Capture, and any other app using the camera. Only one app can own the USB camera session.
3. Open Camera Live and select the Canon in the camera list. Live view starts automatically.
4. In your Syphon receiver, choose the server named **Canon EOS 550D** (the exact name follows the camera's reported model).
5. Use **Stop** before disconnecting when practical. Unexpected disconnects stop the session; reconnecting the same model resumes it when it is unambiguous.

The preview resolution and frame rate come from the camera's live-view output, not its movie recording settings. A 1080p movie setting does not imply a 1080p USB live-view feed. Camera Live publishes video only, with no audio, recording, or shutter capture.

The preview presents the newest decoded frame on a display-synchronised Metal view, independently of the status readout. It does not interpolate motion or generate extra camera frames. Automatic USB discovery pauses during capture to avoid interrupting the feed; use **Refresh cameras** to look for another camera while streaming.

This is a Syphon server, not a system webcam driver. Video-call software needs a separate compatible virtual-camera/Syphon receiver workflow.

## Validation and diagnostics

```sh
python3 scripts/build-dependencies.py
python3 scripts/swift.py test --disable-sandbox --disable-xctest
python3 scripts/swift.py run --disable-sandbox camera-live-diagnostics --list
python3 scripts/swift.py run --disable-sandbox camera-live-diagnostics --capture
```

`--capture [usb:PORT]` reads and publishes the selected camera for 20 seconds, then closes its USB session. This is an actual hardware check, distinct from the automated tests.

Add `--preview` to `--capture` or `--test-pattern` to open the same Metal preview used by the app and measure actual drawable presentation times. Keep the diagnostic window visible. It fails if fewer than 80% of delivered frames reach the screen. In test-pattern mode it also verifies top/bottom colours from the actual preview drawable, separately from the Syphon texture. Timing reports exclude the first two seconds of startup and include median, 95th/99th percentile and maximum inter-frame gaps. `--receive SERVER --measure` measures a separate Syphon receiver for 20 seconds.

Test the video pipeline and Syphon independently of a camera by running these in separate terminals:

```sh
"dist/Camera Live.app/Contents/MacOS/camera-live-diagnostics" --test-pattern "Camera Live Test"
"dist/Camera Live.app/Contents/MacOS/camera-live-diagnostics" --receive "Camera Live Test" --verify-pattern
```

The producer publishes for 25 seconds; the receiver must discover it, receive at least ten Metal frames at two resolutions, and verify their orientation and colour channels. The same check is automated by `python3 scripts/smoke-test.py`. Run this in a logged-in macOS desktop session with a GPU. A headless runner can run the logic/image tests and package checks, but may not have a usable Metal device or Syphon desktop messaging.

Automated tests cover JPEG validation and resolution changes, bounded frame buffering, rapid camera changes, stale callbacks, disconnect/reconnect, sleep/wake and orderly shutdown. Physical 550D compatibility remains subject to the hardware acceptance checks in [VALIDATION.md](VALIDATION.md).

## Library and architecture

Open `Package.swift` in Xcode, or use Swift Package Manager. Build the native dependencies before resolving/building the package. The local package uses explicit include/link paths for those locally built C/Objective-C libraries.

- `CameraCatalog` discovers PTP USB cameras and creates `CameraSource` instances.
- `CameraSource` produces JPEG frames and errors; `stop` completes after USB cleanup.
- `JPEGDecoder` validates compressed data and dimensions before decoding with ImageIO.
- `MetalFramePipeline` maintains at most one frame in flight plus one pending frame, dropping stale queued frames. It publishes valid frames to Syphon and reports dimensions, rate and client presence.
- `PreviewFrames` stores one latest decoded image. `CameraPreviewView` samples it at display refresh, with at most two GPU submissions in flight and no per-frame SwiftUI updates. Statistics refresh separately at up to 5 Hz.
- `CameraController` serializes lifecycle transitions, selection persistence and sleep/reconnect handling. All USB operations run on one worker queue; decoding and Syphon rendering run on another. UI state and preview presentation are isolated to the main thread.

The saved selection uses model plus USB address. After an address change, automatic recovery is allowed only for a unique matching model. It deliberately waits for a selection when multiple identical models make recovery ambiguous. The old Canon SDK's saved serial-number preference is not migrated.

The new Swift API is a source-level redesign; it is not an ABI-compatible replacement for the old `SyPCamera` Objective-C classes. See [third-party notices](THIRD_PARTY_NOTICES.md) for dependency versions, licenses and the documented Syphon build adaptation.
