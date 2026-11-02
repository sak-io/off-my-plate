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
// not one omp_alloc returned (or the length exceeds it); omp_alloc returns 0 for sizes outside 1...9 MiB; every other failure is a JSON error document.

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

/// Request buffers handed out by omp_alloc and not yet freed (address -> size). omp_free and omp_call
/// accept only these, so a double free, a free of the result buffer or a wild pointer cannot corrupt the heap.
private final class Allocations: @unchecked Sendable {
    private var live: [UInt: Int] = [:]
    static let maxSize = 9 * 1024 * 1024

    func allocate(_ size: Int) -> UnsafeMutableRawPointer? {
        guard size > 0, size <= Allocations.maxSize, let pointer = malloc(size) else { return nil }
        live[UInt(bitPattern: pointer)] = size
        return pointer
    }

    func size(of pointer: UnsafeRawPointer) -> Int? { live[UInt(bitPattern: pointer)] }

    func release(_ pointer: UnsafeMutableRawPointer) {
        if live.removeValue(forKey: UInt(bitPattern: pointer)) != nil { free(pointer) }
    }
}

private let allocations = Allocations()

/// Returns null (0) for a size that is not 1...9 MiB.
@_expose(wasm, "omp_alloc")
@_cdecl("omp_alloc")
public func omp_alloc(_ size: Int32) -> UnsafeMutableRawPointer? {
    allocations.allocate(Int(size))
}

/// Frees a buffer from omp_alloc; anything else (unknown pointer, second free, the result buffer) is ignored.
@_expose(wasm, "omp_free")
@_cdecl("omp_free")
public func omp_free(_ pointer: UnsafeMutableRawPointer?) {
    guard let pointer else { return }
    allocations.release(pointer)
}

/// Returns the response length, -1 for a buffer that omp_alloc did not hand out or a length outside it.
@_expose(wasm, "omp_call")
@_cdecl("omp_call")
public func omp_call(_ pointer: UnsafeRawPointer?, _ length: Int32) -> Int32 {
    guard let pointer, length >= 0, let size = allocations.size(of: pointer), Int(length) <= size else { return -1 }
    let request = Data(bytes: pointer, count: Int(length))
    let response = Facade.handleSync(request)
    guard response.count <= Int(Int32.max) else { return -2 }
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
