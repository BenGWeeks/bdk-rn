#!/usr/bin/env bash
# Rebuild BDK 0.30.0's native code without changing its Kotlin/UniFFI API.
# Requires Linux x86_64, Rust 1.77.2, Python 3, git, curl, binutils, NDK r27.1.
set -euo pipefail
: "${ANDROID_NDK_ROOT:?Set ANDROID_NDK_ROOT to NDK 27.1.12297006}"
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d -t bdk16kb.XXXXXX)
trap 'rm -rf "$work"' EXIT
source_commit=599bd8ff06d366ae53233a4c8f54e217d92dee5a
original_sha=b1157894596ab5e792306b305e308ceea14c21d137cf7b7f485415d46833f00f
ndk_bin="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin"
rustup toolchain install 1.77.2 --profile minimal
rustup target add --toolchain 1.77.2 aarch64-linux-android x86_64-linux-android armv7-linux-androideabi
git clone --quiet https://github.com/bitcoindevkit/bdk-ffi.git "$work/source"
git -C "$work/source" checkout --quiet "$source_commit"
curl --fail --location --silent --show-error https://repo.maven.apache.org/maven2/org/bitcoindevkit/bdk-android/0.30.0/bdk-android-0.30.0.aar -o "$work/original.aar"
echo "$original_sha  $work/original.aar" | sha256sum --check
export RUSTFLAGS='-C link-arg=-Wl,-z,max-page-size=16384 -C link-arg=-Wl,-z,common-page-size=16384'
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-2}"
for spec in 'aarch64-linux-android:aarch64-linux-android21' 'x86_64-linux-android:x86_64-linux-android21' 'armv7-linux-androideabi:armv7a-linux-androideabi21'; do
  target=${spec%%:*}
  clang=${spec#*:}
  key=${target//-/_}
  upper=${key^^}
  # Rust's -nodefaultlibs can omit helpers used by NDK-compiled SQLite on x86_64.
  # Link the matching NDK compiler runtime explicitly and reject unresolved symbols.
  builtins=$($ndk_bin/$clang-clang --print-libgcc-file-name)
  export RUSTFLAGS="-C link-arg=-Wl,-z,max-page-size=16384 -C link-arg=-Wl,-z,common-page-size=16384 -C link-arg=$builtins -C link-arg=-Wl,--no-undefined"
  (cd "$work/source" && env "CARGO_TARGET_${upper}_LINKER=$ndk_bin/$clang-clang" "CC_$key=$ndk_bin/$clang-clang" "AR_$key=$ndk_bin/llvm-ar" cargo +1.77.2 build --locked --lib --profile release-smaller --target "$target")
done
python3 "$root/scripts/package-android-16kb.py" "$work/original.aar" "$work/source/target" "$root/android/maven/org/bitcoindevkit/bdk-android/0.30.0-16kb.1/bdk-android-0.30.0-16kb.1.aar"
