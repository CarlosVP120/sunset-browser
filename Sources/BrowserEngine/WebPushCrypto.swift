import CryptoKit
import Foundation

/// El cifrado de Web Push (RFC 8291, "aes128gcm"): las claves de cada suscripción y cómo abrir los
/// mensajes que llegan. El sitio cifra con la clave pública de la suscripción; solo Sunset, que
/// guarda la privada, puede leerlos (el servidor de push no ve el contenido).
struct WebPushKeys: Codable, Equatable {
    /// Clave privada P-256 (32 bytes) para el acuerdo de claves con el sitio.
    var privateKey: Data
    /// Secreto de autenticación (16 bytes) que se comparte con el sitio.
    var authSecret: Data

    static func generate() -> WebPushKeys {
        var secret = Data(count: 16)
        _ = secret.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        return WebPushKeys(privateKey: P256.KeyAgreement.PrivateKey().rawRepresentation, authSecret: secret)
    }

    /// La clave pública sin comprimir (65 bytes): el `p256dh` de la suscripción.
    var publicKey: Data {
        (try? P256.KeyAgreement.PrivateKey(rawRepresentation: privateKey))?.publicKey.x963Representation ?? Data()
    }

    enum DecryptionError: Error { case malformed, unsupported }

    /// Abre un mensaje "aes128gcm": cabecera (sal, tamaño de registro, clave del sitio) y registros
    /// cifrados con AES-GCM, el último terminado en 0x02 y relleno de ceros.
    func decrypt(_ body: Data) throws -> Data {
        let bytes = [UInt8](body)
        guard bytes.count >= 21 else { throw DecryptionError.malformed }
        let salt = Data(bytes[0..<16])
        let recordSize = bytes[16..<20].reduce(0) { $0 << 8 | Int($1) }
        let idLength = Int(bytes[20])
        guard recordSize > 17, bytes.count >= 21 + idLength, idLength == 65 else { throw DecryptionError.malformed }
        let senderKeyData = Data(bytes[21..<(21 + idLength)])

        let userAgentKey = try P256.KeyAgreement.PrivateKey(rawRepresentation: privateKey)
        let senderKey = try P256.KeyAgreement.PublicKey(x963Representation: senderKeyData)
        let shared = try userAgentKey.sharedSecretFromKeyAgreement(with: senderKey)

        // IKM = HKDF(secreto de autenticación, ECDH, "WebPush: info" ‖ 0 ‖ clave UA ‖ clave del sitio)
        let keyInfo = Data("WebPush: info".utf8) + [0] + userAgentKey.publicKey.x963Representation + senderKeyData
        let ikm = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: authSecret, sharedInfo: keyInfo, outputByteCount: 32)
        let cek = HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, salt: salt,
                                         info: Data("Content-Encoding: aes128gcm".utf8) + [0], outputByteCount: 16)
        let nonceBase = HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, salt: salt,
                                               info: Data("Content-Encoding: nonce".utf8) + [0], outputByteCount: 12)
            .withUnsafeBytes { [UInt8]($0) }

        var plaintext = Data()
        var offset = 21 + idLength
        var sequence: UInt64 = 0
        while offset < bytes.count {
            let end = min(offset + recordSize, bytes.count)
            let record = Data(bytes[offset..<end])
            guard record.count > 16 else { throw DecryptionError.malformed }
            var nonce = nonceBase
            for i in 0..<8 { nonce[11 - i] ^= UInt8(truncatingIfNeeded: sequence >> (8 * UInt64(i))) }
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce), ciphertext: record.dropLast(16), tag: record.suffix(16))
            var chunk = try AES.GCM.open(box, using: cek)
            // Quitar el relleno: ceros al final y el delimitador (0x02 en el último registro, 0x01 en los demás).
            while chunk.last == 0 { chunk.removeLast() }
            guard let delimiter = chunk.popLast(), delimiter == 1 || delimiter == 2 else { throw DecryptionError.malformed }
            plaintext.append(chunk)
            if delimiter == 2 { break }
            offset = end
            sequence += 1
        }
        return plaintext
    }
}

extension Data {
    /// Base64 "url" sin relleno, el formato de las claves y los mensajes de Web Push.
    init?(base64URLEncoded string: String) {
        var base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }

    var base64URLEncodedString: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
