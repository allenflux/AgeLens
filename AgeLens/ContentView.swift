//
//  ContentView.swift
//  AgeLens
//
//  Created by AllenFlux on 2026/6/17.
//

import SwiftUI
import UIKit

struct ContentView: View {
    private let productionServerAddress = "https://api.allenflux.tech"
    private let legacyServerAddress = "http://allenflux.tech:8010"

    private enum ActiveSheet: Identifiable {
        case camera
        case photoLibrary

        var id: String {
            switch self {
            case .camera:
                "camera"
            case .photoLibrary:
                "photoLibrary"
            }
        }
    }

    @AppStorage("serverAddress") private var serverAddress = "https://api.allenflux.tech"
    @State private var imageAddress = ""
    @State private var selectedImage: UIImage?
    @State private var predictionResult: PredictionResult?
    @State private var isUploading = false
    @State private var isLoadingImageURL = false
    @State private var errorMessage: String?
    @State private var activeSheet: ActiveSheet?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    imagePreview
                    inputSection
                    actionSection
                    resultSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("AgeLens")
            .onAppear(perform: migrateLegacyServerAddress)
            .sheet(item: $activeSheet) { sheet in
                ImagePicker(sourceType: sheet == .camera ? .camera : .photoLibrary) { image in
                    selectedImage = image
                    predictionResult = nil
                    errorMessage = nil
                }
                .ignoresSafeArea()
            }
        }
    }

    private var imagePreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("照片")
                .font(.headline)

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.secondarySystemGroupedBackground))

                if let previewImage = predictionResult?.annotatedImage ?? selectedImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(1)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 42, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("拍照或从相册选择一张照片")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(4 / 5, contentMode: .fit)

            HStack(spacing: 12) {
                Button {
                    activeSheet = .camera
                } label: {
                    Label("拍照", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera) || isUploading)

                Button {
                    activeSheet = .photoLibrary
                } label: {
                    Label("相册", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isUploading)
            }
        }
        .padding()
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("服务器")
                .font(.headline)

            TextField("https://api.example.com", text: $serverAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textContentType(.URL)
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))

            Divider()
                .padding(.vertical, 4)

            Text("图片链接")
                .font(.headline)

            HStack(spacing: 10) {
                TextField("https://example.com/photo.jpg", text: $imageAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))

                Button {
                    Task {
                        await loadImageFromURL()
                    }
                } label: {
                    if isLoadingImageURL {
                        ProgressView()
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "arrow.down.to.line.compact")
                            .frame(width: 24, height: 24)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(imageAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoadingImageURL || isUploading)
                .accessibilityLabel("加载图片链接")
            }
        }
        .padding()
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private var actionSection: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    await submitImage()
                }
            } label: {
                HStack {
                    if isUploading {
                        ProgressView()
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(isUploading ? "处理中..." : "上传并识别")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selectedImage == nil || isUploading)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if let predictionResult {
            let response = predictionResult.response

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(response.status.title)
                            .font(.headline)
                        Text(response.message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let elapsedMilliseconds = response.elapsedMilliseconds {
                        Text("\(Int(elapsedMilliseconds)) ms")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let counts = response.counts {
                    DetectionSummary(counts: counts)
                }

                if response.subjects.isEmpty {
                    Text("没有可展示的年龄/性别结果。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 10) {
                        ForEach(response.subjects) { subject in
                            SubjectRow(subject: subject)
                        }
                    }
                }
            }
            .padding()
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func submitImage() async {
        guard let selectedImage else { return }

        isUploading = true
        errorMessage = nil
        defer { isUploading = false }

        do {
            let service = MiVOLOService(serverAddress: serverAddress)
            predictionResult = try await service.predict(image: selectedImage)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadImageFromURL() async {
        isLoadingImageURL = true
        errorMessage = nil
        defer { isLoadingImageURL = false }

        do {
            let service = MiVOLOService(serverAddress: serverAddress)
            selectedImage = try await service.loadImage(from: imageAddress)
            predictionResult = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func migrateLegacyServerAddress() {
        if serverAddress == legacyServerAddress {
            serverAddress = productionServerAddress
        }
    }
}

private struct DetectionSummary: View {
    let counts: DetectionCounts

    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                SummaryMetric(title: "目标", value: counts.objects)
                SummaryMetric(title: "人脸", value: counts.faces)
            }
            GridRow {
                SummaryMetric(title: "人体", value: counts.persons)
                SummaryMetric(title: "结果", value: counts.subjects)
            }
        }
    }
}

private struct SummaryMetric: View {
    let title: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title3.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SubjectRow: View {
    let subject: PredictionSubject

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: subject.kind == "face" ? "face.smiling" : "figure.stand")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("\(subject.displayAge) 岁")
                        .font(.headline)
                    Text(subject.displayGender)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Text(subject.confidenceText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    ContentView()
}
