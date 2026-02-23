import Foundation

enum WorkloadState: String, CaseIterable {
    case idle = "Idle"
    case indexing = "Indexing"
    case build = "Build"
    case aiAssistedEditing = "AI-Assisted Editing"
    case backgroundAnalysis = "Background Analysis"
}

struct WorkloadClassification {
    let state: WorkloadState
    let confidence: Double
    let reasons: [String]
}

struct AppImpact: Identifiable {
    let id: pid_t
    let name: String
    let score: Double
    let cpuImpact: Double
    let cpuSustainedImpact: Double
    let memoryImpact: Double
    let rawMemoryPercent: Double
    let memoryGrowthImpact: Double
    let rawCPUPercent: Double
    let residentGB: Double
    let isFrontmost: Bool
    let hasTelemetry: Bool
    let hasSustainedCPUSpike: Bool
    let hasTabLikeMemoryPressure: Bool
    let childProcessCount: Int
    let childCommandHints: [String]
    let workload: WorkloadClassification
}

struct ProcessUsage {
    let cpuPercent: Double
    let residentBytes: Double
}

struct ProcessSample {
    let pid: pid_t
    let ppid: pid_t
    let cpuPercent: Double
    let residentBytes: Double
    let command: String
}

struct AggregatedProcessUsage {
    let cpuPercent: Double
    let residentBytes: Double
    let processCount: Int
    let commands: Set<String>
}

struct CandidateApp {
    let pid: pid_t
    let name: String
    let isFrontmost: Bool
    let matchTokens: [String]
}

enum ImpactTuning {
    static let refreshIntervalMs: UInt64 = 500
    static let telemetryCollectionIntervalMs: UInt64 = 2000
    static let historyLimit = 24
    static let topAppCount = 5
    static let minimumVisibleImpact = 1.0

    static let memoryScaleMultiplier = 1.8

    static let cpuNowWeight = 0.35
    static let cpuSustainedWeight = 0.25
    static let memoryPressureWeight = 0.20
    static let memoryGrowthWeight = 0.10
    static let foregroundResponsivenessWeight = 0.10

    static let sustainedSpikePenalty = 12.0
    static let tabPressurePenalty = 8.0

    static let sustainedSpikeWindow = 4
    static let sustainedSpikeAvgThreshold = 40.0
    static let sustainedSpikePeakThreshold = 65.0

    static let tabPressureWindow = 8
    static let tabPressureMemoryThreshold = 40.0
    static let tabPressureCpuCeiling = 18.0
    static let tabPressureGrowthThreshold = 0.10

    static let classificationWindow = 10
}
