import Foundation

enum ProcessUsageCollector {
    static func collectAsync() async -> [pid_t: ProcessUsage] {
        await Task.detached(priority: .utility) {
            collect()
        }.value
    }

    static func collect() -> [pid_t: ProcessUsage] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "pid=,%cpu=,rss="]

        let output = Pipe()
        task.standardOutput = output
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return [:]
        }

        guard
            let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        else {
            return [:]
        }

        var map: [pid_t: ProcessUsage] = [:]

        for line in text.split(separator: "\n") {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 3 else { continue }

            guard
                let pid = Int32(parts[0]),
                let cpu = Double(parts[1]),
                let rssKB = Double(parts[2])
            else {
                continue
            }

            map[pid] = ProcessUsage(cpuPercent: cpu, residentBytes: rssKB * 1024.0)
        }

        return map
    }
}
