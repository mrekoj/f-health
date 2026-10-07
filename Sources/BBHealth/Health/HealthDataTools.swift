import Foundation
import SwiftData

/// **Công cụ cho AI** (T-027): AI tự gọi để lấy số liệu thêm khi anh hỏi (chi tiết 1 ngày, các đêm,
/// nhịp tim theo giờ, nhật ký, dải ngày). Trả về Markdown — tái dùng `HealthReportBuilder`/`HealthReportText`.
@MainActor
struct HealthDataTools {
    let provider: any HealthStoreProvider
    let source: HealthSource
    let context: ModelContext
    let today: Date

    static let specs: [AIToolSpec] = [
        AIToolSpec(name: "get_day_detail",
                   description: "Lấy toàn bộ số liệu của MỘT ngày: giấc ngủ đêm trước (giai đoạn sâu/REM/nông/thức, các lần thức), nhịp tim theo giờ, nhịp nghỉ, HRV, bước, cân, bữa ăn có giờ, rượu bia, triệu chứng, ngủ trưa, bài thở, ghi chú sự kiện. Dùng khi cần nhìn kỹ một ngày/đêm cụ thể.",
                   parametersJSON: #"{"type":"object","properties":{"date":{"type":"string","description":"Ngày dạng YYYY-MM-DD"}},"required":["date"]}"#),
        AIToolSpec(name: "get_range_table",
                   description: "Bảng số liệu theo ngày (ngủ, đi ngủ→dậy, nhịp nghỉ, HRV, bước, cân, rượu bia, ngủ trưa, triệu chứng) cho một khoảng ngày, tối đa 90 ngày, kèm nhận xét tự động và mối liên hệ app tính. Dùng để so sánh nhiều ngày/tuần/tháng.",
                   parametersJSON: #"{"type":"object","properties":{"from":{"type":"string","description":"Ngày đầu YYYY-MM-DD"},"to":{"type":"string","description":"Ngày cuối YYYY-MM-DD"}},"required":["from","to"]}"#),
        AIToolSpec(name: "get_sleep_nights",
                   description: "Giai đoạn ngủ từng đêm (sâu/REM/nông/thức, phút để thiu thiu, các lần thức ≥ 5 phút với giờ) cho một khoảng ngày, tối đa 14 ngày.",
                   parametersJSON: #"{"type":"object","properties":{"from":{"type":"string"},"to":{"type":"string"}},"required":["from","to"]}"#),
        AIToolSpec(name: "get_heart_rate_hourly",
                   description: "Nhịp tim theo giờ (thấp/TB/cao mỗi giờ) của một ngày — để biết tim lên cao lúc nào, hạ lúc nào.",
                   parametersJSON: #"{"type":"object","properties":{"date":{"type":"string"}},"required":["date"]}"#),
        AIToolSpec(name: "get_profile",
                   description: "Hồ sơ cá nhân: tuổi, cao, mục tiêu, bệnh nền, lời bác sĩ dặn, ăn uống, thuốc, lối sống.",
                   parametersJSON: #"{"type":"object","properties":{}}"#),
    ]

    /// Chạy một công cụ; lỗi trả câu tiếng Việt để AI tự xử.
    func run(_ call: AIToolCall) async -> String {
        let a = call.arguments
        switch call.name {
        case "get_profile":
            return HealthReportText.markdown(await build(.day, end: today), includePrompt: false)
                .components(separatedBy: "## Tổng quan").first ?? ""
        case "get_day_detail":
            guard let d = Self.date(a["date"]) else { return "Thiếu hoặc sai tham số date (YYYY-MM-DD)." }
            let r = await build(.day, end: d)
            return HealthReportText.markdown(r, includePrompt: false, includeProfile: false)
        case "get_heart_rate_hourly":
            guard let d = Self.date(a["date"]) else { return "Thiếu hoặc sai tham số date (YYYY-MM-DD)." }
            let pts = ((try? await provider.intradayHeartRate(for: d)) ?? nil) ?? []
            guard !pts.isEmpty else { return "Không có nhịp tim theo giờ cho ngày này (nguồn chưa đồng bộ)." }
            let h = HealthReportBuilder.hourly(pts)
            let resting = (try? await provider.restingHeartRate(for: d)) ?? nil
            return "Nhịp tim theo giờ \(Self.ymd(d)) (giờ: TB [thấp–cao]): " + h.map { "\($0.hour)h: \($0.avg) [\($0.lo)–\($0.hi)]" }.joined(separator: " · ")
                + (resting.map { ". Nhịp nghỉ: \(Int($0.rounded()))" } ?? "")
        case "get_sleep_nights", "get_range_table":
            guard let from = Self.date(a["from"]), let to = Self.date(a["to"]), from <= to else {
                return "Thiếu hoặc sai tham số from/to (YYYY-MM-DD)."
            }
            let maxDays = call.name == "get_sleep_nights" ? 14 : 90
            let span = min(maxDays, (Calendar.current.dateComponents([.day], from: from, to: to).day ?? 0) + 1)
            let kind: ReportKind = call.name == "get_sleep_nights" ? (span <= 7 ? .week : .week) : (span <= 7 ? .week : (span <= 30 ? .month : .quarter))
            if call.name == "get_sleep_nights" && span > 7 {
                // Hai lượt tuần để vẫn có giai đoạn ngủ.
                let mid = Calendar.current.date(byAdding: .day, value: -7, to: to)!
                let r2 = await build(.week, end: to), r1 = await build(.week, end: mid)
                return HealthReportText.nights(r1, from: from) + HealthReportText.nights(r2, from: from)
            }
            let r = await build(kind, end: to)
            if call.name == "get_sleep_nights" { return HealthReportText.nights(r, from: from) }
            return HealthReportText.markdown(r, includePrompt: false, includeProfile: false)
        default:
            return "Không có công cụ tên \(call.name)."
        }
    }

    private func build(_ kind: ReportKind, end: Date) async -> HealthReport {
        await HealthReportBuilder.build(period: ReportPeriod(kind: kind, end: end), provider: provider,
                                        source: source, context: context, now: today)
    }

    nonisolated static func date(_ v: Any?) -> Date? {
        guard let s = v as? String else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(s.prefix(10)))
    }
    nonisolated static func ymd(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}
