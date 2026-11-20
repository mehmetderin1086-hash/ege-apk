# Third-party notices — Ritim 1.6

Ritim uses the following open-source components. Their respective licenses apply to their code. Apple SDK frameworks are supplied by the operating system and Xcode.

## LAME 4.0

Project: https://lame.sourceforge.io/
Source archive: https://downloads.sourceforge.net/project/lame/lame/4.0/lame-4.0.tar.gz

LAME is copyright The LAME Project and the additional contributors named in its source files. The included encoder sources are licensed under the GNU Library General Public License, version 2 or later. The complete license is included at [Vendor/Lame/COPYING](Vendor/Lame/COPYING); upstream integration guidance is [Vendor/Lame/LICENSE](Vendor/Lame/LICENSE).

Ritim includes the encoder source files and headers it builds, the local SwiftPM package, and configuration in [Vendor/Lame](Vendor/Lame). The optional decoder and command-line frontend are not linked. [INTEGRATION.md](Vendor/Lame/INTEGRATION.md) records the Apple configuration and rebuild instructions; [UPSTREAM.sha256](Vendor/Lame/UPSTREAM.sha256) identifies the original source archive. Upstream library source files retain their copyright and license headers. The supplied application source can be rebuilt with a modified LAME library using Xcode; no proprietary prebuilt LAME binary is required.

## YouTubeKit

Project: https://github.com/alexeichhorn/YouTubeKit
Pinned revision: `89854c93207ad0d2b3d78d6f1aea24595ca66552`
Source and license: https://github.com/alexeichhorn/YouTubeKit/tree/89854c93207ad0d2b3d78d6f1aea24595ca66552

Swift Package Manager resolves this exact revision. Ritim uses the local extraction method only. The package includes the JavaScript resources listed below; their bytes are fixed by the same YouTubeKit revision, rather than fetched dynamically as separate app dependencies.

## YouTubeKit MIT license

Upstream license: https://github.com/alexeichhorn/YouTubeKit/blob/89854c93207ad0d2b3d78d6f1aea24595ca66552/LICENSE

```text
MIT License

Copyright (c) 2022 Alexander Eichhorn

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Meriyah — ISC

Upstream license: https://github.com/meriyah/meriyah/blob/main/LICENSE.md

```text
ISC License

Copyright (c) 2019 and later, KFlash and others.

Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
```

## Astring — MIT

Upstream license: https://github.com/davidbonnet/astring/blob/main/LICENSE

```text
Copyright (c) 2015, David Bonnet <david@bonnet.cc>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

## yt-dlp EJS — Unlicense

Upstream license: https://github.com/yt-dlp/ejs/blob/main/LICENSE

```text
This is free and unencumbered software released into the public domain.

Anyone is free to copy, modify, publish, use, compile, sell, or
distribute this software, either in source code form or as a compiled
binary, for any purpose, commercial or non-commercial, and by any
means.

In jurisdictions that recognize copyright laws, the author or authors
of this software dedicate any and all copyright interest in the
software to the public domain. We make this dedication for the benefit
of the public at large and to the detriment of our heirs and
successors. We intend this dedication to be an overt act of
relinquishment in perpetuity of all present and future rights to this
software under copyright law.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

For more information, please refer to <https://unlicense.org/>
```
