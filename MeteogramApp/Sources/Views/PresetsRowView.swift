import SwiftUI

public struct PresetsRowView: View {
    let activeLocation: String
    let onSelect: (String) -> Void

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("Presets:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.trailing, 2)

                ForEach(MeteogramConfig.defaultPresets) { preset in
                    let isActive = activeLocation.lowercased() == preset.name.lowercased()
                    Button(action: {
                        onSelect(preset.name)
                    }) {
                        Text(preset.displayName)
                            .font(.caption.weight(isActive ? .semibold : .regular))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(isActive ? Color.blue.opacity(0.25) : Color.secondary.opacity(0.12))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(isActive ? Color.blue : Color.clear, lineWidth: 1)
                            )
                            .foregroundColor(isActive ? .blue : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}
