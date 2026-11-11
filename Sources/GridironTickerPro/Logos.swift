import AppKit

/// Team logos for the ticker. Each logo is fetched once at 64 px (the dark-background
/// version when ESPN has one), kept on disk, and wrapped in a single text attachment per
/// team so unchanged ticker text still compares equal and isn't redrawn.
@MainActor
final class LogoStore {
    static let shared = LogoStore()

    /// Called (at most twice a second) after new logos arrive, so the ticker can redraw.
    var onLoad: (() -> Void)?
    private(set) var size: CGFloat = 26

    /// Match the logos to the ticker's text size (26 pt logos at the default 22 pt text).
    func configure(fontSize: CGFloat) {
        let new = (fontSize * 26 / 22).rounded()
        guard new != size else { return }
        size = new
        attachments.removeAll()
    }

    private var attachments: [String: NSTextAttachment] = [:]
    private var loading = Set<String>()
    private var missing = Set<String>()   // no logo on ESPN; don't ask again this run
    private var reloadPending = false

    private let cacheDir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("app.gridirontickerpro.mac/logos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// The logo for a team, or nil while it loads (or if there isn't one).
    func attachment(for teamID: String, font: NSFont) -> NSTextAttachment? {
        if let a = attachments[teamID] { return a }
        guard !teamID.isEmpty, !teamID.hasPrefix("-"), !missing.contains(teamID), loading.insert(teamID).inserted else { return nil }
        let file = cacheDir.appendingPathComponent("\(teamID).png")
        if let img = NSImage(contentsOf: file) {
            loading.remove(teamID)
            return store(img, for: teamID, font: font)
        }
        Task {
            let (data, notFound) = await Self.download(teamID)
            loading.remove(teamID)
            // A network hiccup gets retried on a later redraw; only a real 404 is remembered.
            guard let data, let img = NSImage(data: data) else { if notFound { missing.insert(teamID) }; return }
            try? data.write(to: file)
            _ = store(img, for: teamID, font: font)
            scheduleReload()
        }
        return nil
    }

    private func store(_ img: NSImage, for teamID: String, font: NSFont) -> NSTextAttachment {
        img.size = NSSize(width: size, height: size)
        let a = NSTextAttachment()
        a.image = img
        // Center the logo on the capital letters of the team name.
        a.bounds = CGRect(x: 0, y: ((font.capHeight - size) / 2).rounded(), width: size, height: size)
        attachments[teamID] = a
        return a
    }

    private func scheduleReload() {
        guard !reloadPending else { return }
        reloadPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.reloadPending = false
            self?.onLoad?()
        }
    }

    private nonisolated static func download(_ teamID: String) async -> (Data?, notFound: Bool) {
        var notFound = true
        for variant in ["500-dark", "500"] {
            guard let url = URL(string: "https://a.espncdn.com/combiner/i?img=/i/teamlogos/nfl/\(variant)/\(teamID).png&w=64&h=64"),
                  let (data, resp) = try? await URLSession.shared.data(from: url) else { notFound = false; continue }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 200, !data.isEmpty { return (data, false) }
            if code != 404 { notFound = false }
        }
        return (nil, notFound)
    }
}
