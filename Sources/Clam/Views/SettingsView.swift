import SwiftUI

// MARK: - Settings window

struct SettingsView: View {
    @AppStorage("preferredTerminal") private var preferredTerminalRaw: String = "Automatic"
    @ObservedObject private var launchAtLogin = LaunchAtLogin.shared

    private var preferredTerminal: Binding<TerminalLauncher.PreferredTerminal> {
        Binding(
            get: { TerminalLauncher.PreferredTerminal(rawValue: preferredTerminalRaw) ?? .automatic },
            set: { preferredTerminalRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Preferred terminal", selection: preferredTerminal) {
                    ForEach(TerminalLauncher.PreferredTerminal.installed) { terminal in
                        Text(terminal.displayName).tag(terminal)
                    }
                }
                .pickerStyle(.menu)

                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { _ in launchAtLogin.toggle() }
                ))
            } header: {
                Label("General", systemImage: "gearshape")
            }

            Section {
                LabeledContent("Sessions directory") {
                    Text("~/.claude/sessions/")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Usage cache") {
                    Text("~/.claude/usage-cache.json")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Session poll") {
                    Text("every 5 seconds")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Usage poll") {
                    Text("every 60 seconds")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("Data sources", systemImage: "folder")
            }

            Section {
                LabeledContent("Version") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("About", systemImage: "info.circle")
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 260)
    }
}

// MARK: - Display name helper

extension TerminalLauncher.PreferredTerminal {
    var displayName: String {
        switch self {
        case .automatic: return "Automatic (detect)"
        case .ghostty:   return "Ghostty"
        case .iterm2:    return "iTerm2"
        case .terminal:  return "Terminal"
        case .alacritty: return "Alacritty"
        case .wezterm:   return "WezTerm"
        }
    }
}
