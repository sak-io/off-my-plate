#if DEBUG
import Foundation
import os
import SwiftUI

/// AC-13.2 evidence for the UI tests (Debug builds only; this whole file is compiled out of
/// Release): with `-OMPUITestDenyNetwork`, a `URLProtocol` is registered in the app process that
/// records and fails EVERY URL request the app attempts. A tiny accessibility element
/// (`debug.networkAttempts`, label `net:<count>`) shows the count, so a UI test can assert that
/// zero requests were attempted across the main flows.
///
/// This complements `scripts/lint-no-network.sh`, which keeps network code out of the sources.
/// The lint has ONE reviewed exception for this file (it may name `URLRequest`, which
/// `URLProtocol.canInit(with:)` requires); every other networking symbol stays banned here.
final class DebugNetworkDenial: URLProtocol {
    static let argument = "-OMPUITestDenyNetwork"
    static let elementIdentifier = "debug.networkAttempts"

    private static let attemptCount = OSAllocatedUnfairLock(initialState: 0)
    private static let active = OSAllocatedUnfairLock(initialState: false)

    /// Number of requests the app tried to make since the probe was installed.
    static var attempts: Int { attemptCount.withLock { $0 } }
    static var isActive: Bool { active.withLock { $0 } }

    /// Registers the probe when the launch arguments ask for it.
    static func installIfRequested(arguments: [String]) {
        guard arguments.contains(argument) else { return }
        URLProtocol.registerClass(DebugNetworkDenial.self)
        active.withLock { $0 = true }
    }

    static func record() {
        attemptCount.withLock { $0 += 1 }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.record()
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}

/// The count as one nearly invisible accessibility element. Shown only while the probe is
/// installed, so the other UI tests (and their audits) never see it.
struct DebugNetworkAttemptsProbe: View {
    @State private var count = DebugNetworkDenial.attempts

    var body: some View {
        if DebugNetworkDenial.isActive {
            Text("net:\(count)")
                .font(.system(size: 1))
                .foregroundStyle(.clear)
                .allowsHitTesting(false)
                .accessibilityIdentifier(DebugNetworkDenial.elementIdentifier)
                .task {
                    while !Task.isCancelled {
                        count = DebugNetworkDenial.attempts
                        try? await Task.sleep(for: .milliseconds(500))
                    }
                }
        }
    }
}
#endif
