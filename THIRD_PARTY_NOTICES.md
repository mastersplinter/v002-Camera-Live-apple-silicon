# Third-party software

Camera Live's application and library sources retain the original repository's BSD-style license in `LICENSE`. Native dependencies are built from the following pinned sources, not from the installed Camera Live application or an Intel binary.

| Component | Version / revision | License | Source |
| --- | --- | --- | --- |
| libgphoto2, including its PTP2 and USB port modules | 2.5.34 | LGPL-2.1-or-later (see upstream COPYING and individual source notices) | https://github.com/gphoto/libgphoto2/releases/tag/v2.5.34 |
| libusb | 1.0.30 | LGPL-2.1-or-later | https://github.com/libusb/libusb/releases/tag/v1.0.30 |
| libltdl (from GNU libtool) | 2.5.4 | LGPL-2.1-or-later | https://ftp.gnu.org/gnu/libtool/libtool-2.5.4.tar.gz |
| Syphon | f4761677a45b8034a3c2069ec0f3d2553da81fba | BSD-style, upstream License.txt | https://github.com/Syphon/Syphon-Framework/tree/f4761677a45b8034a3c2069ec0f3d2553da81fba |

The build also uses checksum-pinned pkgconf 2.5.1 (ISC license, https://distfiles.ariadne.space/pkgconf/pkgconf-2.5.1.tar.xz). It is a local build tool and is not included in the app.

`python3 scripts/build-dependencies.py` downloads checksum-verified archives into `.dependencies/src`, retains their source and license files, and builds shared libraries in `.dependencies/usr`. The packaged application includes license texts in `Contents/Resources/Licenses` and the Syphon framework's license in its Resources directory. Libraries remain dynamically linked and replaceable. Re-sign a modified local bundle with an ad-hoc identity after replacing a library.

Syphon build adaptation: `SyphonServerRendererMetal.m` is copied to a generated file, replacing the call that loads a precompiled Metal library with `newLibraryWithSource:options:error:` using the unmodified upstream shader and included type definitions. This permits builds with Apple's Command Line Tools, without downloading Xcode's separate Metal toolchain. Syphon's upstream OpenGL interoperability sources remain in the framework; Camera Live uses only its Metal API.

The camera and USB libraries are compiled without translations or optional JPEG/XML/EXIF dependencies. Only the PTP2 camera and libusb-1.0 transport plugins are packaged. Camera Live decodes live-view JPEGs using Apple's ImageIO and renders with Core Image / Metal.

Before distributing binary releases, include the corresponding dependency source archives (available in `.dependencies/src`) and these build scripts alongside the app to meet applicable source-distribution obligations. The local build is ad-hoc signed; it is not a notarized public release.
