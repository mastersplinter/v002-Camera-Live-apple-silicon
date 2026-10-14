# Camera support

The primary target for this rewrite is the **Canon EOS 550D**, also sold as the **EOS Rebel T2i / EOS Kiss X4**.

The pinned libgphoto2 2.5.34 PTP2 driver lists the 550D's USB vendor/product IDs (`04a9:31ea`) with preview capture capability. The [upstream supported-camera list](https://gphoto.github.io/proj/libgphoto2/support/) and [remote-control documentation](https://gphoto.sourceforge.io/doc/remote/) list its live-view support. This is driver support evidence, not a claim that this rewrite has passed a physical 550D test.

The application includes libgphoto2's PTP2 driver and libusb-1.0 transport. Other Canon, Nikon, Sony and similar PTP cameras may work when that driver advertises live-view capture. No blanket compatibility guarantee is made for all cameras in the original EDSDK camera list. Opening a camera without preview capability returns an actionable error.

USB live-view JPEG dimensions, frame rate, autofocus behaviour and camera mode requirements vary by camera. The camera controls exposure, focus and image dimensions; the app does not change exposure settings, take stills, save or delete camera files, or record movies.

Connection problems:

- Close EOS Utility and all other software that may claim the camera.
- Use a USB data cable, not HDMI or a charge-only cable.
- Turn the camera off and on, then reconnect if a previous app left its session locked.
- If no live-view images arrive, enable Live View in the camera's settings and try a normal still-photo mode.
- The app reports USB claim/busy errors instead of killing macOS camera services or other applications.
- In ambiguous reconnections involving two identical cameras, select the desired camera manually.

See [VALIDATION.md](VALIDATION.md) for the physical-camera acceptance checklist and the current validation record.
