import SwiftUI

public struct ControlPanelView: View {
    @ObservedObject var viewModel: MeteogramViewModel
    @ObservedObject var locationManager = LocationManager.shared
    @Binding var isExpanded: Bool

    public var body: some View {
        VStack(spacing: 8) {
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    // Location Search Field Row
                    HStack(spacing: 8) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                                .font(.caption)

                            TextField("City name or lat, lon coordinates", text: $viewModel.location)
                                .textFieldStyle(.plain)
                                .font(.subheadline)
                                .onSubmit {
                                    viewModel.fetchMeteogram()
                                    withAnimation { isExpanded = false }
                                }

                            if !viewModel.location.isEmpty {
                                Button(action: { viewModel.location = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.secondary.opacity(0.12))
                        )

                        // GPS Button
                        Button(action: {
                            locationManager.requestCurrentLocation { coords in
                                viewModel.location = coords
                                viewModel.fetchMeteogram()
                                withAnimation { isExpanded = false }
                            }
                        }) {
                            if locationManager.isLocating {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 28, height: 28)
                            } else {
                                Image(systemName: "location.fill")
                                    .frame(width: 28, height: 28)
                                    .foregroundColor(.blue)
                            }
                        }
                        .buttonStyle(.bordered)
                        .help("Use Current GPS Location")

                        // Done / Collapse button
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded = false
                            }
                        }) {
                            Text("Done")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    // Presets
                    PresetsRowView(activeLocation: viewModel.location) { selected in
                        viewModel.setLocation(selected)
                        withAnimation { isExpanded = false }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(UIColorOrNSColor.secondarySystemBackground))
                        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

private struct UIColorOrNSColor {
    #if canImport(UIKit)
    static var secondarySystemBackground: UIColor { UIColor.secondarySystemBackground }
    #elseif canImport(AppKit)
    static var secondarySystemBackground: NSColor { NSColor.windowBackgroundColor }
    #endif
}
