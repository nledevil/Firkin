#!/usr/bin/env bash
# Runs the test suite with either full Xcode or just the Command Line Tools.
#
# CLT ships Testing.framework and lib_TestingInterop.dylib outside the default
# search paths, so `swift test` fails with "no such module 'Testing'" on
# CLT-only machines unless we point the compiler and linker at them.
set -euo pipefail
cd "$(dirname "$0")/.."

DEV_DIR="$(xcode-select -p)"
EXTRA_ARGS=()
if [[ "$DEV_DIR" == *CommandLineTools* ]]; then
  FRAMEWORKS="$DEV_DIR/Library/Developer/Frameworks"
  INTEROP_LIB="$DEV_DIR/Library/Developer/usr/lib"
  EXTRA_ARGS=(
    -Xswiftc "-F$FRAMEWORKS"
    -Xlinker "-F$FRAMEWORKS"
    -Xlinker -rpath -Xlinker "$FRAMEWORKS"
    -Xlinker -rpath -Xlinker "$INTEROP_LIB"
  )
fi

# The ${arr[@]+...} form keeps macOS bash 3.2 happy with empty arrays.
exec swift test ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"} "$@"
