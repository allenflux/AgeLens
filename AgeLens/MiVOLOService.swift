//
//  MiVOLOService.swift
//  AgeLens
//
//  Created by AllenFlux on 2026/6/17.
//

import Foundation
import UIKit

enum MiVOLOServiceError: LocalizedError {
    case invalidServerURL
    case invalidImageURL
    case imageEncodingFailed
    case invalidResponse
    case serverError(statusCode: Int, message: String)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            "服务器地址无效，请检查 URL。"
        case .invalidImageURL:
            "图片链接无效，或链接内容不是图片。"
        case .imageEncodingFailed:
            "图片压缩失败，请换一张照片重试。"
        case .invalidResponse:
            "服务器响应无效。"
        case .serverError(let statusCode, let message):
            "服务器返回 \(statusCode)：\(message)"
        case .decodingFailed(let message):
            "解析响应失败：\(message)"
        }
    }
}

struct MiVOLOService {
    var serverAddress: String
    var urlSession: URLSession = .shared

    func loadImage(from imageAddress: String) async throws -> UIImage {
        let trimmedAddress = imageAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedAddress), url.scheme != nil, url.host != nil else {
            throw MiVOLOServiceError.invalidImageURL
        }

        let (data, response) = try await urlSession.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
              let image = UIImage(data: data) else {
            throw MiVOLOServiceError.invalidImageURL
        }

        return image
    }

    func predict(image: UIImage, includeImage: Bool = true) async throws -> PredictionResult {
        let uploadImage = image.resized(maxSide: 1280)

        guard let jpegData = uploadImage.jpegData(compressionQuality: 0.86) else {
            throw MiVOLOServiceError.imageEncodingFailed
        }

        let request = try makePredictRequest(imageData: jpegData, includeImage: includeImage)
        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MiVOLOServiceError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw MiVOLOServiceError.serverError(statusCode: httpResponse.statusCode, message: message)
        }

        do {
            let prediction = try JSONDecoder().decode(PredictionResponse.self, from: data)
            return PredictionResult(response: prediction, annotatedImage: UIImage.annotatedImage(from: prediction.annotatedImage))
        } catch {
            throw MiVOLOServiceError.decodingFailed(error.localizedDescription)
        }
    }

    func healthCheck() async throws {
        guard let url = makeBaseURL()?.appending(path: "health") else {
            throw MiVOLOServiceError.invalidServerURL
        }

        let (_, response) = try await urlSession.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw MiVOLOServiceError.invalidResponse
        }
    }

    private func makePredictRequest(imageData: Data, includeImage: Bool) throws -> URLRequest {
        guard let url = makeBaseURL()?.appending(path: "predict").appending(queryItems: [
            URLQueryItem(name: "include_image", value: includeImage ? "true" : "false")
        ]) else {
            throw MiVOLOServiceError.invalidServerURL
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = MultipartFormData(boundary: boundary)
            .appendFile(fieldName: "file", fileName: "photo.jpg", mimeType: "image/jpeg", data: imageData)
            .finalize()
        return request
    }

    private func makeBaseURL() -> URL? {
        let trimmedAddress = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmedAddress), components.scheme != nil, components.host != nil else {
            return nil
        }

        components.path = ""
        return components.url
    }
}

struct PredictionResult {
    let response: PredictionResponse
    let annotatedImage: UIImage?
}

private struct MultipartFormData {
    private let boundary: String
    private var data = Data()

    init(boundary: String) {
        self.boundary = boundary
    }

    func appendFile(fieldName: String, fileName: String, mimeType: String, data fileData: Data) -> MultipartFormData {
        var copy = self
        copy.data.appendString("--\(boundary)\r\n")
        copy.data.appendString("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n")
        copy.data.appendString("Content-Type: \(mimeType)\r\n\r\n")
        copy.data.append(fileData)
        copy.data.appendString("\r\n")
        return copy
    }

    func finalize() -> Data {
        var copy = data
        copy.appendString("--\(boundary)--\r\n")
        return copy
    }
}

private extension Data {
    mutating func appendString(_ value: String) {
        append(Data(value.utf8))
    }
}

private extension UIImage {
    func resized(maxSide: CGFloat) -> UIImage {
        let longestSide = max(size.width, size.height)
        guard longestSide > maxSide else { return self }

        let scale = maxSide / longestSide
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    static func annotatedImage(from base64String: String?) -> UIImage? {
        guard var value = base64String, !value.isEmpty else { return nil }

        if let commaIndex = value.firstIndex(of: ",") {
            value = String(value[value.index(after: commaIndex)...])
        }

        guard let data = Data(base64Encoded: value, options: .ignoreUnknownCharacters) else {
            return nil
        }

        return UIImage(data: data)
    }
}
