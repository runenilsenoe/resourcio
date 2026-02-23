import AppKit
import SwiftUI

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct TopConsumerAppsMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppImpactStore()
    @State private var hoveredAppID: pid_t?

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 8) {
                if store.topApps.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No eligible apps found")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                } else {
                    ForEach(store.topApps) { app in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(app.name) \(Int(app.score.rounded()))%")
                                .font(.body.weight(.semibold))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 8)
                            Text(details(for: app))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 2)
                        .onHover { isHovering in
                            hoveredAppID = isHovering ? app.id : nil
                        }
                    }
                }

                if let hoveredApp = store.topApps.first(where: { $0.id == hoveredAppID }) {
                    Divider()
                    Text(tooltip(for: hoveredApp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.secondary.opacity(0.12))
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()
                HStack {
                    Spacer()
                    Button("Quit") {
                        NSApp.terminate(nil)
                    }
                    .keyboardShortcut("q")
                    Spacer()
                }
            }
            .padding(10)
            .frame(minWidth: 350, alignment: .leading)
            .task {
                store.start()
            }
        } label: {
            Label("Top Apps", systemImage: "gauge.with.needle")
        }
        .menuBarExtraStyle(.window)
    }

    private func details(for app: AppImpact) -> String {
        let cpuDisplay = min(max(app.rawCPUPercent, 0), 100)
        var parts = [
            "CPU \(Int(cpuDisplay.rounded()))%",
            "MEM \(Int(app.rawMemoryPercent.rounded()))%",
        ]

        if app.hasSustainedCPUSpike {
            parts.append("SPIKE")
        }

        if app.hasTabLikeMemoryPressure {
            parts.append("TABS")
        }

        return parts.joined(separator: "  ")
    }

    private func tooltip(for app: AppImpact) -> String {
        var lines: [String] = [
            "Workload: \(app.workload.state.rawValue) (\(Int((app.workload.confidence * 100).rounded()))% confidence)",
            "Observed metrics: CPU now \(Int(app.cpuImpact.rounded()))%, CPU sustained \(Int(app.cpuSustainedImpact.rounded()))%",
            "Memory share \(Int(app.rawMemoryPercent.rounded()))%, memory pressure \(Int(app.memoryImpact.rounded()))%, memory trend \(Int(app.memoryGrowthImpact.rounded()))%",
            String(format: "Aggregated resident memory: %.2f GB across %d processes", app.residentGB, app.childProcessCount),
        ]

        if !app.hasTelemetry {
            lines.append("Telemetry note: process-level metrics were unavailable on this refresh.")
        }

        if app.isFrontmost {
            lines.append("Foreground boost: active app gets extra weight.")
        }

        if app.hasSustainedCPUSpike {
            lines.append("SPIKE: sustained high CPU over recent samples.")
        }

        if app.hasTabLikeMemoryPressure {
            lines.append("TABS: high memory with low CPU and rising footprint.")
        }

        if !app.workload.reasons.isEmpty {
            lines.append("Signals:")
            for reason in app.workload.reasons {
                lines.append("- \(reason)")
            }
        }

        if !app.childCommandHints.isEmpty {
            lines.append("Observed child commands: \(app.childCommandHints.joined(separator: ", "))")
        }

        let appSpecificLines = AppSpecificTooltipRegistry.tooltipLines(for: app)
        if !appSpecificLines.isEmpty {
            lines.append(contentsOf: appSpecificLines)
        }

        return lines.joined(separator: "\n")
    }
}
