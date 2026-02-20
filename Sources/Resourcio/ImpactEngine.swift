import AppKit
import Foundation

enum ImpactHeuristics {
    static func normalizedCPU(_ cpuPercent: Double) -> Double {
        min(cpuPercent / ImpactTuning.cpuNormalizationDivisor, 100.0)
    }

    static func memoryScore(residentBytes: Double, totalMemoryBytes: Double) -> Double {
        guard totalMemoryBytes > 0 else { return 0 }
        let rawPercent = (residentBytes / totalMemoryBytes) * 100.0
        return min(rawPercent * ImpactTuning.memoryScaleMultiplier, 100.0)
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
        guard
            let latestCPU = cpuHistory.last,
            let latestResidentBytes = memoryHistory.last,
            memoryHistory.count >= ImpactTuning.tabPressureWindow
        else {
            return false
        }

        let memImpact = memoryScore(residentBytes: latestResidentBytes, totalMemoryBytes: totalMemoryBytes)
        let normalizedCpu = normalizedCPU(latestCPU)
        let recentMem = Array(memoryHistory.suffix(ImpactTuning.tabPressureWindow))
        let baseline = recentMem.first ?? latestResidentBytes
        let growthRatio = baseline > 0 ? ((latestResidentBytes - baseline) / baseline) : 0

        return memImpact >= ImpactTuning.tabPressureMemoryThreshold &&
            normalizedCpu <= ImpactTuning.tabPressureCpuCeiling &&
            growthRatio >= ImpactTuning.tabPressureGrowthThreshold
    }

}

enum ImpactScorer {
    static func totalScore(
        cpuImpact: Double,
        memoryImpact: Double,
        isFrontmost: Bool,
        hasSustainedSpike: Bool,
        hasTabPressure: Bool
    ) -> Double {
        let foreground = isFrontmost ? 100.0 : 0.0
        let spikePenalty = hasSustainedSpike ? ImpactTuning.sustainedSpikePenalty : 0.0
        let tabPenalty = hasTabPressure ? ImpactTuning.tabPressurePenalty : 0.0

        return min(
            100.0,
            (cpuImpact * ImpactTuning.cpuWeight) +
                (memoryImpact * ImpactTuning.memoryWeight) +
                (foreground * ImpactTuning.foregroundWeight) +
                spikePenalty + tabPenalty
        )
    }
}

@MainActor
final class AppImpactStore: ObservableObject {
    @Published var topApps: [AppImpact] = []

    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private let totalMemoryBytes = Double(ProcessInfo.processInfo.physicalMemory)
    private var cpuHistory: [pid_t: [Double]] = [:]
    private var memoryHistory: [pid_t: [Double]] = [:]
    private var refreshTask: Task<Void, Never>?
    private var isRefreshing = false

    init() {
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshOnce()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(ImpactTuning.refreshIntervalMs))
                await self.refreshOnce()
            }
        }
    }

    deinit {
        refreshTask?.cancel()
    }

    func refresh() {
        Task { [weak self] in
            await self?.refreshOnce()
        }
    }

    private func refreshOnce() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let candidates = collectCandidateApps()
        let usageByPID = await ProcessUsageCollector.collectAsync()

        let computed = candidates.compactMap { app -> AppImpact? in
            guard let usage = usageByPID[app.pid] else { return nil }
            recordHistory(for: app.pid, usage: usage)

            let cpuSamples = cpuHistory[app.pid] ?? []
            let memorySamples = memoryHistory[app.pid] ?? []
            let cpuImpact = ImpactHeuristics.normalizedCPU(usage.cpuPercent)
            let memoryImpact = ImpactHeuristics.memoryScore(
                residentBytes: usage.residentBytes,
                totalMemoryBytes: totalMemoryBytes
            )
            let hasSustainedSpike = ImpactHeuristics.isSustainedCPUSpike(cpuHistory: cpuSamples)
            let hasTabPressure = ImpactHeuristics.isTabLikeMemoryPressure(
                cpuHistory: cpuSamples,
                memoryHistory: memorySamples,
                totalMemoryBytes: totalMemoryBytes
            )
            let aiBreakdown = AppSpecificInsights.aiBreakdown(
                appName: app.name,
                cpuHistory: cpuSamples,
                memoryHistory: memorySamples,
                isFrontmost: app.isFrontmost,
                totalMemoryBytes: totalMemoryBytes
            )
            let aiTotalPercent = aiBreakdown?.totalPercent ?? 0
            let total = ImpactScorer.totalScore(
                cpuImpact: cpuImpact,
                memoryImpact: memoryImpact,
                isFrontmost: app.isFrontmost,
                hasSustainedSpike: hasSustainedSpike,
                hasTabPressure: hasTabPressure
            )

            return AppImpact(
                id: app.pid,
                name: app.name,
                score: total,
                cpuImpact: cpuImpact,
                memoryImpact: memoryImpact,
                rawCPUPercent: usage.cpuPercent,
                residentGB: usage.residentBytes / 1_073_741_824.0,
                isFrontmost: app.isFrontmost,
                hasSustainedCPUSpike: hasSustainedSpike,
                hasTabLikeMemoryPressure: hasTabPressure,
                isIntelliJFamily: AppSpecificInsights.hasAppSpecificDetails(for: app.name),
                hasLikelyAIActivity: (aiTotalPercent / 100.0) >= ImpactTuning.aiBadgeThreshold,
                aiActivityScore: aiTotalPercent / 100.0,
                aiInferencePercent: aiBreakdown?.inferencePercent ?? 0,
                aiRetrievalPercent: aiBreakdown?.retrievalPercent ?? 0,
                aiEmbeddingPercent: aiBreakdown?.embeddingPercent ?? 0,
                aiGenerationPercent: aiBreakdown?.generationPercent ?? 0,
                aiCachePercent: aiBreakdown?.cachePercent ?? 0
            )
        }

        let activePIDs = Set(candidates.map(\.pid))
        cpuHistory = cpuHistory.filter { activePIDs.contains($0.key) }
        memoryHistory = memoryHistory.filter { activePIDs.contains($0.key) }

        topApps = Array(computed.sorted { $0.score > $1.score }.prefix(ImpactTuning.topAppCount))
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
            CandidateApp(
                pid: app.processIdentifier,
                name: app.localizedName ?? "Unknown App",
                isFrontmost: app.processIdentifier == frontmostPID
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
}
