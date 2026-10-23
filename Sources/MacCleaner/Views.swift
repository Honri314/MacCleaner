import SwiftUI

func miniStat(_ label: String, _ value: String, sub: String? = nil) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(label).font(.caption2).foregroundStyle(.tertiary)
        HStack(spacing: 4) {
            Text(value).font(.callout.weight(.semibold)).monospacedDigit()
            if let sub {
                Text(sub).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

struct CategorySection<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
    }
}

// MARK: - 사이드바
struct SidebarView: View {
    @Binding var selection: Tab
    @ObservedObject var cleanup: CleanupManager
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        List(selection: $selection) {
            // 분류용 헤더 — 항상 펼쳐져 있음 (접기 화살표 없음)
            Section("개요") {
                sidebarItem(.dashboard)
            }
            Section("청소 · 검사") {
                sidebarItem(.cleanup)
                sidebarItem(.largeFiles)
                sidebarItem(.orphans)
                sidebarItem(.duplicates)
            }
            Section("시스템") {
                sidebarItem(.apps)
                sidebarItem(.launchItems)
                sidebarItem(.tuning)
            }
            Section("설정") {
                sidebarItem(.settings)
            }
            Section("현재 상태") {
                GaugeRow(icon: "cpu", title: "CPU", value: monitor.snapshot.cpuPercent,
                         text: String(format: "%.0f%%", monitor.snapshot.cpuPercent))
                GaugeRow(icon: "memorychip", title: "메모리", value: monitor.snapshot.memory.usedPercent,
                         text: ByteFmt.string(Int64(monitor.snapshot.memory.usedGB * 1_073_741_824)))
                GaugeRow(icon: "internaldrive", title: "디스크", value: monitor.snapshot.disk.usedPercent,
                         text: String(format: "%.0f%%", monitor.snapshot.disk.usedPercent))
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 240, idealWidth: 260)
    }

    private func sidebarItem(_ tab: Tab) -> some View {
        Label(tab.title, systemImage: tab.icon)
            .badge(
                tab == .cleanup && cleanup.junkTotal > 0 && !cleanup.isScanning
                    ? Text(ByteFmt.string(cleanup.junkTotal))
                    : nil
            )
            .tag(tab)
    }
}

struct GaugeRow: View {
    let icon: String
    let title: String
    let value: Double
    let text: String

    var color: Color {
        switch value {
        case ..<60: return .green
        case ..<85: return .orange
        default: return .red
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(text).font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.18))
                        Capsule()
                            .fill(color)
                            .frame(width: geo.size.width * max(0, min(value, 100)) / 100)
                            .animation(.easeOut(duration: 0.4), value: value)
                    }
                }
                .frame(height: 5)
                .clipShape(Capsule())
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 대시보드
struct DashboardView: View {
    @ObservedObject var monitor: SystemMonitor
    let junkTotal: Int64
    @ObservedObject var smartScan: SmartScanManager
    @ObservedObject var storageBreakdown: StorageBreakdownManager
    let onNavigate: (String) -> Void
    let onSmartScan: () -> Void

    @State private var cpuHistory: [Double] = []
    @State private var memHistory: [Double] = []
    private let maxHistory = 60  // 2초 간격 → 최근 2분

    var body: some View {
       ScrollView {
            VStack(spacing: 16) {
                // 리소스 요약 + 그래프 (최근 2분 추이)
                CategorySection {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("리소스 추이 (최근 2분)").font(.headline)
                            Spacer()
                            Text(String(format: "갱신: %02d:%02d:%02d",
                                        Calendar.current.component(.hour, from: Date()),
                                        Calendar.current.component(.minute, from: Date()),
                                        Calendar.current.component(.second, from: Date())))
                                .font(.caption2).monospacedDigit().foregroundStyle(.tertiary)
                        }
                        HStack(alignment: .top, spacing: 20) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Circle().fill(Color.blue).frame(width: 8, height: 8)
                                    Text("CPU").font(.caption)
                                    Spacer()
                                    Text(String(format: "%.0f%%", monitor.snapshot.cpuPercent))
                                        .font(.caption.weight(.semibold)).monospacedDigit()
                                }
                                Sparkline(values: cpuHistory.isEmpty ? [monitor.snapshot.cpuPercent] : cpuHistory, color: .blue)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Circle().fill(Color.purple).frame(width: 8, height: 8)
                                    Text("메모리").font(.caption)
                                    Spacer()
                                    Text(String(format: "%.0f%%", monitor.snapshot.memory.usedPercent))
                                        .font(.caption.weight(.semibold)).monospacedDigit()
                                }
                                Sparkline(values: memHistory.isEmpty ? [monitor.snapshot.memory.usedPercent] : memHistory, color: .purple)
                            }
                        }
                    }
                }
                .onChange(of: monitor.snapshot.cpuPercent) { _, v in
                    cpuHistory.append(v)
                    if cpuHistory.count > maxHistory { cpuHistory.removeFirst() }
                }
                .onChange(of: monitor.snapshot.memory.usedPercent) { _, v in
                    memHistory.append(v)
                    if memHistory.count > maxHistory { memHistory.removeFirst() }
                }

                HStack(alignment: .top, spacing: 16) {
                    // 도넛: 저장공간 구성
                    VStack(spacing: 0) {
                        CategorySection {
                            VStack(spacing: 12) {
                                Text("저장공간 구성").font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                DonutChart(
                                    segments: [
                                        DonutSegment(label: "시스템+기타", value: max(monitor.snapshot.disk.totalGB - monitor.snapshot.disk.freeGB - 0.5, 1), color: .gray),
                                        DonutSegment(label: "여유", value: max(monitor.snapshot.disk.freeGB, 0), color: .green),
                                    ],
                                    centerTitle: String(format: "%.0f%%", monitor.snapshot.disk.usedPercent),
                                    centerSub: "사용 중"
                                )
                                .frame(width: 170, height: 170)
                                HStack(spacing: 16) {
                                    legendDot(.gray, "사용 중 \(String(format: "%.0fGB", monitor.snapshot.disk.totalGB - monitor.snapshot.disk.freeGB))")
                                    legendDot(.green, "잔여 \(String(format: "%.0fGB", monitor.snapshot.disk.freeGB))")
                                }
                                .padding(.bottom, 4)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        Spacer(minLength: 0)
                    }
                    // 도넛: 확보 가능 공간 구성
                    VStack(spacing: 0) {
                        CategorySection {
                            VStack(spacing: 12) {
                                Text("확보 가능 공간").font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                let s = smartScan.summary
                                let total = max((s?.totalReclaimable ?? junkTotal), 1)
                                DonutChart(
                                    segments: [
                                        DonutSegment(label: "정리", value: Double(max(s?.junkTotal ?? junkTotal, 1)), color: .blue),
                                        DonutSegment(label: "잔여", value: Double(s?.orphansTotal ?? 0), color: .purple),
                                        DonutSegment(label: "중복", value: Double(s?.duplicateWasted ?? 0), color: .orange),
                                    ],
                                    centerTitle: ByteFmt.string(total),
                                    centerSub: "총 확보 가능"
                                )
                                .frame(width: 170, height: 170)
                                HStack(spacing: 14) {
                                    legendDot(.blue, "정리")
                                    legendDot(.purple, "잔여")
                                    legendDot(.orange, "중복")
                                }
                                .padding(.bottom, 4)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        Spacer(minLength: 0)
                    }
                }

                // 스마트 스캔 카드
                CategorySection {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "wand.and.sparkles")
                                .font(.system(size: 26))
                                .foregroundStyle(.blue)
                                .frame(width: 46, height: 46)
                                .background(Circle().fill(Color.blue.opacity(0.1)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("스마트 스캔").font(.headline)
                                Text("정리·잔여·대용량·중복을 한 번에 검사합니다")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let s = smartScan.summary {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(ByteFmt.string(s.totalReclaimable))
                                        .font(.system(.title3, design: .rounded).weight(.bold))
                                        .monospacedDigit()
                                    Text("확보 가능").font(.caption2).foregroundStyle(.secondary)
                                }
                                Button("지금 정리") {
                                    onNavigate("cleanup")
                                }
                                .buttonStyle(.borderedProminent)
                            } else {
                                Button {
                                    onSmartScan()
                                } label: {
                                    HStack(spacing: 6) {
                                        if smartScan.isRunning {
                                            ProgressView().controlSize(.small)
                                            Text(smartScan.currentStage.isEmpty ? "실행 중…" : smartScan.currentStage)
                                        } else {
                                            Image(systemName: "wand.and.sparkles")
                                            Text("스캔 시작")
                                        }
                                    }
                                    .frame(minWidth: 130)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .disabled(smartScan.isRunning)
                                .overlay(alignment: .bottom) {
                                    if smartScan.isRunning {
                                        Text("\(smartScan.progressPercent)")
                                            .font(.caption2.weight(.semibold))
                                            .monospacedDigit()
                                            .foregroundStyle(.secondary)
                                            .offset(y: 14)
                                    }
                                }
                            }
                        }
                        if let s = smartScan.summary {
                            Divider()
                            HStack(spacing: 14) {
                                miniStat("정리", ByteFmt.string(s.junkTotal))
                                miniStat("잔여", ByteFmt.string(s.orphansTotal))
                                miniStat("중복 낭비", ByteFmt.string(s.duplicateWasted))
                                miniStat("대용량", ByteFmt.string(s.largeFilesTotal), sub: "\(s.largeFilesCount)개")
                            }
                        }
                    }
                }
                // "시스템 데이터" 해석 카드 — macOS가 뭉뚱그려서 보여주는 원인 분해
                StorageBreakdownSection(manager: storageBreakdown)

                // 정리 유도 카드 (junk 스캔 안 됐으면 안 보임)
                Group {
                    if junkTotal > 0 {
                    CategorySection {
                        HStack(spacing: 14) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 30))
                                .foregroundStyle(.yellow)
                                .frame(width: 52, height: 52)
                                .background(Circle().fill(.yellow.opacity(0.12)))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(ByteFmt.string(junkTotal))
                                    .font(.system(.title, design: .rounded).weight(.bold))
                                Text("정리하면 확보되는 공간입니다")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                onNavigate("cleanup")
                            } label: {
                                Text("지금 정리").frame(width: 110)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                    }
                    }
                }
                
                HStack(spacing: 16) {
                    StatCard(icon: "cpu", title: "CPU",
                             value: String(format: "%.0f%%", monitor.snapshot.cpuPercent),
                             sub: String(format: "%d코어", activeCores),
                             progress: monitor.snapshot.cpuPercent)
                    StatCard(icon: "memorychip", title: "메모리",
                             value: ByteFmt.string(GBtoBytes(monitor.snapshot.memory.usedGB)),
                             sub: String(format: "/ %.0fGB · %@",
                                         monitor.snapshot.memory.totalGB,
                                         monitor.snapshot.memory.pressureDescription),
                             progress: monitor.snapshot.memory.usedPercent)
                    StatCard(icon: "internaldrive", title: "저장공간",
                             value: String(format: "%.0fGB", monitor.snapshot.disk.totalGB - monitor.snapshot.disk.freeGB),
                             sub: String(format: "잔여 %.0fGB / %.0fGB", monitor.snapshot.disk.freeGB, monitor.snapshot.disk.totalGB),
                             progress: monitor.snapshot.disk.usedPercent)
                }

                CategorySection {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("리소스 상위 프로세스").font(.headline)
                            Spacer()
                            Text("2초 간격 갱신").font(.caption2).foregroundStyle(.tertiary)
                        }
                        if monitor.snapshot.topProcesses.isEmpty {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("수집 중…").foregroundStyle(.secondary).font(.callout)
                            }
                            .padding(.vertical, 12)
                        } else {
                            // 헤더 행
                            HStack {
                                Text("프로세스").font(.caption).foregroundStyle(.tertiary)
                                Spacer()
                                Text("CPU").font(.caption).foregroundStyle(.tertiary).frame(width: 70, alignment: .trailing)
                                Text("메모리").font(.caption).foregroundStyle(.tertiary).frame(width: 80, alignment: .trailing)
                            }
                            Divider()
                            ForEach(monitor.snapshot.topProcesses.prefix(6)) { p in
                                HStack {
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(p.cpuPercent > 30 ? Color.red : p.cpuPercent > 10 ? Color.orange : Color.green)
                                            .frame(width: 7, height: 7)
                                        Text(p.name)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    Spacer()
                                    ProgressBar(value: p.cpuPercent, color: .blue)
                                        .frame(width: 46, height: 4)
                                    Text(String(format: "%.1f%%", p.cpuPercent))
                                        .monospacedDigit()
                                        .frame(width: 58, alignment: .trailing)
                                        .foregroundStyle(.secondary)
                                    Text(String(format: "%.0f MB", p.memoryMB))
                                        .monospacedDigit()
                                        .frame(width: 74, alignment: .trailing)
                                        .foregroundStyle(.secondary)
                                }
                                .font(.callout)
                            }
                        }
                        // 나머지 요약
                        if monitor.snapshot.topProcesses.count > 6 {
                            Divider()
                            Text("외 \(monitor.snapshot.topProcesses.count - 6)개 더 보기 → 사이드바에서 각 탭 활용")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var activeCores: Int {
        var n: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("hw.activecpu", &n, &size, nil, 0)
        return max(1, Int(n))
    }

    private func GBtoBytes(_ gb: Double) -> Int64 { Int64(gb * 1_073_741_824) }
}

struct ProgressBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                Capsule().fill(color)
                    .frame(width: geo.size.width * max(0, min(value, 100)) / 100)
            }
        }
    }
}

struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    let sub: String
    let progress: Double

    var barColor: Color {
        switch progress {
        case ..<60: return .green
        case ..<85: return .orange
        default: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.secondary.opacity(0.1)))
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .monospacedDigit()
            ProgressBar(value: progress, color: barColor)
                .frame(height: 6)
            Text(sub)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
    }
}

// MARK: - 정리 화면
struct CleanupView: View {
    @ObservedObject var manager: CleanupManager
    @State private var cleaning = false
    @State private var freed: Int64?
    @State private var showFreedAlert = false
    @State private var showCleanConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("정리 가능 항목").font(.title2.weight(.semibold))
                    HStack(spacing: 6) {
                        if manager.isScanning {
                            ProgressView().controlSize(.mini)
                            Text("스캔 중… \(Int(manager.scanProgress))%").font(.callout).foregroundStyle(.secondary).monospacedDigit()
                        } else if !manager.scannedOnce {
                            Text("스캔을 시작하세요").font(.callout).foregroundStyle(.secondary)
                        } else {
                            Text("전체 \(ByteFmt.string(manager.junkTotal))")
                                .font(.callout).foregroundStyle(.secondary)
                            if manager.selectedTotal != manager.junkTotal {
                                Text("· 선택 \(ByteFmt.string(manager.selectedTotal))")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Menu { 
                    Button("진단 정보 복사") {
                        Task {
                            let diag = await manager.diagnose()
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(diag, forType: .string)
                        }
                    }
                } label: {
                    Image(systemName: "stethoscope")
                }
                .disabled(manager.isScanning)
                Spacer()
                Button {
                    Task { await manager.scan() }
                } label: {
                    Label("다시 스캔", systemImage: "arrow.clockwise")
                }
                .disabled(manager.isScanning)
                .keyboardShortcut("r", modifiers: .command)

                // 앱 캐시 원클릭 정리 (사용자 캐시만 안전하게)
                Button {
                    Task {
                        cleaning = true
                        cleaned = await manager.cleanCachesOnly()
                        cleaning = false
                        freed = cleaned
                        showFreedAlert = true
                    }
                } label: {
                    Label("앱 캐시 정리", systemImage: "folder.badge.questionmark.arrow.rectanglepath")
                        .frame(minWidth: 110)
                }
                .disabled(cleaning || manager.isScanning || cacheOnlyTotal == 0)
                .help("사용자 앱 캐시·Homebrew·npm·pip 캐시만 안전하게 정리합니다. 로그·휴지통·Xcode 데이터는 건드리지 않습니다.")

                Button {
                    showCleanConfirm = true
                } label: {
                    Label("선택 항목 정리", systemImage: "sparkles")
                        .frame(minWidth: 110)
                }
                .buttonStyle(.borderedProminent)
                .disabled(cleaning || manager.isScanning || manager.selectedTotal == 0)
            }
            .padding(16)
            .background(.bar)

            if cleaning {
                ProgressView("정리 중… 잠시만 기다려주세요")
                    .padding(.vertical, 8)
            }

            if manager.categories.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 42))
                        .foregroundStyle(.green)
                    Text("정리할 항목이 없습니다")
                        .font(.headline)
                    Text("모든 카테고리가 이미 청결합니다")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(manager.categories) { cat in
                    HStack(spacing: 14) {
                        Toggle("", isOn: Binding(
                            get: { manager.selectedIDs.contains(cat.id) },
                            set: { on in
                                if on { manager.selectedIDs.insert(cat.id) } else { manager.selectedIDs.remove(cat.id) }
                            }))
                            .labelsHidden()
                            .toggleStyle(.checkbox)

                        Image(systemName: cat.icon)
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Color.secondary.opacity(0.1)))

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(cat.name).font(.headline)
                                if cat.isTrash && cat.size > 0 {
                                    Text("영구 삭제")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.red.opacity(0.15)))
                                        .foregroundStyle(.red)
                                }
                            }
                            Text(cat.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        // 크기 배지
                        Group {
                            if !cat.scanned {
                                Text("—")
                            } else {
                                Text(ByteFmt.string(cat.size))
                            }
                        }
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(cat.scanned && cat.size > 0 ? .primary : .tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(cat.scanned && cat.size > 0 ? Color.secondary.opacity(0.10) : Color.clear)
                        )
                    }
                    .padding(.vertical, 5)
                }
                .listStyle(.inset)
            }
        }
        .task {
            await manager.scan()
        }
        .alert("정리 완료", isPresented: $showFreedAlert) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("\(ByteFmt.string(freed ?? 0)) 공간이 확보되었습니다")
        }
        .confirmationDialog("선택 항목 정리", isPresented: $showCleanConfirm, titleVisibility: .visible) {
            Button("정리 시작 (\(ByteFmt.string(manager.selectedTotal)))", role: .destructive) {
                Task {
                    cleaning = true
                    cleaned = await clean()
                    cleaning = false
                    freed = cleaned
                    showFreedAlert = true
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("선택한 항목의 파일을 휴지통으로 이동합니다. 휴지통 카테고리는 영구 삭제됩니다.")
        }
    }

    @State private var cleaned: Int64 = 0
    private func clean() async -> Int64 { await manager.clean() }

    /// 앱 캐시 전용 정리 범위의 총 크기 (버튼 활성화 판단용)
    private var cacheOnlyTotal: Int64 {
        manager.categories
            .filter { Self.cacheCategoryIDs.contains($0.id) }
            .reduce(0) { $0 + $1.size }
    }

    private static let cacheCategoryIDs = Set(["userCache", "homebrew", "npm", "pip", "simulator", "swiftpm"])
}

// MARK: - 대용량 파일
struct LargeFilesView: View {
    @ObservedObject var scanner: LargeFileScanner
    @State private var selection: Set<LargeFile.ID> = []
    @State private var showTrashConfirm = false
    @State private var sortKey: SortKey = .size
    @State private var sortOrder: SortOrder = .descending

    private var sortedResults: [LargeFile] {
        sortFiles(scanner.results, key: sortKey, order: sortOrder,
                  name: { $0.path.lastPathComponent },
                  size: { $0.size },
                  modified: { $0.modified })
    }

        var headerSubtitle: String {
        if scanner.isScanning {
            let mm = scanner.elapsedSeconds / 60
            let ss = scanner.elapsedSeconds % 60
            var base = "스캔 중… "
            if scanner.deepMode {
                base += "[정밀 스캔]\(mm > 0 ? " \(mm)분 " : "")\(ss)초 경과"  
            }
            return base + "발견 \(scanner.results.count)개"
        }
        if scanner.results.isEmpty { return "\(Int(scanner.thresholdMB))MB 이상 파일을 찾습니다" }
        return "총 \(scanner.results.count)개 · \(ByteFmt.string(scanner.totalSize))"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("대용량 파일").font(.title2.weight(.semibold))
                    Text(headerSubtitle).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                SortControl(key: $sortKey, order: $sortOrder)
                toggleCustomFolderMenu(scanner)
                Toggle("정밀 스캔", isOn: $scanner.deepMode)
                    .toggleStyle(.checkbox)
                    .disabled(scanner.isScanning)
                    .help("홈 전체·/usr/local까지 정밀 체크. 시간이 오래 걸릴 수 있으나 꼼꼼하게 다 찾습니다.")
                Toggle("Library 포함", isOn: $scanner.includeLibrary)
                    .toggleStyle(.checkbox)
                Button {
                    scanner.scan()
                } label: {
                    Label("스캔", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .disabled(scanner.isScanning)
                .keyboardShortcut("r", modifiers: .command)
            }
            .padding(16)
            .background(.bar)

            if scanner.results.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: scanner.isScanning ? "magnifyingglass" : "doc.badge.magnifyingglass")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)
                        .symbolEffect(.pulse, isActive: scanner.isScanning)
                    Text(scanner.isScanning ? "스캔 중…" : "결과 없음")
                        .font(.headline)
                    Text(scanner.isScanning ? "파일을 찾는 중입니다" : "스캔 버튼을 눌러 큰 파일을 찾으세요")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(sortedResults, selection: $selection) {
                    TableColumn("파일") { f in
                        HStack(spacing: 8) {
                            Image(systemName: "doc").foregroundStyle(.secondary)
                            Text(f.path.path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(f.path.path)
                        }
                    }
                    TableColumn("크기") { f in
                        Text(ByteFmt.string(f.size)).monospacedDigit()
                    }.width(95)
                    TableColumn("수정일") { f in
                        Text(f.modified.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—")
                    }.width(120)
                    TableColumn("동작") { f in
                        HStack(spacing: 6) {
                            Button {
                                scanner.reveal(f)
                            } label: {
                                Image(systemName: "folder.badge.magnifyingglass")
                            }
                            .buttonStyle(.borderless)
                            .help("파인더에서 보기")
                            Button {
                                scanner.trash(f)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("휴지통으로 이동")
                        }
                    }.width(80)
                }
                .tableStyle(.inset)
                .contextMenu(forSelectionType: LargeFile.ID.self) { ids in
                    if ids.count == 1, let f = scanner.results.first(where: { $0.id == ids.first }) {
                        fileContextMenu(path: { f.path })
                    } else {
                        Button("항목을 선택하세요") {}.disabled(true)
                    }
                } primaryAction: { _ in }
            }
        }
        .task {
            scanner.thresholdMB = AppSettings.shared.largeFileThresholdMB
            scanner.scan()
        }
    }
}

/// 공용: 커스텀 폴더 선택 메뉴 (대용량·중복 스캔 대상 지정)
func toggleCustomFolderMenu(_ scanner: LargeFileScanner) -> some View {
    FolderPickerMenu(roots: Binding(
        get: { scanner.customRoots },
        set: { scanner.customRoots = $0 }
    ))
}

func toggleCustomFolderMenu(_ finder: DuplicateFinder) -> some View {
    FolderPickerMenu(roots: Binding(
        get: { finder.customRoots },
        set: { finder.customRoots = $0 }
    ))
}

/// 폴더 선택 메뉴: 기본 위치 / 내가 고른 폴더들 상시 표시
struct FolderPickerMenu: View {
    @Binding var roots: [URL]
    @State private var showPicker = false
    @State private var pendingURL: URL?

    var body: some View {
        Menu {
            Toggle(isOn: Binding(
                get: { roots.isEmpty },
                set: { on in if on { roots = [] } }
            )) {
                Label("기본 위치 (바탕화면·문서 등)", systemImage: "house")
            }
            Divider()
            ForEach(roots, id: \.path) { url in
                Toggle(isOn: Binding(
                    get: { true },
                    set: { _ in }
                )) {
                    Label(url.lastPathComponent, systemImage: "folder")
                }
                .contextMenu {
                    Button(role: .destructive) {
                        roots.removeAll { $0.path == url.path }
                    } label: {
                        Label("목록에서 제거", systemImage: "minus.circle")
                    }
                }
            }
            Divider()
            Button {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = true
                panel.prompt = "선택"
                panel.message = "스캔할 폴더를 선택하세요"
                if panel.runModal() == .OK {
                    roots = panel.urls
                }
            } label: {
                Label("폴더 직접 선택…", systemImage: "folder.badge.plus")
            }
        } label: {
            Label(roots.isEmpty ? "스캔 위치" : "\(roots.first?.lastPathComponent ?? "")\(roots.count > 1 ? " 외 \(roots.count - 1)개" : "")",
                  systemImage: "folder.badge.gearshape")
        }
    }
}

// MARK: - 앱 관리 (통합: 앱 / Homebrew / pkg 설치 기록)
struct AppManagerView: View {
    @ObservedObject var manager: AppManager
    @ObservedObject var brewManager: BrewManager
    @ObservedObject var pkgManager: PkgReceiptManager

    @State private var selection: InstalledApp.ID?
    @State private var confirmApp: InstalledApp?
    @State private var showConfirm = false
    @State private var searchText = ""

    enum AppsPane: String, CaseIterable, Identifiable {
        case apps = "앱", brew = "Homebrew", pkg = "pkg 설치 기록", lang = "언어 패키지"
        var id: String { rawValue }
    }
    @State private var pane: AppsPane = .apps
    @ObservedObject var langManager = LanguagePackageManager()

    /// 테이블 열 헤더 클릭 → sortOrder 자동 갱신
    @State private var sortOrder = [KeyPathComparator(\InstalledApp.name)]

    var filtered: [InstalledApp] {
        let base = searchText.isEmpty
            ? manager.apps
            : manager.apps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        return base.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 상단: 세그먼트 토글 (앱 / Homebrew / pkg)
            HStack {
                Picker("보기", selection: $pane) {
                    ForEach(AppsPane.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 380)

                Spacer()

                switch pane {
                case .apps:
                    Menu {
                        Toggle("pkg/dmg 인스톨러 포함", isOn: $manager.includePkgInstallers)
                        Divider()
                        ForEach(manager.scanVolumes) { vol in
                            Toggle(vol.name, isOn: Binding(get: { vol.selected }, set: { on in
                                if let i = manager.scanVolumes.firstIndex(where: { $0.id == vol.id }) {
                                    manager.scanVolumes[i].selected = on
                                }
                            }))
                        }
                    } label: {
                        Label("스캔 대상", systemImage: "internaldrive.badge.checkmark")
                    }
                    Button {
                        manager.refresh()
                    } label: {
                        Label("새로고침", systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r", modifiers: .command)
                case .brew:
                    Picker("제거 방식", selection: $brewManager.removalMode) {
                        ForEach(BrewManager.RemovalMode.allCases, id: \.rawValue) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.menu)
                    Button("brew cleanup") {
                        Task { await brewManager.cleanupBrewCache() }
                    }
                    .disabled(brewManager.isScanning || !brewManager.brewAvailable)
                    Button {
                        Task { await brewManager.scan() }
                    } label: {
                        Label("다시 조회", systemImage: "arrow.clockwise")
                    }
                    .disabled(brewManager.isScanning || !brewManager.brewAvailable)
                    .keyboardShortcut("r", modifiers: .command)
                case .pkg:
                    Button {
                        Task { await pkgManager.scan() }
                    } label: {
                        Label("다시 조회", systemImage: "arrow.clockwise")
                    }
                    .disabled(pkgManager.isScanning)
                    .keyboardShortcut("r", modifiers: .command)
                case .lang:
                    Button {
                        Task { await langManager.scan() }
                    } label: {
                        Label("다시 조회", systemImage: "arrow.clockwise")
                    }
                    .disabled(langManager.isScanning)
                    .keyboardShortcut("r", modifiers: .command)
                }
            }
            .padding(14)
            .background(.bar)

            // 내용
            switch pane {
            case .apps:
                appsTable
            case .brew:
                BrewListInline(manager: brewManager)                case .pkg:
                PkgListInline(manager: pkgManager)
            case .lang:
                LangListInline(manager: langManager)
            }
        }
    }

    /// 앱 목록 (원래 화면)
    var appsTable: some View {
        HSplitView {
            Table(filtered, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("이름", value: \InstalledApp.name) { a in
                    HStack(spacing: 10) {
                        iconView(a)
                        Text(a.name).lineLimit(1)
                    }
                }
                TableColumn("버전", value: \InstalledApp.version) { a in
                    Text(a.version).foregroundStyle(.secondary)
                }.width(80)
                TableColumn("크기", value: \InstalledApp.sizeBytes) { a in
                    HStack {
                        if a.isCalculating {
                            ProgressView().controlSize(.mini)
                        } else {
                            Text(ByteFmt.string(a.sizeBytes)).monospacedDigit()
                        }
                    }
                }.width(100)
                TableColumn("경로") { a in
                    Text(a.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(minWidth: 500)
            .searchable(text: $searchText, prompt: "앱 이름 검색")

            sidePanel
                .frame(minWidth: 280, maxWidth: 340)
        }
        .confirmationDialog("\(confirmApp?.name ?? "") 제거", isPresented: $showConfirm, titleVisibility: .visible) {
            Button("휴지통으로 이동", role: .destructive) {
                Task {
                    _ = await manager.remove(app: confirmApp!, includeLeftovers: false)
                    showRemoveError(manager.lastError)
                    selection = nil
                }
            }
            Button("잔여 파일까지 즉시 삭제 (\(manager.leftovers(for: confirmApp ?? placeholderApp).count)개)", role: .destructive) {
                Task {
                    _ = await manager.remove(app: confirmApp!, includeLeftovers: true)
                    showRemoveError(manager.lastError)
                    selection = nil
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("앱은 휴지통으로 이동되고, 관련 잔여 파일(캐시·설정)은 복구 없이 즉시 삭제됩니다.")
        }
    }

    private var placeholderApp: InstalledApp {
        InstalledApp(url: URL(fileURLWithPath: "/"), name: "", version: "", bundleID: nil)
    }

    /// remove 실패 시 lastError 알림. 성공 시 notification 없음.
    private func showRemoveError(_ message: String?) {
        guard let message else { return }
        let alert = NSAlert()
        alert.messageText = "앱 제거 실패"
        alert.informativeText = message
        alert.addButton(withTitle: "확인")
        alert.runModal()
    }

    private func iconView(_ a: InstalledApp) -> some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: a.url.path))
            .resizable()
            .frame(width: 24, height: 24)
    }

    @ViewBuilder
    private var sidePanel: some View {
        if let id = selection, let app = manager.apps.first(where: { $0.id == id }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        iconView(app)
                            .frame(width: 56, height: 56)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.name).font(.title3.weight(.semibold))
                            Text(app.bundleID ?? "—").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    LabeledContent("버전", value: app.version)
                    LabeledContent("크기", value: app.isCalculating ? "계산 중…" : ByteFmt.string(app.sizeBytes))
                    LabeledContent("위치") {
                        Text(app.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .font(.caption)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .help(app.url.path)
                    }

                    Divider()
                    let lo = manager.leftovers(for: app)
                    HStack {
                        Text("관련 잔여 파일").font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(lo.count)개")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(lo.isEmpty ? Color.green.opacity(0.14) : Color.orange.opacity(0.14)))
                            .foregroundStyle(lo.isEmpty ? .green : .orange)
                    }
                    if lo.isEmpty {
                        Text("발견되지 않았습니다. 제거 시 완전히 깨끗이 지워집니다.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(lo, id: \.path) { f in
                            HStack(spacing: 6) {
                                Image(systemName: "doc.badge.ellipsis").font(.caption2).foregroundStyle(.tertiary)
                                Text(f.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }

                    Button(role: .destructive) {
                        confirmApp = app
                        showConfirm = true
                    } label: {
                        Label("앱 제거", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                }
                .padding(18)
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.secondary.opacity(0.4))
                Text("앱을 선택하세요")
                    .font(.headline)
                Text("왼쪽 목록에서 앱을 클릭하면\n상세 정보와 관련 파일이 표시됩니다")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - 백그라운드 항목
struct LaunchItemsView: View {
    @ObservedObject var manager: AppManager
    @State private var pendingItem: LaunchItem?
    @State private var showConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("백그라운드 실행 항목").font(.title2.weight(.semibold))
                    Text("로그인 시 자동 실행되는 LaunchAgents · 총 \(manager.launchItems.count)개")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    manager.refresh()
                } label: {
                    Label("새로고침", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            .padding(16)
            .background(.bar)

            if manager.launchItems.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "power.dotted")
                        .font(.system(size: 42))
                        .foregroundStyle(.green)
                    Text("등록된 항목 없음")
                        .font(.headline)
                    Text("백그라운드에서 자동 실행되는 항목이 없습니다")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(manager.launchItems) { item in
                    HStack(spacing: 14) {
                        Image(systemName: item.fromUserLibrary ? "person.crop.circle" : "building.2")
                            .font(.system(size: 16))
                            .foregroundStyle(item.fromUserLibrary ? .blue : .orange)
                            .frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Color.secondary.opacity(0.1)))
                            .help(item.fromUserLibrary ? "내 사용자 항목" : "시스템 전체 항목")

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name).font(.callout.weight(.medium))
                            Text(item.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                .font(.caption2).foregroundStyle(.tertiary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Button("비활성화") {
                            pendingItem = item
                            showConfirm = true
                        }
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
            }
        }
        .confirmationDialog("백그라운드 항목 비활성화", isPresented: $showConfirm, titleVisibility: .visible) {
            Button("휴지통으로 이동", role: .destructive) {
                if let it = pendingItem { manager.disable(item: it) }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("\(pendingItem?.name ?? "")이(가) 로그인 시 자동 실행되지 않게 됩니다. 복구하려면 휴지통에서 되돌리세요.")
        }
    }
}
