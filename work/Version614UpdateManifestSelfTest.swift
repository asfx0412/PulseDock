import CryptoKit
import Foundation

@main
enum Version614UpdateManifestSelfTest {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    static func main() async throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKey = privateKey.publicKey.rawRepresentation.base64EncodedString()
        let notes = "# Release\n\nA signed note"
        let unsigned = AppUpdateManifest(
            version: "6.14.0",
            url: URL(string: "https://github.com/asfx0412/PulseDock/releases/download/v6.14.0/PulseDock-6.14.0.zip")!,
            sha256: String(repeating: "a", count: 64), signature: "", publishedAt: "2026-09-01T00:00:00Z", notes: notes
        )
        let signed = AppUpdateManifest(
            version: unsigned.version, url: unsigned.url, sha256: unsigned.sha256,
            signature: try privateKey.signature(for: unsigned.signedPayload).base64EncodedString(),
            publishedAt: unsigned.publishedAt, notes: unsigned.notes
        )
        require(AppUpdateManifest.verifiesSignature(signed, publicKeyBase64: publicKey), "signature must validate the canonical client payload")
        let modifiedNotes = AppUpdateManifest(version: signed.version, url: signed.url, sha256: signed.sha256, signature: signed.signature, publishedAt: signed.publishedAt, notes: signed.notes + " changed")
        require(!AppUpdateManifest.verifiesSignature(modifiedNotes, publicKeyBase64: publicKey), "changing release notes must invalidate the signature")
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("PulseDock-update-selftest", isDirectory: true)
        let staged = temporary.appendingPathComponent("PulseDock.app", isDirectory: true)
        try? FileManager.default.removeItem(at: temporary)
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        let service = AppUpdateService()
        await service.discardStagedApp(staged)
        require(!FileManager.default.fileExists(atPath: temporary.path), "failed installer cleanup must remove only its generated staging root")
        print("PulseDock 6.14 update manifest self-test passed")
    }
}
