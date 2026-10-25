import Darwin
import Foundation
import SystemConfiguration

/// This Mac's names and addresses on the network.
public enum HostInfo {
    public static var computerName: String {
        (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "Mac"
    }

    public static var bonjourName: String? {
        (SCDynamicStoreCopyLocalHostName(nil) as String?).map { "\($0).local" }
    }

    /// IPv4 addresses on active interfaces, Wi-Fi/Ethernet first.
    public static var ipv4Addresses: [String] {
        var found: [(name: String, address: String)] = []
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }

        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(entry.pointee.ifa_flags)
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let bytes = host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            found.append((String(cString: entry.pointee.ifa_name), String(decoding: bytes, as: UTF8.self)))
        }
        return found.sorted { $0.name.hasPrefix("en") && !$1.name.hasPrefix("en") }.map(\.address)
    }

    /// This Mac's tailnet name, when Tactile has a Tailscale certificate for it.
    static var tailscaleName: String?

    /// Every name the iPad might use to reach this Mac.
    static var reachableHosts: Set<String> {
        var hosts: Set<String> = ["localhost", "127.0.0.1"]
        hosts.formUnion(ipv4Addresses)
        if let name = bonjourName { hosts.insert(name.lowercased()) }
        if let name = tailscaleName { hosts.insert(name.lowercased()) }
        return hosts
    }
}
