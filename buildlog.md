# MacCleaner 빌드 로그 (buildlog.md)

## 세션 1 — 2026-10-11

### 프로젝트 시작
- **목표**: CleanMyMac 스타일 맥 저장공간·리소스 관리 네이티브 앱 (SwiftUI).
- 사용자 기술 스택 선택: **SwiftUI 네이티브** (macOS 14+).
- 핵심 기능 선택: 저장공간 정리 / 리소스 모니터 / 대용량 파일 / 앱 관리.

### 초기 빌드 실패
1. **CLT 한계**: Xcode 미설치 시 SwiftUI macro plugin 없음 → 'State() macro not found' 오류.
   - 해결: 사용자가 Xcode.app 제공 → `/Volumes/hub/Applications/Xcode.app` (27A266a).
   - `osascript with administrator privileges`로 `xcode-select -s` + `xcodebuild -license accept`.
2. **SDK 27.0 macOS 13 타겟** 에러: `platforms` `.v14`로 상향.
3. **Mach API**: `host_cpu_load_info.cpu_ticks`는 tuple subscript 불가 → `.0 `.1  `.2  `.3 인덱스 접근.
4. **Int32 count**: `proc_listallpids` 리턴 Int32 → `[pid_t](count: Int(count)+16)` 변환.

### 이슈 + 해결
- macOS의 "write_file tool 쓰면 디스크에 안 남는" 가상 경로 문제 2회 발생 (Package.swift, 소스들).
  - 해법: bash heredoc 또는 Python 스크립트로 직접 파일 작성.
- **Docker.raw 228GB**: 이전 Docker Desktop 설치 잔여. `rm` + 타임머신 스냅샷 정리로 **16GB → 41GB** 회수.
- **Funnel 잔재**: 맥의 s-macbook-air 퍼널 502 → `tailscale funnel reset`으로 제거 (리눅스 ubuntu로 이전 완료 상태).

### 기능 추가 히스토리 (사용자 요청 순서)
1. UI 개선 (카드 통일, 확인 다이얼로그, ⌘R 단축키, 잔여 배지)
2. **잔여 파일 탭** (OrphanFinder) — 번들ID 매칭 기반 고아 파일 판정
3. **중복 파일 탭** (DuplicateFinder) — SHA-256 2단계 해시
4. **정렬 컨트롤** (SortControl: 이름/크기/수정일, 오름·내림)
5. **우클릭 메뉴** (`fileContextMenu`) — 파인더 열기/파일 열기/경로 복사
6. **Docker.raw 228GB 진단** — `os.stat().st_blocks` 기반 희소 파일 분석
7. **설정** (AppSettings) — 단일 Form 페이지 (탭 → 단일로 후속 변경)
   - 화면 표시 / 알림 / **위젯 (메뉴바)** / 스캔 임계값 / 정리 안전 / 폴더 접근 권한 / 기타
8. **스마트 스캔** (SmartScanManager) — 통합 헬스체크 후 도넛 요약
9. **메뉴바 위젯** (MenuBarManager) — CPU/MEM/DISK on/off
10. **앱 아이콘**: Python PIL 스크립트 (`make_icon.py`) → `icns` → `CFBundleIconFile` 등록
11. **Release 빌드 + DMG** — `~/Desktop/MacCleaner/release/MacCleaner.dmg` (1.2MB)
12. **다운로드 홈페이지** — `downloads-site/index.html` → 리눅스 우분투 서버 (funnel `/maccleaner`)
13. **Brew 관리 탭** (`BrewManager`) — list/cask/uninstall + `brew cleanup` + 용량·설명 표기
14. **앱 목록 확장** — `.pkg`, `.dmg` 인스톨러 + 외장 볼륨 Applications 스캔 (AppVolume)
15. **앱 관리 정렬 이슈** — `Table(filtered, selection:, sortOrder:)` + `TableColumn(value:)`

### 알려진 이슈 (Open)
- [ ] 앱 관리 화면에서 사이드바 밀림 (HSplitView) 시도 중
- [ ] 홈페이지 이모지 → 인라인 SVG 아이콘 교체
- [ ] Brew 설명이 영어로 나올 수 있음 (brew info의 원문 그대로)

### 배포 아티팩트
- 앱: `~/Applications/MacCleaner.app` (v1.1, release)
- DMG: `release/MacCleaner.dmg` + `.sha256`
- 홈페이지: https://ubuntu.tail543772.ts.net/maccleaner
- 서버: 리눅스 우분투 (honri@100.113.209.56), static-server.js:8446, funnel `/maccleaner`

### 아키텍처 원칙 확정 (규칙은 rule.md 참조)
- 휴지통 우선 영구 삭제는 휴지통 카테고리만
- 이모지 금지 (SF Symbols, 인라인 SVG)
- 설정 단일 페이지, "위젯 (메뉴바)" 명칭
- Table 정렬은 `TableColumn(value:)` 키 표준
