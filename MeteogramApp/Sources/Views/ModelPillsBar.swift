import SwiftUI

public struct ModelPillsBar: View {
    let location: String
    let currentHorizon: ForecastHorizon
    let onSelect: (ForecastHorizon) -> Void

    public var body: some View {
        HStack(spacing: 6) {
            ForEach(ForecastHorizon.displayOrder) { horizon in
                let isSelected = horizon == currentHorizon
                let isOutsideCoverage = (horizon == .iconD22 && MeteogramConfig.isOutsideIconD2Domain(location))

                Button(action: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                        onSelect(horizon)
                    }
                }) {
                    VStack(spacing: 1) {
                        HStack(spacing: 2) {
                            Text(horizon.pillTitle)
                                .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                                .strikethrough(isOutsideCoverage, color: .orange)

                            if isOutsideCoverage {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(.orange)
                            }
                        }
                        .foregroundColor(isSelected ? .white : (isOutsideCoverage ? .secondary.opacity(0.6) : .primary))

                        Text(isOutsideCoverage ? "No coverage" : horizon.subtitle.replacingOccurrences(of: "ECMWF ", with: "").replacingOccurrences(of: "DWD ", with: ""))
                            .font(.system(size: 8, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(isSelected ? .white.opacity(0.85) : (isOutsideCoverage ? .orange.opacity(0.8) : .secondary))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isSelected ? Color.blue : (isOutsideCoverage ? Color.orange.opacity(0.08) : Color.secondary.opacity(0.12)))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.blue.opacity(0.8) : (isOutsideCoverage ? Color.orange.opacity(0.3) : Color.clear), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 11)
                .fill(.ultraThinMaterial)
        )
    }
}
