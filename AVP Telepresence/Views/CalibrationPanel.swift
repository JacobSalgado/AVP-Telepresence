import SwiftUI

struct CalibrationPanel: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var model = appModel
        let id = model.currentViewpointID
        let pose = Binding(
            get: { model.pose(forID: id) },
            set: { model.calibration.poses[id] = $0 }
        )

        VStack(alignment: .leading, spacing: 14) {
            Text("Viewpoint \(id.uppercased())").font(.headline)
            if id == "a" {
                Text("Reference viewpoint — locked").font(.caption).foregroundStyle(.secondary)
            }

            Group {
                row("Yaw", pose.yawDegrees, -180...180, step: 1, unit: "°")
                row("X", pose.x, -6...6, step: 0.05, unit: " m")
                row("Z", pose.z, -6...6, step: 0.05, unit: " m")
                row("Floor", pose.floor, -0.5...0.5, step: 0.01, unit: " m")
            }
            .disabled(id == "a")

            HStack {
                Button("Reset") { model.calibration.poses[id] = nil }.disabled(id == "a")
                Spacer()
                Button("Print") { model.printPoses() }
                Button("Save") { model.saveCalibration() }
            }
        }
        .padding(24)
        .frame(width: 420)
        .glassBackgroundEffect()
    }

    private func row(_ label: String, _ value: Binding<Float>,
                     _ range: ClosedRange<Float>, step: Float, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text("\(value.wrappedValue, specifier: "%.2f")\(unit)").monospacedDigit()
            }
            HStack {
                Button("−") { value.wrappedValue = max(range.lowerBound, value.wrappedValue - step) }
                Slider(value: value, in: range)
                Button("+") { value.wrappedValue = min(range.upperBound, value.wrappedValue + step) }
            }
        }
    }
}
