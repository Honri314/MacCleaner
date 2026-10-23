import Foundation
import SwiftUI

// MARK: - "시스템 데이터" 해석기 (macOS가 '시스템 데이터'로 뭉뚱그리는 실제 원인 분해)

struct StorageCategory: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let sub: String
    let sizeBytes: Int64
    let safeToClean: Bool
    let why: String
}

@MainActor
final class StorageBreakdownManager: ObservableObject {
    @Published private(set) var categories: [StorageCategory] = []
    @Published private(set) var isScanning = false
    @Published private(set) var scannedOnce = false
    @Published private(set) var libraryTotal: Int64 = 0

    /// 스캔: ~/Library 관련 하위 항목을 계산하여 원인분해
    func scan() async {
        isScanning = true
        defer { isScanning = false }

        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        // 병렬검사 대상: macOS가 시스템 데이터로 맵핑하는 실제 대상들
        let targets: [(key: String, rel: String, sub: String, safe: Bool, why: String)] = [
            ("게임·에뮬레이터 컨테이너", "Library/Containers", "게임세이브·iOS앱 데이터·PlayCover·Whisky 등 여기에 모임", true,
             "제거한 게임·iOS 앱의 데이터가 여기 그대로 남을 수 있음. 앱을 지웠다면 잔여파일에서 정리 가능"),
            ("Google·Discord·게임 지원", "Library/Application Support", "브라우저(Google), Discord 답변캐시, 마인크래프트, IDE 등", true,
             "캐시 정리하면 회수 가능. 단, Discord·Chrome 캐시는 앱이 다시 다운로드합니다"),
            ("iOS 기기 서비스", "Library/Containers/com.apple.configurator.xpc.DeviceService", "iPhone/iPad 연결한 각종 백업·설치데이터", true,
             "iPhone을 연결하면 macOS가 여기에 기기 관련 임시파일을 쌓음. 정리해도 안전"),
            ("CloudKit 캐시", "Library/Caches/CloudKit", "iCloud 동기화 임시 데이터", true,
             "iCloud 동기화 후 재생성됨 — 안전하게 정리 가능"),
            ("메타데이터·인덱스", "Library/Metadata", "Spotlight·시스템 메타데이터", false,
             "시스템이 자동 유지관리 — 정리하면 검색이 느려짐. 건드리지 않는 것 추천"),
            ("Group Container", "Library/Group Containers", "모든 앱이 공동 사용하는 경로", false,
             "잘못 건드리면 여러 앱이 동시에 손상. 가능하면 놔두는 것 추천"),
            ("바이오메트리·시스템 인텔리전스", "Library/Biome", "위치·시간·사용패턴 학습 데이터", false,
             "시스템 데이터로 표시되지만 개인설정 — 지우면 히스토리 리셋"),
        ]

        let base = home
        var out: [StorageCategory] = []
        for t in targets {
            let url = base.appendingPathComponent(t.rel)
            guard fm.fileExists(atPath: url.path) else { continue }
            let size = await Task.detached(priority: .utility) {
                fm.directorySize(at: url)
            }.value
            out.append(StorageCategory(name: t.key, sub: t.sub, sizeBytes: size,
                                       safeToClean: t.safe, why: t.why))
        }
        out.sort { $0.sizeBytes > $1.sizeBytes }
        categories = out

        // 전체 ~/Library 총합
        let lib = home.appendingPathComponent("Library")
        if fm.fileExists(atPath: lib.path) {
            libraryTotal = await Task.detached(priority: .utility) {
                fm.directorySize(at: lib)
            }.value
        }
        scannedOnce = true
        _ = home
    }
}
