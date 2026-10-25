import Foundation
import TactileCore

enum SecurityChecks {
    static func run(_ checks: Checks) {
        checks.run("pairing: the right code pairs once, then changes") {
            try withTemporaryDirectory { folder in
                let pairing = Pairing(store: folder.appendingPathComponent("devices.json"))
                let code = pairing.code
                try expect(code.count == 6 && code.allSatisfy(\.isNumber), "code is six digits")
                let paired = try require(pairing.redeem(code: code, from: "10.0.0.2", name: "iPad"), "pairing")
                try expect(paired.token.count == 64 && paired.token.allSatisfy(\.isHexDigit), "token is 64 hex digits")
                try expectEqual(pairing.device(forToken: paired.token)?.id, paired.device.id, "device for token")
                try expect(pairing.code != code, "code is replaced after use")
                try expect(pairing.redeem(code: code, from: "10.0.0.3", name: "iPad") == nil, "a used code is refused")
            }
        }

        checks.run("pairing: wrong codes lock that address only") {
            try withTemporaryDirectory { folder in
                let pairing = Pairing(store: folder.appendingPathComponent("devices.json"))
                for _ in 0..<5 { _ = pairing.redeem(code: wrong(pairing.code), from: "10.0.0.9", name: "iPad") }
                try expect(pairing.isLocked("10.0.0.9"), "address is locked")
                try expect(pairing.redeem(code: pairing.code, from: "10.0.0.9", name: "iPad") == nil, "locked address can't pair")
                try expect(!pairing.isLocked("10.0.0.10"), "other addresses aren't locked")
            }
        }

        checks.run("pairing: many wrong codes from anywhere pause pairing and replace the code") {
            try withTemporaryDirectory { folder in
                let pairing = Pairing(store: folder.appendingPathComponent("devices.json"))
                var newCodes = 0
                pairing.onNewCode = { newCodes += 1 }
                let original = pairing.code
                for i in 0..<20 { _ = pairing.redeem(code: wrong(pairing.code), from: "10.0.1.\(i)", name: "iPad") }
                try expect(pairing.code != original, "code replaced")
                try expectEqual(newCodes, 1, "new codes announced")
                try expect(pairing.isLocked("10.0.2.1"), "pairing paused for new addresses")
            }
        }

        checks.run("pairing: devices are saved privately, as hashes") {
            try withTemporaryDirectory { folder in
                let store = folder.appendingPathComponent("devices.json")
                let pairing = Pairing(store: store)
                let token = try require(pairing.redeem(code: pairing.code, from: "a", name: "iPad"), "pairing").token
                // A fresh instance reads the saved devices.
                let reloaded = Pairing(store: store)
                try expect(reloaded.device(forToken: token) != nil, "token works after reload")
                let saved = try String(contentsOf: store, encoding: .utf8)
                try expect(!saved.contains(token), "token isn't stored in plain text")
                let permissions = try FileManager.default.attributesOfItem(atPath: store.path)[.posixPermissions] as? Int
                try expectEqual(permissions, 0o600, "file permissions")
            }
        }

        checks.run("pairing: revoked and long-unused devices lose access") {
            try withTemporaryDirectory { folder in
                let store = folder.appendingPathComponent("devices.json")
                let pairing = Pairing(store: store)
                let paired = try require(pairing.redeem(code: pairing.code, from: "a", name: "iPad"), "pairing")
                pairing.revoke(paired.device.id)
                try expect(pairing.device(forToken: paired.token) == nil, "revoked token refused")

                let old = Date().addingTimeInterval(-Pairing.idleExpiry - 60)
                let stale = Pairing.Device(id: "stale", tokenHash: String(repeating: "0", count: 64), name: "iPad", pairedAt: old, lastSeen: old)
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                try encoder.encode([stale]).write(to: store)
                try expect(Pairing(store: store).devices.isEmpty, "expired device removed on load")
            }
        }

        checks.run("pairing: malformed tokens are refused") {
            try withTemporaryDirectory { folder in
                let pairing = Pairing(store: folder.appendingPathComponent("devices.json"))
                for token in ["", "abc", String(repeating: "z", count: 64), String(repeating: "0", count: 65)] {
                    try expect(pairing.device(forToken: token) == nil, "token \(token.prefix(8))…")
                }
            }
        }

        checks.run("Tailscale gate: only the owner's untagged devices get in") {
            let owner: Int64 = 7
            let peers: [String: Tailscale.Peer] = [
                "100.0.0.1": Tailscale.Peer(userID: owner, tagged: false, deviceName: "iPad"),
                "100.0.0.2": Tailscale.Peer(userID: 8, tagged: false, deviceName: "iPad"),
                "100.0.0.3": Tailscale.Peer(userID: owner, tagged: true, deviceName: "server"),
            ]
            let gate = TailnetGate(ownerID: owner)
            gate.lookUp = { peers[$0] }
            let allowed = { (address: String) -> Bool? in
                waitFor { done in
                    gate.check(address, on: .global()) { verdict in
                        if case .allowed = verdict { done(true) } else { done(false) }
                    }
                }
            }
            try expectEqual(allowed("100.0.0.1"), true, "owner's device")
            try expectEqual(allowed("100.0.0.2"), false, "someone else's device")
            try expectEqual(allowed("100.0.0.3"), false, "tagged device")
            try expectEqual(allowed("100.0.0.4"), false, "unknown device (fails closed)")

            let unknownOwner = TailnetGate(ownerID: nil)
            unknownOwner.lookUp = { peers[$0] }
            let verdict: Bool? = waitFor { done in
                unknownOwner.check("100.0.0.1", on: .global()) { if case .allowed = $0 { done(true) } else { done(false) } }
            }
            try expectEqual(verdict, false, "Mac's owner unknown (fails closed)")
        }

        checks.run("Tailscale gate: answers are cached briefly") {
            let lookups = NSLock()
            var count = 0
            let gate = TailnetGate(ownerID: 1)
            gate.lookUp = { _ in
                lookups.withLock { count += 1 }
                return Tailscale.Peer(userID: 1, tagged: false, deviceName: "iPad")
            }
            for _ in 0..<3 {
                _ = waitFor { (done: @escaping (Bool) -> Void) in gate.check("100.0.0.1", on: .global()) { _ in done(true) } }
            }
            try expectEqual(lookups.withLock { count }, 1, "lookups")
        }

        checks.run("Tailscale: machine names read naturally") {
            try expectEqual(Tailscale.friendlyName("ipad-air-13"), "iPad Air 13", "ipad-air-13")
            try expectEqual(Tailscale.friendlyName("macbook-pro"), "MacBook Pro", "macbook-pro")
            try expectEqual(Tailscale.friendlyName("work_iphone"), "Work iPhone", "work_iphone")
            try expectEqual(Tailscale.friendlyName(""), "Tailscale device", "empty")
        }
    }

    /// A six-digit code that isn't `code`.
    private static func wrong(_ code: String) -> String {
        code == "000000" ? "111111" : "000000"
    }
}
