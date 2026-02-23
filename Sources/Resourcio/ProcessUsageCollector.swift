import Foundation

enum ProcessUsageCollector {
    static func collectAsync(timeoutMs: UInt64 = 5000) async -> [pid_t: ProcessSample] {
        await Task.detached(priority: .utility) {
            collect(timeoutMs: timeoutMs)
        }.value
    }

    static func collect(timeoutMs: UInt64 = 5000) -> [pid_t: ProcessSample] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "pid=,ppid=,%cpu=,rss=,comm="]

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("resourcio-ps-\(UUID().uuidString).txt")

        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        guard let outputHandle = try? FileHandle(forWritingTo: tempURL) else { return [:] }
        task.standardOutput = outputHandle
        task.standardError = outputHandle

        do {
            try task.run()
        } catch {
            try? outputHandle.close()
            try? FileManager.default.removeItem(at: tempURL)
            return [:]
        }

        let timeoutSeconds = Double(timeoutMs) / 1000.0
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while task.isRunning && Date() < deadline {
            usleep(10_000) // 10ms polling to avoid blocking indefinitely.
        }

        if task.isRunning {
            task.terminate()
            usleep(50_000)
            if task.isRunning {
                task.interrupt()
            }
        }

        try? outputHandle.close()
        guard
            let data = try? Data(contentsOf: tempURL),
            let text = String(data: data, encoding: .utf8)
        else {
            try? FileManager.default.removeItem(at: tempURL)
            return [:]
        }
        try? FileManager.default.removeItem(at: tempURL)

        var map: [pid_t: ProcessSample] = [:]

        for line in text.split(separator: "\n") {
            let parts = line.split(maxSplits: 4, whereSeparator: \.isWhitespace)
            guard parts.count >= 5 else { continue }

            guard
                let pid = Int32(parts[0]),
                let ppid = Int32(parts[1]),
                let cpu = Double(parts[2]),
                let rssKB = Double(parts[3])
            else {
                continue
            }

            map[pid] = ProcessSample(
                pid: pid,
                ppid: ppid,
                cpuPercent: cpu,
                residentBytes: rssKB * 1024.0,
                command: String(parts[4])
            )
        }

        return map
    }
}
