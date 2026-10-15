## 2.4.0 macOS 26 interface refinements

- Require macOS 26 or newer for the app and camera extension; remove the older inspector fallback and update the native CI runner.
- Use the standard system title bar and window buttons, automatic toolbar styling and a native Liquid Glass primary action.
- Hide the full-width toolbar backdrop while retaining the system glass controls and native inspector.
- Correct the linked SDK version supplied by the CLT build so system controls receive current styling instead of legacy compatibility styling.
- Remove the crop toolbar button and the entire bottom status bar. Camera and output details remain in the inspector.
- Put Stream before Framing and open Stream whenever the inspector is reopened.
- Remove the requested canvas, resolution-negotiation and Syphon explanatory text from the interface.

## 2.3.0 Focus interface

- Put the live preview first, with a native macOS toolbar and a camera sidebar that can be hidden.
- Keep Framing beside the preview in an inspector, with Stream Details available in the same pane.
- Bring Start/Stop Virtual Camera into the toolbar and show clear live, standby, approval and error states.
- Use native system materials, semantic colours, accessible control labels and keyboard shortcuts; adopt Liquid Glass on macOS 26 while retaining macOS 13 support.
- Retain the 2.2.0/build 8 camera extension and reuse it when the enabled version already matches, avoiding an unnecessary extension replacement for this UI update.

## 2.2.0 Canvas and framing

- Choose a 1280 × 720 or 1920 × 1080 canvas from the Framing toolbar control.
- Fill the canvas by default with a centred, aspect-preserving crop, removing added side borders.
- Adjust crop zoom and horizontal/vertical position, reset framing, and retain settings between launches.
- Show the composed crop in the Metal preview while preserving the original Syphon feed.
- Advertise both camera-extension formats and resize composed frames when a video app requests a different resolution.
- Validate crop geometry/pixels, saved settings, live canvas changes, and both output sizes.

## 2.1.1 Virtual camera connection correction

- Register the input queue callback required by Core Media I/O, fixing “Open virtual-camera input failed (0)” after extension approval. Unregister it when stopping or when stream startup fails.
- Check the bundled extension on the first start after launching the signed app, so an enabled older extension can be replaced by an update.
- Defer video-device discovery until extension activation finishes, avoiding a connection to the retired extension during an update.
- Authenticate video senders using their running code signature, the extension's signing team, and the two allowed app identifiers, without depending on CMIO's optional signing-ID field. Log the decision once per connection with readable diagnostic fields.
- Validate sender signatures from the running process, so the camera extension does not need filesystem access to the host app.

## 2.1.0 Virtual camera integration (activation testing pending)

- Compile the app icon with Apple's icon utility and share it with the camera extension for consistent System Settings artwork.
- Add a Core Media IO camera extension for direct camera selection in Zoom and other video apps, with activation, start/stop and removal controls.
- Deliver aspect-preserving 720p video at 30 Hz with bounded buffers and a standby frame when camera input stops.
- Package the extension and support Developer ID signing, provisioning validation and notarization. The default ad-hoc build continues to support preview and Syphon; extension activation requires the Apple setup in VIRTUAL_CAMERA.md.
- Add format, stale-frame and publisher lifecycle tests, GPU/CPU orientation checks, signing validation tests and an installed-extension AVFoundation diagnostic.

## 2.0.0 Apple Silicon rewrite

- Correct the Metal preview's inverted vertical orientation and verify pixels from the actual display drawable as well as the separate Syphon receiver.
- Fix the preview's accidental 5 fps limit: use a display-synchronised Metal view with full-rate frames, bounded buffering and independent status updates.
- Avoid periodic USB discovery during active capture; report a recent frame rate and add camera, Syphon and on-screen frame-pacing diagnostics.
- Replace the legacy application with a Swift package, reusable CameraLiveCore library and SwiftUI macOS app.
- Build the camera driver and all embedded dependencies for arm64; target macOS 13 and newer.
- Replace Canon EDSDK with libgphoto2's PTP2 live-view backend, targeting the Canon EOS 550D.
- Replace the OpenGL/turbojpeg video path with ImageIO, Core Image, shared IOSurfaces and Syphon Metal.
- Add bounded frame buffering, explicit session cleanup, reconnect and sleep/wake handling, a live preview and stream statistics.
- Add automated lifecycle/image tests, cross-process Syphon diagnostics and relocatable app packaging with architecture/signature audits.
- Remove the obsolete Xcode project and framework placeholders; open Package.swift for development.

## 9

* Update to latest Canon SDK (3.8.0), adding support for more cameras

## 8

* Avoid another issue affecting some cameras with stored images on macOS High Sierra

## 7

* Avoid an issue which caused crashes on macOS High Sierra when a camera had stored images
* Add an icon

## 6

* Update to latest Canon SDK (3.6.1), adding support for more cameras
* Fix issues which caused the application to hang or crash on macOS Sierra

## 5

* Update to latest Canon SDK and libjpeg-turbo, adding support for recent Canon cameras

## 4

* Fix issue which caused delay under heavy load

## 3

* Add a basic status display
* Fix issue which caused an initial garbage frame to be emitted when a camera started
* Fix issue which caused an active camera to become unresponsive after system sleep
* Suspend system "idle" sleep while a camera is active

## 2

* Prevent active cameras from becoming unresponsive after 30 minutes
* Improve performance

## 1

* Initial public release
