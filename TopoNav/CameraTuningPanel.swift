#if DEBUG
import SwiftUI
import UIKit

/// Debug-only sheet for tuning the follow camera live while a route plays.
/// The map stays visible and interactive above it.
struct CameraTuningPanel: View {
    @Bindable var settings: CameraSettings
    @State private var copied = false

    var body: some View {
        Form {
            Section("Camera") {
                TuningSlider("Pitch", value: $settings.tuning.pitch, in: 0...85, step: 1, unit: "°")
                TuningSlider("Zoom", value: $settings.tuning.followZoom, in: 12...18, step: 0.1)
                TuningSlider("Puck lower by", value: $settings.tuning.puckOffset, in: 0...400, step: 10, unit: " pt")
            }
            Section("Terrain") {
                TuningSlider("Exaggeration", value: $settings.tuning.terrainExaggeration, in: 1...3, step: 0.1, unit: "×")
            }
            Section {
                TuningSlider("Haze starts", value: $settings.tuning.fogStart, in: -5...10, step: 0.25)
                TuningSlider("Haze ends", value: $settings.tuning.fogEnd, in: 1...20, step: 0.25)
                TuningSlider("Horizon blend", value: $settings.tuning.horizonBlend, in: 0...0.5, step: 0.01)
            } header: {
                Text("Atmosphere")
            } footer: {
                Text("Distances are relative to the map's center point; negative values are nearer the camera.")
            }
            Section {
                TuningSlider("Smoothing", value: $settings.tuning.smoothing, in: 0.25...4, step: 0.05, unit: "×")
                TuningSlider("Look ahead", value: $settings.tuning.lookAheadDistance, in: 50...1000, step: 25, unit: " m")
                TuningSlider("Look-ahead weight", value: $settings.tuning.lookAheadWeight, in: 0...1, step: 0.05)
            } header: {
                Text("Direction")
            } footer: {
                Text("Look-ahead turns the camera toward the route ahead. It only applies while a route is shown and you're on it.")
            }
            Section {
                Button(copied ? "Copied" : "Copy values") {
                    UIPasteboard.general.string = settings.tuning.summary
                    copied = true
                }
                Button("Reset to defaults", role: .destructive) {
                    settings.reset()
                }
            }
        }
        .onChange(of: settings.tuning) { copied = false }
        // Start short so the puck stays visible above the sheet; drag up for more controls.
        .presentationDetents([.fraction(0.3), .medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }
}

/// A labelled slider showing its current value.
private struct TuningSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String

    init(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double, unit: String = "") {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.unit = unit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(value.formatted(.number.precision(.fractionLength(0...2))) + unit)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}
#endif
