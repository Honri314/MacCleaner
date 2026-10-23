import SwiftUI

// MARK: - 도넛 차트 (고정 크기 — 부모 frame에 맞춰 항상 동일 시각 크기)

struct DonutChart: View {
    let segments: [DonutSegment]
    var centerTitle: String = ""
    var centerSub: String = ""
    @State private var animated = false

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let lineWidth: CGFloat = 20  // 고정 링 두께 → 모든 도넛 동일 두께
            ZStack {
                // 배경 링
                Circle()
                    .stroke(Color.secondary.opacity(0.12), lineWidth: lineWidth)
                    .padding(lineWidth / 2)
                // 세그먼트
                ForEach(Array(segmentRanges.enumerated()), id: \.offset) { idx, range in
                    Circle()
                        .trim(from: range.lowerBound, to: range.lowerBound + (range.upperBound - range.lowerBound) * (animated ? 1 : 0))
                        .stroke(segments[idx].color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                        .padding(lineWidth / 2)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.6).delay(Double(idx) * 0.08), value: animated)
                }
                VStack(spacing: 2) {
                    Text(centerTitle)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(centerSub)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: side * 0.55)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { animated = true }
    }

    private var segmentRanges: [ClosedRange<Double>] {
        let total = max(segments.reduce(0) { $0 + $1.value }, 1)
        var start = 0.0
        var out: [ClosedRange<Double>] = []
        for seg in segments {
            let frac = Double(seg.value) / Double(total)
            out.append(start...(start + frac - min(frac, 0.002)))
            start += frac
        }
        return out.isEmpty ? [0.0...1.0] : out
    }
}

struct DonutSegment: Identifiable {
    var id = UUID()
    let label: String
    let value: Double
    let color: Color
}

// MARK: - 미니 스파크라인 (추이)

struct Sparkline: View {
    let values: [Double]
    var color: Color = .blue
    var height: CGFloat = 30

    var body: some View {
        GeometryReader { geo in
            if values.count >= 2 {
                let maxV = max(values.max() ?? 1, 0.001)
                let w = geo.size.width
                let h = geo.size.height
                let step = w / CGFloat(values.count - 1)
                Path { p in
                    for (i, v) in values.enumerated() {
                        let x = CGFloat(i) * step
                        let y = h - CGFloat(v / maxV) * h * 0.9 - h * 0.05
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                        else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                // 마지막 점
                let lastY = h - CGFloat((values.last ?? 0) / maxV) * h * 0.9 - h * 0.05
                Circle()
                    .fill(color)
                    .frame(width: 4, height: 4)
                    .position(x: w - 2, y: lastY)
            }
        }
        .frame(height: height)
        .animation(.easeInOut(duration: 0.4), value: values)
    }
}

// MARK: - 안전도 판정 (파일 지우기 전 검토)

enum SafetyVerdict: String {
    case safe = "바로 삭제 가능"
    case review = "검토 후 삭제 권장"
    case caution = "주의 필요"
}

struct SafetyCard: View {
    let title: String
    let path: String
    let sizeBytes: Int64
    let kind: String   // "시스템 캐시" / "로그" / "개인 문서" / "앱 번들" 등
    let verdict: SafetyVerdict
    let reasons: [String]

    var verdictColor: Color {
        switch verdict {
        case .safe: return .green
        case .review: return .orange
        case .caution: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: verdict == .safe ? "checkmark.shield.fill" : verdict == .review ? "exclamationmark.shield.fill" : "xmark.shield.fill")
                    .foregroundStyle(verdictColor)
                Text(title).font(.headline)
                Spacer()
                Text(verdict.rawValue)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(verdictColor.opacity(0.15)))
                    .foregroundStyle(verdictColor)
            }
            Text(path).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            HStack {
                Text(kind).font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.1)))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(ByteFmt.string(sizeBytes)).font(.callout.weight(.semibold)).monospacedDigit()
            }
            if !reasons.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(reasons, id: \.self) { r in
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle").font(.caption2).foregroundStyle(.green)
                            Text(r).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
    }
}

// MARK: - 안전도 판정 로직

enum SafetyChecker {
    /// 잔여 파일이 삭제해도 되는지 판정
    static func verdict(for orphan: OrphanFile) -> (SafetyVerdict, [String]) {
        var reasons: [String] = []
        let path = orphan.url.path.lowercased()
        // 시스템 경로는 caution
        if path.contains("/library/system") || path.contains("com.apple.") {
            return (.caution, ["Apple 시스템 자원일 가능성 - 삭제 시 앱/시스템 오동작 가능"])
        }
        if orphan.risk == .bundleID {
            reasons.append("설치된 앱의 등록 번들ID와 일치하는 항목이 없음")
            reasons.append("휴지통 이동 방식이라 복구 가능")
            return (.safe, reasons)
        }
        reasons.append("앱 이름 유사도 기반 추정 - 동명 다른 자원일 수 있음")
        reasons.append("휴지통 이동 방식이라 복구 가능")
        return (.review, reasons)
    }

    /// 정리 카테고리 판정
    static func verdict(for category: CleanupCategory) -> (SafetyVerdict, [String]) {
        if category.isTrash {
            return (.caution, ["영구 삭제로 복구 불가 - 비우기 전 원하는 파일이 없는지 확인하세요"])
        }
        return (.safe, ["캐시·로그류는 앱이 자동으로 재생성합니다", "휴지통 이동 방식이라 복구 가능"])
    }
}
