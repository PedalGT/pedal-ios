import Foundation
import PassKit

/// Wraps the Apple Pay sheet.
///
/// Proof of concept: nothing is charged. The sheet runs for real, and the
/// resulting payment token is forwarded to the server, which ignores it and
/// just credits the wallet (see docs/API.md, "Wallet").
///
/// Needs the Apple Pay capability with Config.merchantID, which requires a paid
/// Apple Developer account. The Simulator shows a working test sheet.
@MainActor
final class ApplePayService: NSObject {
    struct Result {
        let authorized: Bool
        /// base64 of the Apple Pay token, sent along as `paymentToken`.
        let token: String?
    }

    private var continuation: CheckedContinuation<Result, Never>?
    private var didAuthorize = false
    private var token: String?
    private var controller: PKPaymentAuthorizationController?

    /// Cards the sheet will accept.
    static let networks: [PKPaymentNetwork] = [.visa, .masterCard, .amex, .discover]

    static var isAvailable: Bool {
        PKPaymentAuthorizationController.canMakePayments(usingNetworks: networks)
    }

    func pay(amountCents: Int) async -> Result {
        let request = PKPaymentRequest()
        request.merchantIdentifier = Config.merchantID
        request.merchantCapabilities = .threeDSecure
        request.countryCode = "US"
        request.currencyCode = "USD"
        request.supportedNetworks = Self.networks
        request.paymentSummaryItems = [
            PKPaymentSummaryItem(label: "Pedal balance",
                                 amount: NSDecimalNumber(value: Double(amountCents) / 100),
                                 type: .final)
        ]

        didAuthorize = false
        token = nil

        return await withCheckedContinuation { (continuation: CheckedContinuation<Result, Never>) in
            self.continuation = continuation
            let controller = PKPaymentAuthorizationController(paymentRequest: request)
            controller.delegate = self
            self.controller = controller
            controller.present { presented in
                if !presented {
                    Task { @MainActor in self.finish() }
                }
            }
        }
    }

    private func finish() {
        controller = nil
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: Result(authorized: didAuthorize, token: token))
    }
}

extension ApplePayService: PKPaymentAuthorizationControllerDelegate {
    nonisolated func paymentAuthorizationController(
        _ controller: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        let encoded = payment.token.paymentData.base64EncodedString()
        Task { @MainActor in
            self.didAuthorize = true
            self.token = encoded
        }
        // Nothing to charge, so the sheet always succeeds.
        completion(PKPaymentAuthorizationResult(status: .success, errors: nil))
    }

    nonisolated func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss {
            Task { @MainActor in self.finish() }
        }
    }
}
