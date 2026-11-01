/// SHA-256 (FIPS 180-4) in pure Swift, for plan content hashes (ADR 0008).
///
/// CryptoKit is not available on Linux, so the core carries its own implementation. It is
/// used for change detection, not tamper resistance, and is verified against the NIST test
/// vectors in `SHA256Tests`. All word arithmetic is modulo 2^32 (`&+`).
public enum SHA256 {
    /// Size of a digest in bytes.
    public static let digestByteCount = 32

    /// The 32-byte digest of `message`.
    public static func hash<Bytes: Sequence>(_ message: Bytes) -> [UInt8] where Bytes.Element == UInt8 {
        var bytes = Array(message)
        let bitLength = UInt64(bytes.count) &* 8
        // Padding: a single 1 bit, zeros up to 56 mod 64 bytes, then the 64-bit big-endian length.
        bytes.append(0x80)
        while bytes.count % 64 != 56 {
            bytes.append(0)
        }
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8(truncatingIfNeeded: bitLength >> UInt64(shift)))
        }

        var state = initialState
        var schedule = [UInt32](repeating: 0, count: 64)
        var offset = 0
        while offset < bytes.count {
            for t in 0..<16 {
                let i = offset + t * 4
                let b0 = UInt32(bytes[i]) << 24
                let b1 = UInt32(bytes[i + 1]) << 16
                let b2 = UInt32(bytes[i + 2]) << 8
                let b3 = UInt32(bytes[i + 3])
                schedule[t] = b0 | b1 | b2 | b3
            }
            for t in 16..<64 {
                let w15 = schedule[t - 15]
                let w2 = schedule[t - 2]
                let s0: UInt32 = rotateRight(w15, 7) ^ rotateRight(w15, 18) ^ (w15 >> 3)
                let s1: UInt32 = rotateRight(w2, 17) ^ rotateRight(w2, 19) ^ (w2 >> 10)
                schedule[t] = schedule[t - 16] &+ s0 &+ schedule[t - 7] &+ s1
            }

            var a = state[0]
            var b = state[1]
            var c = state[2]
            var d = state[3]
            var e = state[4]
            var f = state[5]
            var g = state[6]
            var h = state[7]
            for t in 0..<64 {
                let bigSigma1: UInt32 = rotateRight(e, 6) ^ rotateRight(e, 11) ^ rotateRight(e, 25)
                let choose: UInt32 = (e & f) ^ (~e & g)
                let temp1: UInt32 = h &+ bigSigma1 &+ choose &+ roundConstants[t] &+ schedule[t]
                let bigSigma0: UInt32 = rotateRight(a, 2) ^ rotateRight(a, 13) ^ rotateRight(a, 22)
                let majority: UInt32 = (a & b) ^ (a & c) ^ (b & c)
                let temp2: UInt32 = bigSigma0 &+ majority
                h = g
                g = f
                f = e
                e = d &+ temp1
                d = c
                c = b
                b = a
                a = temp1 &+ temp2
            }
            state[0] = state[0] &+ a
            state[1] = state[1] &+ b
            state[2] = state[2] &+ c
            state[3] = state[3] &+ d
            state[4] = state[4] &+ e
            state[5] = state[5] &+ f
            state[6] = state[6] &+ g
            state[7] = state[7] &+ h
            offset += 64
        }

        var digest: [UInt8] = []
        digest.reserveCapacity(digestByteCount)
        for word in state {
            digest.append(UInt8(truncatingIfNeeded: word >> 24))
            digest.append(UInt8(truncatingIfNeeded: word >> 16))
            digest.append(UInt8(truncatingIfNeeded: word >> 8))
            digest.append(UInt8(truncatingIfNeeded: word))
        }
        return digest
    }

    /// Lowercase hex SHA-256 of the UTF-8 bytes of `string`.
    public static func hexDigest(of string: String) -> String {
        hexString(hash(string.utf8))
    }

    /// Lowercase hex encoding of `bytes` (two characters per byte, no separators).
    public static func hexString(_ bytes: [UInt8]) -> String {
        var characters: [UInt8] = []
        characters.reserveCapacity(bytes.count * 2)
        for byte in bytes {
            characters.append(hexDigits[Int(byte >> 4)])
            characters.append(hexDigits[Int(byte & 0x0f)])
        }
        return String(decoding: characters, as: UTF8.self)
    }

    private static let hexDigits: [UInt8] = Array("0123456789abcdef".utf8)

    private static func rotateRight(_ value: UInt32, _ count: UInt32) -> UInt32 {
        (value >> count) | (value << (32 - count))
    }

    /// First 32 bits of the fractional parts of the square roots of the first 8 primes.
    private static let initialState: [UInt32] = [
        0x6a09_e667, 0xbb67_ae85, 0x3c6e_f372, 0xa54f_f53a, 0x510e_527f, 0x9b05_688c, 0x1f83_d9ab, 0x5be0_cd19,
    ]

    /// First 32 bits of the fractional parts of the cube roots of the first 64 primes.
    private static let roundConstants: [UInt32] = [
        0x428a_2f98, 0x7137_4491, 0xb5c0_fbcf, 0xe9b5_dba5, 0x3956_c25b, 0x59f1_11f1, 0x923f_82a4, 0xab1c_5ed5,
        0xd807_aa98, 0x1283_5b01, 0x2431_85be, 0x550c_7dc3, 0x72be_5d74, 0x80de_b1fe, 0x9bdc_06a7, 0xc19b_f174,
        0xe49b_69c1, 0xefbe_4786, 0x0fc1_9dc6, 0x240c_a1cc, 0x2de9_2c6f, 0x4a74_84aa, 0x5cb0_a9dc, 0x76f9_88da,
        0x983e_5152, 0xa831_c66d, 0xb003_27c8, 0xbf59_7fc7, 0xc6e0_0bf3, 0xd5a7_9147, 0x06ca_6351, 0x1429_2967,
        0x27b7_0a85, 0x2e1b_2138, 0x4d2c_6dfc, 0x5338_0d13, 0x650a_7354, 0x766a_0abb, 0x81c2_c92e, 0x9272_2c85,
        0xa2bf_e8a1, 0xa81a_664b, 0xc24b_8b70, 0xc76c_51a3, 0xd192_e819, 0xd699_0624, 0xf40e_3585, 0x106a_a070,
        0x19a4_c116, 0x1e37_6c08, 0x2748_774c, 0x34b0_bcb5, 0x391c_0cb3, 0x4ed8_aa4a, 0x5b9c_ca4f, 0x682e_6ff3,
        0x748f_82ee, 0x78a5_636f, 0x84c8_7814, 0x8cc7_0208, 0x90be_fffa, 0xa450_6ceb, 0xbef9_a3f7, 0xc671_78f2,
    ]
}
