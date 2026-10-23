import Foundation
import SwiftUI
import AppKit

struct LargeFile: Identifiable, Hashable {
    var id: String { path.path }
    let path: URL
    let size: Int64
    let modified: Date?
}

@MainActor
final class LargeFileScanner: ObservableObject {
    @Published private(set) var results: [LargeFile] = []
    @Published private(set) var isScanning = false
    @Published private(set) var scannedCount = 0

    var thresholdMB: Int = 100
    var thresholdBytes: Int64 { Int64(thresholdMB) * 1_048_576 }
    @Published var includeLibrary = false
    var totalSize: Int64 { results.reduce(0) { $0 + $1.size } }

    /// 사용자 지정 추가 스캔 폴더 (nil = 기본 위치만)
    @Published var customRoots: [URL] = []

    /// 정밀 스캔 (Deep Scan): 시간 제한 없이 홈+시스템 정리영역까지 전수 검사
    @Published var deepMode = false
    @Published private(set) var scannedFileCount = 0
    @Published private(set) var scannedDirCount = 0
    @Published private(set) var elapsedSeconds = 0

    private var ticker: Task<Void, Never>?

    private var task: Task<Void, Never>?

    func scan() {
        cancel()
        isScanning = true
        results = []
        scannedCount = 0
        scannedFileCount = 0
        scannedDirCount = 0
        elapsedSeconds = 0
        let threshold = thresholdBytes
        let includeLib = includeLibrary
        let deep = deepMode
        let rootsToScan: [URL] = collectRoots()
        let home = FileManager.default.homeDirectoryForCurrentUser

        // 경과 시간 표시 (정밀 스캔은 오래 걸리므로)
        ticker = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                self.elapsedSeconds += 1
            }
        }

        task = Task.detached(priority: .userInitiated) {
            var batch: [LargeFile] = []
            var foundCount = 0
            func flush() {
                let chunk = batch
                let count = foundCount
                batch.removeAll(keepingCapacity: true)
                Task { @MainActor [weak self] in
                    self?.results.append(contentsOf: chunk)
                    self?.scannedCount = count
                }
            }
            func children(_ dir: URL) throws -> [URL] {
                try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey])
            }
            let skipSet: Set<String> = ["Snapshots", "DesignTimeData", "Caches", "Symbols", "Staging", "WebKit"]
            // TCC 팝업 유발 특수 보호 경로: 이 항목들을 열면 '접근 허용' 대화상자가 뜬다
            let tccProtected = ["Music Library", "Photos Library", "Photo Library", "Music Library.musiclibrary",
                                "Photos Library.photoslibrary", "Mail", "Safari",
                                "Calendars", "Contacts", "AddressBook", "Messages",
                                "Media.localized", "Previous Libraries.localized", "com.apple.music.mediasharing"]
            func walk(_ dir: URL, depth: Int) {
                guard !Task.isCancelled, depth < 12 else { return }
                let list: [URL]
                do { list = try children(dir) } catch { return }
                for url in list {
                    if Task.isCancelled { return }
                    let vals = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey])
                    if vals?.isSymbolicLink == true { continue }
                    if vals?.isDirectory == true {
                        let name = url.lastPathComponent
                        if name.hasPrefix(".") { continue }
                        if !includeLib && name == "Library" && url.deletingLastPathComponent() == home { continue }
                        if skipSet.contains(name) { continue }
                        // TCC 보호 경로 회피 (팝업 유발 방지)
                        if tccProtected.contains(where: { name.contains($0) }) { continue }
                        walk(url, depth: depth + 1)
                    } else if let size = vals?.fileSize, Int64(size) >= threshold {
                        batch.append(LargeFile(path: url, size: Int64(size), modified: vals?.contentModificationDate))
                        foundCount += 1
                        if batch.count >= 200 { flush() }
                    }
                }
            }
            if rootsToScan.isEmpty {
                for root in ["Desktop", "Documents", "Downloads", "Movies"].map({ home.appendingPathComponent($0) }) {
                    walk(root, depth: 0)
                }
            } else {
                for root in rootsToScan { walk(root, depth: 0) }
            }
            if deep {
                // 정밀 모드: 홈 전체 + /usr/local (TCC 회피는 walk 내부 유지 — 안전 지키면서 넓게)
                // '사진 보관함' TCC 문구 유발 방지: walk(home) 내부에서 ~/Pictures·~/Music 루트 하부는
                // macOS 보호 라이브러리(Photos/Music)가 보일 때만 회피하는 게 아니라,
                // 홈 루프에서 보호 폴더 자체를 안 열리게 미리 걸러야 함
                let homeChildren = (try? FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
                for child in homeChildren {
                    let name = child.lastPathComponent
                    if name.hasPrefix(".") { continue }
                    // macOS TCC 보호 사용자 폴더Pictures 자체를 열면 '사진 보관함 접근' 경로 뜸 → 회피
                    if ["Pictures", "Music"].contains(name) { continue }  // 사진·애플뮤직 라이브러리 완전 회피
                    var isDir: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: child.path, isDirectory: &isDir), isDir.boolValue else { continue }
                    walk(child, depth: 0)
                }
                let extra = URL(fileURLWithPath: "/usr/local")
                if FileManager.default.fileExists(atPath: extra.path) {
                    walk(extra, depth: 0)
                }
            }
            if includeLib { walk(home.appendingPathComponent("Library"), depth: 0) }
            flush()
            let finalCount = foundCount
            Task { @MainActor [weak self] in
                self?.scannedCount = finalCount
                self?.isScanning = false
                self?.ticker?.cancel()
                self?.ticker = nil
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        ticker?.cancel()
        ticker = nil
        isScanning = false
    }

    /// 스캔 루트 수집 (메인 액터에서 호출해 detached task에 전달)
    /// 기본 대상: Desktop/Documents/Downloads/Movies만 — Pictures·Music 제외 (사진·애플뮤직 접근 요청 유발 방지)
    /// Pictures/Music 대상은 customRoots로 직접 지정한 경우에만 탐색
    private func collectRoots() -> [URL] {
        let base = customRoots.isEmpty
            ? ["Desktop", "Documents", "Downloads", "Movies"].map({ FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent($0) })
            : customRoots
        // 사진·애플뮤직 라이브러리 보호 폴더 완전 제외 (커스텀 지정에도 불구하고)
        return base.filter { !["Pictures", "Music"].contains($0.lastPathComponent) }
    }

    func trash(_ file: LargeFile) {
        try? FileManager.default.trashItem(at: file.path, resultingItemURL: nil)
        results.removeAll { $0.id == file.id }
    }

    func reveal(_ file: LargeFile) {
        NSWorkspace.shared.activateFileViewerSelecting([file.path])
    }
}
