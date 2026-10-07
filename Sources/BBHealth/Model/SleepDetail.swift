import SwiftUI

/// Bốn giai đoạn giấc ngủ (màu cố định toàn app, lấy từ DesignSystem — không thêm màu mới).
enum SleepStage: String, CaseIterable, Identifiable {
    case awake, light, deep, rem

    var id: String { rawValue }

    /// Tên tiếng Việt.
    var label: String {
        switch self {
        case .awake: return "Thức"
        case .light: return "Nông"
        case .deep: return "Sâu"
        case .rem: return "REM"
        }
    }

    /// Màu cố định: Thức = san hô, Nông = xanh ngọc, Sâu = chàm, REM = tím.
    var color: Color {
        switch self {
        case .awake: return Theme.improve
        case .light: return Theme.brand
        case .deep: return Theme.sleep
        case .rem: return Theme.weight
        }
    }

    /// Thứ tự trục dọc trong hypnogram (thấp = sâu nhất ở dưới).
    var depthRow: Int {
        switch self {
        case .awake: return 3
        case .rem: return 2
        case .light: return 1
        case .deep: return 0
        }
    }
}

/// Một đoạn giấc ngủ liên tục cùng một giai đoạn.
struct SleepSegment: Identifiable {
    let stage: SleepStage
    let start: Date
    let end: Date
    var id: Date { start }
    var minutes: Double { end.timeIntervalSince(start) / 60 }
}

/// Chi tiết một đêm: các đoạn giai đoạn + các chỉ số suy ra.
struct SleepDetail {
    let segments: [SleepSegment]

    var bedTime: Date? { segments.map(\.start).min() }
    var wakeTime: Date? { segments.map(\.end).max() }

    /// Tổng thời gian trên giường (phút) = từ lúc lên giường tới lúc dậy.
    var inBedMinutes: Double {
        guard let b = bedTime, let w = wakeTime else { return 0 }
        return w.timeIntervalSince(b) / 60
    }
    /// Thời gian ngủ thật (phút) = mọi đoạn không phải "thức".
    var asleepMinutes: Double {
        segments.filter { $0.stage != .awake }.reduce(0) { $0 + $1.minutes }
    }
    var asleepHours: Double { asleepMinutes / 60 }

    /// Hiệu suất ngủ (%): ngủ thật / trên giường.
    var efficiency: Double { inBedMinutes > 0 ? asleepMinutes / inBedMinutes * 100 : 0 }

    /// Thời gian để thiu thiu (phút): từ lúc lên giường tới đoạn ngủ đầu tiên.
    var latencyMinutes: Double {
        guard let b = bedTime,
              let firstSleep = segments.first(where: { $0.stage != .awake })?.start else { return 0 }
        return max(0, firstSleep.timeIntervalSince(b) / 60)
    }

    /// Các lần thức giữa đêm (bỏ đoạn thức đầu/cuối nếu nằm ngoài giấc ngủ).
    var awakeEpisodes: [SleepSegment] {
        guard let firstSleep = segments.firstIndex(where: { $0.stage != .awake }),
              let lastSleep = segments.lastIndex(where: { $0.stage != .awake }) else { return [] }
        return segments[firstSleep...lastSleep].filter { $0.stage == .awake }
    }
    /// Số lần thức **đáng kể** (≥ 5 phút) giữa đêm — để câu "thức giữa đêm X lần" có nghĩa,
    /// không đếm những đoạn thức vụn vài giây/vài phút do lấp khoảng trống hay nguồn ghi lắt nhắt.
    var awakeCount: Int { awakeEpisodes.filter { $0.minutes >= 5 }.count }
    /// Tổng phút thức trong giấc (tổng các khối Thức trên hypnogram) — dùng chung cho legend,
    /// mục "thức giữa đêm … phút" và phần Đánh giá để mọi con số khớp nhau.
    var awakeMinutes: Double { minutes(of: .awake) }

    func minutes(of stage: SleepStage) -> Double {
        segments.filter { $0.stage == stage }.reduce(0) { $0 + $1.minutes }
    }
    /// % của một giai đoạn trên tổng ngủ thật.
    func percent(of stage: SleepStage) -> Double {
        asleepMinutes > 0 ? minutes(of: stage) / asleepMinutes * 100 : 0
    }

    var summary: SleepSummary {
        SleepSummary(totalHours: asleepHours, awakeCount: awakeCount, bedTime: bedTime, wakeTime: wakeTime)
    }

    // MARK: - Lấp khoảng trống giữa các đoạn ngủ thành THỨC

    /// Nguồn (Fitbit → Google/Apple Health) thường chỉ ghi các đoạn **có nhãn** và để **trống**
    /// lúc thức giữa đêm. Nếu không lấp, hypnogram để trống đoạn đó và phần "thức giữa đêm"
    /// đếm thiếu — đúng lỗi: thức dài 2–3h giữa đêm bị bỏ qua.
    ///
    /// Hàm này sắp các đoạn theo `start`, rồi với **mỗi khoảng trống bên trong giấc** (giữa đoạn
    /// ngủ đầu tiên và đoạn ngủ cuối cùng) mà `next.start - cur.end >= minGapSeconds` thì chèn một
    /// đoạn `.awake` lấp đúng khoảng đó. KHÔNG đụng tới đoạn thức đầu/cuối nằm ngoài giấc. Các đoạn
    /// Thức liền kề được gộp lại. Dùng chung cho mọi nguồn khi dựng `SleepDetail`.
    static func fillingAwakeGaps(_ segments: [SleepSegment], minGapSeconds: TimeInterval = 60) -> [SleepSegment] {
        let sorted = segments.sorted { $0.start < $1.start }
        guard sorted.count >= 2,
              let firstSleep = sorted.firstIndex(where: { $0.stage != .awake }),
              let lastSleep = sorted.lastIndex(where: { $0.stage != .awake }),
              firstSleep < lastSleep else {
            return mergingAdjacentAwake(sorted)
        }
        var out: [SleepSegment] = []
        for i in sorted.indices {
            out.append(sorted[i])
            // Chỉ lấp khoảng trống giữa hai đoạn nằm trong [firstSleep, lastSleep].
            guard i >= firstSleep, i < lastSleep else { continue }
            let cur = sorted[i], next = sorted[i + 1]
            if next.start.timeIntervalSince(cur.end) >= minGapSeconds {
                out.append(SleepSegment(stage: .awake, start: cur.end, end: next.start))
            }
        }
        return mergingAdjacentAwake(out.sorted { $0.start < $1.start })
    }

    /// Gộp các đoạn Thức chạm/đè nhau thành một đoạn (sau khi lấp hoặc khi nguồn ghi lắt nhắt).
    private static func mergingAdjacentAwake(_ segments: [SleepSegment]) -> [SleepSegment] {
        var out: [SleepSegment] = []
        for seg in segments {
            if seg.stage == .awake, let last = out.last, last.stage == .awake,
               seg.start <= last.end.addingTimeInterval(1) {
                out[out.count - 1] = SleepSegment(stage: .awake, start: last.start, end: max(last.end, seg.end))
            } else {
                out.append(seg)
            }
        }
        return out
    }
}
