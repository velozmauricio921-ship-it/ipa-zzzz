POC preload.dylib

Build a simple `.dylib` that embeds encrypted `.3105` blobs and exposes a small C API.

Example build command (jailbroken device / ad-hoc use):

```sh
clang -dynamiclib -arch arm64 -o preload.dylib preload.c -fvisibility=hidden
```

Then copy `preload.dylib` into the app bundle root (next to the main executable) and name it `preload.dylib`.
On the device, the app will attempt to load `preload.dylib` from the bundle and call its API to copy embedded files into the `Preloaded` cache.

For real use:
- Replace the example byte array in `preload.c` with your encrypted `.3105` bytes.
- Optionally embed multiple files and directory names.
- Use `ldid` or codesign to sign the dylib for device usage as required.
