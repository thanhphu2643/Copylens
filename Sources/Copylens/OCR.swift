import AppKit
import CTextCore
import Vision

enum OCR {
    enum Failure: LocalizedError {
        case helperFailed
        var errorDescription: String? { "Không đọc được text, hãy thử lại" }
    }

    struct Result {
        let text: String
        /// The CPU engine answered, so Vietnamese tone marks are missing.
        let usedFallback: Bool
    }

    /// Vision is the fast, accurate path but sometimes stalls for 30s+ while macOS recompiles
    /// its model. If it hasn't answered by `fallbackDelay`, the CPU engine races it.
    ///
    /// Both run in short-lived copies of this executable. Vision's model can also fail to
    /// reload after sitting idle and then stays broken for the life of the process, so a
    /// long-running menu bar app must not host it.
    static func recognizeRacing(_ image: CGImage) async throws -> Result {
        guard let png = encodePNG(image) else { throw Failure.helperFailed }
        return try await withCheckedThrowingContinuation { continuation in
            Race(png: png, continuation: continuation).start()
        }
    }

    private static let fallbackDelay: TimeInterval = 0.7

    private static func encodePNG(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// Resumes the continuation once, with the first answer or after both engines failed.
    private final class Race {
        private let png: Data
        private let continuation: CheckedContinuation<Result, Error>
        private let lock = NSLock()
        private var finished = false
        private var fallbackStarted = false
        private var failures = 0

        init(png: Data, continuation: CheckedContinuation<Result, Error>) {
            self.png = png
            self.continuation = continuation
        }

        func start() {
            let queue = DispatchQueue.global(qos: .userInitiated)
            queue.async { [self] in
                if let text = runHelper(png, flag: "--ocr") {
                    finish(Result(text: text, usedFallback: false))
                } else {
                    fail()
                    startFallback()
                }
            }
            queue.asyncAfter(deadline: .now() + fallbackDelay) { [self] in startFallback() }
        }

        private func startFallback() {
            lock.lock()
            let skip = finished || fallbackStarted
            fallbackStarted = true
            lock.unlock()
            guard !skip else { return }
            if let text = runHelper(png, flag: "--ocr-fast") {
                finish(Result(text: text, usedFallback: true))
            } else {
                fail()
            }
        }

        private func finish(_ result: Result) {
            lock.lock()
            defer { lock.unlock() }
            guard !finished else { return }
            finished = true
            continuation.resume(returning: result)
        }

        private func fail() {
            lock.lock()
            defer { lock.unlock() }
            failures += 1
            guard failures == 2, !finished else { return }
            finished = true
            continuation.resume(throwing: Failure.helperFailed)
        }
    }

    /// CPU engine, for the helper process.
    static func recognizeFast(_ image: CGImage) -> String? {
        let (width, height) = (image.width, image.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn, let result = text_core_fast_ocr(pixels, width, height, width * 4) else { return nil }
        defer { text_core_free(result) }
        return String(cString: result)
    }

    /// Compiling the model takes about 35s the first time a new build uses it.
    /// Doing that at launch keeps the first capture fast.
    static func warmUp() {
        let size = NSSize(width: 400, height: 100)
        let source = NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            NSAttributedString(string: "Copylens", attributes: [.font: NSFont.systemFont(ofSize: 48)])
                .draw(at: NSPoint(x: 20, y: 20))
            return true
        }
        guard let image = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        guard let png = encodePNG(image) else { return }
        DispatchQueue.global(qos: .utility).async { _ = runHelper(png, flag: "--ocr") }
    }

    private static func runHelper(_ png: Data, flag: String) -> String? {
        guard let executable = Bundle.main.executableURL else { return nil }
        let process = Process()
        let input = Pipe(), output = Pipe()
        process.executableURL = executable
        process.arguments = [flag, "-"]
        process.qualityOfService = .userInitiated
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }

        // The helper reads all of stdin before it writes anything, so this order can't deadlock.
        try? input.fileHandleForWriting.write(contentsOf: png)
        try? input.fileHandleForWriting.close()
        let text = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: text, as: UTF8.self).trimmingCharacters(in: .newlines)
    }

    static func recognize(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["vi-VT", "en-US"]
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image).perform([request])

        let fragments = (request.results ?? []).compactMap { observation -> (String, CGRect)? in
            observation.topCandidates(1).first.map { ($0.string, observation.boundingBox) }
        }
        return layout(fragments)
    }

    private static func layout(_ fragments: [(String, CGRect)]) -> String {
        let texts = fragments.map { strdup($0.0) }
        defer { texts.forEach { free($0) } }

        let boxes = zip(texts, fragments).map { text, fragment in
            let box = fragment.1 // Vision uses a bottom-left origin
            return TextBox(text: text, x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
        }
        guard let result = text_core_layout(boxes, boxes.count) else { return "" }
        defer { text_core_free(result) }
        return String(cString: result)
    }
}
