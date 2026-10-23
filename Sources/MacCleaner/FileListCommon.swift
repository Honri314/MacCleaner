import SwiftUI
import AppKit

// MARK: - 정렬 키 & 순서

enum SortKey: String, CaseIterable {
    case name, size, modified
    var label: String {
        switch self {
        case .name: return "이름"
        case .size: return "크기"
        case .modified: return "수정일"
        }
    }
}

enum SortOrder {
    case ascending, descending
    var toggled: SortOrder { self == .ascending ? .descending : .ascending }
    var icon: String { self == .ascending ? "arrow.up" : "arrow.down" }
}

// MARK: - 정렬 선택 컨트롤 (헤더에 넣는 필)

struct SortControl: View {
    @Binding var key: SortKey
    @Binding var order: SortOrder
    var keys: [SortKey] = SortKey.allCases

    var body: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(keys, id: \.self) { k in
                    Button(k == key ? "✓ \(k.label)" : k.label) {
                        if k == key { order = order.toggled } else { key = k }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.caption)
                    Text(key.label).font(.callout)
                    Image(systemName: order.icon)
                        .font(.caption2)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.secondary.opacity(0.1)))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .menuIndicator(.hidden)
            .help("정렬 기준 변경 (클릭 반복 시 오름/내림 전환)")
        }
    }
}

// MARK: - 파일 공용 컨텍스트 메뉴

struct FileContextMenu: ViewModifier {
    let path: () -> URL

    func body(content: Content) -> some View {
        content.contextMenu {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([path()])
            } label: {
                Label("파인더에서 열기", systemImage: "folder")
            }
            Button {
                NSWorkspace.shared.open(path())
            } label: {
                Label("이 파일 열기", systemImage: "arrow.up.forward.app")
            }
            Divider()
            Button {
                let p = NSPasteboard.general
                p.clearContents()
                p.setString(path().path, forType: .string)
            } label: {
                Label("전체 경로 복사", systemImage: "doc.on.doc")
            }
        }
    }
}

extension View {
    func fileContextMenu(path: @escaping () -> URL) -> some View {
        modifier(FileContextMenu(path: path))
    }
}

// MARK: - 공용 정렬 함수

func sortFiles<T>(_ items: [T], key: SortKey, order: SortOrder,
                  name: (T) -> String, size: (T) -> Int64, modified: (T) -> Date?) -> [T] {
    let asc: [T]
    switch key {
    case .name:
        asc = items.sorted { name($0).localizedCaseInsensitiveCompare(name($1)) == .orderedAscending }
    case .size:
        asc = items.sorted { size($0) < size($1) }
    case .modified:
        asc = items.sorted { a, b in
            let da = modified(a) ?? .distantPast
            let db = modified(b) ?? .distantPast
            return da < db
        }
    }
    return order == .ascending ? asc : asc.reversed()
}
