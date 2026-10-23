import SwiftUI

// MARK: - 시스템 튜닝 화면 (RemoveMacAI 스타일, defaults 기반 안전 토글)

struct TuningView: View {
    @ObservedObject var manager: SystemTuningManager
    @State private var showAIConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 안내 박스
                CategorySection {
                    HStack(spacing: 14) {
                        Image(systemName: "shield.checkerboard")
                            .font(.system(size: 28))
                            .foregroundStyle(.blue)
                            .frame(width: 46, height: 46)
                            .background(Circle().fill(Color.blue.opacity(0.12)))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("시스템 튜닝").font(.headline)
                            Text("macOS 설정을 조정해 광고·분석·AI·불편한 동작을 끕니다. 변경은 기존 값을 기록해두어 원클릭 복구가 됩니다.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            manager.undoAll()
                        } label: {
                            Label("전체 원복", systemImage: "arrow.uturn.backward")
                        }
                        .disabled(manager.applied.values.allSatisfy { !$0 })
                    }
                }

                aiStorageCard

                ForEach(TuningDomain.allCases, id: \.rawValue) { domain in
                    tuningSection(domain)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .task {
            manager.refresh()
            manager.measureAIModels()
        }
    }

    /// AI 모델 용량 + 캐시 정리 카드 (Apple Intelligence 섹션 위)
    private var aiStorageCard: some View {
        CategorySection {
            HStack(spacing: 14) {
                Image(systemName: "brain.filled.head.profile")
                    .font(.system(size: 24))
                    .foregroundStyle(.purple)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.purple.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Intelligence 모델 용량").font(.callout.weight(.medium))
                    Text(manager.aiModelsSizeBytes < 0 ? "측정 중…" : ByteFmt.string(manager.aiModelsSizeBytes))
                        .font(.title3.weight(.semibold).monospacedDigit())
                    Text("SIP 보호 영역이라 모델 파일 자체는 OS에서 자동 정리됩니다. AI 캐시는 아래 버튼으로 즉시 회수할 수 있습니다.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("AI 캐시 정리") {
                    _ = manager.clearAICaches()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private func tuningSection(_ domain: TuningDomain) -> some View {
        let domainItems = manager.items.filter { $0.domain == domain }
        let appliedCount = domainItems.filter { manager.applied[$0.id] == true }.count

        CategorySection {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(domain.rawValue).font(.headline)
                    Spacer()
                    Text("\(appliedCount)/\(domainItems.count) 적용됨")
                        .font(.caption)
                        .foregroundStyle(appliedCount > 0 ? .green : .secondary)
                    Button {
                        manager.applyDomain(domain)
                    } label: {
                        Label("전체 적용", systemImage: "checkmark.circle")
                    }
                    .controlSize(.small)
                    .disabled(appliedCount == domainItems.count)
                }

                ForEach(domainItems) { item in
                    tuningRow(item)
                }
            }
        }
    }

    @ViewBuilder
    private func tuningRow(_ item: TuningItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: manager.applied[item.id] == true ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(manager.applied[item.id] == true ? .green : .secondary.opacity(0.4))
                .font(.system(size: 16))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.callout.weight(.medium))
                Text(item.sub).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if manager.applied[item.id] == true {
                Button("해제") {
                    manager.undo(item)
                }
                .controlSize(.small)
            } else {
                Button("적용") {
                    if item.key == "aiOn" {
                        showAIConfirm = true
                    } else {
                        manager.apply(item)
                    }
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
        .confirmationDialog("Apple Intelligence 끄기", isPresented: $showAIConfirm, titleVisibility: .visible) {
            Button("끄기 + 정리 실행", role: .destructive) {
                manager.apply(item)
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("Apple Intelligence를 끄고 연쇄적으로 다음을 수행합니다:\n\n• AI 기능 비활성화 (Writing Tools·Genmoji 등)\n• AI 임시 캐시 즉시 삭제\n• iOS asset 서비스에 모델 제거 알림 → OS가 백그라운드에서 모델 파일 자동 삭제\n\n모델 파일 (수 GB)은 OS 스케줄에 따라 몇 시간 내 사라집니다.")
        }
    }
}
