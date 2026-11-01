# Copylens

Extract text from any part of your macOS screen and copy it to the clipboard, like Text Extractor in PowerToys.

Press **⌘⇧T**, drag over some text and let go. The text is now in your clipboard. Press **Esc** or right-click to cancel.

## Build and run

Requires an Apple Silicon Mac, macOS 14 or later, Xcode and Rust.

```bash
./build.sh
open build/Copylens.app
```

To package a DMG, run `./dmg.sh`. The result is `build/Copylens-<version>.dmg`.

On your first capture, macOS asks for **Screen Recording** permission. Grant it in System Settings, then reopen the app.

When it runs from Applications, the app registers itself to launch at login the first time you open it. You can turn this off in the Copylens window. To open the window, use the menu bar icon or reopen the app from Applications.

## How it works

| Part | Role |
| --- | --- |
| `Sources/Copylens` (Swift) | Menu bar, window, hotkey, selection overlay, ScreenCaptureKit, Vision OCR, clipboard |
| `core` (Rust) | PP-OCRv5 fallback engine on ONNX Runtime (CPU), arranges OCR fragments into lines and paragraphs, NFC normalization |
| `Sources/CTextCore` | C header connecting Swift to Rust |
| `scripts/make-icon.swift` | Draws `Resources/AppIcon.icns` |

OCR runs entirely on your Mac, with two engines racing each other:

- **Vision** goes first. It takes about 0.2 seconds and reads both English and Vietnamese with tone marks.
- **PP-OCRv5** joins if Vision hasn't finished after 0.7 seconds or reports an error, because macOS occasionally recompiles Vision's model (`ANECompilerService`, about 33 seconds). This engine answers about 1.5 seconds after the capture and reads English and other Latin text only, without Vietnamese tone marks. The message shown after copying tells you when this happened.

## Testing

```bash
./fetch-onnxruntime.sh
(cd core && cargo test)
build/Copylens.app/Contents/MacOS/Copylens --ocr image.png        # OCR with Vision, no UI or permission needed
build/Copylens.app/Contents/MacOS/Copylens --ocr-fast image.png   # OCR with PP-OCRv5
```

## Limitations

- ⌘⇧T is a system-wide shortcut, so while the app runs it no longer reopens closed tabs in browsers. To change it, edit `Sources/Copylens/HotKey.swift`.
- A capture made while Vision is recompiling has no Vietnamese tone marks. Capture again after about 30 seconds to get them.
- Multi-column text gets merged across columns. Select one column at a time.

## Third-party components

- [ONNX Runtime](https://github.com/microsoft/onnxruntime) (MIT): `fetch-onnxruntime.sh` downloads the official release and verifies its SHA-256.
- PP-OCRv5 models from [PaddleOCR](https://github.com/PaddlePaddle/PaddleOCR) (Apache-2.0), converted to ONNX by [monkt/paddleocr-onnx](https://huggingface.co/monkt/paddleocr-onnx), in `core/models`.

## License

[MIT](LICENSE)
