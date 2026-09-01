import CryptoKit
import Foundation

let key = Curve25519.Signing.PrivateKey()
print("Public key (paste into AppUpdateConfiguration.publicKeyBase64):")
print(key.publicKey.rawRepresentation.base64EncodedString())
print("\nPrivate key (add to GitHub Actions secret PULSEDOCK_UPDATE_PRIVATE_KEY_BASE64; do not commit it):")
print(key.rawRepresentation.base64EncodedString())
