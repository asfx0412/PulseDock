import CryptoKit
import Foundation

guard CommandLine.arguments.count == 7 else {
    fputs("usage: create_update_manifest.swift VERSION ZIP_URL ZIP_PATH PUBLISHED_AT NOTES_PATH OUTPUT_PATH\n", stderr)
    exit(2)
}
guard let encodedKey = ProcessInfo.processInfo.environment["PULSEDOCK_UPDATE_PRIVATE_KEY_BASE64"],
      let keyData = Data(base64Encoded: encodedKey),
      let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: keyData),
      let url = URL(string: CommandLine.arguments[2]) else {
    fputs("Missing or invalid PULSEDOCK_UPDATE_PRIVATE_KEY_BASE64.\n", stderr)
    exit(2)
}
let version = CommandLine.arguments[1]
let zip = URL(fileURLWithPath: CommandLine.arguments[3])
let publishedAt = CommandLine.arguments[4]
let notes = (try? String(contentsOfFile: CommandLine.arguments[5], encoding: .utf8)) ?? ""
let output = URL(fileURLWithPath: CommandLine.arguments[6])
let data = try Data(contentsOf: zip, options: .mappedIfSafe)
let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
// This must stay byte-for-byte aligned with AppUpdateManifest.signedPayload.
// Release notes are displayed before the user approves installation, so they
// are part of the authenticated manifest rather than mutable side metadata.
let payload = Data([version, url.absoluteString, hash, publishedAt, notes].joined(separator: "\n").utf8)
let signature = try key.signature(for: payload).base64EncodedString()
let manifest: [String: String] = [
    "version": version, "url": url.absoluteString, "sha256": hash,
    "signature": signature, "publishedAt": publishedAt, "notes": notes
]
let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
try encoder.encode(manifest).write(to: output, options: .atomic)
