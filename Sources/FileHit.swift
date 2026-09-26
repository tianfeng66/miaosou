import Foundation

struct FileHit {
    let name: String
    let path: String
    let parent: String
    let size: Int64?
    let modified: Date?
    let isDirectory: Bool

    var fileURL: URL {
        URL(fileURLWithPath: path)
    }
}
