import Foundation

enum AppSpecificInsights {
    // Registry/router for app-specific implementations.
    // Add a new file per app and route it here.
    static func hasAppSpecificDetails(for appName: String) -> Bool {
        IntelliJAppInsights.matches(appName)
    }

    static func aiBreakdown(
        appName: String,
        cpuHistory: [Double],
        memoryHistory: [Double],
        isFrontmost: Bool,
        totalMemoryBytes: Double
    ) -> IntelliJAIBreakdown? {
        IntelliJAppInsights.aiBreakdown(
            appName: appName,
            cpuHistory: cpuHistory,
            memoryHistory: memoryHistory,
            isFrontmost: isFrontmost,
            totalMemoryBytes: totalMemoryBytes
        )
    }

    static func tooltip(for app: AppImpact) -> String? {
        if hasAppSpecificDetails(for: app.name) {
            return IntelliJAppInsights.tooltip(for: app)
        }
        return nil
    }
}
