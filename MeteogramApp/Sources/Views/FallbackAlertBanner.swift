import SwiftUI

public struct FallbackAlertBanner: View {
    let fromModel: String
    let toModel: String
    let location: String
    let language: ForecastLanguage
    let onClose: () -> Void

    private var titleText: String {
        language == .sk ? "Model automaticky prepnutý" : "Model Automatically Switched"
    }

    private var fromName: String {
        if fromModel == "icon_d2" {
            return language == .sk ? "2-dňový model (DWD ICON-D2 2.2 km)" : "2-day (DWD ICON-D2 2.2 km)"
        }
        return fromModel.uppercased()
    }

    private var toName: String {
        if toModel == "icon_eu" {
            return language == .sk ? "DWD ICON-EU (5-dňový, 7.0 km)" : "DWD ICON-EU (5-day, 7.0 km)"
        }
        return "ECMWF AIFS (15-day)"
    }

    private var messageText: String {
        if language == .sk {
            return "\(fromName) nie je pre lokalitu „\(location)“ dostupný (poloha je mimo domény modelu). Automaticky sme prepli na najbližší dostupný model: \(toName)."
        } else {
            return "\(fromName) is not available for \"\(location)\" (location is outside Central Europe model domain). Automatically switched to closest available model: \(toName)."
        }
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bolt.fill")
                .foregroundColor(.yellow)
                .font(.title2)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(titleText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.yellow)

                Text(messageText)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(4)
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.body)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.yellow.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.yellow.opacity(0.35), lineWidth: 1)
                )
        )
    }
}
