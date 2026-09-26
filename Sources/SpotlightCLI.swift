import Foundation

enum SpotlightCLI {
    static func run(arguments: [String]) -> Never {
        var queryText = ""
        var json = false
        var i = 1
        while i < arguments.count {
            let arg = arguments[i]
            if arg == "--search" {
                i += 1
                var parts: [String] = []
                while i < arguments.count, !arguments[i].hasPrefix("--") {
                    parts.append(arguments[i])
                    i += 1
                }
                queryText = parts.joined(separator: " ")
                continue
            }
            if arg == "--json" {
                json = true
                i += 1
                continue
            }
            if arg == "--help" || arg == "-h" {
                fputs("用法: Miaosou --search <文件名> [--json]\n", stdout)
                exit(0)
            }
            i += 1
        }

        guard !queryText.isEmpty else {
            fputs("缺少 --search 关键词\n", stderr)
            exit(2)
        }

        let searcher = SpotlightSearch()
        var rows: [FileHit] = []
        var done = false
        searcher.setHandler { hits, _, finished in
            rows = hits
            if finished {
                done = true
                CFRunLoopStop(CFRunLoopGetMain())
            }
        }
        searcher.search(text: queryText, kind: .all, scope: .home, hideSystem: true)

        let deadline = Date().addingTimeInterval(12)
        while !done, Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        if json {
            let payload: [[String: Any]] = rows.map { hit in
                var item: [String: Any] = [
                    "name": hit.name,
                    "path": hit.path,
                    "directory": hit.isDirectory
                ]
                if let size = hit.size { item["size"] = size }
                if let modified = hit.modified {
                    item["modified"] = ISO8601DateFormatter().string(from: modified)
                }
                return item
            }
            let data = try! JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        } else {
            for hit in rows {
                print(hit.path)
            }
            fputs("共 \(rows.count) 项\n", stderr)
        }
        exit(0)
    }
}
