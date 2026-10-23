import Foundation
import AppKit
import Combine

struct BrewPackage: Identifiable, Hashable {
    var id: String { "\(type.rawValue)_\(name)" }
    enum PkgType: String { case formula = "Formula (CLI)", cask = "Cask (앱)" }
    let type: PkgType
    let name: String
    let version: String
    var sizeBytes: Int64 = -1        // -1 = 계산 중
    var descriptionText: String = ""  // brew info 설명
    var isCalculating: Bool { sizeBytes < 0 }

    var sizeText: String {
        guard sizeBytes >= 0 else { return "…" }
        let gb = 1 << 30, mb = 1 << 20
        if sizeBytes >= Int64(gb) { return String(format: "%.1f GB", Double(sizeBytes) / Double(gb)) }
        if sizeBytes >= Int64(mb) { return String(format: "%.1f MB", Double(sizeBytes) / Double(mb)) }
        return String(format: "%.0f KB", Double(sizeBytes) / 1_048_576)
    }
}

@MainActor
final class BrewManager: ObservableObject {
    @Published private(set) var packages: [BrewPackage] = []
    @Published private(set) var isScanning = false
    @Published private(set) var scannedOnce = false
    @Published var brewAvailable = true

    /// 연동 여부 (설정 화면에서 끄면 흔적 청소만 진행)
    @Published var removalMode: RemovalMode = .brewUninstall

    enum RemovalMode: String, CaseIterable {
        case brewUninstall = "brew uninstall (완전 제거)"
        case trashOnly = "휴지통으로 이동만"
    }

    func scan() async {
        isScanning = true
        defer { isScanning = false }

        let brewPath = Self.brewExecutable()
        guard let brewPath else {
            brewAvailable = false
            packages = []
            return
        }
        brewAvailable = true

        func runBrew(_ args: [String]) async -> String {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: brewPath)
            proc.arguments = args
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()
            do { try proc.run() } catch { return "" }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        }

        // Formulas (이름·버전)
        let formulasOut = await runBrew(["list", "--formula", "--versions"])
        var found: [BrewPackage] = []
        for line in formulasOut.split(separator: "\n") {
            let parts = line.split(separator: " ").map(String.init)
            guard let name = parts.first else { continue }
            let ver = parts.count > 1 ? parts[1] : "—"
            let friendly = Self.friendlyDescription(for: name, type: .formula)
            found.append(BrewPackage(type: .formula, name: name, version: ver, descriptionText: friendly))
        }
        // Casks
        let casksOut = await runBrew(["list", "--cask", "--versions"])
        for line in casksOut.split(separator: "\n") {
            let parts = line.split(separator: " ").map(String.init)
            guard let name = parts.first else { continue }
            let ver = parts.count > 1 ? parts[1] : "—"
            let friendly = Self.friendlyDescription(for: name, type: .cask)
            found.append(BrewPackage(type: .cask, name: name, version: ver, descriptionText: friendly))
        }
        packages = found.sorted { $0.name < $1.name }
        scannedOnce = true

        // 백그라운드로 설명 + 용량 채워넣기 (brew info / 실측 du)
        let list = found
        await withTaskGroup(of: Void.self) { group in
            for pkg in list.prefix(80) {   // 성능상 상위 80개만 상세 조회
                group.addTask { [weak self] in
                    let info = await Self.runBrewInfo(brewPath, pkg)
                    guard let self else { return }
                    await MainActor.run {
                        guard let i = self.packages.firstIndex(where: { $0.id == pkg.id }) else { return }
                        self.packages[i].descriptionText = info.desc
                        self.packages[i].sizeBytes = info.size
                    }
                }
            }
        }
    }

    /// 알려진 패키지에 대한 한국어 이해하기 쉬운 설명
    nonisolated static func friendlyDescription(for name: String, type: BrewPackage.PkgType) -> String {
        let map: [String: String] = [
            "node": "Node.js — JavaScript 런타임",
            "python@3.12": "Python 3.12 — 파이썬 언어",
            "python@3.11": "Python 3.11 — 파이썬 언어",
            "git": "Git — 버전 관리 도구",
            "wget": "Wget — 파일 다운로더 (CLI)",
            "ffmpeg": "FFmpeg — 동영상·음성 변환",
            "curl": "Curl — HTTP 통신 도구",
            "htop": "Htop — 터미널 모니터",
            "jq": "JQ — JSON 처리 도구",
            "openssl": "OpenSSL — 암호화 라이브러리",
            "sqlite": "SQLite — 경량 데이터베이스",
            "gh": "GitHub CLI — GitHub 커맨드 도구",
            "go": "Go — 프로그래밍 언어",
            "rust": "Rust — 프로그래밍 언어",
            "docker": "Docker — 컨테이너 도구",
            "postgresql": "PostgreSQL — 데이터베이스",
            "mysql": "MySQL — 데이터베이스",
            "redis": "Redis — 인메모리 DB",
            "tailscale": "Tailscale — VPN 네트워크",
            "rsync": "Rsync — 파일 동기화",
            "cmake": "CMake — C++ 빌드 도구",
            "llvm": "LLVM — 컴파일러",
            "xz": "XZ — 압축 도구",
            "zlib": "Zlib — 압축 라이브러리",
        ]
        let caskMap: [String: String] = [
            "visual-studio-code": "VS Code — 코드 에디터",
            "google-chrome": "Chrome — 웹 브라우저",
            "brave-browser": "Brave — 웹 브라우저",
            "firefox": "Firefox — 웹 브라우저",
            "discord": "Discord — 채팅 앱",
            "slack": "Slack — 채팅 툴",
            "spotify": "Spotify — 음악 스트리밍",
            "zoom": "Zoom — 화상 회의",
            "notion": "Notion — 노트 툴",
            "obsidian": "Obsidian — 로컬 노트",
            "raycast": "Raycast — 런처 앱",
            "rectangle": "Rectangle — 창 정렬",
            "iterm2": "iTerm2 — 터미널 대체",
            "the-unarchiver": "The Unarchiver — 압축 해제",
            "wireshark": "Wireshark — 네트워크 분석",
            "postman": "Postman — API 테스트",
            "vlc": "VLC — 미디어 플레이어",
            "figma": "Figma — 디자인 툴",
        ]
        if type == .cask, let kd = caskMap[name] { return kd }
        return map[name] ?? ""
    }

    nonisolated private static func runBrewInfo(_ brewPath: String, _ pkg: BrewPackage) async -> (desc: String, size: Int64) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: brewPath)
        proc.arguments = ["info", pkg.type == .cask ? "--cask" : "--formula", pkg.name]
        let pipe = Pipe(); proc.standardOutput = pipe; proc.standardError = Pipe()
        do { try proc.run() } catch { return ("", -1) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        // 첫 줄: == Info ==; 다음줄에 이름: 설명
        var desc = ""
        for line in text.split(separator: "\n").map(String.init) {
            if line.hasPrefix("") && line.contains(": ") {
                let parts = line.split(separator: ": ", maxSplits: 1).map(String.init)
                if parts.count == 2, parts[0].contains(pkg.name) || parts[0] == pkg.name {
                    desc = parts[1]; break
                }
            }
        }
        // 용량: celler 경로 실측 또는 cask app
        var sizeBytes: Int64 = -1
        if pkg.type == .cask {
            let appPath = "/Applications/\(pkg.name).app"
            if FileManager.default.fileExists(atPath: appPath) {
                sizeBytes = await Task.detached(priority: .utility) {
                    FileManager.default.directorySize(at: URL(fileURLWithPath: appPath))
                }.value
            }
        } else {
            for root in ["/opt/homebrew/Cellar", "/usr/local/Cellar"] {
                let cellar = URL(fileURLWithPath: root).appendingPathComponent(pkg.name)
                if FileManager.default.fileExists(atPath: cellar.path) {
                    sizeBytes = await Task.detached(priority: .utility) {
                        FileManager.default.directorySize(at: cellar)
                    }.value
                    break
                }
            }
        }
        return (desc, sizeBytes)
    }

    nonisolated static func brewExecutable() -> String? {
        for p in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] {
            if FileManager.default.fileExists(atPath: p) { return p }
        }
        return nil
    }

    @discardableResult
    func remove(_ pkg: BrewPackage) async -> Bool {
        let brew = Self.brewExecutable()
        if removalMode == .brewUninstall, let brew = brew {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: brew)
            proc.arguments = ["uninstall", pkg.type == .cask ? "--cask" : "--formula", pkg.name]
            proc.standardOutput = Pipe(); proc.standardError = Pipe()
            try? proc.run()
            proc.waitUntilExit()
            packages.removeAll { $0.id == pkg.id }
            return proc.terminationStatus == 0
        }
        // 휴지통 모드: 캐스크는 /Applications, formula는 /opt/homebrew/Cellar
        let target: URL
        if pkg.type == .cask {
            target = URL(fileURLWithPath: "/Applications").appendingPathComponent(pkg.name + ".app")
        } else {
            target = URL(fileURLWithPath: "/opt/homebrew/Cellar").appendingPathComponent(pkg.name)
        }
        if FileManager.default.fileExists(atPath: target.path) {
            try? FileManager.default.trashItem(at: target, resultingItemURL: nil)
        }
        packages.removeAll { $0.id == pkg.id }
        return true
    }

    /// brew 정리 (brew cleanup): 캐시·구버전 제거
    @discardableResult
    func cleanupBrewCache() async -> String? {
        guard let brew = Self.brewExecutable() else { return nil }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: brew)
        proc.arguments = ["cleanup", "--prune=all"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        try? proc.run()
        proc.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return out
    }
}
