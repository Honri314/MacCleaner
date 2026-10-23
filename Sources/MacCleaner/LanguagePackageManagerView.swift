import SwiftUI

// MARK: - 언어 패키지 인라인 리스트 (앱 관리 탭의 4번째 세그먼트)

struct LangListInline: View {
    @ObservedObject var manager: LanguagePackageManager
    @State private var searchText = ""

    var filtered: [LanguagePackage] {
        searchText.isEmpty
            ? manager.packages
            : manager.packages.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if manager.packages.isEmpty && !manager.isScanning {
                VStack(spacing: 10) {
                    Image(systemName: "curlybraces")
                        .font(.system(size: 42))
                        .foregroundStyle(Color.secondary.opacity(0.4))
                    Text(manager.scannedOnce ? "pip·npm 패키지가 없습니다" : "조회 전입니다")
                        .font(.headline)
                    Text("pip3 설치 패키지 · npm 전역 패키지를 보여줍니다")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if !manager.scannedOnce {
                        Button("지금 조회") {
                            Task { await manager.scan() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if manager.packages.isEmpty {
                ProgressView("pip·npm 조회 중…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(filtered) {
                    TableColumn("매니저") { p in
                        Text(p.manager.uppercased())
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(p.manager == "pip" ? Color.orange.opacity(0.14) : Color.green.opacity(0.14)))
                            .foregroundStyle(p.manager == "pip" ? .orange : .green)
                    }
                    .width(80)
                    TableColumn("이름") { p in
                        Text(p.name).lineLimit(1)
                    }
                    TableColumn("버전") { p in
                        Text(p.version).foregroundStyle(.secondary)
                    }
                    .width(110)
                    TableColumn("동작") { p in
                        Button("제거") {
                            Task { await manager.remove(p) }
                        }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                    }
                    .width(70)
                }
                .overlay(alignment: .top) {
                    // 검색창 (선택하지 않은 상태에서도)
                    Color.clear
                }
                .searchable(text: $searchText, prompt: "패키지 이름 검색")
            }
        }
        .task {
            if !manager.scannedOnce {
                await manager.scan()
            }
        }
    }
}
