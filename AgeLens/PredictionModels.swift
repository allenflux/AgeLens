//
//  PredictionModels.swift
//  AgeLens
//
//  Created by AllenFlux on 2026/6/17.
//

import Foundation

struct PredictionResponse: Decodable {
    let status: PredictionStatus
    let message: String
    let elapsedMilliseconds: Double?
    let image: SourceImage?
    let counts: DetectionCounts?
    let subjects: [PredictionSubject]
    let annotatedImage: String?
    let annotatedImageMime: String?

    enum CodingKeys: String, CodingKey {
        case status
        case message
        case elapsedMilliseconds = "elapsed_ms"
        case image
        case counts
        case subjects
        case annotatedImage = "annotated_image"
        case annotatedImageMime = "annotated_image_mime"
    }
}

enum PredictionStatus: String, Decodable {
    case ok
    case personOnly = "person_only"
    case noDetection = "no_detection"
    case noFace = "no_face"
    case noPrediction = "no_prediction"
    case error
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = PredictionStatus(rawValue: rawValue) ?? .unknown
    }

    var title: String {
        switch self {
        case .ok:
            "识别完成"
        case .personOnly:
            "仅检测到人体"
        case .noDetection:
            "未检测到目标"
        case .noFace:
            "未检测到人脸"
        case .noPrediction:
            "无法估计年龄性别"
        case .error:
            "服务器处理失败"
        case .unknown:
            "未知状态"
        }
    }

    var isSuccessful: Bool {
        self == .ok || self == .personOnly
    }
}

struct SourceImage: Decodable {
    let width: Int
    let height: Int
}

struct DetectionCounts: Decodable {
    let objects: Int
    let faces: Int
    let persons: Int
    let subjects: Int
}

struct PredictionSubject: Decodable, Identifiable {
    let id = UUID()
    let kind: String
    let age: Double?
    let gender: String?
    let genderScore: Double?
    let faceBox: [Double]?
    let faceConfidence: Double?
    let personBox: [Double]?
    let personConfidence: Double?

    enum CodingKeys: String, CodingKey {
        case kind
        case age
        case gender
        case genderScore = "gender_score"
        case faceBox = "face_box"
        case faceConfidence = "face_confidence"
        case personBox = "person_box"
        case personConfidence = "person_confidence"
    }

    var displayAge: String {
        guard let age else { return "-" }
        return String(format: "%.1f", age)
    }

    var displayGender: String {
        switch gender?.lowercased() {
        case "male":
            return "男"
        case "female":
            return "女"
        case .some(let value):
            return value
        case .none:
            return "-"
        }
    }

    var confidenceText: String {
        if let genderScore {
            return String(format: "性别置信度 %.0f%%", genderScore * 100)
        }

        if let faceConfidence {
            return String(format: "人脸置信度 %.0f%%", faceConfidence * 100)
        }

        if let personConfidence {
            return String(format: "人体置信度 %.0f%%", personConfidence * 100)
        }

        return "无置信度数据"
    }
}
