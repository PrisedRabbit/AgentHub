//
//  SettingsView.swift
//  AgentHub
//
//  Settings panel for app configuration.
//

import SwiftUI

public struct SettingsView: View {
  @AppStorage(AgentHubDefaults.smartModeEnabled)
  private var smartModeEnabled: Bool = false

  @AppStorage(AgentHubDefaults.flatSessionLayout)
  private var flatSessionLayout: Bool = false

  @AppStorage(AgentHubDefaults.terminalFontSize)
  private var terminalFontSize: Double = 12

  @AppStorage(AgentHubDefaults.terminalFontName)
  private var terminalFontName: String = "SF Mono"

  @AppStorage(AgentHubDefaults.webServerEnabled)
  private var webServerEnabled: Bool = false

  #if DEBUG
  @AppStorage(AgentHubDefaults.webServerPort) private var webServerPort: Int = 8081
  #else
  @AppStorage(AgentHubDefaults.webServerPort) private var webServerPort: Int = 8080
  #endif

  @AppStorage(AgentHubDefaults.notificationSoundsEnabled)
  private var notificationSoundsEnabled: Bool = true

  @AppStorage(AgentHubDefaults.pushNotificationsEnabled)
  private var pushNotificationsEnabled: Bool = true

  @AppStorage(AgentHubDefaults.claudeCommand)
  private var claudeCommand: String = "claude"

  @AppStorage(AgentHubDefaults.codexCommand)
  private var codexCommand: String = "codex"

  @AppStorage(AgentHubDefaults.claudeCommandLockedByDeveloper)
  private var claudeCommandLocked: Bool = false

  @AppStorage(AgentHubDefaults.codexCommandLockedByDeveloper)
  private var codexCommandLocked: Bool = false

  @Environment(ThemeManager.self) private var themeManager
  @AppStorage(AgentHubDefaults.selectedTheme) private var selectedThemeId: String = "claude"
  private let defaultThemeId = "claude"

  private var availableFonts: [String] {
    NSFontManager.shared.availableFontFamilies
      .filter { NSFont(name: $0, size: 12)?.isFixedPitch == true }
      .sorted()
  }

  public init() {}

  public var body: some View {
    TabView {
      generalTab
        .tabItem { Label("General", systemImage: "gear") }

      appearanceTab
        .tabItem { Label("Appearance", systemImage: "paintbrush") }

      terminalTab
        .tabItem { Label("Terminal", systemImage: "character.cursor.ibeam") }

      notificationsTab
        .tabItem { Label("Notifications", systemImage: "bell") }

      cliTab
        .tabItem { Label("CLI", systemImage: "terminal") }
    }
    .frame(width: 420, height: 260)
    .task {
      await ensureSupportedThemeSelection()
      if !availableFonts.contains(terminalFontName), let first = availableFonts.first {
        terminalFontName = first
      }
    }
  }

  // MARK: - Tabs

  private var generalTab: some View {
    Form {
      Section("Features") {
        Toggle(isOn: $smartModeEnabled) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Smart mode")
            Text("Use AI to plan and orchestrate multi-session launches")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
        Toggle(isOn: $flatSessionLayout) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Flat session layout")
            Text("Show all sessions without per-repository sections")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
      }
    }
    .formStyle(.grouped)
  }

  private var cliTab: some View {
    Form {
      Section("CLI Status") {
        DisclosureGroup {
          HStack {
            Text("Command:")
              .foregroundColor(.secondary)
            TextField("claude", text: $claudeCommand)
              .textFieldStyle(.roundedBorder)
              .disabled(claudeCommandLocked)
            if claudeCommandLocked {
              Image(systemName: "lock.fill")
                .foregroundColor(.secondary)
                .font(.caption)
            }
          }
          .padding(.vertical, 4)
        } label: {
          HStack {
            Text("Claude")
              .foregroundColor(Color.brandPrimary(for: .claude))
            Spacer()
            if CLIDetectionService.isClaudeInstalled() {
              Label("Installed", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.caption)
            } else {
              Label("Not Installed", systemImage: "xmark.circle.fill")
                .foregroundColor(.secondary)
                .font(.caption)
            }
          }
        }

        DisclosureGroup {
          HStack {
            Text("Command:")
              .foregroundColor(.secondary)
            TextField("codex", text: $codexCommand)
              .textFieldStyle(.roundedBorder)
              .disabled(codexCommandLocked)
            if codexCommandLocked {
              Image(systemName: "lock.fill")
                .foregroundColor(.secondary)
                .font(.caption)
            }
          }
          .padding(.vertical, 4)
        } label: {
          HStack {
            Text("Codex")
              .foregroundColor(Color.brandPrimary(for: .codex))
            Spacer()
            if CLIDetectionService.isCodexInstalled() {
              Label("Installed", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.caption)
            } else {
              Label("Not Installed", systemImage: "xmark.circle.fill")
                .foregroundColor(.secondary)
                .font(.caption)
            }
          }
        }
      }
    }
    .formStyle(.grouped)
  }

  private var terminalTab: some View {
    Form {
      Section("Terminal") {
        Picker("Font", selection: $terminalFontName) {
          ForEach(availableFonts, id: \.self) { name in
            Text(name).tag(name)
          }
        }
        .onChange(of: terminalFontName) { _, newValue in
          if !availableFonts.contains(newValue), let first = availableFonts.first {
            terminalFontName = first
          }
        }

        Stepper(value: $terminalFontSize, in: 8...24, step: 1) {
          HStack {
            Text("Font size")
            Spacer()
            Text("\(Int(terminalFontSize)) pt")
              .foregroundColor(.secondary)
              .monospacedDigit()
          }
        }
      }
    }
    .formStyle(.grouped)
  }

  private var notificationsTab: some View {
    Form {
      Section("Notifications") {
        Toggle(isOn: $notificationSoundsEnabled) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Notification sounds")
            Text("Play a sound when tools require approval")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
        Toggle(isOn: $pushNotificationsEnabled) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Push notifications")
            Text("Show a notification banner when tools require approval")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
      }
    }
    .formStyle(.grouped)
  }

  private var appearanceTab: some View {
    Form {
      Section {
        Toggle(isOn: $webServerEnabled) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Web terminal")
            Text("Stream terminal sessions to a browser")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }

        Stepper(value: $webServerPort, in: 1024...65535, step: 1) {
          HStack {
            Text("Port")
            Spacer()
            Text("\(webServerPort)")
              .foregroundColor(.secondary)
              .monospacedDigit()
          }
        }
        .disabled(!webServerEnabled)

        if webServerEnabled {
          let address = "http://\(localIPAddress()):\(webServerPort)"
          HStack {
            Text(address)
              .font(.caption)
              .foregroundColor(.secondary)
              .textSelection(.enabled)
            Spacer()
            Button {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(address, forType: .string)
            } label: {
              Image(systemName: "doc.on.doc")
                .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Copy address")
          }
          Text("Restart app to apply changes")
            .font(.caption2)
            .foregroundColor(.secondary)
        }
      } header: {
        Text("Web Terminal")
      }

      Section {
        Picker("Theme", selection: themeSelectionBinding) {
          Text("Default").tag(defaultThemeId)
          ForEach(themeManager.availableYAMLThemes) { theme in
            Text(theme.name).tag(theme.id)
          }
        }

        HStack(spacing: 8) {
          Button(action: {
            Task { await themeManager.discoverThemes() }
          }) {
            Image(systemName: "arrow.clockwise")
          }
          .help("Refresh theme list")
        }
      } header: {
        Text("Theme")
      } footer: {
        if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
          Text("AgentHub v\(appVersion)")
            .font(.caption)
        }
      }
    }
    .formStyle(.grouped)
  }

  // MARK: - Theme Helpers

  private var themeSelectionBinding: Binding<String> {
    Binding(
      get: {
        let yamlIds = themeManager.availableYAMLThemes.map(\.id)
        return yamlIds.contains(selectedThemeId) ? selectedThemeId : defaultThemeId
      },
      set: { newValue in
        Task { await applyThemeSelection(newValue) }
      }
    )
  }

  private func ensureSupportedThemeSelection() async {
    if selectedThemeId == defaultThemeId {
      themeManager.loadBuiltInTheme(.claude)
      return
    }

    if let theme = themeManager.availableYAMLThemes.first(where: { $0.id == selectedThemeId }),
       let fileURL = theme.fileURL {
      try? await themeManager.loadTheme(fileURL: fileURL)
      return
    }

    selectedThemeId = defaultThemeId
    themeManager.loadBuiltInTheme(.claude)
  }

  private func applyThemeSelection(_ selection: String) async {
    if selection == defaultThemeId {
      selectedThemeId = defaultThemeId
      themeManager.loadBuiltInTheme(.claude)
      return
    }

    await themeManager.discoverThemes()

    if let theme = themeManager.availableYAMLThemes.first(where: { $0.id == selection }),
       let fileURL = theme.fileURL {
      try? await themeManager.loadTheme(fileURL: fileURL)
      selectedThemeId = theme.id
      return
    }

    selectedThemeId = defaultThemeId
    themeManager.loadBuiltInTheme(.claude)
  }

  private func localIPAddress() -> String {
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return "localhost" }
    defer { freeifaddrs(ifaddr) }
    for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
      let sa = ptr.pointee.ifa_addr.pointee
      guard sa.sa_family == UInt8(AF_INET) else { continue }
      let name = String(cString: ptr.pointee.ifa_name)
      guard name == "en0" || name == "en1" else { continue }
      var addr = ptr.pointee.ifa_addr.pointee
      var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      getnameinfo(&addr, socklen_t(sa.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
      return String(cString: hostname)
    }
    return "localhost"
  }
}
