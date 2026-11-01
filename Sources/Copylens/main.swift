import AppKit

// `Copylens --ocr <image>` prints the recognized text, without any UI or permission.
// `--ocr-fast` does the same with the CPU engine. With `-` as the image they read stdin,
// which is how the app runs its OCR helpers.
let arguments = CommandLine.arguments
if arguments.count == 3, arguments[1] == "--ocr" || arguments[1] == "--ocr-fast" {
    let source = arguments[2] == "-"
        ? NSImage(data: FileHandle.standardInput.readDataToEndOfFile())
        : NSImage(contentsOfFile: arguments[2])
    guard let image = source?.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let text = arguments[1] == "--ocr" ? try? OCR.recognize(image) : OCR.recognizeFast(image) else {
        FileHandle.standardError.write(Data("OCR failed for \(arguments[2])\n".utf8))
        exit(1)
    }
    print(text)
    exit(0)
}

// A helper that dies early must not take the app down when we write to its stdin.
signal(SIGPIPE, SIG_IGN)

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
