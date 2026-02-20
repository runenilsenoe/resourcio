import Foundation

enum IntelliJAppInsights {
    static func matches(_ appName: String) -> Bool {
        let name = appName.lowercased()
        return name.contains("intellij") || name.contains("jetbrains")
    }

    static func aiBreakdown(
        appName: String,
        cpuHistory: [Double],
        memoryHistory: [Double],
        isFrontmost: Bool,
        totalMemoryBytes: Double
    ) -> IntelliJAIBreakdown? {
        guard matches(appName) else { return nil }
        guard !cpuHistory.isEmpty, !memoryHistory.isEmpty else {
            return IntelliJAIBreakdown(
                totalPercent: percent(ImpactTuning.aiNoHistoryBaseline),
                inferencePercent: 22,
                retrievalPercent: 26,
                embeddingPercent: 30,
                generationPercent: 20,
                cachePercent: 34
            )
        }

        let cpuRecent = Array(cpuHistory.suffix(ImpactTuning.aiWindow))
        let memRecent = Array(memoryHistory.suffix(ImpactTuning.aiWindow))
        let normalizedCpu = cpuRecent.map(ImpactHeuristics.normalizedCPU)
        let avgCpu = normalizedCpu.reduce(0, +) / Double(normalizedCpu.count)
        let peakCpu = normalizedCpu.max() ?? 0

        let memLatest = memRecent.last ?? 0
        let memScore = ImpactHeuristics.memoryScore(residentBytes: memLatest, totalMemoryBytes: totalMemoryBytes)
        let memBase = memRecent.first ?? memLatest
        let memGrowth = memBase > 0 ? max(0, (memLatest - memBase) / memBase) : 0

        let cpuSignal = min(avgCpu / ImpactTuning.aiCpuNormDivisor, 1.0)
        let burstSignal = peakCpu >= ImpactTuning.aiBurstNormDivisor ? 1.0 : peakCpu / ImpactTuning.aiBurstNormDivisor
        let memorySignal = min(memScore / ImpactTuning.aiMemoryNormDivisor, 1.0)
        let growthSignal = min(memGrowth / ImpactTuning.aiGrowthNormDivisor, 1.0)
        let foregroundSignal = isFrontmost ? ImpactTuning.aiForegroundBoost : 0.0

        let total = min(1.0, (cpuSignal * 0.35) + (burstSignal * 0.20) + (memorySignal * 0.25) + (growthSignal * 0.20) + foregroundSignal)
        let foregroundUnit = isFrontmost ? 1.0 : 0.0

        let inference = min(1.0, (cpuSignal * 0.55) + (burstSignal * 0.35) + (foregroundUnit * 0.10))
        let retrieval = min(1.0, (cpuSignal * 0.30) + (memorySignal * 0.45) + (growthSignal * 0.25))
        let embedding = min(1.0, (memorySignal * 0.50) + (growthSignal * 0.40) + (cpuSignal * 0.10))
        let generation = min(1.0, (burstSignal * 0.45) + (cpuSignal * 0.40) + (foregroundUnit * 0.15))
        let cache = min(1.0, (memorySignal * 0.55) + (growthSignal * 0.35) + ((1.0 - cpuSignal) * 0.10))

        return IntelliJAIBreakdown(
            totalPercent: percent(total),
            inferencePercent: percent(inference),
            retrievalPercent: percent(retrieval),
            embeddingPercent: percent(embedding),
            generationPercent: percent(generation),
            cachePercent: percent(cache)
        )
    }

    static func tooltip(for app: AppImpact) -> String {
        let score = Int((app.aiActivityScore * 100).rounded())
        if score >= 75 {
            return """
            AI resources (\(score)%): high activity.
            Inference/API: \(Int(app.aiInferencePercent.rounded()))%
            Retrieval/context scan: \(Int(app.aiRetrievalPercent.rounded()))%
            Embeddings/indexing: \(Int(app.aiEmbeddingPercent.rounded()))%
            Code generation/rerank: \(Int(app.aiGenerationPercent.rounded()))%
            Background cache/context sync: \(Int(app.aiCachePercent.rounded()))%
            """
        }
        if score >= 55 {
            return """
            AI resources (\(score)%): moderate activity.
            Inference/API: \(Int(app.aiInferencePercent.rounded()))%
            Retrieval/context scan: \(Int(app.aiRetrievalPercent.rounded()))%
            Embeddings/indexing: \(Int(app.aiEmbeddingPercent.rounded()))%
            Code generation/rerank: \(Int(app.aiGenerationPercent.rounded()))%
            Background cache/context sync: \(Int(app.aiCachePercent.rounded()))%
            """
        }
        return """
        AI resources (\(score)%): low activity.
        Inference/API: \(Int(app.aiInferencePercent.rounded()))%
        Retrieval/context scan: \(Int(app.aiRetrievalPercent.rounded()))%
        Embeddings/indexing: \(Int(app.aiEmbeddingPercent.rounded()))%
        Code generation/rerank: \(Int(app.aiGenerationPercent.rounded()))%
        Background cache/context sync: \(Int(app.aiCachePercent.rounded()))%
        """
    }

    private static func percent(_ value: Double) -> Double {
        min(100.0, max(0.0, value * 100.0))
    }
}
