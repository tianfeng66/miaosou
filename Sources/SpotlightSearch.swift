import Foundation

enum KindFilter: Int {
    case all = 0
    case files = 1
    case folders = 2
    case images = 3
    case videos = 4
    case documents = 5
}

enum SearchScope: Int {
    case home = 0
    case computer = 1
}

final class SpotlightSearch {
    static let displayLimit = 800

    private let query = NSMetadataQuery()
    private var onUpdate: (([FileHit], Int, Bool) -> Void)?

    init() {
        query.operationQueue = .main
        query.valueListAttributes = [
            NSMetadataItemFSNameKey,
            NSMetadataItemPathKey,
            NSMetadataItemFSSizeKey,
            NSMetadataItemFSContentChangeDateKey,
            NSMetadataItemContentTypeKey,
            NSMetadataItemContentTypeTreeKey
        ]

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(queryChanged(_:)), name: .NSMetadataQueryDidStartGathering, object: query)
        nc.addObserver(self, selector: #selector(queryChanged(_:)), name: .NSMetadataQueryGatheringProgress, object: query)
        nc.addObserver(self, selector: #selector(queryChanged(_:)), name: .NSMetadataQueryDidUpdate, object: query)
        nc.addObserver(self, selector: #selector(queryChanged(_:)), name: .NSMetadataQueryDidFinishGathering, object: query)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        query.stop()
    }

    func setHandler(_ handler: @escaping ([FileHit], Int, Bool) -> Void) {
        onUpdate = handler
    }

    func stop() {
        if query.isStarted {
            query.stop()
        }
    }

    func search(text: String, kind: KindFilter, scope: SearchScope, hideSystem: Bool) {
        stop()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            onUpdate?([], 0, true)
            return
        }
        guard let predicate = Self.makePredicate(text: trimmed, kind: kind, hideSystem: hideSystem) else {
            onUpdate?([], 0, true)
            return
        }

        currentHideSystem = hideSystem
        query.predicate = predicate
        query.searchScopes = Self.scopes(for: scope)
        query.start()
        collect(hideSystem: hideSystem, finished: false)
    }

    @objc private func queryChanged(_ notification: Notification) {
        let finished = notification.name == .NSMetadataQueryDidFinishGathering
        collect(hideSystem: currentHideSystem, finished: finished)
    }

    private var currentHideSystem = true

    func rememberHideSystem(_ hide: Bool) {
        currentHideSystem = hide
    }

    private func collect(hideSystem: Bool, finished: Bool) {
        query.disableUpdates()
        defer { query.enableUpdates() }

        let total = query.resultCount
        let scanCap = min(total, hideSystem ? 4000 : Self.displayLimit)
        var hits: [FileHit] = []
        hits.reserveCapacity(min(scanCap, Self.displayLimit))

        for i in 0..<scanCap {
            if hits.count >= Self.displayLimit { break }
            guard let item = query.result(at: i) as? NSMetadataItem else { continue }
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            if hideSystem, Self.isSystemPath(path) { continue }

            let name = (item.value(forAttribute: NSMetadataItemFSNameKey) as? String)
                ?? (path as NSString).lastPathComponent
            let size = item.value(forAttribute: NSMetadataItemFSSizeKey) as? Int64
            let modified = item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date
            let tree = item.value(forAttribute: NSMetadataItemContentTypeTreeKey) as? [String] ?? []
            let uti = item.value(forAttribute: NSMetadataItemContentTypeKey) as? String ?? ""
            let isDirectory = uti == "public.folder" || tree.contains("public.folder")

            hits.append(
                FileHit(
                    name: name,
                    path: path,
                    parent: (path as NSString).deletingLastPathComponent,
                    size: size,
                    modified: modified,
                    isDirectory: isDirectory
                )
            )
        }

        onUpdate?(hits, total, finished)
    }

    private static func scopes(for scope: SearchScope) -> [Any] {
        switch scope {
        case .home:
            return [
                NSMetadataQueryUserHomeScope,
                URL(fileURLWithPath: "/Applications"),
                URL(fileURLWithPath: NSHomeDirectory() + "/Applications")
            ]
        case .computer:
            return [NSMetadataQueryIndexedLocalComputerScope]
        }
    }

    static func isSystemPath(_ path: String) -> Bool {
        path.hasPrefix("/System/")
            || path.hasPrefix("/Library/")
            || path.hasPrefix("/private/")
            || path.hasPrefix("/usr/")
            || path.hasPrefix("/bin/")
            || path.hasPrefix("/sbin/")
            || path.hasPrefix("/opt/homebrew/Cellar/")
    }

    static func makePredicate(text: String, kind: KindFilter, hideSystem: Bool = true) -> NSPredicate? {
        let tokens = text.split { $0.isWhitespace || $0 == "\n" }.map(String.init)
        guard !tokens.isEmpty else { return nil }

        var parts: [NSPredicate] = []
        if hideSystem {
            for prefix in ["/System/", "/Library/", "/private/", "/usr/", "/bin/", "/sbin/"] {
                parts.append(NSPredicate(format: "NOT (%K BEGINSWITH %@)", NSMetadataItemPathKey, prefix))
            }
        }
        for token in tokens {
            if let extra = specialPredicate(token) {
                parts.append(extra)
                continue
            }
            let pattern = likePattern(from: token)
            if token.contains("/") {
                parts.append(NSPredicate(format: "%K LIKE[cd] %@", NSMetadataItemPathKey, pattern))
            } else {
                parts.append(NSPredicate(format: "%K LIKE[cd] %@", NSMetadataItemFSNameKey, pattern))
            }
        }

        if let kindPred = kindPredicate(kind) {
            parts.append(kindPred)
        }
        return NSCompoundPredicate(andPredicateWithSubpredicates: parts)
    }

    private static func specialPredicate(_ token: String) -> NSPredicate? {
        let lower = token.lowercased()
        if lower.hasPrefix("ext:") {
            let ext = String(token.dropFirst(4)).trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard !ext.isEmpty else { return nil }
            return NSPredicate(format: "%K LIKE[cd] %@", NSMetadataItemFSNameKey, "*.\(escapeLikeLiterals(ext))")
        }
        if lower == "file:" || lower == "files:" {
            return NSPredicate(format: "NOT (%K == %@)", NSMetadataItemContentTypeKey, "public.folder")
        }
        if lower == "folder:" || lower == "folders:" {
            return NSPredicate(format: "%K == %@", NSMetadataItemContentTypeKey, "public.folder")
        }
        return nil
    }

    private static func kindPredicate(_ kind: KindFilter) -> NSPredicate? {
        switch kind {
        case .all:
            return nil
        case .files:
            return NSPredicate(format: "NOT (%K == %@)", NSMetadataItemContentTypeKey, "public.folder")
        case .folders:
            return NSPredicate(format: "%K == %@", NSMetadataItemContentTypeKey, "public.folder")
        case .images:
            return NSPredicate(format: "%K == %@", NSMetadataItemContentTypeTreeKey, "public.image")
        case .videos:
            return NSPredicate(format: "%K == %@", NSMetadataItemContentTypeTreeKey, "public.movie")
        case .documents:
            return NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "NOT (%K == %@)", NSMetadataItemContentTypeKey, "public.folder"),
                NSPredicate(format: "NOT (%K == %@)", NSMetadataItemContentTypeTreeKey, "public.image"),
                NSPredicate(format: "NOT (%K == %@)", NSMetadataItemContentTypeTreeKey, "public.movie"),
                NSPredicate(format: "NOT (%K == %@)", NSMetadataItemContentTypeTreeKey, "public.audio")
            ])
        }
    }

    private static func likePattern(from token: String) -> String {
        if token.contains("*") || token.contains("?") {
            return escapeLikeLiterals(token, keepWildcards: true)
        }
        return "*" + escapeLikeLiterals(token, keepWildcards: false) + "*"
    }

    private static func escapeLikeLiterals(_ token: String, keepWildcards: Bool = false) -> String {
        var out = ""
        for ch in token {
            switch ch {
            case "*", "?":
                if keepWildcards {
                    out.append(ch)
                } else {
                    out.append("\\")
                    out.append(ch)
                }
            case "[", "]", "\\":
                out.append("\\")
                out.append(ch)
            default:
                out.append(ch)
            }
        }
        return out
    }
}
