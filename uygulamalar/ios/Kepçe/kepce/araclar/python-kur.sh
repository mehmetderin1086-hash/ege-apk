#!/bin/zsh
# Xcode derleme adımı: Python standart kitaplığını, yt-dlp paketlerini ve motor kodunu
# uygulama paketine koyar; ikili modülleri iOS'un yükleyebileceği çerçevelere çevirir.
set -e
source "$PROJECT_DIR/Bagimliliklar/Python.xcframework/build/utils.sh"
install_stdlib Bagimliliklar/Python.xcframework
PYLIB="$CODESIGNING_FOLDER_PATH/python/lib/$(ls -1 "$CODESIGNING_FOLDER_PATH/python/lib" | grep -E '^python3\.[0-9]+$')"
# Uygulamada gerekmeyen büyük parçalar (≈45 MB).
rm -rf "$PYLIB"/{test,idlelib,tkinter,turtledemo,ensurepip,pydoc_data,_pyrepl,lib2to3}
rm -rf "$PYLIB"/lib-dynload/{_test*,_ctypes_test*,_tkinter*,_xxtest*,xx*}.so 2>/dev/null || true
process_dylibs Bagimliliklar/Python.xcframework "python/lib/$(basename "$PYLIB")/lib-dynload"
rsync -a --delete --exclude '__pycache__' "$PROJECT_DIR/Bagimliliklar/app_packages/" "$CODESIGNING_FOLDER_PATH/app_packages/"
rsync -a --delete --exclude '__pycache__' "$PROJECT_DIR/python/" "$CODESIGNING_FOLDER_PATH/app/"
