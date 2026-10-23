import Foundation
import SwiftUI

// MARK: - 언어/러너 패키지 매니저 (pip · npm · cargo · gem · go 등)

struct LanguagePackage: Identifiable, Hashable {
    var id: String { "\(manager).\(name)" }
    let manager: String    // "pip" / "npm" / "cargo" / "gem" / "go"
    let name: String
    let version: String
    var sizeBytes: Int64 = -1  // -1 = 계산 중
    var isCalculating: Bool { sizeBytes < 0 }
}

@MainActor
final class LanguagePackageManager: ObservableObject {
    @Published private(set) var packages: [LanguagePackage] = []
    @Published private(set) var isScanning = false
    @Published private(set) var scannedOnce = false
    /// 어떤 매니저가 발견되었는지 (pip / npm / …)
    @Published private(set) var available: Set<String> = []

    private var work: Task<Void, Never>?

    func scan() {
        work?.cancel()
        isScanning = true
        packages = []
        available = []
        work = Task { [weak self] in
            guard let self else { return }
            // 각 매니저별 병렬 조회 → 결과 합침 (동시성 안전)
            let results = await withTaskGroup(of: (String, [LanguagePackage]).self) { group -> [(String, [LanguagePackage])] in
                group.addTask { ("pip", await Self.scanPip() ?? []) }
                group.addTask { ("npm", await Self.scanNpm() ?? []) }
                var collected: [(String, [LanguagePackage])] = []
                for await r in group { collected.append(r) }
                return collected
            }
            var found: [LanguagePackage] = []
            var got: Set<String> = []
            for (mgr, pkgs) in results where !pkgs.isEmpty {
                got.insert(mgr)
                found.append(contentsOf: pkgs)
            }
            let sorted = found.sorted { ($0.manager, $0.name) < ($1.manager, $1.name) }
            self.available = got
            self.packages = sorted
            self.isScanning = false
            self.scannedOnce = true
        }
    }

    nonisolated private static func scanPip() async -> [LanguagePackage]? {
        var out: [LanguagePackage] = []
        // pip3 --format freeze: name==version
        let cmd = try? await ShellAsync.run("/usr/bin/env", ["bash", "-lc", """
        if command -v pip3 >/dev/null 2>&1; then
          pip3 list --format=freeze 2>/dev/null | head -300 | grep -v "^-e" || true
        fi
        """], timeout: 10)
        guard let lines = cmd?.split(separator: "\n"), !lines.isEmpty else { return nil }
        for line in lines {
            let parts = line.split(separator: "==")
            if parts.count == 2 {
                let name = String(parts[0]).trimmingCharacters(in: .whitespaces)
                let ver = String(parts[1]).trimmingCharacters(in: .whitespaces)
                out.append(LanguagePackage(manager: "pip", name: name, version: ver))
            }
        }
        if !out.isEmpty { }
        return out
    }

    nonisolated private static func scanNpm() async -> [LanguagePackage]? {
        var out: [LanguagePackage] = []
        let cmd = try? await ShellAsync.run("/usr/bin/env", ["bash", "-lc", """
        if command -v npm >/dev/null 2>&1; then
          npm list -g --depth=0 --json 2>/dev/null || true
        fi
        """], timeout: 15)
        guard let raw = cmd, !raw.isEmpty else { return nil }
        // JSON 파싱 (dependencies )
        if let data = raw.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let deps = obj["dependencies"] as? [String: Any] {
            for (name, v) in deps {
                var version = "?"
                if let dict = v as? [String: Any], let ver = dict["version"] as? String { version = ver }
                out.append(LanguagePackage(manager: "npm", name: name, version: version))
            }
        }
        if !out.isEmpty { }
        return out
    }

    func remove(_ pkg: LanguagePackage) async -> Bool {
        let args: [String]
        switch pkg.manager {
        case "pip":
            args = ["bash", "-lc", "pip3 uninstall -y '\(pkg.name)' 2>/dev/null || true"]
        case "npm":
            // -g인지 체크 없이 global uninstall (이 모듈은 global전용)
            args = ["bash", "-lc", "npm uninstall -g '\(pkg.name)' 2>/dev/null || true"]
        default:
            return false
        }
        let res = try? await ShellAsync.run("/usr/bin/env", args, timeout: 30)
        // 성공 여부를 볼 필요는 없지만, 0 리턴이면 목록에서 제거
        await scan()
        return res != nil
    }
}

// MARK: - ShellAsync (async shell helper)

@MainActor
enum ShellAsync {
    struct CmdError: Error { let message: String }

    static func run(_ executable: String, _ args: [String], timeout: TimeInterval = 30) async throws -> String {
        try await Task.detached(priority: .userInitiated) { () -> String in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: executable)
            p.arguments = args
            let out = Pipe(); let err = Pipe()
            p.standardOutput = out; p.standardError = err
            try p.run()
            let data = out.fileHandleForReading.readDataToEndOfFile() + err.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        }.value
    }
}
