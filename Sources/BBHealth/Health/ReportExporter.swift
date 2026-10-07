import Foundation
import SwiftData

/// **Xuất ra app Tệp** (T-033, gộp T-006): thư mục `Trên iPhone của tôi → BBHealth` (bật UIFileSharingEnabled).
/// - `health.csv`: mỗi ngày 1 dòng `YYYY-MM-DD,ngu_gio,nhip_tim_nghi,buoc,can_kg,ruou_ly,ghi_chu` (để công cụ/trợ lý khác đọc).
/// - `bao-cao-<kỳ>-<ngày>.md`: báo cáo + bài AI khi anh bấm "Lưu vào Tệp".
/// iCloud Drive cần bật iCloud trong Developer portal (chưa có) → tạm để trong Documents của app; từ app Tệp
/// bạn kéo sang iCloud Drive được.
enum ReportExporter {
    static var folder: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs
    }
    static var csvURL: URL { folder.appendingPathComponent("health.csv") }
    static let csvHeader = "ngay,ngu_gio,nhip_tim_nghi,buoc,can_kg,ruou_ly,ghi_chu\n"

    /// Ghi/thay dòng của ngày `date` trong `health.csv` (chống trùng theo ngày).
    static func writeDailyCSV(date: Date, sleepHours: Double?, restingHR: Double?, steps: Int?,
                              weightKg: Double?, alcoholUnits: Double, note: String) {
        let ymd = HealthDataTools.ymd(date)
        func n(_ v: Double?, _ d: Int) -> String { v.map { String(format: "%.\(d)f", $0) } ?? "" }
        let line = [ymd, n(sleepHours, 1), n(restingHR, 0), steps.map(String.init) ?? "", n(weightKg, 1),
                    String(format: "%.0f", alcoholUnits), note.replacingOccurrences(of: ",", with: ";").replacingOccurrences(of: "\n", with: " ")]
            .joined(separator: ",")
        var lines = (try? String(contentsOf: csvURL, encoding: .utf8))?.components(separatedBy: "\n").filter { !$0.isEmpty } ?? []
        if lines.first?.hasPrefix("ngay,") != true { lines.insert(csvHeader.trimmingCharacters(in: .newlines), at: 0) }
        lines.removeAll { $0.hasPrefix(ymd + ",") }
        lines.append(line)
        let body = lines.dropFirst().sorted().joined(separator: "\n")
        try? (lines[0] + "\n" + body + "\n").write(to: csvURL, atomically: true, encoding: .utf8)
    }

    /// Lưu báo cáo (+ bài AI nếu có) thành file Markdown; trả về tên file.
    @discardableResult
    static func saveReport(_ r: HealthReport, aiText: String?, aiLabel: String?) -> String {
        var md = HealthReportText.markdown(r, includePrompt: false)
        if let aiText, !aiText.isEmpty {
            md += "\n\n---\n\n## Bài phân tích của AI" + (aiLabel.map { " (\($0))" } ?? "") + "\n\n" + aiText + "\n"
        }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        let name = "bao-cao-\(r.period.kind.rawValue)-\(f.string(from: r.period.end)).md"
        try? md.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
        return name
    }

    /// Dòng CSV hôm nay từ màn Hôm nay (gọi sau khi tải xong; 1 lần/ngày là đủ nhưng ghi đè cũng không sao).
    @MainActor
    static func writeToday(from model: TodayViewModel, context: ModelContext) {
        let day = Calendar.current.startOfDay(for: model.date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
        let entries = (try? context.fetch(FetchDescriptor<LogEntry>(
            predicate: #Predicate { $0.timestamp >= day && $0.timestamp < end }))) ?? []
        let alcohol = entries.filter { $0.kind == .alcohol }.reduce(0.0) { $0 + ($1.amount ?? 1) }
        let symptoms = entries.filter { $0.kind == .symptom }.compactMap(\.detail).joined(separator: "; ")
        writeDailyCSV(date: day, sleepHours: model.sleep?.totalHours, restingHR: model.restingHeartRate,
                      steps: model.steps, weightKg: model.bodyMass?.kg, alcoholUnits: alcohol, note: symptoms)
    }
}
