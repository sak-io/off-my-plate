#if DEBUG
import Foundation
final class Probe: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { URLSession.shared.configuration.isDiscretionary }
}
#endif
