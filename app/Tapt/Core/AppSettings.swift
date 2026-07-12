import SwiftUI

/// App appearance override (persisted via @AppStorage "appearance").
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// In-app language override. iOS applies bundle localization on next launch,
/// so the picker shows a "reopen to apply" note after a change.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, es, de, fr, ja, ptBR

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .en: "English"
        case .es: "Español"
        case .de: "Deutsch"
        case .fr: "Français"
        case .ja: "日本語"
        case .ptBR: "Português (BR)"
        }
    }

    var localeCode: String? {
        switch self {
        case .system: nil
        case .ptBR: "pt-BR"
        default: rawValue
        }
    }

    /// Apply as the app-specific language override (standard iOS mechanism).
    func apply() {
        if let code = localeCode {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
    }
}

enum AppInfo {
    static var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

enum AppLinks {
    static let webBase = "https://taptbeer.com"
    static let privacy = webBase + "/privacy"
    static let terms = webBase + "/terms"
}
