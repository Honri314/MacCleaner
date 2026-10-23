import SwiftUI

// MARK: - Brew 인라인 리스트 (AppManagerView 안에 들어가는 경량 버전)

struct BrewListInline: View {
    @ObservedObject var manager: BrewManager
    @State private var selection: Set<BrewPackage.ID> = []
    @State private var searchText = ""
    @State private var showRemoveConfirm = false

    var filtered: [BrewPackage] {
        searchText.isEmpty
            ? manager.packages
            : manager.packages.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    var selectedPkgs: [BrewPackage] {
        manager.packages.filter { selection.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !manager.brewAvailable {
                VStack(spacing: 10) {
                    Image(systemName: "terminal")
                        .font(.system(size: 42))
                        .foregroundStyle(Color.secondary.opacity(0.4))
                    Text("Homebrew가 설치되지 않았습니다")
                        .font(.headline)
                    Text("brew.sh에서 설치하면 Formula·Cask를 여기서 관리할 수 있습니다")
                        .font(.callout).foregroundStyle(.secondary)
                    Link("brew.sh 열기", destination: URL(string: "https://brew.sh")!)
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: manager.isScanning ? "magnifyingglass" : "terminal")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)
                        .symbolEffect(.pulse, isActive: manager.isScanning)
                    Text(manager.isScanning ? "조회 중…" : "설치된 패키지 없음")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(filtered, selection: $selection) {
                    TableColumn("유형") { p in
                        Text(p.type == .cask ? "Cask" : "Formula")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(p.type == .cask ? Color.purple.opacity(0.14) : Color.blue.opacity(0.14)))
                            .foregroundStyle(p.type == .cask ? .purple : .blue)
                    }.width(90)
                    TableColumn("이름") { p in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.name).lineLimit(1)
                            if !p.descriptionText.isEmpty {
                                Text(p.descriptionText)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                        .help(p.descriptionText)
                    }
                    TableColumn("버전") { p in
                        Text(p.version).foregroundStyle(.secondary)
                    }.width(100)
                    TableColumn("용량") { p in
                        HStack {
                            if p.isCalculating {
                                ProgressView().controlSize(.mini)
                            } else {
                                Text(p.sizeText).monospacedDigit()
                            }
                        }
                    }.width(95)
                    TableColumn("동작") { p in
                        Button("제거") {
                            Task {
                                _ = await manager.remove(p)
                                await manager.scan()
                            }
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }.width(70)
                }
                .tableStyle(.inset)
            }

            if !selectedPkgs.isEmpty {
                HStack {
                    Text("선택 \(selectedPkgs.count)개 · \(manager.removalMode == .brewUninstall ? "brew uninstall" : "휴지통 이동")")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("선택 제거") {
                        Task {
                            for p in selectedPkgs { await manager.remove(p) }
                            selection.removeAll()
                            await manager.scan()
                        }
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 16).padding(.vertical, 8).background(.bar)
            }
        }
        .searchable(text: $searchText, prompt: "패키지 검색")
        .task { await manager.startScanIfNeeded() }
    }
}

// MARK: - pkg 인라인 리스트

struct PkgListInline: View {
    @ObservedObject var manager: PkgReceiptManager
    @State private var selection: Set<PkgReceipt.ID> = []
    @State private var showForgetConfirm = false
    @State private var pendingReceipt: PkgReceipt?

    var selectedReceipts: [PkgReceipt] {
        manager.receipts.filter { selection.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if manager.receipts.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: manager.isScanning ? "magnifyingglass" : "doc.badge.gearshape")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)
                        .symbolEffect(.pulse, isActive: manager.isScanning)
                    Text(manager.isScanning ? "조회 중…" : "설치 기록 없음")
                        .font(.headline)
                    Text("pkgutil --pkgs 기준, Apple 시스템 항목 제외")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(manager.receipts, selection: $selection) {
                    TableColumn("패키지 ID") { r in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.appName).lineLimit(1)
                            Text(r.pkgID).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    TableColumn("버전") { r in
                        Text(r.version).foregroundStyle(.secondary)
                    }.width(110)
                    TableColumn("용량") { r in
                        HStack {
                            if r.sizeBytes < 0 {
                                ProgressView().controlSize(.mini)
                            } else {
                                Text(ByteFmt.string(r.sizeBytes)).monospacedDigit()
                            }
                        }
                    }.width(95)
                    TableColumn("동작") { r in
                        Button("기록 삭제") {
                            pendingReceipt = r
                            showForgetConfirm = true
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .disabled(r.isApple)
                    }.width(90)
                }
                .tableStyle(.inset)

                Text("'기록 삭제'는 설치 기록만 제거하며 실제 파일은 앱 탭에서 지워야 합니다")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.bar)
            }
        }
        .task { await manager.startScanIfNeeded() }
        .confirmationDialog(
            pendingReceipt == nil ? "선택한 설치 기록 삭제" : "\(pendingReceipt!.appName) 기록 삭제",
            isPresented: $showForgetConfirm, titleVisibility: .visible
        ) {
            Button("기록 삭제 (sudo)", role: .destructive) {
                Task {
                    if let r = pendingReceipt {
                        _ = await manager.forget(r)
                    } else {
                        for r in selectedReceipts { _ = await manager.forget(r) }
                        selection.removeAll()
                    }
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("설치 기록만 시스템에서 제거되고 파일은 남아 있습니다.")
        }
    }
}

extension BrewManager {
    func startScanIfNeeded() async {
        if !scannedOnce && !isScanning { await scan() }
    }
}

extension PkgReceiptManager {
    func startScanIfNeeded() async {
        if !scannedOnce && !isScanning { await scan() }
    }
}
