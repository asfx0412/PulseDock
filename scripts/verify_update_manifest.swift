import CryptoKit
import Foundation

struct UpdateManifest: Codable {
    let version: String
    let url: URL
    let sha256: String
    let signature: String
    let publishedAt: String
    let notes: String

    var signedPayload: Data {
        // Must remain byte-for-byte aligned with AppUpdateManifest.signedPayload.
        Data([version, url.absoluteString, sha256.lowercased(), publishedAt, notes].joined(separator: "\n").utf8)
    }
}

guard CommandLine.arguments.count == 3,
      let publicData = Data(base64Encoded: CommandLine.arguments[2]),
      let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicData),
      let data = try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])),
      let manifest = try? JSONDecoder().decode(UpdateManifest.self, from: data),
      let signature = Data(base64Encoded: manifest.signature),
      key.isValidSignature(signature, for: manifest.signedPayload) else {
    fputs("Manifest Ed25519 verification failed.\n", stderr)
    exit(1)
}
print("Manifest Ed25519 signature verified")
