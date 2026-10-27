import AppKit
import SwiftUI
import TactileCore

/// What the menu bar panel shows, kept current by `MenuBarController`.
final class PanelModel: ObservableObject {
    @Published var state: TactileService.Snapshot?
    @Published var trusted = true
    @Published var showDetails = false
    @Published var pauseWhenLocked = true
    @Published var notifyOnConnect = true
    @Published var openAtLogin = false
    @Published var loginAvailable = false
    @Published var confirmingRevoke: String?

    var actions = Actions()

    struct Actions {
        var setRunning: (Bool) -> Void = { _ in }
        var setPaused: (Bool) -> Void = { _ in }
        var setPauseWhenLocked: (Bool) -> Void = { _ in }
        var setUseTailscale: (Bool) -> Void = { _ in }
        var setOnlyMyDevices: (Bool) -> Void = { _ in }
        var setNotify: (Bool) -> Void = { _ in }
        var setOpenAtLogin: (Bool) -> Void = { _ in }
        var disconnect: (String) -> Void = { _ in }
        var reconnect: (String) -> Void = { _ in }
        var revoke: (String) -> Void = { _ in }
        var pair: () -> Void = {}
        var copyTailscaleLink: () -> Void = {}
        var allowAccessibility: () -> Void = {}
        var showLog: () -> Void = {}
        var quit: () -> Void = {}
    }
}

/// The panel that drops down from the Tactile icon, in the style of the Wi-Fi
/// and Control Center menus. Controls are drawn here rather than borrowed from
/// AppKit so the panel looks the same everywhere it's rendered.
struct MenuPanelView: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        VStack(spacing: 0) {
            header
            if needsAccessibility {
                ActionRow(symbol: "exclamationmark.triangle.fill", title: "Allow Accessibility Access…",
                          tint: Color(nsColor: .systemOrange), action: model.actions.allowAccessibility)
            }

            SectionTitle("Devices")
            devices

            SectionTitle("Options")
            options

            PanelDivider()
            ActionRow(symbol: "qrcode", title: "Pair a Device…", shortcut: "⌘P",
                      enabled: running, action: model.actions.pair)
            if state?.tailscaleURL != nil {
                ActionRow(symbol: "link", title: "Copy Tailscale Link", action: model.actions.copyTailscaleLink)
            }

            if model.showDetails, let state {
                PanelDivider()
                SectionTitle("Details")
                details(state)
            }

            PanelDivider()
            ActionRow(symbol: "xmark.circle", title: "Quit Tactile", shortcut: "⌘Q", action: model.actions.quit)
                .padding(.bottom, 6)
        }
        .frame(width: 330)
    }

    private var state: TactileService.Snapshot? { model.state }
    private var running: Bool { state?.running == true }
    private var needsAccessibility: Bool { !model.trusted && state?.dryRun != true }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 11) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Tactile").font(.system(size: 14, weight: .semibold))
                // Re-evaluated every second so "input flowing" fades when typing stops.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let status = status(at: context.date)
                    HStack(spacing: 5) {
                        Circle().fill(status.color).frame(width: 7, height: 7)
                        Text(status.text).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Spacer()
            PanelSwitch(isOn: running, label: "Tactile", large: true) { model.actions.setRunning(!running) }
                .disabled(state == nil)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private func status(at now: Date) -> (text: String, color: Color) {
        let gray = Color(nsColor: .tertiaryLabelColor)
        let orange = Color(nsColor: .systemOrange)
        guard let state else { return ("Starting…", gray) }
        if !state.running { return ("Off", gray) }
        if needsAccessibility { return ("Needs Accessibility access", orange) }
        if state.paused { return ("Input paused", orange) }
        if state.lockPaused { return ("Paused while Mac is locked", orange) }
        if state.connected.isEmpty { return ("Waiting for a device", gray) }
        let flowing = state.lastInput.contains { state.connected.contains($0.key) && now.timeIntervalSince($0.value) < 2 }
        return (flowing ? "Connected · input flowing" : "Connected", Color(nsColor: .systemGreen))
    }

    // MARK: Devices

    @ViewBuilder
    private var devices: some View {
        let list = orderedDevices
        if list.isEmpty {
            Text("No paired devices yet. Choose Pair a Device… to add your iPad.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
        } else {
            VStack(spacing: 4) {
                ForEach(list) { device in
                    DeviceCard(device: device, state: state!, model: model)
                }
            }
        }
    }

    /// Connected first, then devices held off from the menu, then the rest by last use.
    private var orderedDevices: [Pairing.Device] {
        guard let state else { return [] }
        func rank(_ device: Pairing.Device) -> Int {
            state.connected.contains(device.id) ? 0 : state.held.contains(device.id) ? 1 : 2
        }
        return state.devices.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    // MARK: Options

    private var options: some View {
        VStack(spacing: 0) {
            SwitchRow(symbol: "pause.circle", title: "Pause Input", shortcut: "⌃⌥⌘P",
                      isOn: state?.paused == true, enabled: running) { model.actions.setPaused(!(state?.paused ?? false)) }
            SwitchRow(symbol: "lock", title: "Pause While Mac Is Locked", isOn: model.pauseWhenLocked) {
                model.actions.setPauseWhenLocked(!model.pauseWhenLocked)
            }
            SwitchRow(symbol: "point.3.connected.trianglepath.dotted", title: "Use Tailscale",
                      isOn: state?.usesTailscale == true) { model.actions.setUseTailscale(!(state?.usesTailscale ?? false)) }
            if state?.usesTailscale == true {
                SwitchRow(symbol: "person.badge.shield.checkmark", title: "Only My Devices on Tailscale",
                          isOn: state?.onlyMyDevices == true) { model.actions.setOnlyMyDevices(!(state?.onlyMyDevices ?? true)) }
            }
            SwitchRow(symbol: "bell", title: "Notify When a Device Connects", isOn: model.notifyOnConnect) {
                model.actions.setNotify(!model.notifyOnConnect)
            }
            SwitchRow(symbol: "power", title: "Open at Login", isOn: model.openAtLogin, enabled: model.loginAvailable) {
                model.actions.setOpenAtLogin(!model.openAtLogin)
            }
        }
    }

    // MARK: Details (shown while ⌥ is held)

    private func details(_ state: TactileService.Snapshot) -> some View {
        let bytes = state.fingerprint.split(separator: " ")
        let fingerprint = bytes.count > 8 ? "\(bytes.prefix(4).joined(separator: " ")) … \(bytes.suffix(4).joined(separator: " "))" : state.fingerprint
        return VStack(spacing: 0) {
            DetailRow(label: "Setup page", value: state.setupHost)
            DetailRow(label: "Secure ports", value: state.portsSummary)
            DetailRow(label: "Certificate", value: fingerprint)
            if let expiry = state.tailscaleExpiry {
                DetailRow(label: "Tailscale cert expires", value: expiry.formatted(date: .abbreviated, time: .omitted))
            }
            ActionRow(symbol: "doc.text.magnifyingglass", title: "Show Log", action: model.actions.showLog)
        }
    }
}

// MARK: - Device card

private struct DeviceCard: View {
    let device: Pairing.Device
    let state: TactileService.Snapshot
    @ObservedObject var model: PanelModel
    @State private var hovering = false

    private var connected: Bool { state.connected.contains(device.id) }
    private var held: Bool { state.held.contains(device.id) }
    private var parts: (name: String, route: String) {
        let pieces = device.name.components(separatedBy: " · ")
        return (pieces.first ?? device.name, pieces.count > 1 ? pieces[1] : "")
    }

    var body: some View {
        HStack(spacing: 11) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(connected ? Color.accentColor : Color.primary.opacity(0.12))
                    .frame(width: 30, height: 30)
                    .overlay(Image(systemName: symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(connected ? Color.white : Color.secondary))
                if connected {
                    Circle().fill(Color(nsColor: .systemGreen)).frame(width: 9, height: 9)
                        .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(parts.name).font(.system(size: 13, weight: .medium))
                HStack(spacing: 4) {
                    if !parts.route.isEmpty { Image(systemName: routeSymbol).font(.system(size: 9, weight: .semibold)) }
                    Text(subtitle).lineLimit(1)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            if hovering {
                HStack(spacing: 6) {
                    if connected { Pill("Disconnect") { model.actions.disconnect(device.id) } }
                    if held { Pill("Reconnect") { model.actions.reconnect(device.id) } }
                    let confirming = model.confirmingRevoke == device.id
                    Pill(confirming ? "Confirm" : "Revoke", destructive: true) {
                        if confirming {
                            model.confirmingRevoke = nil
                            model.actions.revoke(device.id)
                        } else {
                            model.confirmingRevoke = device.id
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                if model.confirmingRevoke == device.id { model.confirmingRevoke = nil }
                            }
                        }
                    }
                }
            } else if connected, let ms = state.latency[device.id] {
                SignalBars(bars: Self.quality(ms).bars)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(hovering ? 0.1 : 0.05)))
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(parts.name), \(subtitle)")
    }

    private var subtitle: String {
        let route = parts.route.isEmpty ? "" : "\(parts.route) · "
        if connected {
            guard let ms = state.latency[device.id] else { return "\(route)Connected" }
            return "\(route)\(Self.quality(ms).label) · \(ms) ms"
        }
        if held { return "\(route)Disconnected" }
        return "\(route)last used \(device.lastSeen.formatted(.relative(presentation: .named)))"
    }

    private var symbol: String {
        switch parts.name {
        case "iPhone": return "iphone"
        case "Mac": return "laptopcomputer"
        case "Browser": return "globe"
        default: return "ipad.landscape"
        }
    }

    private var routeSymbol: String {
        switch parts.route {
        case "Tailscale": return "point.3.connected.trianglepath.dotted"
        case "Wi-Fi": return "wifi"
        case "Dry run": return "hammer"
        default: return "network"
        }
    }

    static func quality(_ ms: Int) -> (label: String, bars: Int) {
        switch ms {
        case ..<40: return ("Excellent", 4)
        case ..<90: return ("Good", 3)
        case ..<160: return ("Fair", 2)
        default: return ("Poor", 1)
        }
    }
}

// MARK: - Building blocks

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct PanelDivider: View {
    var body: some View {
        Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1)
            .padding(.horizontal, 14).padding(.vertical, 5)
    }
}

/// An on/off switch in the system's style.
private struct PanelSwitch: View {
    let isOn: Bool
    let label: String
    var large = false
    let toggle: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: toggle) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Color.accentColor : Color.primary.opacity(0.15))
                    .frame(width: large ? 34 : 30, height: large ? 20 : 18)
                Circle().fill(.white)
                    .frame(width: large ? 18 : 16, height: large ? 18 : 16)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                    .padding(1)
            }
            .animation(.snappy(duration: 0.18), value: isOn)
            .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

private struct SwitchRow: View {
    let symbol: String
    let title: String
    var shortcut: String?
    let isOn: Bool
    var enabled = true
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).frame(width: 18)
            Text(title).font(.system(size: 13))
            Spacer()
            if let shortcut { Text(shortcut).font(.system(size: 12)).foregroundStyle(.tertiary) }
            PanelSwitch(isOn: isOn, label: title, toggle: toggle)
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
        .contentShape(Rectangle())
        .onTapGesture { if enabled { toggle() } }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}

/// A menu-style row: highlights on hover, runs its action when clicked.
private struct ActionRow: View {
    let symbol: String
    let title: String
    var shortcut: String?
    var tint: Color?
    var enabled = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tint ?? .secondary).frame(width: 18)
                Text(title).font(.system(size: 13))
                Spacer()
                if let shortcut { Text(shortcut).font(.system(size: 12)).foregroundStyle(.tertiary) }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(hovering && enabled ? 0.1 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .onHover { hovering = $0 }
    }
}

private struct Pill: View {
    let text: String
    var destructive = false
    let action: () -> Void

    init(_ text: String, destructive: Bool = false, action: @escaping () -> Void) {
        self.text = text
        self.destructive = destructive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(destructive ? Color(nsColor: .systemRed) : Color.primary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}

private struct SignalBars: View {
    let bars: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(index < bars ? Color(nsColor: .systemGreen) : Color.primary.opacity(0.15))
                    .frame(width: 3, height: CGFloat(5 + index * 3))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
    }
}
