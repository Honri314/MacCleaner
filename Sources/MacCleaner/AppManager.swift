import Foundation
import SwiftUI
import AppKit

struct InstalledApp: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let name: String
    let version: String
    let bundleID: String?
    var sizeBytes: Int64 = -1 // -1 = 계산 중
    var isInstaller: Bool = false   // .pkg 등 인스톨러
    var isCalculating: Bool { sizeBytes < 0 }
}

struct AppVolume: Identifiable, Hashable {
    var id: String { path.path }
    let name: String
    let path: URL
    var selected: Bool
}

struct LaunchItem: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let name: String
    let fromUserLibrary: Bool
}

@MainActor
final class AppManager: ObservableObject {
    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var launchItems: [LaunchItem] = []
    @Published private(set) var isLoadingApps = false

    /// 스캔 대상 볼륨 (기본: 내장 /Applications + 사용자 Applications)
    @Published var scanVolumes: [AppVolume] = AppManager.defaultVolumes() {
        didSet { if scanVolumes.allSatisfy(\.selected) != oldValue.allSatisfy(\.selected) { } }
    }
    @Published var includePkgInstallers = true

    static func defaultVolumes() -> [AppVolume] {
        var list = [AppVolume(name: "내장 디스크", path: URL(fileURLWithPath: "/Applications"), selected: true)]
        let fm = FileManager.default
        // 외장/추가 볼륨 자동 탐색 (/Volumes 아래 볼륨의 Applications)
        if let vols = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: "/Volumes"), includingPropertiesForKeys: [.isDirectoryKey]) {
            for v in vols {
                let name = v.lastPathComponent
                // 로컬 내장 볼륨은 기본 포함, 외장/백업/스냅샷 볼륨은 기본 제외 (selected=false)
                if name == "Macintosh HD" || name == "Macintosh HD - Data" || name.hasPrefix("com.apple") || name.contains("백업") { continue }
                let appsDir = v.appendingPathComponent("Applications")
                if fm.fileExists(atPath: appsDir.path) {
                    list.append(AppVolume(name: "\(name) (외장)", path: appsDir, selected: false))
                }
            }
        }
        return list
    }

    private var work: Task<Void, Never>?

    init() {
        refresh()
    }

    func refresh() {
        work?.cancel()
        isLoadingApps = true
        let home = FileManager.default.homeDirectoryForCurrentUser
        // 체크된 볼륨만 스캔 (무조건 내장 /Applications 포함해 안전하게)
        var selectedRoots = scanVolumes.filter(\.selected).map(\.path)
        if selectedRoots.isEmpty { selectedRoots = [URL(fileURLWithPath: "/Applications")] }
        // 사용자 Applications 추가 (특별 선택 안 했어도 항상)
        selectedRoots.append(home.appendingPathComponent("Applications"))
        let withPkg = includePkgInstallers
        let rootCopies = selectedRoots
        work = Task {
            var roots = rootCopies
            var found: [InstalledApp] = []
            var seen = Set<URL>()
            for root in roots {
                // 실제히 존재하지 않는 루트는 넘김
                guard FileManager.default.fileExists(atPath: root.path) else { continue }
                let bundles = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
                for url in bundles {
                    if Task.isCancelled { return }
                    let ext = url.pathExtension.lowercased()
                    // .app 번들 + .pkg/.dmg 인스톨러 모두 나열 (isInstaller 표시)
                    if ext == "app" {
                        guard seen.insert(url).inserted else { continue }
                        let info = Self.readInfo(url)
                        found.append(InstalledApp(url: url,
                                                  name: info.name.isEmpty ? url.deletingPathExtension().lastPathComponent : info.name,
                                                  version: info.version,
                                                  bundleID: info.bundleID))
                    } else if withPkg && (ext == "pkg" || ext == "dmg") {
                        guard seen.insert(url).inserted else { continue }
                        found.append(InstalledApp(url: url,
                                                  name: url.deletingPathExtension().lastPathComponent,
                                                  version: "—",
                                                  bundleID: nil,
                                                  isInstaller: true))
                    }
                }
            }
            found.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            self.apps = found
            self.isLoadingApps = false

            // 백그라운드에서 존재 여부 확인 후 크기 계산
            let list = found
            for app in list {
                if Task.isCancelled { return }
                let url = app.url
                let size = await Task.detached(priority: .utility) {
                    FileManager.default.directorySize(at: url)
                }.value
                guard let i = self.apps.firstIndex(where: { $0.id == url }) else { continue }
                self.apps[i].sizeBytes = size
            }
            self.loadLaunchItems()
        }
    }

    private static func readInfo(_ url: URL) -> (name: String, version: String, bundleID: String?) {
        let bundle = Bundle(url: url)
        if let info = bundle?.infoDictionary {
            return (info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? "",
                    info["CFBundleShortVersionString"] as? String ?? "—",
                    bundle?.bundleIdentifier)
        }
        return (url.deletingPathExtension().lastPathComponent, "—", nil)
    }

    // MARK: 잔여 파일

    func leftovers(for app: InstalledApp) -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let lib = home.appendingPathComponent("Library")
        var urls: [URL] = []
        if let id = app.bundleID {
            urls.append(lib.appendingPathComponent("Caches/\(id)"))
            urls.append(lib.appendingPathComponent("Preferences/\(id).plist"))
            urls.append(lib.appendingPathComponent("HTTPStorages/\(id)"))
            urls.append(lib.appendingPathComponent("WebKit/\(id)"))
        }
        urls.append(lib.appendingPathComponent("Application Support/\(app.name)"))
        urls.append(lib.appendingPathComponent("Caches/\(app.name)"))
        urls.append(lib.appendingPathComponent("Containers/\(app.name)"))
        return urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// 마지막 remove 실패 시 사용자 친화 에러 메시지 (nil = 성공)
    @Published private(set) var lastError: String?

    /*
     * 하나의 파일/폴더를 휴지통으로 옮기는 3단계 안전 루트 (비밀번호 없이 최대한 처리):
     *  1) FileManager.trashItem (Swift 내장) — 대부분의 파일, 비밀번호 불필요
     *  2) 직접 ~/.Trash 이동 (rename) — trashItem 실패해도 내 소유 파일이면 비밀번호 불필요
     *  3) Finder AppleScript — root 소유 파일 등 마지막 수단 (이때만 OS가 비밀번호를 물 수 있음)
     *  모두 실패 시에만 실패로 보고 목록을 유지한다.
     */
    private func moveToTrash(_ url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil } // 이미 없어도 성공 취급

        // 1) 기본 시도
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            return nil
        } catch {
            // 2) 직접 ~/.Trash로 rename (내 소유 파일이면 대부분 여기서 성공, 비밀번호 없음)
            let home = FileManager.default.homeDirectoryForCurrentUser
            let trashURL = home.appendingPathComponent(".Trash/\(url.lastPathComponent)")
            var finalTrash = trashURL
            // 동일 이름 충돌 시 이름 뒤에 번호 붙임 (덮어쓰기 방지)
            var n = 1
            while FileManager.default.fileExists(atPath: finalTrash.path) {
                finalTrash = trashURL.deletingPathExtension()
                    .appendingPathExtension("(\(n))\(url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)")")
                n += 1
            }
            do {
                try FileManager.default.moveItem(at: url, to: finalTrash)
                return nil
            } catch {
                // 3) 최후: Finder에게 맡기기 (root 소유 등 — 이때만 권한 프롬프트가 발생할 수 있음)
                let esc = url.path.replacingOccurrences(of: "\\", with: "\\\\")
                                  .replacingOccurrences(of: "\"", with: "\\\"")
                let script = "tell application \"Finder\" to delete POSIX file \"\(esc)\""
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                p.arguments = ["-e", script]
                let err = Pipe(); p.standardError = err
                do { try p.run() } catch { return "제거 실패: Finder 우회 실행 실패" }
                p.waitUntilExit()
                guard p.terminationStatus == 0,
                      FileManager.default.fileExists(atPath: url.path) == false else {
                    let detail = (try? err.fileHandleForReading.readToEnd())
                        .flatMap { String(data: $0, encoding: .utf8) } ?? error.localizedDescription
                    return "휴지통 이동 실패: \(detail)"
                }
                return nil
            }
        }
    }

    /// 앱을 휴지통으로. 실패 시 lastError 세팅하고 목록 유지.
    @discardableResult
    func remove(app: InstalledApp, includeLeftovers: Bool) async -> Int64 {
        lastError = nil

        // 실행 중인 앱은 보호 (삭제하면 잠긴 번들이 되어 실패하는 원인이 됨)
        if NSWorkspace.shared.runningApplications.contains(where: {
            $0.bundleURL?.standardizedFileURL == app.url.standardizedFileURL && !$0.isTerminated
        }) {
            lastError = "'\(app.name)'이(가) 실행 중이라 지울 수 없습니다. 먼저 종료해주세요."
            return 0
        }

        guard moveToTrash(app.url) == nil else {   // 실패 시 목록 유지
            return 0
        }
        apps.removeAll { $0.id == app.url }

        var freed: Int64 = 0
        if lastError == nil {
            freed = FileManager.default.directorySize(at: app.url)  // 이미 휴지통으로 갔으므로 0에 가까움
        }

        if includeLeftovers {
            // 잔여 파일은 휴지통 거치지 않고 바로 영구 삭제 (사용자 요청)
            for url in leftovers(for: app) {
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    lastError = (lastError.map { $0 + "\n" } ?? "")
                        + "잔여 파일 삭제 실패 (\(url.lastPathComponent)): \(error.localizedDescription)"
                }
            }
        }

        return (lastError == nil) ? freed : 0
    }

    // MARK: 백그라운드 실행 항목

    private func loadLaunchItems() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let fm = FileManager.default
        var items: [LaunchItem] = []
        let userAgents = home.appendingPathComponent("Library/LaunchAgents")
        for url in (try? fm.contentsOfDirectory(at: userAgents, includingPropertiesForKeys: nil)) ?? [] where url.pathExtension == "plist" {
            items.append(LaunchItem(url: url, name: url.lastPathComponent, fromUserLibrary: true))
        }
        let systemAgents = URL(fileURLWithPath: "/Library/LaunchAgents")
        for url in (try? fm.contentsOfDirectory(at: systemAgents, includingPropertiesForKeys: nil)) ?? [] where url.pathExtension == "plist" {
            items.append(LaunchItem(url: url, name: url.lastPathComponent, fromUserLibrary: false))
        }
        launchItems = items.sorted { $0.name < $1.name }
    }

    /// 백그라운드 항목 plist를 휴지통으로 이동
    func disable(item: LaunchItem) {
        try? FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
        launchItems.removeAll { $0.id == item.url }
    }
}
