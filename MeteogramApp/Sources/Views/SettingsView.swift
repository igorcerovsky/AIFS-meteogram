import SwiftUI

public struct SettingsView: View {
    @ObservedObject var viewModel: MeteogramViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var serverInput: String = ""
    @State private var selectedLanguage: ForecastLanguage
    @State private var selectedTimeZone: ForecastTimeZone
    @State private var selectedHorizon: ForecastHorizon

    @State private var isTesting = false
    @State private var testResult: String?
    @State private var testSuccess: Bool?

    public init(viewModel: MeteogramViewModel) {
        self.viewModel = viewModel
        _serverInput = State(initialValue: viewModel.serverUrl)
        _selectedLanguage = State(initialValue: viewModel.language)
        _selectedTimeZone = State(initialValue: viewModel.timeZone)
        _selectedHorizon = State(initialValue: viewModel.horizon)
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Forecast Preferences") {
                    Picker("Language", selection: $selectedLanguage) {
                        ForEach(ForecastLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }

                    Picker("Time Zone", selection: $selectedTimeZone) {
                        ForEach(ForecastTimeZone.allCases) { tz in
                            Text(tz.displayName).tag(tz)
                        }
                    }

                    Picker("Default Horizon", selection: $selectedHorizon) {
                        ForEach(ForecastHorizon.displayOrder) { h in
                            Text("\(h.pillTitle) — \(h.displayName)").tag(h)
                        }
                    }
                }

                Section("Server Connection") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Meteogram Backend URL")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("http://localhost:8080", text: $serverInput)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            #endif

                        HStack(spacing: 8) {
                            Button("Localhost") {
                                serverInput = MeteogramConfig.defaultServerUrl
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)

                            Button("Mac Bonjour") {
                                serverInput = MeteogramConfig.defaultBonjourUrl
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                        }

                        HStack {
                            Button(action: testConnection) {
                                if isTesting {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Label("Test Connection", systemImage: "network")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isTesting || serverInput.isEmpty)

                            if let result = testResult {
                                HStack(spacing: 4) {
                                    Image(systemName: (testSuccess ?? false) ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor((testSuccess ?? false) ? .green : .red)
                                    Text(result)
                                        .font(.caption)
                                        .foregroundColor((testSuccess ?? false) ? .green : .red)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                }

                Section("Swipe Navigation Order") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Swipe left or right directly on the meteogram chart to switch between models in this order:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 6) {
                            ForEach(Array(ForecastHorizon.displayOrder.enumerated()), id: \.offset) { index, item in
                                Text("\(index + 1). \(item.pillTitle)")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.secondary.opacity(0.15))
                                    .cornerRadius(6)
                                if index < ForecastHorizon.displayOrder.count - 1 {
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 8))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.top, 2)
                    }
                }

                Section("About") {
                    LabeledContent("App Version", value: "1.0.0")
                    LabeledContent("AI Weather Model", value: "ECMWF AIFS 0.25° (50 members)")
                    LabeledContent("Regional Models", value: "DWD ICON-EU (7km), ICON-D2 (2.2km)")
                    LabeledContent("Data Provider", value: "Open-Meteo & ECMWF Open Data")
                    LabeledContent("Style Inspiration", value: "SHMÚ EPSGRAM")
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let needsRefresh = (viewModel.serverUrl != serverInput ||
                                            viewModel.language != selectedLanguage ||
                                            viewModel.timeZone != selectedTimeZone ||
                                            viewModel.horizon != selectedHorizon)

                        viewModel.serverUrl = serverInput
                        viewModel.language = selectedLanguage
                        viewModel.timeZone = selectedTimeZone
                        viewModel.horizon = selectedHorizon

                        if needsRefresh {
                            viewModel.fetchMeteogram()
                        }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 440)
        #endif
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        testSuccess = nil

        Task {
            let (success, latency, msg) = await MeteogramService.shared.testConnection(serverBaseUrl: serverInput)
            await MainActor.run {
                self.isTesting = false
                self.testSuccess = success
                self.testResult = success ? "OK (\(Int(latency)) ms)" : "Failed: \(msg)"
            }
        }
    }
}
