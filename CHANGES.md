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
