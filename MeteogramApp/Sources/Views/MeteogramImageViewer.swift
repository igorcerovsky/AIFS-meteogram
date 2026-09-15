import SwiftUI

public struct MeteogramImageViewer: View {
    let image: PlatformImage?
    let isLoading: Bool
    let statusText: String
    let errorMessage: String?
    let onRetry: () -> Void
    var onSwipeLeft: (() -> Void)? = nil
    var onSwipeRight: (() -> Void)? = nil

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var swipeOffset: CGFloat = 0.0

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.03)

                if let image = image {
                    #if canImport(AppKit)
                    let swiftUIImage = Image(nsImage: image)
                    #elseif canImport(UIKit)
                    let swiftUIImage = Image(uiImage: image)
                    #endif

                    swiftUIImage
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(x: scale > 1.0 ? offset.width : swipeOffset,
                                y: scale > 1.0 ? offset.height : 0)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let delta = value / lastScale
                                    lastScale = value
                                    scale = max(0.8, min(scale * delta, 5.0))
                                }
                                .onEnded { _ in
                                    lastScale = 1.0
                                    if scale <= 1.0 {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                            scale = 1.0
                                            offset = .zero
                                            lastOffset = .zero
                                            swipeOffset = 0
                                        }
                                    } else {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                            offset = clampOffset(proposed: offset, scale: scale, geometry: geometry, image: image)
                                            lastOffset = offset
                                        }
                                    }
                                }
                                .simultaneously(with:
                                    DragGesture()
                                        .onChanged { value in
                                            if scale > 1.0 {
                                                // Pan zoomed image with boundary constraints
                                                let rawX = lastOffset.width + value.translation.width
                                                let rawY = lastOffset.height + value.translation.height
                                                let clamped = clampOffset(proposed: CGSize(width: rawX, height: rawY), scale: scale, geometry: geometry, image: image)
                                                let excessX = rawX - clamped.width
                                                let excessY = rawY - clamped.height

                                                // Apply soft rubber-banding past edges
                                                offset = CGSize(
                                                    width: clamped.width + excessX * 0.2,
                                                    height: clamped.height + excessY * 0.2
                                                )
                                            } else {
                                                // Horizontal swipe resistance preview
                                                swipeOffset = value.translation.width * 0.35
                                            }
                                        }
                                        .onEnded { value in
                                            if scale > 1.0 {
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                                    offset = clampOffset(proposed: offset, scale: scale, geometry: geometry, image: image)
                                                    lastOffset = offset
                                                }
                                            } else {
                                                let horizontalTranslation = value.translation.width
                                                let threshold: CGFloat = 50.0

                                                if horizontalTranslation < -threshold {
                                                    // Swiped Left -> Next model in order
                                                    onSwipeLeft?()
                                                } else if horizontalTranslation > threshold {
                                                    // Swiped Right -> Previous model in order
                                                    onSwipeRight?()
                                                }

                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                    swipeOffset = 0
                                                }
                                            }
                                        }
                                )
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                if scale > 1.0 {
                                    scale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                    swipeOffset = 0
                                } else {
                                    scale = 2.0
                                    offset = .zero
                                    lastOffset = .zero
                                }
                            }
                        }

                    // Floating zoom controls overlay
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            HStack(spacing: 12) {
                                Button(action: {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                        scale = max(1.0, scale - 0.5)
                                        offset = clampOffset(proposed: offset, scale: scale, geometry: geometry, image: image)
                                        lastOffset = offset
                                        if scale <= 1.0 {
                                            offset = .zero
                                            lastOffset = .zero
                                        }
                                    }
                                }) {
                                    Image(systemName: "minus.magnifyingglass")
                                        .font(.system(size: 13, weight: .semibold))
                                }

                                Text("\(Int(scale * 100))%")
                                    .font(.caption2.monospacedDigit())
                                    .frame(minWidth: 36)

                                Button(action: {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                        scale = min(4.0, scale + 0.5)
                                        offset = clampOffset(proposed: offset, scale: scale, geometry: geometry, image: image)
                                        lastOffset = offset
                                    }
                                }) {
                                    Image(systemName: "plus.magnifyingglass")
                                        .font(.system(size: 13, weight: .semibold))
                                }

                                Divider().frame(height: 12)

                                Button(action: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                        scale = 1.0
                                        offset = .zero
                                        lastOffset = .zero
                                        swipeOffset = 0
                                    }
                                }) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .shadow(color: .black.opacity(0.12), radius: 5, x: 0, y: 2)
                            )
                            .padding(12)
                        }
                    }
                }

                // Loading overlay
                if isLoading {
                    ZStack {
                        Color.black.opacity(0.18)
                            .background(.ultraThinMaterial)

                        VStack(spacing: 14) {
                            ProgressView()
                                .scaleEffect(1.2)

                            Text(statusText.isEmpty ? "Generating meteogram..." : statusText)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(UIColorOrNSColor.secondarySystemBackground))
                                .shadow(radius: 10)
                        )
                    }
                    .transition(.opacity)
                }

                // Error overlay
                if let errorMessage = errorMessage, !isLoading {
                    VStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 34))
                            .foregroundColor(.orange)

                        Text("Failed to Load Meteogram")
                            .font(.headline)

                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)

                        Button(action: onRetry) {
                            Label("Try Again", systemImage: "arrow.clockwise")
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(UIColorOrNSColor.secondarySystemBackground))
                            .shadow(radius: 10)
                    )
                }
            }
            .clipped()
        }
    }

    /// Calculates boundary constraints to ensure the image cannot be dragged outside the visible screen
    private func clampOffset(proposed: CGSize, scale: CGFloat, geometry: GeometryProxy, image: PlatformImage) -> CGSize {
        let containerWidth = geometry.size.width
        let containerHeight = geometry.size.height
        guard containerWidth > 0, containerHeight > 0, image.size.width > 0, image.size.height > 0 else {
            return .zero
        }

        let imageAspect = image.size.width / image.size.height
        let containerAspect = containerWidth / containerHeight

        let fittedWidth: CGFloat
        let fittedHeight: CGFloat

        if imageAspect > containerAspect {
            fittedWidth = containerWidth
            fittedHeight = containerWidth / imageAspect
        } else {
            fittedHeight = containerHeight
            fittedWidth = containerHeight * imageAspect
        }

        let displayedWidth = fittedWidth * scale
        let displayedHeight = fittedHeight * scale

        let maxOffsetX = max(0, (displayedWidth - containerWidth) / 2)
        let maxOffsetY = max(0, (displayedHeight - containerHeight) / 2)

        let clampedX = min(max(proposed.width, -maxOffsetX), maxOffsetX)
        let clampedY = min(max(proposed.height, -maxOffsetY), maxOffsetY)

        return CGSize(width: clampedX, height: clampedY)
    }
}

// Cross-platform color helper
private struct UIColorOrNSColor {
    #if canImport(UIKit)
    static var secondarySystemBackground: UIColor { UIColor.secondarySystemBackground }
    #elseif canImport(AppKit)
    static var secondarySystemBackground: NSColor { NSColor.windowBackgroundColor }
    #endif
}
