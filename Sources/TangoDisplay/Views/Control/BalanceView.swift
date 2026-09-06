import SwiftUI

struct BalanceView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(spacing: 10) {
            Text("Balance")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(balanceLabel)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(height: 14)

            HStack(spacing: 6) {
                Text("L")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                AppSlider(value: $settings.builtInBalance, range: -1.0...1.0)
                Text("R")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Button("Centre") {
                settings.builtInBalance = 0.0
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 200)
    }

    private var balanceLabel: String {
        let v = settings.builtInBalance
        if abs(v) < 0.01 { return "Centre" }
        let pct = Int((abs(v) * 100).rounded())
        return v < 0 ? "L \(pct)%" : "R \(pct)%"
    }
}
