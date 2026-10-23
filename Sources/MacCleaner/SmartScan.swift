import Foundation
import SwiftUI
import AppKit
import UserNotifications

// MARK: - 스마트 스캔

struct SmartScanSummary {
    var junkTotal: Int64 = 0
    var largeFilesCount = 0
    var largeFilesTotal: Int64 = 0
    var orphansCount = 0
    var orphansTotal: Int64 = 0
    var duplicateGroups = 0
    var duplicateWasted: Int64 = 0

    /// 총 확보 가능 공간
    var totalReclaimable: Int64 {
        junkTotal + orphansTotal + duplicateWasted
    }
}

@MainActor
final class SmartScanManager: ObservableObject {
    @Published var isRunning = false
    @Published var currentStage = ""
    /// 스캔 진행률 (0~100)
    @Published var progress: Double = 0
    var progressPercent: String { "\(Int(progress))%" }
    @Published var summary: SmartScanSummary?
    @Published var finishedAt: Date?

    func run(cleanup: CleanupManager, largeFiles: LargeFileScanner, orphans: OrphanFinder, duplicates: DuplicateFinder) async {
        guard !isRunning else { return }
        isRunning = true
        defer {
            isRunning = false
            finishedAt = Date()
        }
        summary = nil
        progress = 0

        // 1) 정리 카테고리 스캔 (0→25%, CleanupManager 카테고리 진행률을 스케일링)
        currentStage = "정리 항목 분석 중…"
        let cleanupTask = Task { await cleanup.scan() }
        while cleanup.isScanning {
            progress = cleanup.scanProgress * 0.25
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        await cleanupTask.value
        progress = 25
        var s = SmartScanSummary()
        s.junkTotal = cleanup.junkTotal

        // 2) 잔여 파일 (50%)
        currentStage = "잔여 파일 찾는 중…"
        await orphans.scan()
        s.orphansCount = orphans.results.count
        s.orphansTotal = orphans.totalSize
        progress = 50

        // 3) 대용량 파일 (80%)
        currentStage = "대용량 파일 찾는 중…"
        largeFiles.scan()
        // 스캔 끝날 때까지 잠시 대기 (사실상 비동기 루프 — 최대 30초)
        for i in 0..<300 {
            if !largeFiles.isScanning { break }
            progress = 50 + Double(i) / 300.0 * 30   // 50→80% 보간
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        s.largeFilesCount = largeFiles.results.count
        s.largeFilesTotal = largeFiles.totalSize

        // 4) 중복 파일 (100%)
        currentStage = "중복 파일 검사 중…"
        duplicates.scan()
        for i in 0..<600 {
            if !duplicates.isScanning { break }
            progress = 80 + Double(i) / 600.0 * 20   // 80→100% 보간
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        s.duplicateGroups = duplicates.groups.count
        s.duplicateWasted = duplicates.totalWasted
        progress = 100

        summary = s
        currentStage = ""
        progress = 0

        // 알림 (설정에 따라)
        if AppSettings.shared.notifySmartScanDone {
            sendNotification(
                title: "스마트 스캔 완료",
                body: "확보 가능 \(ByteFmt.string(s.totalReclaimable)) · 정리 \(ByteFmt.string(s.junkTotal)) + 잔여 \(ByteFmt.string(s.orphansTotal)) + 중복 \(ByteFmt.string(s.duplicateWasted))"
            )
        }
    }

    nonisolated private func sendNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let req = UNNotificationRequest(
                identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(req)
        }
    }
}

// MARK: - 메뉴바 매니저

@MainActor
final class MenuBarManager: ObservableObject {
    private var statusItem: NSStatusItem?
    private let monitor = SystemMonitor()
    private var timer: Timer?

    func update(settings: AppSettings) {
        if settings.menuBarEnabled {
            if statusItem == nil {
                statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                let menu = NSMenu()
                menu.addItem(withTitle: "MacCleaner 열기", action: #selector(activateApp), keyEquivalent: "")
                menu.addItem(.separator())
                let toggle = NSMenuItem(title: "메뉴바 표시 끄기", action: #selector(toggleMenuBar(_:)), keyEquivalent: "")
                toggle.target = self
                menu.addItem(toggle)
                statusItem?.menu = menu
            }
            if timer == nil {
                timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.refresh() }
                }
                refresh()
            }
        } else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
            timer?.invalidate()
            timer = nil
        }
    }

    @objc private func activateApp() {
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleMenuBar(_ sender: Any?) {
        AppSettings.shared.menuBarEnabled = false
    }

    private func refresh() {
        guard let item = statusItem, let button = item.button else { return }
        let settings = AppSettings.shared
        var parts: [String] = []
        if settings.menuBarShowCPU {
            parts.append(String(format: "CPU %.0f%%", monitor.snapshot.cpuPercent))
        }
        if settings.menuBarShowMemory {
            parts.append("MEM \(Int(monitor.snapshot.memory.usedPercent))%")
        }
        if settings.menuBarShowDisk {
            let free = monitor.snapshot.disk.freeGB
            parts.append(String(format: "DISK %.0fGB", free))
        }
        button.title = parts.joined(separator: "  ")
    }
}

// MARK: - 권한 관리

struct PermissionItem: Identifiable {
    enum Kind: String { case fullDisk, folder }
    var id: String { path.path }
    let name: String
    let path: URL
    let kind: Kind
    let description: String
}

@MainActor
final class PermissionManager: ObservableObject {
    @Published private(set) var permissions: [PermissionItem] = PermissionManager.defaults
    @Published private(set) var status: [String: Bool] = [:]

    static var defaults: [PermissionItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            PermissionItem(name: "홈 폴더", path: home, kind: .folder, description: "기본 스캔 영역"),
            PermissionItem(name: "Documents", path: home.appendingPathComponent("Documents"), kind: .folder, description: "문서 영역 스캔"),
            PermissionItem(name: "Downloads", path: home.appendingPathComponent("Downloads"), kind: .folder, description: "다운로드 파일"),
            PermissionItem(name: "Desktop", path: home.appendingPathComponent("Desktop"), kind: .folder, description: "바탕화면"),
            PermissionItem(name: "휴지통", path: home.appendingPathComponent(".Trash"), kind: .folder, description: "휴지통 정리"),
            PermissionItem(name: "전체 디스크 접근", path: URL(fileURLWithPath: "/Library"), kind: .fullDisk, description: "시스템 설정 > 개인정보보호 > 전체 디스크 접근 권한"),
        ]
    }

    func checkAll() {
        var new: [String: Bool] = [:]
        for p in permissions {
            new[p.id] = Self.isAccessible(p.path)
        }
        status = new
    }

    /// 실제로 읽기 시도까지 해보는 정밀 권한 검사 (TCC 팝업 없이)
    /// stat만으로는 '폴더 존재+실행 권한'만 판별하므로 실제 읽기 실패를 가릴 수 있음
    nonisolated static func deepAccessible(_ url: URL) -> Bool {
        // readdir 1회까지 해보는 실질 접근 판정 (opendir+readdir모두 안전 — TCC 알림 무유발)
        guard let dir = opendir(url.path) else { return false }
        defer { closedir(dir) }
        _ = readdir(dir)
        return true
    }

    /// 전체 디스크 접근(FDA) 여부 별도 판정:
    /// FDA는 /Library 외에 보호 경로(/Users/다른사용자 등)에 접근 가능해야 성립
    /// 여기서는 /Library + /Users 안의 보호 파일(다른 사용자 홈) 두 가지를 opendir 시도
    nonisolated static func fullDiskAccessible() -> Bool {
        // FDA 부여 시 성공하는 대표 루트들
        let probes = [
            URL(fileURLWithPath: "/Library"),
            URL(fileURLWithPath: "/Library/Application Support/com.apple.TCC"),
            URL(fileURLWithPath: "/Users"),
        ]
        var granted = 0
        for p in probes {
            if let dir = opendir(p.path) {
                _ = readdir(dir)
                closedir(dir)
                granted += 1
            }
        }
        // 모든 필수 probe가 열리면 FDA 허용 상태로 판단
        return granted == probes.count
    }

    /// 권한 안내 액션 — deep 검사 후 어떻게 표시할지의 기준
    func checkAllDeep() {
        var new: [String: Bool] = [:]
        for p in permissions {
            if p.kind == .fullDisk {
                new[p.id] = Self.fullDiskAccessible()
            } else {
                new[p.id] = Self.deepAccessible(p.path)
            }
        }
        status = new
    }

    nonisolated static func isAccessible(_ url: URL) -> Bool {
        // stat(2) 직접 호출 — FileManager.fileExists가 내부에서 뭘 하는지 몰라도
        // stat은 TCC '파일·폴더 접근' 알림을 유발하지 않음 (open/read/contentsOfDirectory만 유발)
        var st = stat()
        return stat(url.path, &st) == 0
    }

    func requestAccess(_ item: PermissionItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.path])
    }
    /// 전체 디스크 접근: 시스템 설정 앱 열기
    func openFullDiskSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!)
        }
    }
}
