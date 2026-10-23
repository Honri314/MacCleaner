import SwiftUI

struct DuplicatesView: View {
    @ObservedObject var finder: DuplicateFinder
    @State private var showRemoveConfirm = false
    @State private var sortKey: SortKey = .size
    @State private var sortOrder: SortOrder = .descending

    var sortedGroups: [DuplicateGroup] {
        sortFiles(finder.groups, key: sortKey, order: sortOrder,
                  name: { $0.files.first?.path.lastPathComponent ?? "" },
                  size: { $0.wastedBytes },
                  modified: { $0.files.compactMap(\.modified).max() })
    }

    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("중복 파일").font(.title2.weight(.semibold))
                    HStack(spacing: 6) {
                        if finder.isScanning {
                            ProgressView().controlSize(.mini)
                            Text("스캔 중… 검사한 파일 \(finder.scannedFileCount)개").font(.callout).foregroundStyle(.secondary)
                        } else if !finder.scannedOnce {
                            Text("10MB 이상 동일 내용 파일끼리 묶어 보여줍니다").font(.callout).foregroundStyle(.secondary)
                        } else if finder.groups.isEmpty {
                            Text("중복 없음").font(.callout).foregroundStyle(.green)
                        } else {
                            Text("\(finder.groups.count)그룹 · 중복 \(finder.totalDuplicateCount)개 · 낭비 \(ByteFmt.string(finder.totalWasted))")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                SortControl(key: $sortKey, order: $sortOrder)
                toggleCustomFolderMenu(finder)
                if !finder.groups.isEmpty {
                    Button("기본 선택") { finder.defaultsOriginalsAll() }
                        .controlSize(.small)
                    Button("전체 선택") { finder.selectAllCandidates() }
                        .controlSize(.small)
                    Button("해제") { finder.deselectAll() }
                        .controlSize(.small)
                }
                Button {
                    finder.scan()
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
                .disabled(finder.isScanning || finder.selectedPaths.isEmpty)
            }
            .padding(16)
            .background(.bar)

            if finder.groups.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: finder.isScanning ? "magnifyingglass" : "doc.on.doc")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)
                        .symbolEffect(.pulse, isActive: finder.isScanning)
                    Text(finder.isScanning ? "스캔 중…" : "중복 파일 없음")
                        .font(.headline)
                    Text(finder.isScanning
                        ? "동일 크기 파일들의 SHA-256 해시를 비교하는 중입니다"
                        : "해시가 완전히 같은 10MB 이상의 파일만 표시됩니다")
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(sortedGroups) { group in
                        Section {
                            ForEach(group.files) { f in
                                HStack(spacing: 12) {
                                    // 원본 체크박스 (남길 것 하나만 선택 가능)
                                    Button {
                                        finder.toggleOriginal(f)
                                    } label: {
                                        Image(systemName: isOriginal(f, group) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(isOriginal(f, group) ? Color.blue : Color.secondary)
                                            .font(.system(size: 17))
                                    }
                                    .buttonStyle(.borderless)
                                    .help(isOriginal(f, group) ? "유지 중 (클릭해도 유지)" : "이 파일을 유지 대표로 선택")

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(f.path.lastPathComponent)
                                            .font(.callout)
                                            .lineLimit(1)
                                        Text(f.path.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }

                                    Spacer()

                                    if isDeleteCandidate(f) {
                                        Text("삭제 예정")
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(Color.red.opacity(0.13)))
                                            .foregroundStyle(.red)
                                    }

                                    Text(ByteFmt.string(f.sizeBytes))
                                        .font(.callout)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                        .frame(width: 80, alignment: .trailing)

                                    Text(f.modified.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "—")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 130, alignment: .trailing)

                                    HStack(spacing: 4) {
                                        Button {
                                            finder.reveal(f)
                                        } label: {
                                            Image(systemName: "folder.badge.magnifyingglass")
                                        }
                                        .buttonStyle(.borderless)
                                        .help("파인더에서 보기")
                                    }
                                }
                                .padding(.vertical, 3)
                                .fileContextMenu(path: { f.path })
                            }
                        } header: {
                            HStack {
                                Text("\(group.files.count)개 동일")
                                    .font(.callout.weight(.semibold))
                                Spacer()
                                Text("그룹 낭비 \(ByteFmt.string(group.wastedBytes))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .task { await finder.startScanIfNeeded() }
        .confirmationDialog("선택한 중복 파일 삭제", isPresented: $showRemoveConfirm, titleVisibility: .visible) {
            Button("휴지통으로 이동 (\(finder.selectedPaths.count)개)", role: .destructive) {
                Task { await finder.removeSelected() }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("선택한 중복 파일(\(ByteFmt.string(finder.selectedSizeTotal)) 확보)을 휴지통으로 이동합니다.")
        }
    }

    private func isOriginal(_ f: DuplicateFile, _ group: DuplicateGroup) -> Bool {
        !finder.selectedPaths.contains(f.path.path)
    }
    private func isDeleteCandidate(_ f: DuplicateFile) -> Bool {
        finder.selectedPaths.contains(f.path.path)
    }
}

extension DuplicateFinder {
    func startScanIfNeeded() async {
        if !scannedOnce && !isScanning { scan() }
    }
}
