# MacCleaner

macOS 저장공간 청소와 관리를 돕는 네이티브 앱입니다 (SwiftUI, 외부 의존성 0개).

## 다운로드 / 웹
- 웹: https://ubuntu.tail543772.ts.net/MacCleaner
- 릴리스: https://github.com/Honri314/MacCleaner/releases (macOS DMG)

## 화면 구성 (9개 탭)

| 탭 | 내용 |
|---|---|
| 대시보드 | 저장공간 요약, "시스템 데이터" 분해 위젯, 실시간 모니터링 도넛/미니 통계 |
| 정리 | 카테고리별 청소 항목 스캔/선택/실행 |
| 대용량 파일 | 임계값 이상 파일 스캔, 정렬/선택 삭제 |
| 잔여 파일 | 삭제된 앱의 찌꺼기(위험도 등급 포함) 검색·삭제 |
| 중복 파일 | 해시 기반 중복 탐지, 그룹별 보존 1개 선택 후 삭제 |
| 앱 관리 | 설치 앱/볼륨 분석 + Homebrew·언어 패키지 매니저 통합 |
| 실행 항목 | LaunchItems/LaunchAgents 점검 |
| 튜닝 | `defaults` 기반 시스템 설정 토글 |
| 설정 | 스캔 제외 경로, 크기 임계값 등 사용자 옵션 |

## 주요 기능 상세

### 정리 (CleanupManager)
- 청소 대상 카테고리(캐시, 로그, 휴지통, Xcode DerivedData, 브라우저 캐시, 컨테이너 캐시 등)를 스캔해 크기를 계산하고 사용자가 선택한 항목만 삭제합니다.
- 스냅샷 기반으로 선택 상태를 유지하며, 삭제 진행 중에도 카테고리별 진행 상황이 갱신됩니다.

### "시스템 데이터" 해석 (StorageBreakdown)
- macOS 설정 앱이 "시스템 데이터"로만 표시하는 공간을 실제 원인(특정 디렉터리들의 크기)으로 분해해 보여줍니다. 대시보드 위젯은 도넛 차트(UIGraphs)로 구성비를 표시합니다.

### 잔여 파일 (OrphanFinder)
- 설치된 .app 목록과 파일 경로를 대조해 "삭제된 앱이 남긴 파일"을 찾습니다.
- 각 파일은 위험도(Risk)를 계산해 표시하므로, 시스템 관련 찌꺼기를 무분별하게 지우는 사고를 방지합니다.

### 중복 파일 (DuplicateFinder)
- 크기별 1차 걸러내기 후 내용 해시를 비교해 중복을 확정합니다(정확한 탐지).
- 그룹당 1개 보존을 기본 전략으로 제안합니다.

### 앱 관리 (AppManager / BrewManager / LanguagePackageManager / PkgReceiptManager)
- 설치된 앱과 해당 .app 볼륨 크기 분석
- Homebrew Formula(CLI)/Cask(앱) 목록 조회 및 제거 — 앱 관리 탭 안에 인라인 리스트로 동작
- 언어/러너 패키지 매니저: pip · npm · cargo · gem · go 등 전역/사용자 패키지 나열 및 제거
- .pkg 설치 수령서(receipt) 조회/제거

### 시스템 튜닝 (SystemTuningManager)
- `defaults write/read` 기반 안전 토글만 사용 — 시스템 파일·SIP 영역은 전혀 건드리지 않습니다.
- 변경 전 기존 값을 저널에 기록해 원복(undo)이 가능합니다.
- 도메인별 항목(파인더, 독, 입력 등) UI는 TuningView에서 체크 토글로 선택합니다.

### 실시간 시스템 모니터 (SystemMonitor)
- 프로세스별 CPU/메모리(ProcessStat)와 메모리 스냅샷을 주기적으로 수집해 대시보드에 표시합니다.

## 코드 구조

```
Sources/MacCleaner/
  MacCleanerApp.swift       @main, 9개 탭 라우팅
  Views.swift               공통 UI 컴포넌트, 대시보드/정리 메인 화면
  FileListCommon.swift      목록 정렬 키/순서 공통 로직
  UIGraphs.swift            도넛/미니 차트 (고정 크기 렌더)
  CleanManager 쪽
    CleanupManager.swift    카테고리 스캔/선택/삭제 엔진
    SmartScan.swift         한 번에 여러 대상을 훑는 "스마트 스" 요약
    LargeFileScanner.swift  대용량 파일 스
    OrphanFinder.swift / OrphansView.swift        잔여 파일 탐색/UI
    DuplicateFinder.swift / DuplicatesView.swift  중복 탐사/UI
  앱/패키지 쪽
    AppManager.swift        설치 앱·볼륨 분석
    AppSettings.swift       전역 설정 (UserDefaults)
    BrewManager.swift / BrewView.swift / InlineBrewPkg.swift   Homebrew
    LanguagePackageManager(.swift/View)  pip/npm/cargo/gem/go
    PkgReceiptManager.swift / PkgView.swift   .pkg receipt
  저장소 분석
    StorageBreakdown.swift / StorageBreakdownSection.swift  "시스템 데이터" 분석
    SystemMonitor.swift     실시간 프로세스/메모리
  튜닝
    SystemTuningManager.swift / TuningView.swift  defaults 기반 토글 + 저널 원복
  Utilities.swift           바이트 포맷, 디렉터리 크기 계산 등 공용 헬퍼
```

## 빌드

```
swift build
swift run
swift build -c release
```
외부 의존성 없음 (SwiftPM 단일 타깃). `make_icon.py`는 앱 아이콘 생성 보조 스크립트입니다.

## 안전 설계 원칙
- 삭제는 항상 사용자가 명시적으로 선택한 항목에만 수행됩니다.
- 잔여 파일은 위험도 등급을, 튜닝은 저널 기록 원복을 기본 동작으로 둡니다.
- 캐시 삭제 등 시스템 변경은 표준 경로(App container/~/Library/Caches 등)로 한정됩니다.
