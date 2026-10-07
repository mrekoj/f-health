import Foundation
import SwiftData
import SwiftUI

/// Loại mục ghi nhanh: bữa ăn · rượu bia · triệu chứng · cân nặng.
enum LogKind: String, Codable, CaseIterable, Identifiable {
    case meal, alcohol, symptom, weight

    var id: String { rawValue }

    var label: String {
        switch self {
        case .meal: return "Bữa ăn"
        case .alcohol: return "Rượu bia"
        case .symptom: return "Triệu chứng"
        case .weight: return "Cân nặng"
        }
    }

    var symbol: String {
        switch self {
        case .meal: return "fork.knife"
        case .alcohol: return "wineglass.fill"
        case .symptom: return "stethoscope"
        case .weight: return "scalemass.fill"
        }
    }

    /// Màu riêng (nhuộm icon, chip).
    var tint: Color {
        switch self {
        case .meal: return Theme.meal
        case .alcohol: return Theme.improve
        case .symptom: return Theme.caution
        case .weight: return Theme.weight
        }
    }
}

/// Các triệu chứng dạ dày hay gặp của bạn (chip nhiều lựa chọn).
enum Symptom {
    static let all = ["Đầy bụng", "Ợ nóng", "Đau bụng", "Mệt", "Mất ngủ", "Khác"]
}

/// Nhật ký một ngày — gom các mục ghi trong ngày (khoá theo đầu ngày).
@Model
final class DailyLog {
    @Attribute(.unique) var day: Date
    @Relationship(deleteRule: .cascade, inverse: \LogEntry.dailyLog)
    var entries: [LogEntry] = []

    init(day: Date) { self.day = day }
}

/// Một mục ghi nhanh (bữa ăn / rượu bia / triệu chứng / cân nặng).
@Model
final class LogEntry {
    var timestamp: Date
    var kindRaw: String
    /// Nhãn chính (tên bữa / "Rượu bia" / "Triệu chứng" / "Cân nặng").
    var title: String
    /// Chi tiết (món ăn / "2 ly" / danh sách triệu chứng / "48,5 kg").
    var detail: String?
    /// Số kèm theo: số ly rượu hoặc số cân (kg).
    var amount: Double?
    var dailyLog: DailyLog?

    init(kind: LogKind, title: String, detail: String? = nil, amount: Double? = nil, timestamp: Date = Date()) {
        self.kindRaw = kind.rawValue
        self.title = title
        self.detail = detail
        self.amount = amount
        self.timestamp = timestamp
    }

    var kind: LogKind { LogKind(rawValue: kindRaw) ?? .meal }
}

extension LogEntry {
    /// Tìm hoặc tạo nhật ký ngày rồi thêm mục vào context.
    static func add(_ entry: LogEntry, on date: Date, in context: ModelContext) {
        let day = Calendar.current.startOfDay(for: date)
        var descriptor = FetchDescriptor<DailyLog>(predicate: #Predicate { $0.day == day })
        descriptor.fetchLimit = 1
        let log = (try? context.fetch(descriptor).first) ?? {
            let new = DailyLog(day: day)
            context.insert(new)
            return new
        }()
        entry.dailyLog = log
        context.insert(entry)
    }
}
