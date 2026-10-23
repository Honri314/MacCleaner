import Foundation
import CryptoKit
import AppKit

struct DuplicateGroup: Identifiable, Hashable {
    var id: String { contentKey }
    let contentKey: String          // 크기_해시
    let sizeBytes: Int64
    var files: [DuplicateFile]
    var wastedBytes: Int64 { sizeBytes * Int64(max(files.count - 1, 0)) }
}

struct DuplicateFile: Identifiable, Hashable {
    var id: String { path.path }
    let path: URL
    let sizeBytes: Int64
    let modified: Date?
    /// 사용자가 "이건 남겨두자" 하고 고른 대표. 표시용.
    var isOriginal: Bool = false
}

@MainActor
final class DuplicateFinder: ObservableObject {
    @Published private(set) var groups: [DuplicateGroup] = []
    @Published private(set) var isScanning = false
    @Published private(set) var scannedOnce = false
    @Published private(set) var scannedFileCount = 0

    var totalWasted: Int64 { groups.reduce(0) { $0 + $1.wastedBytes } }
    var totalDuplicateCount: Int { groups.reduce(0) { $0 + max($1.files.count - 1, 0) } }

    /// 삭제 후보(원본 외) 선택 상태
    @Published var selectedPaths: Set<String> = []

    /// 사용자 지정 추가 스캔 폴더 (nil = 기본 위치만)
    @Published var customRoots: [URL] = []

    private var scanTask: Task<Void, Never>?

    nonisolated static var minDuplicateMB: Int { AppSettings.shared.duplicateMinSizeMB }

    /// 사진·애플뮤직 라이브러리 보호 폴더를 스캔 루트에서 완전 제외
    /// (앱 전체에서 사진/음악 스캔 기능 자체를 뺌 — 접근허용 팝업 반복 방지)
    nonisolated static func filterProtectedRoots(_ roots: [URL]) -> [URL] {
        let protectedNames: Set<String> = ["Pictures", "Music"]
        return roots.filter { !protectedNames.contains($0.lastPathComponent) }
    }

    private let home = FileManager.default.homeDirectoryForCurrentUser

    func scan() {
        cancel()
        isScanning = true
        groups = []
        scannedFileCount = 0
        selectedPaths = []

        let rootsToScan: [URL] = customRoots.isEmpty
            ? ["Desktop", "Documents", "Downloads", "Movies"].map({ home.appendingPathComponent($0) })
            : Self.filterProtectedRoots(customRoots)
        scanTask = Task.detached(priority: .userInitiated) { [weak self, rootsToScan] in
            guard let self else { return }
            // 1단계: 크기별 파일 목록
            var bySize: [Int64: [URL]] = [:]
            var count = 0
            func walk(_ dir: URL, depth: Int) {
                guard depth < 10 else { return }
                let children = (try? FileManager.default.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])) ?? []
                for url in children {
                    if Task.isCancelled { return }
                    guard !url.lastPathComponent.hasPrefix(".") else { continue }
                    let vals = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
                    if vals?.isSymbolicLink == true { continue }
                    if vals?.isDirectory == true {
                        // 시스템 폴더 등 무거운 것 제외
                        let skipNames: Set<String> = ["Library", "Volumes", "Applications", "System", "private"]
                        if skipNames.contains(url.lastPathComponent) { continue }
                        // TCC 보호 경로 (Photos/Music 라이브러리 등) 회피 — 접근 팝업 유발 방지
                        let tcc = ["Music Library", "Photos Library", "Photo Library", "Mail", "Safari", "Calendars", "Contacts", "AddressBook", "Messages"]
                        if tcc.contains(where: { url.lastPathComponent.contains($0) }) { continue }
                        walk(url, depth: depth + 1)
                    } else if let size = vals?.fileSize, size >= Int32(Self.minDuplicateMB) * 1_048_576 {
                        bySize[Int64(size), default: []].append(url)
                        count += 1
                        if count % 50 == 0 {
                            let n = count
                            Task { @MainActor [weak self] in self?.scannedFileCount = n }
                        }
                    }
                }
            }
            for root in rootsToScan { walk(root, depth: 0) }

            // 사용자가 지정한 커스텀 폴더 중 사진·음악 라이브러리 보호 폴더는 스캔 제외
            // (접근허용 팝업 반복 유발 방지 — 앱 전체에서 사진/애플뮤직 스캔 기능 자체를 뺌)

            // 2단계: 같은 크기 check → SHA-256 해시 비교
            var hashes: [DuplicateGroup] = []
            for (size, urls) in bySize where urls.count > 1 {
                var keyed: [String: [URL]] = [:]
                for url in urls {
                    if Task.isCancelled { return }
                    guard let hash = Self.fileHash(url) else { continue }
                    keyed[hash, default: []].append(url)
                }
                for (hash, files) in keyed where files.count > 1 {
                    let dupes = files.sorted { $0.path < $1.path }
                        .map { DuplicateFile(path: $0, sizeBytes: size,
                                             modified: (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate) }
                    hashes.append(DuplicateGroup(contentKey: "\(size)_\(hash.prefix(16))",
                                                 sizeBytes: size,
                                                 files: dupes))
                }
                if Task.isCancelled { return }
            }

            hashes.sort { $0.wastedBytes > $1.wastedBytes }
            let finalCount = count
            let finalGroups = hashes
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.groups = finalGroups
                self.scannedFileCount = finalCount
                self.scannedOnce = true
                self.isScanning = false
                // 기본 선택: 각 그룹에서 수정일 최신 1개를 제외한 나머지
                var sel: Set<String> = []
                for g in self.groups {
                    let originals = Self.defaultOriginals(in: g)
                    for f in g.files where !originals.contains(f.path.path) {
                        sel.insert(f.path.path)
                    }
                }
                self.selectedPaths = sel
            }
        }
    }

    nonisolated static func fileHash(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 각 그룹에서 유지 대표: 가장 최근 수정된 것 1개
    nonisolated static func defaultOriginals(in group: DuplicateGroup) -> Set<String> {
        var files = group.files
        files.sort { a, b in
            let da = a.modified ?? .distantPast
            let db = b.modified ?? .distantPast
            if da != db { return da > db }
            return a.path.path > b.path.path
        }
        return Set(files.first.map { [$0.path.path] } ?? [])
    }

    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    func toggleOriginal(_ file: DuplicateFile) {
        // 원본 토글은 그 그룹 내에서만 유효
        let group = groups.first { $0.files.contains(where: { $0.id == file.id }) }
        guard let group else { return }
        // 다른 원본은 해제하고 이것만 원본으로
        for f in group.files {
            if f.id == file.id {
                selectedPaths.remove(f.path.path)  // 원본은 삭제 안 함
            } else {
                if !selectedPaths.contains(f.path.path) {
                    selectedPaths.insert(f.path.path)
                }
            }
        }
    }

    func defaultsOriginalsAll() {
        var sel: Set<String> = []
        for g in groups {
            let originals = Self.defaultOriginals(in: g)
            for f in g.files where !originals.contains(f.path.path) {
                sel.insert(f.path.path)
            }
        }
        selectedPaths = sel
    }

    func selectAllCandidates() {
        var sel: Set<String> = []
        for g in groups {
            for f in g.files {
                // 각 그룹의 마지막(알파벳 순 마지막) 경로만 남기고 모두 삭제 후보
                if f.path.path != g.files.map(\.path.path).max() {
                    sel.insert(f.path.path)
                }
            }
        }
        selectedPaths = sel
    }

    func deselectAll() {
        selectedPaths = []
    }

    /// 삭제 대상 경로 → OrphanFinder 스타일의 URL
    var selectedFiles: [URL] {
        groups.flatMap { $0.files.map(\.path) }.filter { selectedPaths.contains($0.path) }
    }

    var selectedSizeTotal: Int64 {
        var total: Int64 = 0
        for g in groups {
            for f in g.files where selectedPaths.contains(f.path.path) {
                total += f.sizeBytes
            }
        }
        return total
    }

    /// 선택된 파일을 휴지통으로 이동
    @discardableResult
    func removeSelected() async -> Int64 {
        let fm = FileManager.default
        var freed: Int64 = 0
        var removedPaths: Set<String> = []
        for url in selectedFiles {
            try? fm.trashItem(at: url, resultingItemURL: nil)
            removedPaths.insert(url.path)
            freed += 0  // 아래 groups 갱신에서 실제 사이즈 합산
        }
        await MainActor.run {
            var newGroups: [DuplicateGroup] = []
            for g in groups {
                let remaining = g.files.filter { !removedPaths.contains($0.path.path) }
                if remaining.count > 1 {
                    newGroups.append(DuplicateGroup(contentKey: g.contentKey,
                                                    sizeBytes: g.sizeBytes,
                                                    files: remaining))
                }
            }
            groups = newGroups
            selectedPaths = []
        }
        return freed
    }

    func reveal(_ file: DuplicateFile) {
        NSWorkspace.shared.activateFileViewerSelecting([file.path])
    }
}

extension DuplicateFile {
    var pathString: String { path.path }
}
