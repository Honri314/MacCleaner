import SwiftUI

struct BrewView: View {
    @ObservedObject var manager: BrewManager
    @State private var selection: Set<BrewPackage.ID> = []
    @State private var showRemoveConfirm = false
    @State private var searchText = ""
    @State private var showCleanupResult = false
    @State private var cleanupResult: String = ""

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
            // 헤더
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Homebrew").font(.title2.weight(.semibold))
                    HStack(spacing: 6) {
                        if manager.isScanning {
                            ProgressView().controlSize(.mini)
                            Text("조회 중…").font(.callout).foregroundStyle(.secondary)
                        } else if !manager.brewAvailable {
                            Text("Homebrew 미설정").font(.callout).foregroundStyle(.orange)
                        } else {
                            let f = manager.packages.filter { $0.type == .formula }.count
                            let c = manager.packages.filter { $0.type == .cask }.count
                            Text("Formula \(f)개 · Cask \(c)개").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                Picker("제거 방식", selection: $manager.removalMode) {
                    ForEach(BrewManager.RemovalMode.allCases, id: \.rawValue) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 240)
                Button("brew cleanup") {
                    Task {
                        cleanupResult = (await manager.cleanupBrewCache()) ?? "완료"
                        showCleanupResult = true
                    }
                }
                .disabled(manager.isScanning || !manager.brewAvailable)
                Button {
                    Task { await manager.scan() }
                } label: {
                    Label("다시 조회", systemImage: "arrow.clockwise")
                }
                .disabled(manager.isScanning || !manager.brewAvailable)
                .keyboardShortcut("r", modifiers: .command)

                Button {
                    showRemoveConfirm = true
                } label: {
                    Label("제거", systemImage: "trash")
                        .frame(minWidth: 90)
                }
                .buttonStyle(.borderedProminent)
                .disabled(manager.isScanning || selectedPkgs.isEmpty || !manager.brewAvailable)
            }
            .padding(16)
            .background(.bar)

            if !manager.brewAvailable {
                VStack(spacing: 10) {
                    Image(systemName: "terminal")
                        .font(.system(size: 42))
                        .foregroundStyle(Color.secondary.opacity(0.4))
                    Text("Homebrew가 설치되지 않았습니다")
                        .font(.headline)
                    Text("brew.sh 사이트에서 설치하면 이 탭에서 패키지를 관리할 수 있습니다")
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
                                    .truncationMode(.tail)
                            }
                        }
                        .help(p.descriptionText)
                    }
                    TableColumn("버전") { p in
                        Text(p.version).foregroundStyle(.secondary)
                    }.width(110)
                    TableColumn("용량") { p in
                        HStack {
                            if p.isCalculating {
                                ProgressView().controlSize(.mini)
                            } else {
                                Text(p.sizeText).monospacedDigit()
                            }
                        }
                    }.width(100)
                }
                .tableStyle(.inset)
            }

            // 하단 요약바
            if !selectedPkgs.isEmpty {
                HStack {
                    Text("선택 \(selectedPkgs.count)개")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(manager.removalMode == .brewUninstall ? "brew uninstall로 제거됩니다" : "휴지통 이동 (복구 가능)")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16).padding(.vertical, 8).background(.bar)
            }
        }
        .task { await manager.scan() }
        .searchable(text: $searchText, prompt: "패키지 검색")
        .alert("brew cleanup 완료", isPresented: $showCleanupResult) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(cleanupResult.isEmpty ? "캐시 정리가 완료되었습니다" : cleanupResult)
        }
        .confirmationDialog("선택 패키지 제거", isPresented: $showRemoveConfirm, titleVisibility: .visible) {
            Button("\(manager.removalMode == .brewUninstall ? "brew uninstall" : "휴지통으로 이동") (\(selectedPkgs.count)개)", role: .destructive) {
                Task {
                    for p in selectedPkgs { await manager.remove(p) }
                    selection.removeAll()
                    await manager.scan()
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("선택한 \(selectedPkgs.count)개 패키지를 제거합니다. 이 작업은 되돌리기 어려울 수 있습니다.")
        }
    }
}
