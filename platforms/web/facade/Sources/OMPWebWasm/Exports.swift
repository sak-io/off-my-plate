#if os(WASI)
import Foundation
import OMPWeb

// The memory protocol of the browser module (documented with examples in docs/windows/w03-report.md):
//
//   1. JS calls omp_alloc(n) -> ptr, copies the UTF-8 request document into memory at ptr.
//   2. JS calls omp_call(ptr, n) -> m. The module runs the request to completion (synchronously) and keeps
//      the UTF-8 response document, m bytes, until the next omp_call.
//   3. JS calls omp_result_ptr() -> p and reads m bytes at p, then omp_free(ptr) for the request buffer.
//
// Never keep p across another omp_call. omp_call returns a negative number only if the request buffer is
// invalid; every other failure is a JSON error document.

private final class ResultStore: @unchecked Sendable {
    var pointer: UnsafeMutableRawPointer?
    var length: Int = 0

    func replace(with data: Data) -> Int {
        if let pointer { free(pointer) }
        pointer = nil
        length = data.count
        guard !data.isEmpty, let buffer = malloc(data.count) else { return 0 }
        data.withUnsafeBytes { raw in
            if let base = raw.baseAddress { buffer.copyMemory(from: base, byteCount: data.count) }
        }
        pointer = buffer
        return data.count
    }
}

private let store = ResultStore()

@_expose(wasm, "omp_alloc")
@_cdecl("omp_alloc")
public func omp_alloc(_ size: Int32) -> UnsafeMutableRawPointer? {
    malloc(Int(max(size, 1)))
}

@_expose(wasm, "omp_free")
@_cdecl("omp_free")
public func omp_free(_ pointer: UnsafeMutableRawPointer?) {
    free(pointer)
}

@_expose(wasm, "omp_call")
@_cdecl("omp_call")
public func omp_call(_ pointer: UnsafeRawPointer?, _ length: Int32) -> Int32 {
    guard let pointer, length >= 0 else { return -1 }
    let request = Data(bytes: pointer, count: Int(length))
    let response = Facade.handleSync(request)
    return Int32(store.replace(with: response))
}

@_expose(wasm, "omp_result_ptr")
@_cdecl("omp_result_ptr")
public func omp_result_ptr() -> UnsafeMutableRawPointer? {
    store.pointer
}

/// The version of this memory protocol (not of the core; ask `meta.version` for that).
@_expose(wasm, "omp_version")
@_cdecl("omp_version")
public func omp_version() -> Int32 {
    1
}
#endif
