# BDK Android 0.30.0, rebuilt for 16 KB memory pages

This local Maven repository supplies `org.bitcoindevkit:bdk-android:0.30.0-16kb.1`.
It retains the exact Kotlin classes, resources and dependency list from Maven
Central's 0.30.0 AAR. Only its three `libbdkffi.so` binaries are replaced.
The bridge also requires JNA 5.17.0, whose Android dispatch binaries support
16 KB pages on arm64 and x86_64. The iOS SDK and JavaScript API are unchanged.

Native source: https://github.com/bitcoindevkit/bdk-ffi/tree/599bd8ff06d366ae53233a4c8f54e217d92dee5a
(v0.30.0). Cargo dependencies come from that revision's unchanged `Cargo.lock`.
Toolchain: Rust 1.77.2, Android NDK 27.1.12297006, Android API 21.
Both maximum and common page-size linker flags are set to 16384; RELRO is checked.
The matching NDK compiler runtime is explicitly linked, and `--no-undefined`
rejects missing compiler helpers at build time (including x86_64 float128 helpers).

Rebuild on Linux x86_64 with Rust/rustup, Python 3, git, curl and binutils:

```sh
ANDROID_NDK_ROOT=/path/to/ndk/27.1.12297006 bash scripts/rebuild-android-16kb.sh
```

The packaging script verifies the upstream AAR checksum, every rebuilt ELF's
LOAD/RELRO alignment and byte-for-byte preservation of all other AAR entries.
The adjacent `.aar.sha256` records the committed artifact checksum. The native
binaries are distributed under the upstream MIT or Apache-2.0 licences here.

When updating BDK, update the source revision, upstream AAR checksum, Maven
version/POM and React Native bridge together. Re-run the full Android native
wallet smoke test on both 4 KB and 16 KB systems before consuming a new build.
