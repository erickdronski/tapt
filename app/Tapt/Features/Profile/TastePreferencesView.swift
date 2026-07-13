import SwiftUI

enum TastePreferences {
    static let options = [
        "IPA", "Hazy IPA", "Pilsner", "Lager", "Stout", "Porter",
        "Sour", "Belgian", "Wheat", "Pale Ale", "No / Low"
    ]

    static func decode(_ rawValue: String) -> [String] {
        let selected = Set(rawValue.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
        return options.filter { selected.contains($0.lowercased()) }
    }

    static func encode<S: Sequence>(_ styles: S) -> String where S.Element == String {
        let selected = Set(styles.map { $0.lowercased() })
        return options.filter { selected.contains($0.lowercased()) }.joined(separator: ",")
    }

    static func matches(style: String, isNaLow: Bool, selectedStyles: [String]) -> Bool {
        let candidate = style.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return selectedStyles.contains { selected in
            switch selected.lowercased() {
            case "no / low":
                return isNaLow
            case "belgian":
                return candidate.contains("belgian")
                    || candidate.contains("tripel")
                    || candidate.contains("dubbel")
                    || candidate.contains("saison")
            case "wheat":
                return candidate.contains("wheat")
                    || candidate.contains("weiss")
                    || candidate.contains("weizen")
                    || candidate.contains("witbier")
            case "sour":
                return candidate.contains("sour")
                    || candidate.contains("gose")
                    || candidate.contains("berliner")
            default:
                return !candidate.isEmpty && candidate.contains(selected.lowercased())
            }
        }
    }
}

struct TasteStylePicker: View {
    @Binding var selection: Set<String>
    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(TastePreferences.options, id: \.self) { style in
                let isSelected = selection.contains(style)
                Button {
                    if isSelected { selection.remove(style) } else { selection.insert(style) }
                } label: {
                    Text(style)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(isSelected ? Brand.gold : Brand.surface, in: Capsule())
                        .foregroundStyle(isSelected ? Brand.malt : Brand.text)
                        .overlay(Capsule().stroke(isSelected ? Brand.gold : Brand.malt.opacity(0.15)))
                        .scaleEffect(isSelected ? 1.04 : 1)
                }
                .buttonStyle(.plain)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
            }
        }
    }
}

struct TastePreferencesView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @AppStorage("favoriteStyles") private var favoriteStyles = ""
    @State private var selected = Set<String>()
    @State private var loaded = false
    @State private var saving = false
    @State private var saveError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Choose what you reach for.")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(Brand.text)
                TasteStylePicker(selection: $selected)
                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Brand.copper)
                }
            }
            .padding()
        }
        .background(Brand.background)
        .navigationTitle("Favorite styles")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button { save() } label: {
                    if saving {
                        ProgressView()
                    } else {
                        Label("Save", systemImage: "checkmark")
                    }
                }
                .disabled(saving)
            }
        }
        .task { await load() }
    }

    @MainActor private func load() async {
        guard !loaded else { return }
        loaded = true
        selected = Set(TastePreferences.decode(favoriteStyles))
        guard let userId = session.user?.id else { return }
        do {
            let serverStyles = try await ProfileService.topStyles(userId: userId)
            selected = Set(TastePreferences.decode(serverStyles.joined(separator: ",")))
            favoriteStyles = TastePreferences.encode(selected)
        } catch {
            // The local copy remains usable when account preferences are offline.
        }
    }

    private func save() {
        saving = true
        saveError = nil
        let styles = TastePreferences.options.filter { selected.contains($0) }
        Task {
            do {
                if let userId = session.user?.id {
                    try await ProfileService.setTopStyles(styles, userId: userId)
                }
                favoriteStyles = TastePreferences.encode(styles)
                dismiss()
            } catch {
                saveError = "Favorite styles could not be saved. Try again."
            }
            saving = false
        }
    }
}
