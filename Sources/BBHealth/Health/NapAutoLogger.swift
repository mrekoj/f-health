import Foundation
import SwiftData

/// Tự động quét **giấc ngủ trưa / ngủ ngày** từ nguồn rồi lưu vào SwiftData (`NapLog`) — KHÔNG ghi tay.
///
/// Quét hôm nay + 2 ngày gần nhất, chống trùng với mục đã có (so khớp `start` lệch ≤ 10 phút),
/// chèn giấc mới kèm note đánh giá chất lượng (`Explanations.napNote`).
///
/// GIỚI HẠN: chỉ lưu được giấc mà nguồn (vòng Fitbit → Apple/Google Health) đã **ghi phiên ngủ**.
/// Giấc rất ngắn có thể thiết bị không ghi → sẽ không có gì để lưu. Đây là best-effort đúng kỹ thuật.
@MainActor
enum NapAutoLogger {
    /// Chống trùng: coi là cùng một giấc nếu `start` lệch không quá 10 phút.
    private static let dedupWindow: TimeInterval = 10 * 60

    /// Nhãn nguồn cho giấc **ước tính từ nhịp tim** (Fitbit không ghi phiên ngủ).
    static let estimatedSource = "Ước tính từ nhịp tim"

    /// Quét từ `provider` cho hôm nay + 2 ngày trước `now`, lưu giấc mới vào `context`.
    ///
    /// Hai nguồn, theo thứ tự ưu tiên:
    /// 1. **Phiên ngủ Fitbit** (`daytimeSleeps`) — chính xác, `estimated = false`.
    /// 2. **HR-dò** (`estimatedDaytimeNaps`) — ước tính từ nhịp tim, chỉ nhận khi KHÔNG chồng lấn
    ///    một phiên ngủ hay một `NapLog` đã có (ưu tiên dữ liệu phiên-ngủ thật).
    @discardableResult
    static func scanAndLog(provider: any HealthStoreProvider,
                           context: ModelContext,
                           now: Date = Date(),
                           source: String) async -> Int {
        let cal = Calendar.current
        let days = (0...2).compactMap { cal.date(byAdding: .day, value: -$0, to: now) }

        // Mốc `start` đã có (chống trùng theo start như cũ) + khung giờ đã có (chống trùng chồng lấn).
        let existing = (try? context.fetch(FetchDescriptor<NapLog>())) ?? []
        var knownStarts: [Date] = existing.map(\.start)
        var knownRanges: [(start: Date, end: Date)] = existing.map { ($0.start, $0.end) }

        func isDupStart(_ start: Date) -> Bool {
            knownStarts.contains { abs($0.timeIntervalSince(start)) <= dedupWindow }
        }
        func overlapsKnown(_ nap: NapSummary) -> Bool {
            knownRanges.contains { nap.overlaps(start: $0.start, end: $0.end) }
        }
        func insert(_ nap: NapSummary, estimated: Bool, source: String) {
            var note = Explanations.napNote(minutes: nap.minutes, at: nap.start)
            if estimated {
                note = "Ước tính từ nhịp tim (Fitbit không ghi giấc này); độ dài/chất lượng chỉ gần đúng. " + note
            }
            context.insert(NapLog(start: nap.start, end: nap.end, minutes: nap.minutes,
                                  source: source, note: note, estimated: estimated))
            knownStarts.append(nap.start)
            knownRanges.append((nap.start, nap.end))
        }

        var inserted = 0
        for day in days {
            // 1) Phiên ngủ thật (ưu tiên) — kể cả khi trùng vẫn ghi khung giờ vào `knownRanges`
            //    để chặn giấc HR-dò chồng lấn ở bước sau.
            let sessions = (try? await provider.daytimeSleeps(for: day)) ?? []
            for nap in sessions where nap.minutes >= 1 {
                if isDupStart(nap.start) {
                    knownRanges.append((nap.start, nap.end))   // vẫn chặn HR-dò chồng lấn
                    continue
                }
                insert(nap, estimated: false, source: source)
                inserted += 1
            }

            // 2) HR-dò — bỏ nếu trùng start hoặc chồng lấn phiên-ngủ / NapLog đã có.
            let estimated = (try? await provider.estimatedDaytimeNaps(for: day)) ?? []
            for nap in estimated where nap.minutes >= 1 {
                if isDupStart(nap.start) || overlapsKnown(nap) { continue }
                insert(nap, estimated: true, source: estimatedSource)
                inserted += 1
            }
        }
        if inserted > 0 { try? context.save() }
        return inserted
    }

    /// Nhãn nguồn ngắn để lưu kèm mỗi giấc.
    static func sourceLabel(for source: HealthSource) -> String {
        switch source {
        case .apple: return "Sức khoẻ"
        case .google: return "Google Health"
        case .both: return "Google/Sức khoẻ"
        }
    }
}
