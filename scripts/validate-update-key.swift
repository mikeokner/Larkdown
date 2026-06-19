import CryptoKit
import Foundation

// Accept the 32-byte seed format exported by current Sparkle generate_keys.
// Never print the private key or pass it through command-line arguments.
guard CommandLine.arguments.count == 2,
      let encoded = try? String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8),
      let seed = Data(base64Encoded: encoded.trimmingCharacters(in: .whitespacesAndNewlines)),
      seed.count == 32,
      let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed),
      let expected = ProcessInfo.processInfo.environment["SPARKLE_PUBLIC_ED_KEY"],
      key.publicKey.rawRepresentation.base64EncodedString() == expected else {
    fputs("Sparkle private seed must match SPARKLE_PUBLIC_ED_KEY. Use the current generate_keys export format.\n", stderr)
    exit(1)
}
