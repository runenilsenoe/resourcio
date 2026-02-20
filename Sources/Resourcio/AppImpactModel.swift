import Foundation

struct AppImpact: Identifiable {
    let id: pid_t
    let name: String
    let score: Double
    let cpuImpact: Double
    let memoryImpact: Double
    let rawCPUPercent: Double
    let residentGB: Double
    let isFrontmost: Bool
    let hasSustainedCPUSpike: Bool
    let hasTabLikeMemoryPressure: Bool
    let isIntelliJFamily: Bool
    let hasLikelyAIActivity: Bool
    let aiActivityScore: Double
    let aiInferencePercent: Double
    let aiRetrievalPercent: Double
    let aiEmbeddingPercent: Double
    let aiGenerationPercent: Double
    let aiCachePercent: Double
}

struct IntelliJAIBreakdown {
    let totalPercent: Double
    let inferencePercent: Double
    let retrievalPercent: Double
    let embeddingPercent: Double
    let generationPercent: Double
    let cachePercent: Double
}

struct ProcessUsage {
    let cpuPercent: Double
    let residentBytes: Double
}

struct CandidateApp {
    let pid: pid_t
    let name: String
    let isFrontmost: Bool
}

enum ImpactTuning {
    static let refreshIntervalMs: UInt64 = 500
    static let historyLimit = 8
    static let topAppCount = 5

    static let cpuNormalizationDivisor = 2.0
    static let memoryScaleMultiplier = 4.0

    static let cpuWeight = 0.60
    static let memoryWeight = 0.30
    static let foregroundWeight = 0.10

    static let sustainedSpikePenalty = 12.0
    static let tabPressurePenalty = 8.0
    static let aiBadgeThreshold = 0.55

    static let sustainedSpikeWindow = 4
    static let sustainedSpikeAvgThreshold = 55.0
    static let sustainedSpikePeakThreshold = 75.0

    static let tabPressureWindow = 4
    static let tabPressureMemoryThreshold = 45.0
    static let tabPressureCpuCeiling = 25.0
    static let tabPressureGrowthThreshold = 0.12

    static let aiWindow = 6
    static let aiNoHistoryBaseline = 0.25
    static let aiCpuNormDivisor = 70.0
    static let aiBurstNormDivisor = 75.0
    static let aiMemoryNormDivisor = 55.0
    static let aiGrowthNormDivisor = 0.20
    static let aiForegroundBoost = 0.20
}
