import Foundation

enum ByteFmt {
    static func string(_ bytes: Int64) -> String {
        let v = Double(max(bytes, 0))
        let gb = 1 << 30, mb = 1 << 20, kb = 1 << 10
        if v >= Double(gb) { return String(format: "%.1f GB", v / Double(gb)) }
        if v >= Double(mb) { return String(format: "%.1f MB", v / Double(mb)) }
        if v >= Double(kb) { return String(format: "%.0f KB", v / Double(kb)) }
        return String(format: "%.0f B", v)
    }
}

extension FileManager {
    /// 디렉터리 전체 크기 계산
    func directorySize(at url: URL) -> Int64 {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            let vals = try? url.resourceValues(forKeys: [.fileSizeKey])
            return Int64(vals?.fileSize ?? 0)
        }
        var total: Int64 = 0
        guard let en = self.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [],
            errorHandler: { _, _ in true }) else { return 0 }
        while let next = en.nextObject() {
            guard let fileURL = next as? URL else { continue }
            if let vals = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
               vals.isRegularFile == true {
                total += Int64(vals.fileSize ?? 0)
            }
        }
        return total
    }

    func topLevelChildren(of url: URL) -> [URL] {
        (try? self.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
    }
}
