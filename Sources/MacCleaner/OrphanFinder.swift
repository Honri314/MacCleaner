import Foundation
import AppKit

struct OrphanFile: Identifiable, Hashable {
    /// URL은 요구사항이 아니라서 String id 사용 (Table selection 호환)
    var id: String { url.path }
    let url: URL

    var urlID: URL { url }
    let name: String
    let sizeBytes: Int64
    let sourceApp: String   // 흔적을 남긴 것으로 추정되는 앱 이름
    let bundleID: String?
    let risk: Risk

    enum Risk: Int, Comparable {
        case bundleID = 0   // 번들ID가 일치하는 설치 앱 없음 → 안전 제거
        case nameOnly = 1   // 앱 이름 휴리스틱 매칭 → 동명 다른 자원일 수 있음 (확인 권장)

        static func < (l: Risk, r: Risk) -> Bool { l.rawValue < r.rawValue }
    }

    var riskLabel: String {
        switch risk {
        case .bundleID: return "확인됨"
        case .nameOnly: return "이름 기반"
        }
    }

    var riskColor: String {
        switch risk {
        case .bundleID: return "green"
        case .nameOnly: return "orange"
        }
    }
}

@MainActor
final class OrphanFinder: ObservableObject {
    @Published private(set) var results: [OrphanFile] = []
    @Published private(set) var isScanning = false
    @Published private(set) var scannedOnce = false
    @Published var includeLowConfidence = true

    var totalSize: Int64 { results.reduce(0) { $0 + $1.sizeBytes } }
    var selectedTotalSize: Int64 { results.reduce(0) { $0 + $1.sizeBytes } }

    private let fm = FileManager.default

    func scan() async {
        isScanning = true
        defer { isScanning = false }

        let installed = installedBundleIDsAndNames()
        let home = fm.homeDirectoryForCurrentUser
        let lib = home.appendingPathComponent("Library")

        // 검색 대상 폴더 (정리 카테고리와는 별개 — 자주 있는 잔여 위치들)
        let searchRoots: [(dir: URL, kind: String)] = [
            (lib.appendingPathComponent("Application Support"), "appSupport"),
            (lib.appendingPathComponent("Caches"), "cache"),
            (lib.appendingPathComponent("Preferences"), "prefs"),
            (lib.appendingPathComponent("Containers"), "container"),
            (lib.appendingPathComponent("Group Containers"), "group"),
            (lib.appendingPathComponent("HTTPStorages"), "http"),
            (lib.appendingPathComponent("Logs"), "log"),
            (lib.appendingPathComponent("WebKit"), "webkit"),
            (lib.appendingPathComponent("Application Scripts"), "script"),
            (lib.appendingPathComponent("Saved Application State"), "savedState"),
            (lib.appendingPathComponent("Cookies"), "cookie"),
        ]

        var found: [OrphanFile] = []
        var seenPaths = Set<String>()

        for (root, _) in searchRoots {
            guard fm.fileExists(atPath: root.path) else { continue }
            let children = (try? fm.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey])) ?? []

            for url in children {
                if Task.isCancelled { return }
                let name = url.lastPathComponent
                guard !name.hasPrefix(".") else { continue }
                guard !seenPaths.contains(name) else { continue } // 같은 이름 반복 매칭 방지
                seenPaths.insert(name)

                // size 계산
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let size: Int64
                if isDir {
                    size = await Task.detached(priority: .utility) {
                        FileManager.default.directorySize(at: url)
                    }.value
                } else {
                    size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                }
                // 1MB 미만은 노이즈로 스킵 (plist 등)
                guard size >= 1_048_576 else { continue }

                // 매칭 판정
                let match = Self.matchOrphan(name: name,
                                             installedBundleIDs: installed.ids,
                                             installedNames: installed.names)
                guard let match else { continue } // 현재 설치된 앱 소유 → 스킵

                found.append(OrphanFile(url: url,
                                        name: name,
                                        sizeBytes: size,
                                        sourceApp: match.appName,
                                        bundleID: match.bundleID,
                                        risk: match.risk))
            }
        }

        results = found.sorted { $0.sizeBytes > $1.sizeBytes }
        scannedOnce = true
    }

    private struct InstallRecord {
        let ids: Set<String>
        let names: Set<String>
    }
    private func installedBundleIDsAndNames() -> (ids: Set<String>, names: Set<String>) {
        var ids: Set<String> = []
        var names: Set<String> = []
        let roots = [URL(fileURLWithPath: "/Applications"),
                     fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        for root in roots {
            let bundles = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            for url in bundles where url.pathExtension == "app" {
                if let bundle = Bundle(url: url), let bid = bundle.bundleIdentifier {
                    ids.insert(bid)
                }
                names.insert(url.deletingPathExtension().lastPathComponent)
            }
        }
        return (ids, names)
    }

    private static func matchOrphan(name: String,
                                    installedBundleIDs: Set<String>,
                                    installedNames: Set<String>) -> (appName: String, bundleID: String?, risk: OrphanFile.Risk)? {
        // 1) 번들ID 방식: com.company.Name.plist / com.company.Name 확장 제거 후 비교
        var withoutExt = (name as NSString).deletingPathExtension
        // .savedState 같은 접미사 제거
        let suffixes = [".savedState", ".plist"]
        for s in suffixes where withoutExt.hasSuffix(s) {
            withoutExt = String(withoutExt.dropLast(s.count))
        }
        // Group Containers 접미사 (com.apple.*, team-id.com.* 형식)
        var candidate = withoutExt
        if candidate.contains(".") {
            // 마지막 두 세그먼트 (com.x.Name) 비교를 위한 suffix 탐색
            let parts = candidate.split(separator: ".").map(String.init)
            if parts.count >= 2 {
                let two = parts.suffix(2).joined(separator: ".")
                if installedBundleIDs.contains(two) { return nil } // 설치된 것 → 스킵
                let three = parts.count >= 3 ? parts.suffix(3).joined(separator: ".") : two
                if installedBundleIDs.contains(three) { return nil }
            }
        }
        if installedBundleIDs.contains(candidate) { return nil }

        // 설치된 번들ID의 하위 매칭: com.apple.Name 처럼 Apple 시스템 자원이면 건드리지 않음
        if candidate.hasPrefix("com.apple.") || candidate.hasPrefix("Apple.") { return nil }

        // 2) 앱 이름 휴리스틱: 폴더/파일 이름이 설치 앱과 동일한지
        //  예: "Chrome" 캐시 폴더, "Slack" savedState 등
        let baseName = withoutExt.components(separatedBy: ".").last ?? withoutExt
        for app in installedNames {
            if baseName.caseInsensitiveCompare(app) == .orderedSame {
                // 설치 앱과 이름이 동일 → 현재 소유일 가능성 높음, 스킵
                return nil
            }
        }

        // 3) 흔적 소유자 추정: 설치 앱 중에서 이름이 유사한 것 찾기
        var bestApp: String = "알 수 없음"
        var bestBundle: String? = nil
        var risk: OrphanFile.Risk = .nameOnly

        // Preference-style에서 첫 세그먼트가 도메인 (예: com.google.)
        let domainPrefixes: [String: String] = [
            "com.google.": "Google", "org.mozilla.": "Mozilla", "com.apple.": "Apple",
            "net.": "", "io.github.": "", "com.microsoft.": "Microsoft", "com.jetbrains.": "JetBrains"
        ]
        for (prefix, appName) in domainPrefixes where candidate.hasPrefix(prefix) {
            bestApp = appName.isEmpty ? String(candidate.dropFirst(prefix.count)) : appName
            bestBundle = candidate
            break
        }
        if bestBundle == nil {
            bestBundle = withoutExt != name ? withoutExt : nil
        }

        return (appName: bestApp, bundleID: bestBundle, risk: risk)
    }

    @discardableResult
    func remove(_ file: OrphanFile) async -> Int64 {
        var freed = file.sizeBytes
        try? fm.trashItem(at: file.url, resultingItemURL: nil)
        await MainActor.run {
            results.removeAll { $0.id == file.id }
        }
        return freed
    }

    /// 다수 동시 삭제 (각각 휴지통으로)
    func removeAll(_ files: [OrphanFile]) async -> Int64 {
        var freed: Int64 = 0
        for f in files {
            freed += await remove(f)
        }
        return freed
    }

    func reveal(_ file: OrphanFile) {
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }
}
