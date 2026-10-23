import SwiftUI

struct PkgView: View {
    @ObservedObject var manager: PkgReceiptManager
    @State private var selection: Set<PkgReceipt.ID> = []
    @State private var showForgetConfirm = false
    @State private var pendingReceipt: PkgReceipt?

    var selectedReceipts: [PkgReceipt] {
        manager.receipts.filter { selection.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("pkg 설치 기록").font(.title2.weight(.semibold))
                    HStack(spacing: 6) {
                        if manager.isScanning {
                            ProgressView().controlSize(.mini)
                            Text("조회 중…").font(.callout).foregroundStyle(.secondary)
                        } else if !manager.scannedOnce {
                            Text("인스톨러(pkg)로 설치된 항목을 확인합니다").font(.callout).foregroundStyle(.secondary)
                        } else {
                            Text("설치 기록 \(manager.receipts.count)개 (Apple 시스템 항목 제외)")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                Button {
                    Task { await manager.scan() }
                } label: {
                    Label("다시 조회", systemImage: "arrow.clockwise")
                }
                .disabled(manager.isScanning)
                .keyboardShortcut("r", modifiers: .command)

                Button {
                    pendingReceipt = nil
                    showForgetConfirm = true
                } label: {
                    Label("기록 삭제", systemImage: "doc.badge.minus")
                        .frame(minWidth: 100)
                }
                .buttonStyle(.bordered)
                .disabled(manager.isScanning || selectedReceipts.isEmpty)
            }
            .padding(16)
            .background(.bar)

            if manager.receipts.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: manager.isScanning ? "magnifyingglass" : "doc.badge.gearshape")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)
                        .symbolEffect(.pulse, isActive: manager.isScanning)
                    Text(manager.isScanning ? "조회 중…" : "설치 기록 없음")
                        .font(.headline)
                    Text("pkgutil --pkgs 기준, Apple 시스템 항목은 제외하고 표시됩니다")
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
                        .help("pkg receipt 기록을 시스템에서 제거합니다 (sudo)")
                    }.width(95)
                }
                .tableStyle(.inset)

                Text("⚠️ '기록 삭제'는 시스템에서 설치 기록만 제거합니다. 실제 파일은 파인더에서 직접 지워야 합니다.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.bar)
            }
        }
        .task { await manager.scan() }
        .confirmationDialog(
            pendingReceipt == nil ? "선택한 설치 기록 삭제" : "\(pendingReceipt!.appName) 기록 삭제",
            isPresented: $showForgetConfirm, titleVisibility: .visible
        ) {
            Button("기록 삭제 (sudo 필요)", role: .destructive) {
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
            Text("이 작업은 설치 기록을 시스템에서 제거하고, 앱 자체는 남아 있습니다. 파일 삭제는 '앱 관리' 탭에서, 잔여 청소는 '잔여 파일' 탭에서 처리하세요.")
        }
    }
}
