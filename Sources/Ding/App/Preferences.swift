import Foundation

/// User settings, persisted to UserDefaults as they change.
@MainActor
final class Preferences: ObservableObject {
    private let defaults = UserDefaults.standard
    private static let characterKey = "character"

    /// Name of the chosen character (a bundled animation or one of your images).
    @Published var characterName: String {
        didSet { defaults.set(characterName, forKey: Self.characterKey) }
    }

    init() {
        characterName = defaults.string(forKey: Self.characterKey) ?? ""
    }

    /// The chosen character, or the first one available.
    var character: Character? {
        let all = Character.all
        return all.first { $0.name == characterName } ?? all.first
    }
}
