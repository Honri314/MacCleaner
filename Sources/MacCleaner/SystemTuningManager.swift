import Foundation
import SwiftUI

// MARK: - 시스템 튜닝 (RemoveMacAI 스타일 — defaults 기반 안전 토글)
// 모든 항목은 `defaults write/read` 사용. 시스템 파일·SIP 영역은 건드리지 않음.
// 변경 전 기존 값을 journal에 기록 → 원복 가능 (RemoveMacAI의 journal.json 방식).

enum TuningDomain: String, CaseIterable {
    case ai = "Apple Intelligence"
    case privacy = "개인정보·광고"
    case annoyances = "불편한 동작"
    case finder = "Finder"
    case typing = "입력 보정"
}

struct TuningItem: Identifiable, Hashable {
    var id: String { "\(domain.rawValue).\(key)" }
    let domain: TuningDomain
    let key: String
    let title: String
    let sub: String
}

@MainActor
final class SystemTuningManager: ObservableObject {
    @Published private(set) var items: [TuningItem] = SystemTuningManager.buildItems()
    @Published private(set) var applied: [String: Bool] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var aiModelsSizeBytes: Int64 = -1  // -1 = 미측정

    static let journalPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/MacCleaner/tuning-journal.json")

    init() { refresh() }

    // MARK: 아이템 정의

    static func buildItems() -> [TuningItem] {
        var out: [TuningItem] = []
        // Apple Intelligence
        out.append(TuningItem(domain: .ai, key: "aiOn", title: "Apple Intelligence 끄기", sub: "Siri 제안·Writing Tools·Genmoji 등 AI 기능 전체 비활성화"))
        out.append(TuningItem(domain: .ai, key: "writingtools", title: "Writing Tools 끄기", sub: "메일·메모·사파리 등의 AI 문장 다듬기 비활성"))
        out.append(TuningItem(domain: .ai, key: "genmoji", title: "Genmoji·Image Playground 끄기", sub: "AI 이모지·이미지 생성 비활성"))
        out.append(TuningItem(domain: .ai, key: "cleanup", title: "Photos Clean Up 끄기", sub: "사진앱 AI 오브젝트 제거 도구 비활성"))
        out.append(TuningItem(domain: .ai, key: "siriglow", title: "Siri 애니메이션 앱 팝 끄기", sub: "Siri·Spotlight 상단의 시각 효과 간소화"))
        // 개인정보·광고
        out.append(TuningItem(domain: .privacy, key: "adtracking", title: "개인화 광고 끄기", sub: "Apple이 내 데이터로 광고 조정 중지"))
        out.append(TuningItem(domain: .privacy, key: "analytics", title: "Mac 분석 공유 끄기", sub: "사용 통계를 Apple에 전송 중지"))
        out.append(TuningItem(domain: .privacy, key: "sirisuggest", title: "Siri 제안·개선 끄기", sub: "Siri/Dictation 개선 데이터 전송 중지"))
        out.append(TuningItem(domain: .privacy, key: "spotlightweb", title: "Spotlight 웹 검색 끄기", sub: "Spotlight에서 웹 제안 중지"))
        // 불편한 동작
        out.append(TuningItem(domain: .annoyances, key: "desktopwidgets", title: "바탕화면 위젯 끄기", sub: "바탕화면의 위젯 표시 끄기"))
        out.append(TuningItem(domain: .annoyances, key: "musicplaykey", title: "재생 키가 Music 열게 끄기", sub: "F8 재생 키로 Music 앱이 안 열리게"))
        // Finder
        out.append(TuningItem(domain: .finder, key: "hiddenfiles", title: "숨김 파일 표시", sub: "Finder에서 숨김 파일도 보여주기"))
        out.append(TuningItem(domain: .finder, key: "pathbar", title: "경로 막대 표시", sub: "Finder 창 아래에 현재 경로 표시"))
        out.append(TuningItem(domain: .finder, key: "statusbar", title: "상태 막대 표시", sub: "Finder 창 하단에 용량·개수 표시"))
        out.append(TuningItem(domain: .finder, key: "foldersfirst", title: "폴더를 항상 맨 위로", sub: "정렬 시 폴더가 파일보다 항상 앞에"))
        out.append(TuningItem(domain: .finder, key: "searchcurrent", title: "검색이 현재 폴더에서 시작", sub: "Finder 검색 기본을 현재 폴더로"))
        out.append(TuningItem(domain: .finder, key: "dsstorenet", title: "네트워크 드라이브 .DS_Store 금지", sub: "외부 디스크·SMB에 .DS_Store 생성 중지"))
        out.append(TuningItem(domain: .finder, key: "trash30d", title: "휴지통 30일 자동 삭제 끄기", sub: "macOS 기본 자동 삭제 중지"))
        out.append(TuningItem(domain: .finder, key: "savelocal", title: "새 문서 iCloud 아닌 내 Mac 저장", sub: "문서 저장 기본 위치를 로컬로"))
        // 입력 보정
        out.append(TuningItem(domain: .typing, key: "autocorrect", title: "자동 수정 끄기", sub: "입력 시 자동 치환 중지"))
        out.append(TuningItem(domain: .typing, key: "smartquotes", title: "스마트 따옴표·대시 끄기", sub: "quotes/dashes 자동 치환 중지"))
        out.append(TuningItem(domain: .typing, key: "period2space", title: "두 번 스페이스 → 온점 자동 치환 끄기", sub: "Space 두 번이 .이 되는 동작 중지"))
        out.append(TuningItem(domain: .typing, key: "autocaps", title: "문장 첫 글자 자동 대문자 끄기", sub: "영문 입력 시 자동 대문자 중지"))
        return out
    }

    // MARK: 조정 정의 (key → 실제 defaults 명령)

    struct Spec {
        let domain: String
        let key: String
        let onValue: String        // "튜닝 적용" 값
        let offValue: String?      // 원상복구 값 (nil이면 delete)
        let needsRestart: String?  // 적용 후 재시작할 프로세스 (Finder 등)
    }

    nonisolated static func spec(for item: TuningItem) -> Spec? {
        switch item.key {
        // Apple Intelligence — 공식 옵션: CloudSubscriptionFeatures 플래그로 전체 AI 오프
        case "aiOn":
            return Spec(domain: "com.apple.CloudSubscriptionFeatures.generativeModels", key: "generativeSystemIntelligenceEnabled", onValue: "0", offValue: "1", needsRestart: nil)
        case "writingtools":
            return Spec(domain: "com.apple.CloudSubscriptionFeatures.generativeModels", key: "writingToolsEnabled", onValue: "0", offValue: "1", needsRestart: nil)
        case "genmoji":
            return Spec(domain: "com.apple.CloudSubscriptionFeatures.generativeModels", key: "imagePlaygroundEnabled", onValue: "0", offValue: "1", needsRestart: nil)
        case "cleanup":
            return Spec(domain: "com.apple.CloudSubscriptionFeatures.generativeModels", key: "objectCleanupEnabled", onValue: "0", offValue: "1", needsRestart: nil)
        case "siriglow":
            return Spec(domain: "com.apple.CloudSubscriptionFeatures.generativeModels", key: "siriAnimationsEnabled", onValue: "0", offValue: "1", needsRestart: nil)
        case "adtracking":
            return Spec(domain: "com.apple.AdLib", key: "allowApplePersonalizedAdvertising", onValue: "0", offValue: "1", needsRestart: nil)

        case "analytics":
            return Spec(domain: "com.apple.settings.privacy.submitAnalytics", key: "", onValue: "false", offValue: nil, needsRestart: nil)
        case "sirisuggest":
            return Spec(domain: "com.apple.Siri", key: "SuggestionsEnabled", onValue: "0", offValue: "1", needsRestart: nil)
        case "spotlightweb":
            return Spec(domain: "com.apple.Spotlight", key: "allowWebSuggestions", onValue: "0", offValue: "1", needsRestart: nil)

        case "desktopwidgets":
            return Spec(domain: "com.apple.WindowManager", key: "AutoHide", onValue: "1", offValue: "0", needsRestart: nil)
        case "musicplaykey":
            return Spec(domain: "com.apple.mediakey", key: "RemoteMediaApplicationLaunch", onValue: "0", offValue: "1", needsRestart: nil)

        case "hiddenfiles":
            return Spec(domain: "com.apple.finder", key: "AppleShowAllFiles", onValue: "1", offValue: "0", needsRestart: "Finder")
        case "pathbar":
            return Spec(domain: "com.apple.finder", key: "ShowPathbar", onValue: "1", offValue: "0", needsRestart: "Finder")
        case "statusbar":
            return Spec(domain: "com.apple.finder", key: "ShowStatusBar", onValue: "1", offValue: "0", needsRestart: "Finder")
        case "foldersfirst":
            return Spec(domain: "com.apple.finder", key: "FXPreferredGroupBy", onValue: "FoldersFirst", offValue: "None", needsRestart: "Finder")
        case "searchcurrent":
            return Spec(domain: "com.apple.finder", key: "NSNavDefaultSearchLocation", onValue: "CFPreferencesSet", offValue: nil, needsRestart: "Finder")
        case "dsstorenet":
            return Spec(domain: "com.apple.desktopservices", key: "DSDontWriteNetworkStores", onValue: "1", offValue: "0", needsRestart: nil)
        case "trash30d":
            return Spec(domain: "com.apple.finder", key: "FXRemoveOldTrashInterval", onValue: "0", offValue: "30", needsRestart: "Finder")
        case "savelocal":
            return Spec(domain: "NSGlobalDomain", key: "NSDocumentSaveNewDocumentsToCloud", onValue: "0", offValue: "1", needsRestart: nil)

        case "autocorrect":
            return Spec(domain: "NSGlobalDomain", key: "NSAutomaticSpellingCorrectionEnabled", onValue: "0", offValue: "1", needsRestart: nil)
        case "smartquotes":
            return Spec(domain: "NSGlobalDomain", key: "NSAutomaticQuoteSubstitutionEnabled", onValue: "0", offValue: "1", needsRestart: nil)
        case "period2space":
            return Spec(domain: "NSGlobalDomain", key: "NSAutomaticPeriodSubstitutionEnabled", onValue: "0", offValue: "1", needsRestart: nil)
        case "autocaps":
            return Spec(domain: "NSGlobalDomain", key: "NSAutomaticCapitalizationEnabled", onValue: "0", offValue: "1", needsRestart: nil)
        default:
            return nil
        }
    }

    // MARK: 상태 조회

    nonisolated private static func queryState(_ item: TuningItem) -> Bool {
        let spec = Self.spec(for: item)
        guard let s = spec, !s.key.isEmpty else { return false }
        let out = shellRun("/usr/bin/defaults", "read", s.domain, s.key)
        let v = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return v == s.onValue
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let list = items
        Task.detached(priority: .utility) { [weak self] in
            var states: [String: Bool] = [:]
            for item in list {
                states[item.id] = Self.queryState(item)
            }
            let result = states
            await MainActor.run { [weak self] in
                self?.applied = result
                self?.isRefreshing = false
            }
        }
    }

    // MARK: 적용 / 해제

    func apply(_ item: TuningItem) {
        guard let s = Self.spec(for: item), !s.key.isEmpty else { return }
        let old = shellRun("/usr/bin/defaults", "read", s.domain, s.key)
        Self.recordJournal(domain: s.domain, key: s.key, old: old)
        shellRun("/usr/bin/defaults", "write", s.domain, s.key, s.onValue)
        if let proc = s.needsRestart {
            shellRun("/usr/bin/killall", proc)
        }
        // 'Apple Intelligence 끄기' 적용 = 즉시 캐시 정리 + 자동 삭제 트리거
        if item.key == "aiOn" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.clearAICaches()
                self?.triggerModelRemoval()
            }
        }
        refresh()
    }

    func undo(_ item: TuningItem) {
        guard let s = Self.spec(for: item), !s.key.isEmpty else { return }
        let recorded = Self.readJournal(domain: s.domain, key: s.key)
        if let recorded, !recorded.isEmpty {
            shellRun("/usr/bin/defaults", "write", s.domain, s.key, recorded)
        } else {
            shellRun("/usr/bin/defaults", "delete", s.domain, s.key)
        }
        if let proc = s.needsRestart {
            shellRun("/usr/bin/killall", proc)
        }
        refresh()
    }

    /// Apple Intelligence 모델 총 용량 (AssetsV2 하위)
    func measureAIModels() {
        Task.detached(priority: .utility) { [weak self] in
            let base = URL(fileURLWithPath: "/System/Library/AssetsV2/com_apple_MobileAsset_UAF_FM_GenerativeModels")
            guard FileManager.default.fileExists(atPath: base.path) else {
                await MainActor.run { self?.aiModelsSizeBytes = 0 }
                return
            }
            let size = FileManager.default.directorySize(at: base)
            await MainActor.run { [weak self] in self?.aiModelsSizeBytes = size }
        }
    }

    /// Apple Intelligence 로컬 모델 캐시/임시 데이터 삭제 (핵심 모델은 다운로드 시 바뀌므로 캐시만)
    /// 휴지통 강한 삭제(direct) 대신 임시 캐시 폴더 정리, SIP 영역은 건드리지 않음
    func clearAICaches() -> Int64 {
        let fm = FileManager.default
        var freed: Int64 = 0
        let targets = [
            "Library/Caches/com.apple.intelligenceflow.agent",
            "Library/Caches/com.apple.intelligenceflow.datastore",
            "Library/Caches/com.apple.intelligenceplatformd",
        ]
        let home = fm.homeDirectoryForCurrentUser
        for rel in targets {
            let url = home.appendingPathComponent(rel)
            guard fm.fileExists(atPath: url.path) else { continue }
            let size = FileManager.default.directorySize(at: url)
            try? fm.removeItem(at: url)   // AI 캐시는 재생성 가능
            freed += size
        }
        measureAIModels()
        return freed
    }

    /// 명시적 요청: AI가 끊김 상태에서 모델 다운로드를 다시 시도하지 않게
    /// macOS asset service에 모델 제거 알림 (실제 파일 정리는 OS가 백그라운드에서 함)
    private func triggerModelRemoval() {
        // Apple Intelligence 설정이 이미 0인 상태에서 asset 서비스의 등록정보를 재확인시킴
        // (RemoveMacAI는 여기서 closed local port로 다운로드를 봉쇄하지만,
        // 구성프로필 없이는 바로 재다운로드 방지는 APP도 못함. OS가 자기 스케줄로 지움)
        shellRun("/bin/launchctl", "kickstart", "-k", "system/com.apple.mobileassetd")
    }

    func applyDomain(_ domain: TuningDomain) {
        for item in items where item.domain == domain && applied[item.id] != true {
            apply(item)
        }
        // Apple Intelligence 도메인은 끄는 순간 연쇄 정리 (모델 캐시 회수 + OS 삭제 트리거)
        if domain == .ai {
            clearAICaches()
        }
    }

    func undoAll() {
        for item in items where applied[item.id] == true {
            undo(item)
        }
    }

    // MARK: journal (원복용)

    private struct Journal: Codable {
        var entries: [String: String] = [:]
    }

    private static func recordJournal(domain: String, key: String, old: String) {
        var j = loadJournal()
        j.entries["\(domain).\(key)"] = old
        saveJournal(j)
    }

    private static func readJournal(domain: String, key: String) -> String? {
        loadJournal().entries["\(domain).\(key)"]
    }

    private static func loadJournal() -> Journal {
        guard let data = try? Data(contentsOf: journalPath),
              let j = try? JSONDecoder().decode(Journal.self, from: data) else { return Journal() }
        return j
    }

    private static func saveJournal(_ j: Journal) {
        try? FileManager.default.createDirectory(at: journalPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(j) {
            try? data.write(to: journalPath, options: .atomic)
        }
    }
}

// MARK: - Shell helper (이 파일에서만 사용)

@discardableResult
func shellRun(_ command: String, _ args: String...) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: command)
    p.arguments = args
    let out = Pipe(); let err = Pipe()
    p.standardOutput = out; p.standardError = err
    do { try p.run() } catch { return "" }
    p.waitUntilExit()
    let data = out.fileHandleForReading.readDataToEndOfFile() + err.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}
