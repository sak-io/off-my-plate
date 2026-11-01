import Foundation
import OMPDomain
import Testing

@Suite("SHA-256 (ADR 0008, NIST FIPS 180-4 vectors)")
struct SHA256Tests {
    struct Vector: Sendable, CustomTestStringConvertible {
        let name: String
        let message: String
        let digest: String
        var testDescription: String { name }
    }

    static let vectors: [Vector] = [
        Vector(
            name: "empty string", message: "",
            digest: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
        Vector(
            name: "abc (one block)", message: "abc",
            digest: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
        Vector(
            name: "448-bit message (two blocks)",
            message: "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
            digest: "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"),
        Vector(
            name: "896-bit message",
            message:
                "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu",
            digest: "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1"),
        // Padding boundaries: 55 bytes fit one block, 56 need two, 64 is exactly one block of data.
        Vector(
            name: "55 x a", message: String(repeating: "a", count: 55),
            digest: "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318"),
        Vector(
            name: "56 x a", message: String(repeating: "a", count: 56),
            digest: "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a"),
        Vector(
            name: "63 x a", message: String(repeating: "a", count: 63),
            digest: "7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34"),
        Vector(
            name: "64 x a", message: String(repeating: "a", count: 64),
            digest: "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb"),
        Vector(
            name: "65 x a", message: String(repeating: "a", count: 65),
            digest: "635361c48bb9eab14198e76ea8ab7f1a41685d6ad62aa9146d301d4f17eb0ae0"),
        Vector(
            name: "119 x a", message: String(repeating: "a", count: 119),
            digest: "31eba51c313a5c08226adf18d4a359cfdfd8d2e816b13f4af952f7ea6584dcfb"),
        Vector(
            name: "120 x a", message: String(repeating: "a", count: 120),
            digest: "2f3d335432c70b580af0e8e1b3674a7c020d683aa5f73aaaedfdc55af904c21c"),
        Vector(
            name: "non-ASCII UTF-8", message: "caf\u{e9} \u{1F600}",
            digest: "043764df773ac7ceea6175e1498893e6ee33e79885288417cc1d75cba6094827"),
    ]

    @Test("matches the reference digest", arguments: vectors)
    func matchesVector(_ vector: Vector) {
        #expect(SHA256.hexDigest(of: vector.message) == vector.digest)
    }

    @Test("NIST long message: one million x a")
    func millionA() {
        let message = [UInt8](repeating: 0x61, count: 1_000_000)
        #expect(
            SHA256.hexString(SHA256.hash(message))
                == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }

    @Test("a digest is 32 bytes and its hex is 64 lowercase characters")
    func digestShape() {
        let digest = SHA256.hash("abc".utf8)
        #expect(digest.count == SHA256.digestByteCount)
        let hex = SHA256.hexString(digest)
        #expect(hex.count == 64)
        #expect(hex.allSatisfy { "0123456789abcdef".contains($0) })
    }

    @Test("hexString encodes each byte as two lowercase digits")
    func hexEncoding() {
        #expect(SHA256.hexString([]) == "")
        #expect(SHA256.hexString([0x00, 0x0f, 0xa0, 0xff]) == "000fa0ff")
    }
}
