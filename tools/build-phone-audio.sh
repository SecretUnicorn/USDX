#!/bin/sh
# Builds the remote microphone transport (native/phone-audio) and puts it where
# the game looks for it: next to the binary in game/, and inside the macOS
# bundle when one has been built.
set -e

root=$(cd "$(dirname "$0")/.." && pwd)
build=${BUILD_DIR:-$root/build/phone-audio}

# Homebrew's openssl is not in the default search path, and CMake 4 refuses the
# older minimum version libdatachannel asks for.
openssl_hint=
for candidate in "$OPENSSL_ROOT_DIR" /opt/homebrew/opt/openssl@3 /usr/local/opt/openssl@3; do
  if [ -n "$candidate" ] && [ -d "$candidate" ]; then
    openssl_hint="-DOPENSSL_ROOT_DIR=$candidate"
    break
  fi
done

cmake -S "$root/native/phone-audio" -B "$build" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DBUILD_TESTING=${BUILD_TESTING:-OFF} $openssl_hint
cmake --build "$build" --parallel "${JOBS:-4}"

name=libusce-phone-audio.so
case "$(uname -s)" in
  Darwin) name=libusce-phone-audio.dylib ;;
  MINGW*|MSYS*|CYGWIN*) name=usce-phone-audio.dll ;;
esac

library=$(find "$build" -maxdepth 2 -name "$name" -type f | head -n 1)
if [ -z "$library" ]; then
  echo "built, but $name was not found under $build" >&2
  exit 1
fi

cp "$library" "$root/game/$name"
echo "installed game/$name"

bundle="$root/UltraStar Deluxe.app/Contents/MacOS"
if [ -d "$bundle" ]; then
  cp "$library" "$bundle/$name"
  echo "installed into the app bundle"
fi
