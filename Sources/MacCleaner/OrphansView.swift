import SwiftUI

struct OrphansView: View {
    @ObservedObject var finder: OrphanFinder
    @State private var selection: Set<OrphanFile.ID> = []
    @State private var showRemoveConfirm = false

    var selectedItems: [OrphanFile] {
        finder.results.filter { selection.contains($0.id) }
    }
    var selectedSize: Int64 {
        selectedItems.reduce(0) { $0 + $1.sizeBytes }
    }

    @State private var sortKey: SortKey = .size
    @State private var sortOrder: SortOrder = .descending

    var sortedResults: [OrphanFile] {
        sortFiles(finder.results, key: sortKey, order: sortOrder,
                  name: { $0.name },
                  size: { $0.sizeBytes },
                  modified: { _ in .distantPast })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("잔여 파일").font(.title2.weight(.semibold))
                    HStack(spacing: 6) {
                        if finder.isScanning {
                            ProgressView().controlSize(.mini)
                            Text("스캔 중…").font(.callout).foregroundStyle(.secondary)
                        } else if !finder.scannedOnce {
                            Text("설치된 앱 중 소유자가 사라진 파일을 찾습니다").font(.callout).foregroundStyle(.secondary)
                        } else if finder.results.isEmpty {
                            Text("발견된 고아 파일 없음").font(.callout).foregroundStyle(.green)
                        } else {
                            Text("총 \(finder.results.count)개 · \(ByteFmt.string(finder.totalSize))")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                SortControl(key: $sortKey, order: $sortOrder)
                Button {
                    Task { await finder.scan() }
                } label: {
                    Label("다시 스캔", systemImage: "arrow.clockwise")
                }
                .disabled(finder.isScanning)
                .keyboardShortcut("r", modifiers: .command)

                Button {
                    showRemoveConfirm = true
                } label: {
                    Label("선택 삭제", systemImage: "trash")
                        .frame(minWidth: 100)
                }
                .buttonStyle(.borderedProminent)
                .disabled(finder.isScanning || selectedItems.isEmpty)
            }
            .padding(16)
            .background(.bar)

            if finder.results.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: finder.isScanning ? "magnifyingglass" : "trash.slash")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)
                        .symbolEffect(.pulse, isActive: finder.isScanning)
                    Text(finder.isScanning ? "스캔 중…" : "잔여 파일 없음")
                        .font(.headline)
                    Text(finder.isScanning
                         ? "설치된 앱 목록과 Library 파일을 대조 중입니다"
                         : "삭제된 앱의 남은 파일이 없습니다")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(sortedResults, selection: $selection) {
                    TableColumn("파일") { f in
                        HStack(spacing: 8) {
                            Image(systemName: "folder.badge.questionmark")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(f.name).lineLimit(1).truncationMode(.middle)
                                Text("추정 소유: \(f.sourceApp)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .help(f.url.path)
                    }
                    TableColumn("위험도") { f in
                        Text(f.riskLabel)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(f.risk == .bundleID
                                                       ? Color.green.opacity(0.15)
                                                       : Color.orange.opacity(0.15)))
                            .foregroundStyle(f.risk == .bundleID ? Color.green : Color.orange)
                    }.width(90)
                    TableColumn("크기") { f in
                        Text(ByteFmt.string(f.sizeBytes)).monospacedDigit()
                    }.width(95)
                    TableColumn("동작") { f in
                        HStack(spacing: 6) {
                            Button {
                                finder.reveal(f)
                            } label: {
                                Image(systemName: "folder.badge.magnifyingglass")
                            }
                            .buttonStyle(.borderless)
                            .help("파인더에서 보기")
                            Button {
                                Task { _ = await finder.remove(f) }
                                selection.remove(f.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("휴지통으로 이동")
                        }
                    }.width(80)
                }
                .tableStyle(.inset)
                .contextMenu(forSelectionType: String.self) { ids in
                    if ids.count == 1, let f = finder.results.first(where: { $0.id == ids.first }) {
                        fileContextMenu(path: { f.url })
                    } else {
                        Button("항목을 선택하세요") {}.disabled(true)
                    }
                } primaryAction: { _ in }
            }

            // 선택 항목 안전도 판정
            if let first = selectedItems.first {
                let v = SafetyChecker.verdict(for: first)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("선택 항목 삭제 검토").font(.headline)
                        Spacer()
                        if selectedItems.count > 1 {
                            Text("+\(selectedItems.count - 1)개 더").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    SafetyCard(title: first.name,
                               path: first.url.path,
                               sizeBytes: first.sizeBytes,
                               kind: first.risk == .bundleID ? "고아 파일(확인됨)" : "고아 파일(이름 기반)",
                               verdict: v.0,
                               reasons: v.1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)
            }

            // 하단 요약바
            if !finder.results.isEmpty {
                HStack {
                    Text("선택 \(selectedItems.count)개 · \(ByteFmt.string(selectedSize))")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("모두 휴지통으로 이동되며 복구 가능합니다")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
        .task { await finder.scan() }
        .confirmationDialog("선택한 잔여 파일 삭제", isPresented: $showRemoveConfirm, titleVisibility: .visible) {
            Button("휴지통으로 이동 (\(selectedItems.count)개 · \(ByteFmt.string(selectedSize)))", role: .destructive) {
                Task {
                    _ = await finder.removeAll(selectedItems)
                    selection.removeAll()
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("선택한 파일들을 휴지통으로 이동합니다. 이 작업은 휴지통에서 복구할 수 있습니다.")
        }
    }
}
