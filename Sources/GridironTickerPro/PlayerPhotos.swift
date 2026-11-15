import AppKit

/// Player headshots from ESPN's image server, fetched once per player at a small size and kept on disk.
/// Never bundled with the app; a missing photo just means the card shows initials.
@MainActor
final class PlayerPhotos {
    static let shared = PlayerPhotos()
    var onLoad: (() -> Void)?

    private var images: [String: NSImage] = [:]
    private var loading = Set<String>()
    private var missing = Set<String>()
    private var reloadPending = false
    private let dir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("app.gridirontickerpro.mac/photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    func image(for playerID: String) -> NSImage? {
        if let i = images[playerID] { return i }
        guard !playerID.isEmpty, !missing.contains(playerID), loading.insert(playerID).inserted else { return nil }
        let file = dir.appendingPathComponent("\(playerID).png")
        if let img = NSImage(contentsOf: file) {
            loading.remove(playerID)
            images[playerID] = img
            return img
        }
        Task {
            let result = await Self.download(playerID)
            loading.remove(playerID)
            guard let data = result.data, let img = NSImage(data: data) else { if result.notFound { missing.insert(playerID) }; return }
            try? data.write(to: file)
            images[playerID] = img
            scheduleReload()
        }
        return nil
    }

    private func scheduleReload() {
        guard !reloadPending else { return }
        reloadPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.reloadPending = false
            self?.onLoad?()
        }
    }

    private nonisolated static func download(_ id: String) async -> (data: Data?, notFound: Bool) {
        guard let url = URL(string: "https://a.espncdn.com/combiner/i?img=/i/headshots/nfl/players/full/\(id).png&w=96&h=70"),
              let (data, resp) = try? await URLSession.shared.data(from: url) else { return (nil, false) }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        return code == 200 && !data.isEmpty ? (data, false) : (nil, code == 404)
    }
}
