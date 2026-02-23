import AppKit
import Foundation

enum ImpactHeuristics {
    static func normalizedCPU(_ cpuPercent: Double) -> Double {
        let maxCPU = Double(ProcessInfo.processInfo.processorCount) * 100.0
        guard maxCPU > 0 else { return 0 }
        return min((cpuPercent / maxCPU) * 100.0, 100.0)
    }

    static func memoryScore(residentBytes: Double, totalMemoryBytes: Double) -> Double {
        guard totalMemoryBytes > 0 else { return 0 }
        let rawPercent = memoryPercent(residentBytes: residentBytes, totalMemoryBytes: totalMemoryBytes)
        return min(rawPercent * ImpactTuning.memoryScaleMultiplier, 100.0)
    }

    static func memoryPercent(residentBytes: Double, totalMemoryBytes: Double) -> Double {
        guard totalMemoryBytes > 0 else { return 0 }
        return min((residentBytes / totalMemoryBytes) * 100.0, 100.0)
    }

    static func memoryGrowthRatio(memoryHistory: [Double], window: Int) -> Double {
        guard memoryHistory.count >= window else { return 0 }
        let recent = Array(memoryHistory.suffix(window))
        guard let first = recent.first, let last = recent.last, first > 0 else { return 0 }
        return max(0, (last - first) / first)
    }

    static func memoryGrowthScore(memoryHistory: [Double], window: Int) -> Double {
        let growth = memoryGrowthRatio(memoryHistory: memoryHistory, window: window)
        return min(growth * 250.0, 100.0)
    }

    static func sustainedCPUScore(cpuHistory: [Double], window: Int) -> Double {
        guard cpuHistory.count >= window else { return normalizedCPU(cpuHistory.last ?? 0) }
        let recent = Array(cpuHistory.suffix(window))
        let normalized = recent.map(normalizedCPU)
        return normalized.reduce(0, +) / Double(normalized.count)
    }

    static func isSustainedCPUSpike(cpuHistory: [Double]) -> Bool {
        guard cpuHistory.count >= ImpactTuning.sustainedSpikeWindow else { return false }
        let recent = Array(cpuHistory.suffix(ImpactTuning.sustainedSpikeWindow))
        let normalized = recent.map(normalizedCPU)
        let avg = normalized.reduce(0, +) / Double(normalized.count)
        let peak = normalized.max() ?? 0
        return avg >= ImpactTuning.sustainedSpikeAvgThreshold && peak >= ImpactTuning.sustainedSpikePeakThreshold
    }

    static func isTabLikeMemoryPressure(
        cpuHistory: [Double],
        memoryHistory: [Double],
        totalMemoryBytes: Double
    ) -> Bool {
        guard let latestCPU = cpuHistory.last, let latestMemory = memoryHistory.last else { return false }
        let memImpact = memoryScore(residentBytes: latestMemory, totalMemoryBytes: totalMemoryBytes)
        let cpu = normalizedCPU(latestCPU)
        let growth = memoryGrowthRatio(memoryHistory: memoryHistory, window: ImpactTuning.tabPressureWindow)
        return memImpact >= ImpactTuning.tabPressureMemoryThreshold &&
            cpu <= ImpactTuning.tabPressureCpuCeiling &&
            growth >= ImpactTuning.tabPressureGrowthThreshold
    }
}

enum ImpactScorer {
    static func totalScore(
        cpuNow: Double,
        cpuSustained: Double,
        memoryPressure: Double,
        memoryGrowth: Double,
        isFrontmost: Bool,
        hasSustainedSpike: Bool,
        hasTabPressure: Bool
    ) -> Double {
        let foregroundSignal = isFrontmost ? max(cpuNow, memoryPressure * 0.70) : 0.0
        let spikePenalty = hasSustainedSpike ? ImpactTuning.sustainedSpikePenalty : 0.0
        let tabPenalty = hasTabPressure ? ImpactTuning.tabPressurePenalty : 0.0

        return min(
            100.0,
            (cpuNow * ImpactTuning.cpuNowWeight) +
                (cpuSustained * ImpactTuning.cpuSustainedWeight) +
                (memoryPressure * ImpactTuning.memoryPressureWeight) +
                (memoryGrowth * ImpactTuning.memoryGrowthWeight) +
                (foregroundSignal * ImpactTuning.foregroundResponsivenessWeight) +
                spikePenalty + tabPenalty
        )
    }
}

enum WorkloadClassifier {
    static func classify(
        appName: String,
        isFrontmost: Bool,
        cpuHistory: [Double],
        memoryHistory: [Double],
        commands: Set<String>,
        totalMemoryBytes: Double
    ) -> WorkloadClassification {
        let window = ImpactTuning.classificationWindow
        let cpuNow = ImpactHeuristics.normalizedCPU(cpuHistory.last ?? 0)
        let cpuSustained = ImpactHeuristics.sustainedCPUScore(cpuHistory: cpuHistory, window: min(window, max(1, cpuHistory.count)))
        let cpuPeak = cpuHistory.suffix(window).map(ImpactHeuristics.normalizedCPU).max() ?? cpuNow
        let cpuVolatility = max(0, cpuPeak - cpuSustained)
        let memGrowth = ImpactHeuristics.memoryGrowthRatio(memoryHistory: memoryHistory, window: min(window, max(2, memoryHistory.count)))
        let memPressure = ImpactHeuristics.memoryScore(residentBytes: memoryHistory.last ?? 0, totalMemoryBytes: totalMemoryBytes)

        let buildHit = tokenSignal(commands: commands, appName: appName, tokens: [
            "swiftc", "clang", "ld", "xcodebuild", "gradle", "javac", "kotlinc", "cargo", "cmake", "make", "ninja", "go", "npm", "pnpm", "yarn",
        ])
        let indexHit = tokenSignal(commands: commands, appName: appName, tokens: [
            "index", "indexing", "sourcekit", "clangd", "tsserver", "language-server", "lsp", "jetbrains", "idea",
        ])
        let aiHit = tokenSignal(commands: commands, appName: appName, tokens: [
            "copilot", "codeium", "tabnine", "jetbrains-ai", "cursor", "continue", "llm", "ollama",
        ])
        let backgroundHit = tokenSignal(commands: commands, appName: appName, tokens: [
            "analysis", "analyzer", "eslint", "spotlight", "mdworker", "scanner", "daemon", "index",
        ])

        let idleScore = clamp01(1.0 - max(max(cpuSustained / 18.0, cpuNow / 24.0), memGrowth / 0.10))
        let buildScore = clamp01((buildHit * 0.55) + ((cpuSustained / 100.0) * 0.35) + ((cpuPeak / 100.0) * 0.10))
        let indexingScore = clamp01((indexHit * 0.50) + ((memGrowth / 0.25) * 0.25) + ((cpuSustained / 100.0) * 0.25))
        let aiEditingScore = clamp01((aiHit * 0.55) + (isFrontmost ? 0.20 : 0.0) + ((cpuVolatility / 45.0) * 0.15) + ((cpuNow / 100.0) * 0.10))
        let backgroundScore = clamp01((isFrontmost ? 0.0 : 0.25) + (backgroundHit * 0.45) + ((cpuSustained / 100.0) * 0.15) + ((memPressure / 100.0) * 0.15))

        let candidates: [(WorkloadState, Double)] = [
            (.idle, idleScore),
            (.indexing, indexingScore),
            (.build, buildScore),
            (.aiAssistedEditing, aiEditingScore),
            (.backgroundAnalysis, backgroundScore),
        ]
        let sorted = candidates.sorted { $0.1 > $1.1 }
        let best = sorted.first ?? (.idle, 0)
        let second = sorted.dropFirst().first?.1 ?? 0
        let confidence = min(0.98, max(0.35, 0.45 + (best.1 - second) * 0.65))

        return WorkloadClassification(
            state: best.0,
            confidence: confidence,
            reasons: reasons(
                state: best.0,
                cpuNow: cpuNow,
                cpuSustained: cpuSustained,
                memPressure: memPressure,
                memGrowth: memGrowth,
                isFrontmost: isFrontmost,
                buildHit: buildHit,
                indexHit: indexHit,
                aiHit: aiHit,
                backgroundHit: backgroundHit
            )
        )
    }

    private static func reasons(
        state: WorkloadState,
        cpuNow: Double,
        cpuSustained: Double,
        memPressure: Double,
        memGrowth: Double,
        isFrontmost: Bool,
        buildHit: Double,
        indexHit: Double,
        aiHit: Double,
        backgroundHit: Double
    ) -> [String] {
        var items: [String] = []

        switch state {
        case .idle:
            items.append("Low sustained CPU (\(Int(cpuSustained.rounded()))%) and low memory growth.")
            if memPressure > 30 {
                items.append("Memory footprint is present but stable.")
            }
        case .build:
            items.append("Build/compile tool process signatures detected.")
            items.append("High sustained CPU (\(Int(cpuSustained.rounded()))%).")
        case .indexing:
            items.append("Index/language-server signatures detected.")
            items.append("Memory growth suggests index/cache expansion.")
        case .aiAssistedEditing:
            if aiHit > 0 {
                items.append("AI assistant process signatures detected.")
            }
            if isFrontmost {
                items.append("Foreground interactive workload.")
            }
            items.append("Burst-like CPU pattern while editing.")
        case .backgroundAnalysis:
            items.append("Analysis/scanner signatures detected.")
            if !isFrontmost {
                items.append("Workload is primarily background.")
            }
            items.append("Steady CPU + memory pressure profile.")
        }

        if items.isEmpty {
            items.append("Classification based on observed CPU, memory pressure, growth, and process signatures.")
        }
        return items
    }

    private static func tokenSignal(commands: Set<String>, appName: String, tokens: [String]) -> Double {
        let corpus = (commands + [appName]).joined(separator: " ").lowercased()
        let hits = tokens.filter { corpus.contains($0) }.count
        guard hits > 0 else { return 0 }
        return min(1.0, Double(hits) / 2.0)
    }

    private static func clamp01(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
}

@MainActor
final class AppImpactStore: ObservableObject {
    @Published var topApps: [AppImpact] = []
    @Published var telemetryStatus: String = ""

    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private let totalMemoryBytes = Double(ProcessInfo.processInfo.physicalMemory)
    private var cpuHistory: [pid_t: [Double]] = [:]
    private var memoryHistory: [pid_t: [Double]] = [:]
    private var refreshTimer: Timer?
    private var isRefreshing = false
    private var started = false
    private var lastCollectionAt: Date?

    init() {
        telemetryStatus = "starting"
        topApps = [
            AppImpact(
                id: ownPID,
                name: "Initializing",
                score: 0,
                cpuImpact: 0,
                cpuSustainedImpact: 0,
                memoryImpact: 0,
                rawMemoryPercent: 0,
                memoryGrowthImpact: 0,
                rawCPUPercent: 0,
                residentGB: 0,
                isFrontmost: false,
                hasTelemetry: false,
                hasSustainedCPUSpike: false,
                hasTabLikeMemoryPressure: false,
                childProcessCount: 0,
                childCommandHints: [],
                workload: WorkloadClassification(
                    state: .idle,
                    confidence: 0.20,
                    reasons: ["Waiting for first telemetry refresh."]
                )
            ),
        ]
    }

    func start() {
        guard !started else { return }
        started = true
        startRefreshLoopIfNeeded()
        refresh(force: true)
    }

    private func refresh(force: Bool = false) {
        guard !isRefreshing else { return }
        if !force, let lastCollectionAt {
            let elapsedMs = Date().timeIntervalSince(lastCollectionAt) * 1000.0
            if elapsedMs < Double(ImpactTuning.telemetryCollectionIntervalMs) {
                return
            }
        }
        isRefreshing = true
        telemetryStatus = "refreshing"

        Task { @MainActor [weak self] in
            guard let self else { return }
            let samples = await ProcessUsageCollector.collectAsync(timeoutMs: 5000)
            if samples.isEmpty {
                self.telemetryStatus = "refresh timeout/empty samples"
            }
            self.applyRefresh(samples: samples)
        }
    }

    private func startRefreshLoopIfNeeded() {
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Double(ImpactTuning.refreshIntervalMs) / 1000.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(force: false)
            }
        }
    }

    private func applyRefresh(samples: [pid_t: ProcessSample]) {
        defer { isRefreshing = false }
        lastCollectionAt = Date()
        let candidates = collectCandidateApps()
        telemetryStatus = "candidates=\(candidates.count) samples=\(samples.count)"
        let aggregated = aggregateByAppRoot(samples: samples, appCandidates: candidates)

        let computed = candidates.compactMap { app -> AppImpact? in
            let usage = aggregated[app.pid] ?? directUsage(for: app.pid, samples: samples)
            guard let usage else {
                let workload = WorkloadClassification(
                    state: .idle,
                    confidence: 0.35,
                    reasons: ["Per-process telemetry unavailable for this app on this refresh."]
                )
                return AppImpact(
                    id: app.pid,
                    name: app.name,
                    score: app.isFrontmost ? 2.0 : 1.0,
                    cpuImpact: 0,
                    cpuSustainedImpact: 0,
                    memoryImpact: 0,
                    rawMemoryPercent: 0,
                    memoryGrowthImpact: 0,
                    rawCPUPercent: 0,
                    residentGB: 0,
                    isFrontmost: app.isFrontmost,
                    hasTelemetry: false,
                    hasSustainedCPUSpike: false,
                    hasTabLikeMemoryPressure: false,
                    childProcessCount: 0,
                    childCommandHints: [],
                    workload: workload
                )
            }
            let flatUsage = ProcessUsage(cpuPercent: usage.cpuPercent, residentBytes: usage.residentBytes)
            recordHistory(for: app.pid, usage: flatUsage)

            let cpuSamples = cpuHistory[app.pid] ?? []
            let memorySamples = memoryHistory[app.pid] ?? []
            let cpuNow = ImpactHeuristics.normalizedCPU(usage.cpuPercent)
            let cpuSustained = ImpactHeuristics.sustainedCPUScore(cpuHistory: cpuSamples, window: ImpactTuning.classificationWindow)
            let memoryPressure = ImpactHeuristics.memoryScore(
                residentBytes: usage.residentBytes,
                totalMemoryBytes: totalMemoryBytes
            )
            let rawMemoryPercent = ImpactHeuristics.memoryPercent(
                residentBytes: usage.residentBytes,
                totalMemoryBytes: totalMemoryBytes
            )
            let memoryGrowth = ImpactHeuristics.memoryGrowthScore(
                memoryHistory: memorySamples,
                window: ImpactTuning.classificationWindow
            )
            let commandHints = usage.commands
                .map { URL(fileURLWithPath: $0).lastPathComponent }
                .filter { !$0.isEmpty }
                .sorted()
                .prefix(3)
            let hasSustainedSpike = ImpactHeuristics.isSustainedCPUSpike(cpuHistory: cpuSamples)
            let hasTabPressure = ImpactHeuristics.isTabLikeMemoryPressure(
                cpuHistory: cpuSamples,
                memoryHistory: memorySamples,
                totalMemoryBytes: totalMemoryBytes
            )
            let workload = WorkloadClassifier.classify(
                appName: app.name,
                isFrontmost: app.isFrontmost,
                cpuHistory: cpuSamples,
                memoryHistory: memorySamples,
                commands: usage.commands,
                totalMemoryBytes: totalMemoryBytes
            )
            let total = ImpactScorer.totalScore(
                cpuNow: cpuNow,
                cpuSustained: cpuSustained,
                memoryPressure: memoryPressure,
                memoryGrowth: memoryGrowth,
                isFrontmost: app.isFrontmost,
                hasSustainedSpike: hasSustainedSpike,
                hasTabPressure: hasTabPressure
            )

            return AppImpact(
                id: app.pid,
                name: app.name,
                score: total,
                cpuImpact: cpuNow,
                cpuSustainedImpact: cpuSustained,
                memoryImpact: memoryPressure,
                rawMemoryPercent: rawMemoryPercent,
                memoryGrowthImpact: memoryGrowth,
                rawCPUPercent: usage.cpuPercent,
                residentGB: usage.residentBytes / 1_073_741_824.0,
                isFrontmost: app.isFrontmost,
                hasTelemetry: true,
                hasSustainedCPUSpike: hasSustainedSpike,
                hasTabLikeMemoryPressure: hasTabPressure,
                childProcessCount: usage.processCount,
                childCommandHints: Array(commandHints),
                workload: workload
            )
        }

        let activePIDs = Set(candidates.map(\.pid))
        cpuHistory = cpuHistory.filter { activePIDs.contains($0.key) }
        memoryHistory = memoryHistory.filter { activePIDs.contains($0.key) }

        let visible = computed
            .filter { $0.score >= ImpactTuning.minimumVisibleImpact }
            .sorted { $0.score > $1.score }
        topApps = Array(visible.prefix(ImpactTuning.topAppCount))
        telemetryStatus += " aggregated=\(aggregated.count) computed=\(computed.count) visible=\(visible.count)"
    }

    private func collectCandidateApps() -> [CandidateApp] {
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let running = NSWorkspace.shared.runningApplications.filter { app in
            app.activationPolicy == .regular &&
                !app.isTerminated &&
                app.processIdentifier != ownPID &&
                app.localizedName != nil
        }

        return running.map { app in
            let fallbackName = app.bundleURL?.deletingPathExtension().lastPathComponent
            var tokenSet = Set<String>()
            if let localized = app.localizedName?.lowercased(), !localized.isEmpty {
                tokenSet.insert(localized)
            }
            if let bundleName = fallbackName?.lowercased(), !bundleName.isEmpty {
                tokenSet.insert(bundleName)
            }
            if let bundleID = app.bundleIdentifier?.lowercased() {
                tokenSet.insert(bundleID)
                if let tail = bundleID.split(separator: ".").last {
                    tokenSet.insert(String(tail))
                }
            }
            return CandidateApp(
                pid: app.processIdentifier,
                name: app.localizedName ?? fallbackName ?? "PID \(app.processIdentifier)",
                isFrontmost: app.processIdentifier == frontmostPID,
                matchTokens: Array(tokenSet).filter { $0.count >= 3 }
            )
        }
    }

    private func aggregateByAppRoot(
        samples: [pid_t: ProcessSample],
        appCandidates: [CandidateApp]
    ) -> [pid_t: AggregatedProcessUsage] {
        let appRoots = Set(appCandidates.map(\.pid))
        let candidatesByToken = appCandidates
            .flatMap { app in app.matchTokens.map { (app.pid, $0) } }
            .sorted { $0.1.count > $1.1.count }

        var totals: [pid_t: (cpu: Double, memory: Double, count: Int, commands: Set<String>)] = [:]
        var ownerCache: [pid_t: pid_t?] = [:]

        func ownerByCommand(_ command: String) -> pid_t? {
            let lower = command.lowercased()
            for (pid, token) in candidatesByToken where lower.contains("/\(token).app/") {
                return pid
            }
            for (pid, token) in candidatesByToken where token.count >= 8 || token.contains(" ") {
                if lower.contains(token) {
                    return pid
                }
            }
            return nil
        }

        func owner(for pid: pid_t, command: String) -> pid_t? {
            if let cached = ownerCache[pid] { return cached }
            var current: pid_t? = pid
            var visited = Set<pid_t>()
            var depth = 0

            while let node = current, depth < 128 {
                if appRoots.contains(node) {
                    ownerCache[pid] = node
                    return node
                }
                if visited.contains(node) { break }
                visited.insert(node)
                current = samples[node].map(\.ppid)
                depth += 1
            }

            if let byCommand = ownerByCommand(command) {
                ownerCache[pid] = byCommand
                return byCommand
            }

            ownerCache[pid] = nil
            return nil
        }

        for sample in samples.values {
            guard let root = owner(for: sample.pid, command: sample.command) else { continue }
            var bucket = totals[root] ?? (0, 0, 0, Set<String>())
            bucket.cpu += sample.cpuPercent
            bucket.memory += sample.residentBytes
            bucket.count += 1
            bucket.commands.insert(sample.command)
            totals[root] = bucket
        }

        return totals.mapValues { value in
            AggregatedProcessUsage(
                cpuPercent: value.cpu,
                residentBytes: value.memory,
                processCount: value.count,
                commands: value.commands
            )
        }
    }

    private func recordHistory(for pid: pid_t, usage: ProcessUsage) {
        cpuHistory[pid, default: []].append(usage.cpuPercent)
        memoryHistory[pid, default: []].append(usage.residentBytes)

        if let history = cpuHistory[pid], history.count > ImpactTuning.historyLimit {
            cpuHistory[pid] = Array(history.suffix(ImpactTuning.historyLimit))
        }

        if let history = memoryHistory[pid], history.count > ImpactTuning.historyLimit {
            memoryHistory[pid] = Array(history.suffix(ImpactTuning.historyLimit))
        }
    }

    private func directUsage(for pid: pid_t, samples: [pid_t: ProcessSample]) -> AggregatedProcessUsage? {
        guard let sample = samples[pid] else { return nil }
        return AggregatedProcessUsage(
            cpuPercent: sample.cpuPercent,
            residentBytes: sample.residentBytes,
            processCount: 1,
            commands: [sample.command]
        )
    }

}
