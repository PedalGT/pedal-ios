import Foundation
#if canImport(CoreNFC)
import CoreNFC
#endif

enum ScanError: LocalizedError {
    case unavailable
    case cancelled
    case unreadable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "NFC isn't available on this device. Enter the code printed on the lock."
        case .cancelled:
            return nil          // a quiet no-op, not an error
        case .unreadable:
            return "That tag isn't a Pedal lock. Enter the code printed on the lock instead."
        case .failed(let detail):
            return detail
        }
    }
}

/// Reads the lock's NDEF tag and returns the bike code.
///
/// The payload is either a URI `https://<host>/b/<CODE>` (take the last path
/// component) or a text record `PEDAL:<CODE>`. See docs/API.md.
///
/// Requires the "Near Field Communication Tag Reading" capability, which needs a
/// paid Apple Developer account, and a real iPhone 7 or newer. Everywhere else
/// `isAvailable` is false and the caller falls back to typing the code.
final class NFCScanner: NSObject {
    static var isAvailable: Bool {
        #if canImport(CoreNFC) && !targetEnvironment(simulator)
        return NFCNDEFReaderSession.readingAvailable
        #else
        return false
        #endif
    }

    #if canImport(CoreNFC) && !targetEnvironment(simulator)
    private var session: NFCNDEFReaderSession?
    private var continuation: CheckedContinuation<String, Error>?
    #endif

    func scan() async throws -> String {
        #if canImport(CoreNFC) && !targetEnvironment(simulator)
        guard NFCNDEFReaderSession.readingAvailable else { throw ScanError.unavailable }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: true)
            session.alertMessage = "Hold your iPhone near the Pedal lock."
            self.session = session
            session.begin()
        }
        #else
        throw ScanError.unavailable
        #endif
    }

    /// Pulls a bike code out of an NDEF payload. Kept separate from the session
    /// so it can be reasoned about (and reused by the QR scanner) without NFC hardware.
    static func code(fromURIOrText raw: String) -> String? {
        var candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if candidate.uppercased().hasPrefix("PEDAL:") {
            candidate = String(candidate.dropFirst("PEDAL:".count))
        } else if let url = URL(string: candidate), url.scheme != nil {
            candidate = url.lastPathComponent
        }

        candidate = candidate.uppercased().filter { $0.isLetter || $0.isNumber }
        guard (4...8).contains(candidate.count) else { return nil }
        return candidate
    }
}

#if canImport(CoreNFC) && !targetEnvironment(simulator)
extension NFCScanner: NFCNDEFReaderSessionDelegate {
    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        let payloads = messages.flatMap(\.records)
        for record in payloads {
            // wellKnownTypeURIPayload decodes the one-byte URI prefix ("https://" etc.);
            // text records come back through wellKnownTypeTextPayload; anything else
            // is read as raw UTF-8.
            var text: String?
            if let url = record.wellKnownTypeURIPayload() {
                text = url.absoluteString
            } else if let payload = record.wellKnownTypeTextPayload().0 {
                text = payload
            } else {
                text = String(data: record.payload, encoding: .utf8)
            }

            if let text, let code = NFCScanner.code(fromURIOrText: text) {
                session.alertMessage = "Found bike \(code)."
                session.invalidate()
                finish(.success(code))
                return
            }
        }
        session.invalidate(errorMessage: "That tag isn't a Pedal lock.")
        finish(.failure(ScanError.unreadable))
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        self.session = nil
        guard continuation != nil else { return }
        let nfcError = error as? NFCReaderError
        switch nfcError?.code {
        case .readerSessionInvalidationErrorUserCanceled,
             .readerSessionInvalidationErrorFirstNDEFTagRead:
            // User tapped Cancel, or we already returned a code above.
            finish(.failure(ScanError.cancelled))
        default:
            finish(.failure(ScanError.failed(error.localizedDescription)))
        }
    }

    private func finish(_ result: Result<String, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}
#endif
