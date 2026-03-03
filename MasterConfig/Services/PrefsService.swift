import Foundation

@Observable
@MainActor
final class PrefsService {
    var prefs: AppPrefs = .default

    private let prefsURL: URL

    init() {
        let claudeRoot = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude")
        prefsURL = claudeRoot.appendingPathComponent("master-config-prefs.json")
        Task { await load() }
    }

    func load() async {
        guard FileManager.default.fileExists(atPath: prefsURL.path),
              let data = try? Data(contentsOf: prefsURL),
              let decoded = try? JSONDecoder().decode(AppPrefs.self, from: data) else { return }
        prefs = decoded
    }

    func save() async {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(prefs) else { return }
        try? FileManager.default.createDirectory(at: prefsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: prefsURL)
    }
}
