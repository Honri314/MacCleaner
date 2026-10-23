import SwiftUI

// MARK: - "시스템 데이터" 해석 섹션 (대시보드 위젯)

struct StorageBreakdownSection: View {
    @ObservedObject var manager: StorageBreakdownManager
    @State private var showAll = false

    var body: some View {
        CategorySection {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .font(.system(size: 26))
                        .foregroundStyle(.orange)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(Color.orange.opacity(0.12)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("시스템 데이터 분석").font(.headline)
                        Text("macOS가 “시스템 데이터”로 표시하는 실제 공간을 분해해 보여줍니다")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await manager.scan() }
                    } label: {
                        Label("분해 스캔", systemImage: "arrow.clockwise")
                    }
                    .disabled(manager.isScanning)
                }

                if manager.isScanning {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("계산 중…").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } else if manager.categories.isEmpty {
                    if manager.scannedOnce {
                        Text("분석 가능한 대용량 항목 없음")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                } else {
                    let shown = showAll ? manager.categories : Array(manager.categories.prefix(4))
                    ForEach(shown) { c in
                        HStack(spacing: 12) {
                            Image(systemName: c.safeToClean ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(c.safeToClean ? .green : .orange)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(c.name).font(.callout.weight(.medium))
                                    Spacer()
                                    Text(ByteFmt.string(c.sizeBytes))
                                        .font(.callout.weight(.semibold))
                                        .monospacedDigit()
                                }
                                Text(c.sub).font(.caption).foregroundStyle(.secondary)
                                Text(c.why).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    if manager.categories.count > 4 && !showAll {
                        Button("나머지 \(manager.categories.count - 4)개 더 보기") {
                            showAll = true
                        }
                        .controlSize(.small)
                    }

                    // 총합 라인
                    Divider().padding(.top, 6)
                    HStack {
                        Text("전체 ~/Library").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(ByteFmt.string(manager.libraryTotal))
                            .font(.callout.weight(.semibold))
                            .monospacedDigit()
                    }
                    Text("이 외에도 시스템 예약 공간·스냅샷 등이 macOS 계산에 합산됩니다. 안전하게 회수하려면 위의 “정리 가능” 항목을 선택해 정리하거나, 대용량 파일 탭에서 실제 파일을 정리하시면 됩니다.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .task {
            if !manager.scannedOnce && !manager.isScanning {
                await manager.scan()
            }
        }
    }
}
