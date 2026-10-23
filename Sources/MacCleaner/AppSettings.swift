import Foundation
import Combine

/// 앱 전역 설정 — UserDefaults 저장
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let d = UserDefaults.standard

    // MARK: 알림
    @Published var notifyCleanupDone: Bool { didSet { d.set(notifyCleanupDone, forKey: "notifyCleanupDone") } }
    // 정리 완료 시 macOS 알림

    @Published var notifySmartScanDone: Bool { didSet { d.set(notifySmartScanDone, forKey: "notifySmartScanDone") } }
    // 스마트 스캔 완료 시 알림

    @Published var notifyDiskLow: Bool { didSet { d.set(notifyDiskLow, forKey: "notifyDiskLow") } }
    @Published var diskLowThresholdGB: Int { didSet { d.set(diskLowThresholdGB, forKey: "diskLowThresholdGB") } }

    // MARK: 표시
    @Published var fontScale: Double { didSet { d.set(fontScale, forKey: "fontScale") } }
    // 0.8 ~ 1.4

    @Published var compactRows: Bool { didSet { d.set(compactRows, forKey: "compactRows") } }

    // MARK: 메뉴바
    @Published var menuBarEnabled: Bool { didSet { d.set(menuBarEnabled, forKey: "menuBarEnabled") } }
    @Published var menuBarShowCPU: Bool { didSet { d.set(menuBarShowCPU, forKey: "menuBarShowCPU") } }
    @Published var menuBarShowMemory: Bool { didSet { d.set(menuBarShowMemory, forKey: "menuBarShowMemory") } }
    @Published var menuBarShowDisk: Bool { didSet { d.set(menuBarShowDisk, forKey: "menuBarShowDisk") } }

    // MARK: 스캔
    @Published var largeFileThresholdMB: Int { didSet { d.set(largeFileThresholdMB, forKey: "largeFileThresholdMB") } }
    // 대용량 파일 기준 MB

    @Published var duplicateMinSizeMB: Int { didSet { d.set(duplicateMinSizeMB, forKey: "duplicateMinSizeMB") } }
    // 중복 검사 최소 크기 MB

    @Published var orphanMinSizeMB: Int { didSet { d.set(orphanMinSizeMB, forKey: "orphanMinSizeMB") } }
    @Published var cleanupIncludeTrash: Bool { didSet { d.set(cleanupIncludeTrash, forKey: "cleanupIncludeTrash") } }
    // 정리 시 휴지통 카테고리 포함 여부 (영구 삭제이므로 기본 끔)

    init() {
        notifyCleanupDone = d.object(forKey: "notifyCleanupDone") as? Bool ?? true
        notifySmartScanDone = d.object(forKey: "notifySmartScanDone") as? Bool ?? true
        notifyDiskLow = d.object(forKey: "notifyDiskLow") as? Bool ?? true
        diskLowThresholdGB = d.object(forKey: "diskLowThresholdGB") as? Int ?? 10
        fontScale = d.object(forKey: "fontScale") as? Double ?? 1.0
        compactRows = d.object(forKey: "compactRows") as? Bool ?? false
        menuBarEnabled = d.object(forKey: "menuBarEnabled") as? Bool ?? false
        menuBarShowCPU = d.object(forKey: "menuBarShowCPU") as? Bool ?? true
        menuBarShowMemory = d.object(forKey: "menuBarShowMemory") as? Bool ?? true
        menuBarShowDisk = d.object(forKey: "menuBarShowDisk") as? Bool ?? true
        largeFileThresholdMB = d.object(forKey: "largeFileThresholdMB") as? Int ?? 100
        duplicateMinSizeMB = d.object(forKey: "duplicateMinSizeMB") as? Int ?? 10
        orphanMinSizeMB = d.object(forKey: "orphanMinSizeMB") as? Int ?? 1
        cleanupIncludeTrash = d.object(forKey: "cleanupIncludeTrash") as? Bool ?? false
    }

    func resetDefaults() {
        notifyCleanupDone = true
        notifySmartScanDone = true
        notifyDiskLow = true
        diskLowThresholdGB = 10
        fontScale = 1.0
        compactRows = false
        largeFileThresholdMB = 100
        duplicateMinSizeMB = 10
        orphanMinSizeMB = 1
        cleanupIncludeTrash = false
    }
}
