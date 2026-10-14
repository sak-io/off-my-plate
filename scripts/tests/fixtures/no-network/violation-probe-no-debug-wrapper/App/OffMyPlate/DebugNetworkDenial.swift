import Foundation
final class P: URLProtocol {
  override class func canInit(with request: URLRequest) -> Bool { true }
}
