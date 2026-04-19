import AppKit
import Foundation
import ServiceManagement

enum AppBehaviorPreferenceKey {
    static let hideWindowOnRecordingStart = "appBehavior.hideWindowOnRecordingStart"
    static let showWindowWhenRecordingStops = "appBehavior.showWindowWhenRecordingStops"
    static let activationPolicy = "appBehavior.activationPolicy"
    static let launchAtLogin = "appBehavior.launchAtLogin"
}

enum AppActivationPolicyPreference: String, CaseIterable, Identifiable {
    case regular
    case accessory

    var id: String { rawValue }

    var label: String {
        switch self {
        case .regular:
            return String(localized: "Dock'ta göster")
        case .accessory:
            return String(localized: "Yalnızca menü çubuğunda çalıştır")
        }
    }

    var resolvedPolicy: NSApplication.ActivationPolicy {
        switch self {
        case .regular:
            return .regular
        case .accessory:
            return .accessory
        }
    }
}

struct AppBehaviorPreferences: Equatable {
    var hideWindowOnRecordingStart = true
    var showWindowWhenRecordingStops = true
    var activationPolicy: AppActivationPolicyPreference = .regular
    var launchAtLogin = false

    var resolvedActivationPolicy: NSApplication.ActivationPolicy {
        activationPolicy.resolvedPolicy
    }
}

@MainActor
protocol LaunchAtLoginControlling {
    func setEnabled(_ isEnabled: Bool) throws
}

@MainActor
struct SMAppLaunchAtLoginController: LaunchAtLoginControlling {
    func setEnabled(_ isEnabled: Bool) throws {
        if isEnabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
