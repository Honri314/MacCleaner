import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var permissions = PermissionManager()

    var body: some View {
        Form {
            Section("화면 표시") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("글자 크기").font(.callout.weight(.medium))
                        Spacer()
                        Text(String(format: "%.0f%%", settings.fontScale * 100))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.fontScale, in: 0.8...1.4, step: 0.05) {
                        Text("글자 크기")
                    } minimumValueLabel: {
                        Text("작게").font(.caption)
                    } maximumValueLabel: {
                        Text("크게").font(.caption)
                    }
                }
                Toggle("행 간격 줄이기 (컴팩트 모드)", isOn: $settings.compactRows)
            }

            Section("알림") {
                Toggle("정리 완료 시 알림", isOn: $settings.notifyCleanupDone)
                Toggle("스마트 스캔 완료 시 알림", isOn: $settings.notifySmartScanDone)
                Toggle("디스크 여유 부족 시 알림", isOn: $settings.notifyDiskLow)
                if settings.notifyDiskLow {
                    Stepper(value: $settings.diskLowThresholdGB, in: 1...100) {
                        Text("여유 \(settings.diskLowThresholdGB)GB 이하일 때")
                    }
                }
            }

            Section("위젯 (메뉴바)") {
                Toggle("메뉴바에 사용량 위젯 표시", isOn: $settings.menuBarEnabled)
                if settings.menuBarEnabled {
                    Toggle("CPU 표시", isOn: $settings.menuBarShowCPU)
                    Toggle("메모리 표시", isOn: $settings.menuBarShowMemory)
                    Toggle("디스크 여유 표시", isOn: $settings.menuBarShowDisk)
                    Text("예: CPU 12%  MEM 62%  DISK 41GB")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Section("스캔 임계값") {
                ThresholdRow(
                    title: "대용량 파일",
                    sub: "이보다 큰 파일만 대용량으로 분류합니다",
                    value: $settings.largeFileThresholdMB,
                    presets: [50, 100, 200, 500],
                    range: 10...1000,
                    unit: "MB",
                    presetLabel: { MB in MB >= 1000 ? "1GB" : "\(MB)MB" }
                )

                ThresholdRow(
                    title: "중복 검사 최소",
                    sub: "이보다 큰 파일만 해시 비교합니다 (작을수록 검사 오래 걸림)",
                    value: $settings.duplicateMinSizeMB,
                    presets: [1, 10, 50, 100],
                    range: 1...500,
                    unit: "MB",
                    presetLabel: { MB in "\(MB)MB" }
                )

                ThresholdRow(
                    title: "잔여 파일 최소",
                    sub: "이보다 작은 잔여물은 노이즈로 무시합니다",
                    value: $settings.orphanMinSizeMB,
                    presets: [1, 5, 10, 50],
                    range: 1...100,
                    unit: "MB",
                    presetLabel: { MB in "\(MB)MB" }
                )
            }

            Section("정리 안전 옵션") {
                Toggle(isOn: $settings.cleanupIncludeTrash) {
                    Text("정리 시 휴지통 카테고리 포함 (영구 삭제됨!)")
                }
                Text("휴지통 카테고리는 파일을 완전히 지워서 복구가 안 됩니다")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("폴더 접근 권한") {
                ForEach(permissions.permissions) { item in
                    HStack {
                        Image(systemName: statusIcon(for: item))
                            .foregroundStyle(statusColor(for: item))
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.callout.weight(.medium))
                            Text(item.description).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        statusBadge(for: item)
                        Button("폴더 열기") { permissions.requestAccess(item) }
                            .controlSize(.small)
                    }
                    .padding(.vertical, 3)
                }
                HStack {
                    Button("권한 다시 확인") { permissions.checkAllDeep() }
                    Button("시스템 설정 > 전체 디스크 접근 열기") { permissions.openFullDiskSettings() }
                }
                Text("일부 폴더(macOS 보안 정책)는 앱이 직접 권한을 부여할 수 없고 시스템 설정에서 수동으로 허용해야 합니다. '폴더 열기' 후 '권한 다시 확인'을 눌러 갱신하세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("기타") {
                Button("모든 설정 기본값으로") { settings.resetDefaults() }
            }

            Section("정보") {
                LabeledContent("앱", value: "MacCleaner v1.1")
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 620, minHeight: 480)
        .onAppear {
            permissions.checkAllDeep()  // 정밀 판정 (opendir 기반, TCC 무유발)
        }
    }

    private func statusIcon(for item: PermissionItem) -> String {
        let ok = permissions.status[item.id] ?? false
        return ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }
    private func statusColor(for item: PermissionItem) -> Color {
        (permissions.status[item.id] ?? false) ? .green : .orange
    }
    private func statusBadge(for item: PermissionItem) -> some View {
        let ok = permissions.status[item.id] ?? false
        return Text(ok ? "허용됨" : "확인 필요")
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(ok ? Color.green.opacity(0.14) : Color.orange.opacity(0.14)))
            .foregroundStyle(ok ? Color.green : Color.orange)
    }
}

// MARK: - 임계값 편집 행 (프리셋 버튼 + 슬라이더)

struct ThresholdRow: View {
    let title: String
    let sub: String
    @Binding var value: Int
    let presets: [Int]
    let range: ClosedRange<Int>
    let unit: String
    let presetLabel: (Int) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.callout.weight(.medium))
                    Text(sub).font(.caption).foregroundStyle(.tertiary)
                }
                Spacer()
                Text(value >= 1000 ? "1GB" : "\(value)\(unit)")
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.blue.opacity(0.12)))
                    .foregroundStyle(.blue)
            }

            // 프리셋 원클릭 버튼
            HStack(spacing: 7) {
                ForEach(presets, id: \.self) { p in
                    let selected = value == p
                    Button {
                        value = p
                    } label: {
                        Text(presetLabel(p))
                            .font(.caption.weight(selected ? .semibold : .regular))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(selected ? Color.blue.opacity(0.18) : Color.secondary.opacity(0.08))
                            )
                            .foregroundStyle(selected ? Color.blue : Color.primary)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            // 미세 조정 슬라이더
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { newVal in
                        let stepped = Int(newVal / 5) * 5
                        value = min(max(stepped, range.lowerBound), range.upperBound)
                    }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound)
            )
            .tint(.blue)
        }
        .padding(.vertical, 4)
    }
}
