# MacCleaner 개발 규칙 (rule.md)

세션 간 유지되는 프로젝트 규칙입니다. 새 작업 시작 시 이 파일을 먼저 읽으세요.

## 1. 기술 스택 & 빌드

- **순수 SwiftUI** (macOS 14+ 대상, `platforms: [.macOS(.v14)]`) — 외부 의존성 금지, Apple 프레임워크만 사용.
- 빌드: `swift build` (dev) / `swift build -c release` (배포).
- 실행 파일: `~/Desktop/MacCleaner/.build/release/MacCleaner`
- `.app` 구성: `~/Applications/MacCleaner.app` (Info.plist + AppIcon.icns + codesign ad-hoc `codesign --force --sign -`)
- DMG: `hdiutil create -volname "MacCleaner" -srcfolder <staging> -ov -format UDZO ...` → `release/MacCleaner.dmg`

## 2. 아키텍처

- 상태 매니저: `@MainActor final class XxxManager: ObservableObject` — `@Published` 상태 + async 메서드.
- 무거운 파일/Disk 작업: `Task.detached(priority: .userInitiated)` 또는 `.utility` 백그라운드.
- 파일 1개 = 1 기능 (예: `CleanupManager.swift` + `CleanupView`는 `Views.swift`/파일 별도 뷰 파일).
- 스캐너가 있으면 반드시 `.task { ... }` 로 화면 진입 시 자동 스캔.

## 3. 코드 스타일 (필수 준수)

- 문자열 인라인 UI: `Text("한글")` — 사용자 대상 텍스트는 모두 한국어.
- `.foregroundStyle(.secondary)` 같은 SwiftUI 7 표준 사용, deprecated API 금지.
- 삭제 정책: **휴지통 이동이 원칙**. 영구 삭제는 휴지통 카테고리만, UI에 '영구 삭제' 배지든 경고 표시 필수.
- 정렬: `Table`은 `sortOrder` 바인딩 + `TableColumn(value:)` 키셋 사용 (User 가 클릭해야 정렬 바뀜).
- `fileContextMenu(path:)` 우클릭 — 모든 파일 목록에 적용.

## 4. UI 규칙

- 헤더바: `.background(.bar)` 공통.
- 카드: `CategorySection` 재사용 (배경 + 테두리 14px radius).
- 그래프: `DonutChart`, `Sparkline` (UIGraphs.swift 재사용, 새 그래프는 이 파일에 추가).
- 안전도 판정: `SafetyChecker.verdict(...)` 로 3단계 (safe/review/caution) 표기.
- 아이콘: SF Symbols만 사용. **이모지 금지** (홈페이지 HTML도 인라인 SVG 권장).

## 5. 설정 (AppSettings)

- UserDefaults 키 접두사 없이 그대로 (`notify*`, `fontScale`, `menuBar*`, `*ThresholdMB` 등).
- 추가 설정 시 `AppSettings`에 @Published + didSet 저장 + resetDefaults에 초기값 반영.
- 설정 UI는 **단일 Form 페이지** (탭/TabView 금지 — 사용자 요청 반영).
- 명칭: "메뉴바"가 아닌 **"위젯 (메뉴바)"** 으로 통일.

## 6. 권한

- `PermissionManager.checkAll()` 로 6개 기본 항목 접근성 확인.
- 전체 디스크 접근은 `openFullDiskSettings()` 로 시스템 설정 열기.
- 권한과 무관하게 앱은 크래시 없이 graceful fallback 해야 함.

## 7. 배포 (Funnel)

- 홈페이지: `~/Desktop/MacCleaner/downloads-site/index.html`
- 배포: `scp index.html honri@100.113.209.56:~/mac-cleaner/site/`
- DMG 배포: `scp release/MacCleaner.dmg *.sha256 honri@100.113.209.56:~/mac-cleaner/dl/`
- 스크린샷: `~/mac-cleaner/site/Screenshots/` 에 두어야 서버가 제공 (dl 아님!).
- URL: https://ubuntu.tail543772.ts.net/maccleaner
- 서버: `~/mac-cleaner/static-server.js` (포트 8446, funnel `/maccleaner`)
- 이모지 대신 인라인 SVG 아이콘 사용.

## 8. 빌드 검증 (배포 전 필수)

1. `swift build -c release` 오류 0
2. `codesign --verify` 통과
3. `open -n .app` 후 `pgrep -f MacCleaner.app` 성공
4. 탭별 스크린샷 캡처 (`screencapture -x`)
5. DMG 재생성 + sha256 갱신 + 서버 업로드

## 9. 금지 사항

- 인터넷 전송 기능 추가 금지 (Privacy: 모든 데이터 로컬 처리).
- sudo 필요한 명령은 osascript `with administrator privileges`로만.
- 휴지통 카테고리 영구 삭제는 UI에서 반드시 다시 한 번 확인.

## 10. 개인정보 보호 (스크린샷)
- screencapture 사용 금지 (전체 화면 캡처에는 사용자 유튜브 등 비공개 창 노출 위험).
- 창 전용 캡처 옵션(`screencapture -l<wid>` 또는 osascript로 앱 창)만 사용.
- 서버 업로드 전 반드시 캡처 내 개인정보 검토 후 업로드.
