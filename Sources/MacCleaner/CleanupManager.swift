import Foundation
import SwiftUI

struct CleanupCategory: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let paths: [URL]
    var size: Int64 = 0
    var scanned: Bool = false

    /// 휴지통은 trashItem을 못 쓰므로 직접 삭제
    var isTrash: Bool { id == "trash" }
}

@MainActor
final class CleanupManager: ObservableObject {
    @Published private(set) var categories: [CleanupCategory] = []
    @Published var isScanning = false
    @Published var selectedIDs: Set<String> = []

    @Published private(set) var scannedOnce = false
    /// 스캔 진행률 (0~100) — 카테고리 완료 개수 기반
    @Published private(set) var scanProgress: Double = 0
    var scanProgressText: String { "\(Int(scanProgress))%" }

    var junkTotal: Int64 { categories.reduce(0) { $0 + $1.size } }
    var selectedTotal: Int64 {
        categories.filter { selectedIDs.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    private let home = FileManager.default.homeDirectoryForCurrentUser

    init() { buildCategories() }

    private func buildCategories() {
        var cats: [CleanupCategory] = []
        func add(_ id: String, _ name: String, _ desc: String, _ icon: String, _ paths: [String]) {
            let urls = paths.map { home.appendingPathComponent($0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !urls.isEmpty else { return }
            cats.append(CleanupCategory(id: id, name: name, description: desc, icon: icon, paths: urls))
        }
        add("userCache", "사용자 캐시", "앱이 임시로 저장한 캐시. 정리해도 자동으로 다시 생성됩니다.", "folder.badge.questionmark", ["Library/Caches", "Library/Saved Application State"])
        add("logs", "로그 파일", "앱·시스템 로그. 필요 시 자동 재생성됩니다.", "doc.text.below.ecg", ["Library/Logs"])
        add("xcodeDerived", "Xcode 파생 데이터", "Xcode 빌드 캐시. 다음 빌드 때 다시 생성됩니다.", "hammer", ["Library/Developer/Xcode/DerivedData"])
        add("xcodeSupport", "Xcode 디바이스 지원", "연결한 iPhone/iPad 디버그 데이터.", "iphone.gen2.badge.gear", ["Library/Developer/Xcode/iOS DeviceSupport"])
        add("simulator", "시뮬레이터 캐시", "iOS 시뮬레이터 임시파일.", "apps.iphone", ["Library/Developer/CoreSimulator/Caches"])
        add("homebrew", "Homebrew 캐시", "brew 다운로드 임시파일.", "terminal", ["Library/Caches/Homebrew"])
        add("swiftpm", "SwiftPM 캐시", "스위프트 패키지 매니저 캐시.", "swift", ["Library/Caches/org.swift.swiftpm"])
        add("npm", "npm 캐시", "Node.js 패키지 캐시.", "curlybraces", [".npm"])
        add("pip", "pip 캐시", "Python 패키지 캐시.", "chevron.left.forwardslash.chevron.right", ["Library/Caches/pip"])
        add("trash", "휴지통", "삭제되지 않고 남아있는 파일들.", "trash", [".Trash"])
        // '시스템 데이터 분석' 카드 연동 — 분석에 나오는 정리 가능 항목을 정리 탭에도 노출
        add("simulator", "시뮬레이터 캐시", "iOS 시뮬레이터 임시파일.", "apps.iphone", ["Library/Developer/CoreSimulator/Caches"])
        add("cloudKitCache", "CloudKit 캐시", "iCloud 동기화 임시 데이터. 재생성됩니다.", "icloud", ["Library/Caches/CloudKit"])
        add("iosDeviceService", "iOS 기기 서비스", "iPhone/iPad 연결 시 쌓인 임시데이터.", "iphone.gen2", ["Library/Containers/com.apple.configurator.xpc.DeviceService"])
        add("containerCaches", "앱 컨테이너 캐시", "설치된 앱 컨테이너의 Caches 폴더 내용물만 (앱 데이터는 유지).", "shippingbox", ["__containerCaches__"])
        categories = cats
        selectedIDs = Set(cats.map(\.id))
    }

    /// containerCaches 항목의 실제 대상 경로 (동적 수집): 각 앱 컨테이너의 Data/Library/Caches
    nonisolated static func containerCachePaths(home: URL) -> [URL] {
        let roots = ["Library/Containers", "Library/Group Containers"].map { home.appendingPathComponent($0) }
        var out: [URL] = []
        for root in roots {
            guard let children = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
            for child in children {
                // 컨테이너 하위 Data/Library/Caches
                let c1 = child.appendingPathComponent("Data/Library/Caches")
                if FileManager.default.fileExists(atPath: c1.path) { out.append(c1) }
                // Group Containers는 group.<id>/Library/Caches
                let c2 = child.appendingPathComponent("Library/Caches")
                if FileManager.default.fileExists(atPath: c2.path) { out.append(c2) }
            }
        }
        return out
    }

    func scan() async {
        isScanning = true
        scanProgress = 0
        defer { isScanning = false; scanProgress = 100 }
        // containerCaches 실제 경로 주입 (동적 수집)
        if let i = categories.firstIndex(where: { $0.id == "containerCaches" }) {
            let fm = FileManager.default
            let paths = Self.containerCachePaths(home: home)
            if paths.count == 0 {
                // 대상 없으면 항목 자체를 숨김
                var updated = categories
                updated.remove(at: i)
                categories = updated
                selectedIDs.remove("containerCaches")
            } else {
                var updated = categories
                updated[i] = CleanupCategory(id: "containerCaches", name: "앱 컨테이너 캐시", description: "설치된 앱 컨테이너의 Caches 폴더 내용물만 (앱 데이터는 유지).", icon: "shippingbox", paths: paths)
                categories = updated
            }
        }
        let snapshot = categories
        let done = snapshot.count
        var finished = 0
        let results = await withTaskGroup(of: (String, Int64).self) { group -> [(String, Int64)] in
            for c in snapshot {
                group.addTask {
                    let size = Self.computeSize(of: c)
                    return (c.id, size)
                }
            }
            var out: [(String, Int64)] = []
            for await r in group {
                out.append(r)
                finished += 1
                self.scanProgress = Double(finished) / Double(done) * 100
            }
            return out
        }
        var updated = categories
        for (id, size) in results {
            if let i = updated.firstIndex(where: { $0.id == id }) {
                updated[i].size = size
                updated[i].scanned = true
            }
        }
        categories = updated
        scannedOnce = true
        scanProgress = 100
    }

    nonisolated static func computeSize(of c: CleanupCategory) -> Int64 {
        c.paths.reduce(Int64(0)) { FileManager.default.directorySize(at: $1) + $0 }
    }

    /// 진단용: 각 카테고리의 접근 성공여부 · 특히 .Trash에서 실측 데이터가 뭔지 확인
    func diagnose() async -> String {
        var lines: [String] = []
        for c in categories {
            for p in c.paths {
                let exists = FileManager.default.fileExists(atPath: p.path)
                var isDir: ObjCBool = false
                _ = FileManager.default.fileExists(atPath: p.path, isDirectory: &isDir)
                let count = (try? FileManager.default.contentsOfDirectory(at: p, includingPropertiesForKeys: nil))?.count ?? -1
                let size = Self.computeSize(of: c)
                lines.append("\(c.id): path=\(p.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) exists=\(exists) dir=\(isDir.boolValue) childCount=\(count) size=\(ByteFmt.string(size))")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// 선택된 카테고리의 내용물을 휴지통으로 이동(휴지통 카테고리는 영구 삭제). 정리된 바이트를 반환.
    @discardableResult
    func clean() async -> Int64 {
        var freed: Int64 = 0
        let targets = categories.filter { selectedIDs.contains($0.id) && $0.size > 0 }
        for c in targets {
            let before = c.size
            for path in c.paths {
                if c.isTrash {
                    // 휴지통 비우기: 폴더ACL(group:everyone-deny-delete) 회위 위해
                    // Finder를 경유해 비우기 (Finder는 이를 알고 ACL 우회)
                    let out = shellRun("/usr/bin/osascript",
                                       "-e", "tell application \"Finder\" to empty trash")
                } else {
                    for child in FileManager.default.topLevelChildren(of: path) {
                        try? FileManager.default.trashItem(at: child, resultingItemURL: nil)
                    }
                }
            }
            var updated = categories
            if let i = updated.firstIndex(where: { $0.id == c.id }) {
                updated[i].size = 0
                categories = updated
            }
            freed += before
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return freed
    }

    /// 앱 캐시 전용 정리: 사용자 캐시 + Homebrew/npm/pip/SwiftPM 캐시 (로그·Xcode·휴지통은 건드리지 않음)
    @discardableResult
    func cleanCachesOnly() async -> Int64 {
        let cacheIDs = Set(["userCache", "homebrew", "npm", "pip", "simulator", "swiftpm"])
        let originalSelected = selectedIDs
        selectedIDs = cacheIDs
        let freed = await clean()
        selectedIDs = originalSelected
        return freed
    }
}
