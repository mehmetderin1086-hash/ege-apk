#!/bin/zsh
set -e
MOTOR_ROOT="$PROJECT_DIR/Vendor/KepceMotor"
source "$MOTOR_ROOT/Python.xcframework/build/utils.sh"
install_stdlib "Vendor/KepceMotor/Python.xcframework"
PYLIB="$CODESIGNING_FOLDER_PATH/python/lib/$(ls -1 "$CODESIGNING_FOLDER_PATH/python/lib" | grep -E '^python3\.[0-9]+$')"
rm -rf "$PYLIB"/{test,idlelib,tkinter,turtledemo,ensurepip,pydoc_data,_pyrepl,lib2to3}
rm -rf "$PYLIB"/lib-dynload/{_test*,_ctypes_test*,_tkinter*,_xxtest*,xx*}.so 2>/dev/null || true
process_dylibs "Vendor/KepceMotor/Python.xcframework" "python/lib/$(basename "$PYLIB")/lib-dynload"
rsync -a --delete --exclude '__pycache__' "$MOTOR_ROOT/app_packages/" "$CODESIGNING_FOLDER_PATH/app_packages/"
rsync -a --delete --exclude '__pycache__' "$MOTOR_ROOT/python/" "$CODESIGNING_FOLDER_PATH/app/"
