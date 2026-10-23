import Foundation
import Combine

struct PkgReceipt: Identifiable, Hashable {
    var id: String { pkgID }
    let pkgID: String          // e.g. com.company.App.pkg
    let version: String
    let installLocation: String
    let appName: String        // pkgID에서 파싱한 보기 좋은 이름
    var sizeBytes: Int64 = -1
    var isApple: Bool { pkgID.hasPrefix("com.apple") }
}

@MainActor
final class PkgReceiptManager: ObservableObject {
    @Published private(set) var receipts: [PkgReceipt] = []
    @Published private(set) var isScanning = false
    @Published private(set) var scannedOnce = false

    private(set) var lastError: String?

    func scan() async {
        isScanning = true
        defer { isScanning = false }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/pkgutil")
        proc.arguments = ["--pkgs"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do { try proc.run() } catch {
            lastError = "pkgutil 실행 실패"
            return
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        // Apple 자체 시스템 항목은 스킵 (사용자가 지우지 않는 것)
        var list: [PkgReceipt] = []
        for line in text.split(separator: "\n").map(String.init) where !line.isEmpty {
            guard !line.hasPrefix("com.apple.") else { continue }
            guard !line.contains("files.") else { continue }
            let info = Self.queryInfo(line)
            // 사람이 읽기 쉬운 이름: pkgID에서 회사 도메인 세그먼트 제거 후 남은 세그먼트 연결
            // 예: com.jetbrains.PyCharm → PyCharm  /  io.github.owner.App-Name → App-Name
            let parts = line.split(separator: ".").map(String.init)
            var segs = parts
            if line.hasPrefix("com.") || line.hasPrefix("org.") || line.hasPrefix("net.") || line.hasPrefix("io.") {
                segs = Array(parts.dropFirst(2))   // 도메인(2세그먼트) 제거
            }
            // 버전 접미사 (이미 version 필드 있으므로) 및 일반 접미사 제거
            let pretty = segs
                .joined(separator: " ")
                .replacingOccurrences(of: "-" , with: " ")
            list.append(PkgReceipt(pkgID: line,
                                   version: info.version,
                                   installLocation: info.location,
                                   appName: pretty.isEmpty ? line : pretty))
        }
        receipts = list.sorted { $0.appName < $1.appName }
        scannedOnce = true

        // 백그라운드로 용량 계산
        await withTaskGroup(of: Void.self) { group in
            for r in list {
                group.addTask { [weak self] in
                    let size = await Task.detached(priority: .utility) {
                        Self.volumeOf(installLocation: r.installLocation, pkgID: r.pkgID)
                    }.value
                    guard let self else { return }
                    await MainActor.run {
                        guard let i = self.receipts.firstIndex(where: { $0.id == r.id }) else { return }
                        self.receipts[i].sizeBytes = size
                    }
                }
            }
        }
    }

    private static func queryInfo(_ pkgID: String) -> (version: String, location: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/pkgutil")
        proc.arguments = ["--pkg-info", pkgID]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do { try proc.run() } catch { return ("—", "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        var ver = "—", loc = ""
        for line in text.split(separator: "\n").map(String.init) {
            if line.hasPrefix("version: ") { ver = String(line.dropFirst("version: ".count)) }
            if line.hasPrefix("location: ") { loc = String(line.dropFirst("location: ".count)) }
        }
        return (ver, loc)
    }

    /// pkg receipt의 installLocation 기준 용량 산정 (존재 추정)
    nonisolated private static func volumeOf(installLocation: String, pkgID: String) -> Int64 {
        let fm = FileManager.default
        // 관례: / 나 /Applications. location이 "/"면 pkg가 시스템 전역 설치 → 정확한 파일 목록이 필요
        guard !installLocation.isEmpty else { return -1 }
        let base = installLocation == "/" ? "/" : installLocation
        if base == "/" {
            // files list로 합산
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/sbin/pkgutil")
            proc.arguments = ["--files", pkgID]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()
            do { try proc.run() } catch { return -1 }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            let text = String(data: data, encoding: .utf8) ?? ""
            let files = text.split(separator: "\n").prefix(3000)
            var total: Int64 = 0
            for f in files {
                let url = URL(fileURLWithPath: "/" + f)
                if let vals = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                   vals.isRegularFile == true {
                    total += Int64(vals.fileSize ?? 0)
                }
            }
            return total
        }
        return fm.directorySize(at: URL(fileURLWithPath: base))
    }

    /// pkg receipt로 실제 설치 기록 삭제 (sudo 필요 → osascript)
    func forget(_ receipt: PkgReceipt) async -> Bool {
        let script = "do shell script \"/usr/sbin/pkgutil --forget \(receipt.pkgID)\" with administrator privileges"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        p.standardOutput = Pipe(); p.standardError = Pipe()
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        if p.terminationStatus == 0 {
            receipts.removeAll { $0.id == receipt.id }
            return true
        }
        return false
    }
}
