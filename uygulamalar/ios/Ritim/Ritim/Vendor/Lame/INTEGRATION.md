# LAME in Ritim

Ritim builds the MP3 encoder directly from the unmodified upstream LAME 4.0
library C and header files. No prebuilt or remotely updated code is executed.
AVFoundation decodes the audio; the optional LAME decoder and command line
frontend are not included. Each conversion owns an independent encoder.

Upstream: https://lame.sourceforge.io/  
Source: https://downloads.sourceforge.net/project/lame/lame/4.0/lame-4.0.tar.gz

`UPSTREAM.sha256` records the downloaded source archive. `COPYING`, `LICENSE`,
and source copyright headers retain upstream license and attribution. LAME is LGPL 2 or later;
the complete Ritim source distribution includes the library sources and build
configuration so the application can be rebuilt with a modified library.

`Sources/CLame/config.h` was produced by upstream configure on Apple arm64
with frontend, decoder, analyzer hooks, NASM, and CPML disabled. It uses the
portable C implementation, standard Darwin headers, and 64-bit Apple types.
The configuration explicitly undefines `DEBUG` to prevent Xcode's application
debug flag from enabling LAME's per-frame diagnostic logging.
No configure/build tools are required on an iPhone; SwiftPM compiles the
bundled source at application build time.

Rebuild: add the local package `Vendor/Lame` and product `CLame` to the
application target, then build using Xcode 27.1 or later. Both device and
simulator builds compile the source for the selected SDK.
