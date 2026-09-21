import SwiftUI

public struct ContentView: View {
    @StateObject private var viewModel = MeteogramViewModel()
    @State private var showSettings = false
    @State private var isLocationSearchExpanded = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Main Top Bar / Header
            headerBar
                .zIndex(20)

            // Collapsible Location Search Panel
            if isLocationSearchExpanded {
                ControlPanelView(viewModel: viewModel, isExpanded: $isLocationSearchExpanded)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .zIndex(15)
            }

            // Sleek Model Pills Bar (15d, 2d, 5d, 10d, 7d)
            ModelPillsBar(location: viewModel.location, currentHorizon: viewModel.horizon) { selected in
                viewModel.switchToModel(selected)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .zIndex(10)

            // Fallback Banner Notice
            if viewModel.showFallbackAlert {
                FallbackAlertBanner(
                    fromModel: viewModel.fallbackFromModel,
                    toModel: viewModel.fallbackToModel,
                    location: viewModel.location,
                    language: viewModel.language,
                    onClose: {
                        viewModel.dismissFallbackAlert()
                    }
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(9)
            }

            // Offline / Cached Mode Banner
            if viewModel.isOfflineCached {
                HStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.caption2.bold())
                        .foregroundColor(.orange)
                    Text(viewModel.offlineCacheNotice ?? "Offline • Using cached forecast")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Spacer()
                    Button("Retry") {
                        viewModel.fetchMeteogram()
                    }
                    .font(.caption2.bold())
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(6)
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(8)
            }

            // Meteogram Chart Viewer: Native Swift Charts or Server Raster Image
            Group {
                if viewModel.displayMode == .nativeCharts && !viewModel.timeSeries.isEmpty {
                    NativeMeteogramChartView(
                        viewModel: viewModel,
                        selectedDate: $viewModel.selectedDate,
                        onSwipeLeft: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                viewModel.switchToNextModel()
                            }
                        },
                        onSwipeRight: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                viewModel.switchToPreviousModel()
                            }
                        }
                    )
                } else {
                    MeteogramImageViewer(
                        image: viewModel.currentImage,
                        isLoading: viewModel.isLoading,
                        statusText: viewModel.loadingStatusText,
                        errorMessage: viewModel.errorMessage,
                        onRetry: {
                            viewModel.fetchMeteogram()
                        },
                        onSwipeLeft: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                viewModel.switchToNextModel()
                            }
                        },
                        onSwipeRight: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                viewModel.switchToPreviousModel()
                            }
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .zIndex(1)

            // Subtle bottom bar with swipe hint & timestamp
            bottomStatusBar
                .zIndex(5)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(viewModel: viewModel)
        }
        .onAppear {
            if viewModel.timeSeries.isEmpty && viewModel.currentImage == nil {
                viewModel.fetchMeteogram()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                // View Mode Toggle (Native Charts vs Server Image)
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.displayMode = (viewModel.displayMode == .nativeCharts) ? .rasterImage : .nativeCharts
                    }
                }) {
                    Label(
                        viewModel.displayMode == .nativeCharts ? "Native Charts" : "Raster Image",
                        systemImage: viewModel.displayMode == .nativeCharts ? "chart.xyaxis.line" : "photo"
                    )
                }
                .help("Toggle between Native Swift Charts and Server Image")

                // Refresh
                Button(action: { viewModel.fetchMeteogram() }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .help("Refresh Meteogram (⌘R)")

                // Copy Image
                Button(action: { viewModel.copyImageToClipboard() }) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(viewModel.currentImage == nil)
                .keyboardShortcut("c", modifiers: .command)
                .help("Copy Image to Clipboard (⌘C)")

                // Share
                if let rawData = viewModel.rawImageData {
                    ShareLink(
                        item: rawData,
                        preview: SharePreview(viewModel.formattedTitle, icon: Image(systemName: "cloud.sun.fill"))
                    ) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .help("Share Meteogram")
                }

                // Settings
                Button(action: { showSettings = true }) {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Forecast Settings & Server Connection")
            }
        }
    }

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 10) {
            // App Badge Icon
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(LinearGradient(colors: [.green, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 26, height: 26)

                Text("AI")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            }

            // Location Title Button (Tapping opens search)
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isLocationSearchExpanded.toggle()
                }
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(.blue)
                        .font(.subheadline)

                    Text(viewModel.location)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Image(systemName: isLocationSearchExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            // Star favorite
            Button(action: {
                viewModel.toggleFavorite(viewModel.location)
            }) {
                Image(systemName: viewModel.isFavorite(viewModel.location) ? "star.fill" : "star")
                    .foregroundColor(viewModel.isFavorite(viewModel.location) ? .yellow : .secondary)
                    .font(.subheadline)
            }
            .buttonStyle(.plain)

            Spacer()

            // Quick Search toggle icon
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isLocationSearchExpanded.toggle()
                }
            }) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.body)
            }
            .buttonStyle(.plain)

            // Settings gear
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape")
                    .foregroundColor(.secondary)
                    .font(.body)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var bottomStatusBar: some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 8, weight: .bold))
                Text("Swipe to change model")
                    .font(.caption2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundColor(.secondary.opacity(0.8))

            Spacer()

            if viewModel.isUsingStaticFallback {
                HStack(spacing: 3) {
                    Image(systemName: "globe.europe.africa.fill")
                        .font(.system(size: 8))
                    Text("GitHub Pages CDN")
                        .font(.caption2)
                }
                .foregroundColor(.cyan)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.cyan.opacity(0.12))
                .cornerRadius(4)
            }

            if let updated = viewModel.lastUpdated {
                HStack(spacing: 3) {
                    if viewModel.isOfflineCached {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 8))
                            .foregroundColor(.orange)
                        Text("Cached \(viewModel.formatRelativeTime(updated))")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    } else {
                        Text("Updated \(updated.formatted(date: .omitted, time: .standard))")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.02))
    }
}
