import SwiftUI

enum Tab: Hashable, CaseIterable, Identifiable {
    case dashboard, cleanup, largeFiles, orphans, duplicates, apps, launchItems, tuning, settings
    var id: Self { self }
    var title: String {
        switch self {
        case .dashboard: return "대시보드"
        case .cleanup: return "정리"            case .largeFiles: return "대용량 파일"
            case .orphans: return "잔여 파일"            case .duplicates: return "중복 파일"
            case .apps: return "앱 관리"
            case .launchItems: return "백그라운드"
            case .tuning: return "시스템 튜닝"
            case .settings: return "설정"
        }
    }
    var icon: String {
        switch self {
        case .dashboard: return "speedometer"
        case .cleanup: return "sparkles.rectangle.stack"            case .largeFiles: return "doc.richtext"
            case .orphans: return "trash.slash"            case .duplicates: return "doc.on.doc"
            case .apps: return "square.grid.2x2"
            case .launchItems: return "power"
            case .tuning: return "slider.horizontal.3"
            case .settings: return "gearshape"
        }
    }
    var key: String {
        switch self {
        case .dashboard: return "dashboard"
        case .cleanup: return "cleanup"            case .largeFiles: return "largeFiles"
            case .orphans: return "orphans"            case .duplicates: return "duplicates"
            case .apps: return "apps"
            case .launchItems: return "launchItems"
            case .tuning: return "tuning"
            case .settings: return "settings"
        }
    }

    /// 스크린샷 자동화용: `--tab cleanup` 같은 실행 인자로 시작 탭 지정
    static func initial() -> Tab {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--tab"), args.indices.contains(i + 1) else { return .dashboard }
        return Tab.allCases.first { $0.key == args[i + 1].lowercased() } ?? .dashboard
    }
}

@main
struct MacCleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var settings = AppSettings.shared
    @StateObject private var cleanup = CleanupManager()
    @StateObject private var monitor = SystemMonitor()
    @StateObject private var largeFiles = LargeFileScanner()
    @StateObject private var orphans = OrphanFinder()
    @StateObject private var duplicates = DuplicateFinder()
    @StateObject private var apps = AppManager()
    @StateObject private var brew = BrewManager()
    @StateObject private var pkgReceipts = PkgReceiptManager()
    @StateObject private var tuning = SystemTuningManager()
    @StateObject private var storageBreakdown = StorageBreakdownManager()
    @StateObject private var smartScan = SmartScanManager()
    @StateObject private var menuBar = MenuBarManager()
    @State private var selection: Tab = Tab.initial()
    @State private var showSettings = false

    var body: some Scene {
        WindowGroup("MacCleaner") {
            NavigationSplitView {
                SidebarView(selection: $selection, cleanup: cleanup, monitor: monitor)
            } detail: {
                switch selection {
                case .dashboard:
                    DashboardView(monitor: monitor, junkTotal: cleanup.junkTotal, smartScan: smartScan,
                                  storageBreakdown: storageBreakdown) { tab in
                        switch tab {
                        case "cleanup": selection = .cleanup
                        case "largeFiles": selection = .largeFiles
                        case "orphans": selection = .orphans
                        case "duplicates": selection = .duplicates
                        default: break
                        }
                    } onSmartScan: {
                        Task { await smartScan.run(cleanup: cleanup, largeFiles: largeFiles, orphans: orphans, duplicates: duplicates) }
                    }
                case .cleanup:
                    CleanupView(manager: cleanup)
                case .largeFiles:
                    LargeFilesView(scanner: largeFiles)
                case .orphans:
                    OrphansView(finder: orphans)
                case .duplicates:
                    DuplicatesView(finder: duplicates)
                case .apps:
                    AppManagerView(manager: apps, brewManager: brew, pkgManager: pkgReceipts)
                case .launchItems:
                    LaunchItemsView(manager: apps)
                case .tuning:
                    TuningView(manager: tuning)
                case .settings:
                    SettingsView()
                }
            }
            .frame(minWidth: 1180, minHeight: 760)
            .navigationTitle(selection.title)
            .environment(\.fontScale, settings.fontScale)
            // 글자크기 실동작: SwiftUI 동적타입(Dynamic Type)을 스케일로 조정
            // 0.8 ~ 1.4 → xSmall ... xxxLarge 대응 (DynamicTypeSize 11단계)
            .dynamicTypeSize(dynamicType(from: settings.fontScale))
            .onAppear {
                menuBar.update(settings: settings)
            }
            .onChange(of: settings.menuBarEnabled) { _, _ in menuBar.update(settings: settings) }
            .onChange(of: settings.menuBarShowCPU) { _, _ in menuBar.update(settings: settings) }
            .onChange(of: settings.menuBarShowMemory) { _, _ in menuBar.update(settings: settings) }
            .onChange(of: settings.menuBarShowDisk) { _, _ in menuBar.update(settings: settings) }
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("설정…") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .keyboardShortcut(",")
            }
        }
    }
}

extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
}

extension EnvironmentValues {
    @Entry var fontScale: Double = 1.0
}

extension MacCleanerApp {
    /// fontScale(0.8~1.4) → DynamicTypeSize 매핑 (slider 위치별로 실제 글자가 커지/작아짐)
    fileprivate func dynamicType(from scale: Double) -> DynamicTypeSize {
        switch scale {
        case ..<0.9: return .xSmall
        case ..<1.0: return .small
        case ..<1.1: return .medium          // 기본 (100%)
        case ..<1.2: return .large
        case ..<1.3: return .xLarge
        default:     return .xxLarge
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
