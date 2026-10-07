import Foundation

/// **Suy ra giấc ngủ trưa TỪ NHỊP TIM** khi Fitbit không ghi được thành phiên ngủ.
///
/// Lý do: giấc trưa NGẮN (chợp mắt 10–40 phút) nhiều khi Fitbit không đánh dấu là "phiên ngủ",
/// nên `daytimeSleeps(for:)` trả rỗng — dù nhịp tim lúc đó rõ ràng tụt về gần mức nghỉ.
/// Bộ dò này đọc nhịp tim trong ngày, tìm đoạn nhịp "yên tĩnh như lúc nghỉ" đủ dài → coi là một
/// giấc trưa **ước tính** (cờ `estimated = true`, độ dài chỉ gần đúng).
///
/// VÍ DỤ: ~14:00–14:40 nhịp tim ~60 trong khi nhịp nghỉ 59 → bắt được một giấc.
enum NapDetector {

    // MARK: - Ngưỡng heuristic (ghi rõ để sau còn tinh chỉnh)

    /// Chỉ xét **ban ngày**: trước 09h còn là giấc đêm/sáng sớm, sau 19h là chiều tối — không coi là "trưa".
    private static let dayStartHour = 9
    private static let dayEndHour = 19
    /// Cửa sổ làm mượt nhịp tim (trung bình trượt ~5 phút) để bớt nhiễu một-hai nhịp lẻ.
    private static let smoothingWindow: TimeInterval = 5 * 60
    /// Ngưỡng để GOM đoạn (độ dài): nhịp ≤ (nghỉ + 16). CANH THEO 2 GIẤC THẬT (người dùng thử):
    /// hôm trước nằm ngủ ~60 (nghỉ 59), hôm sau giấc nhẹ chỉ ~70–72 (nghỉ 61) trong khi thức ban ngày
    /// anh ở ~85–100 → giấc trưa KHÔNG nhất thiết xuống sát mức nghỉ. Nền thức thấp nhất ~78 nên
    /// ceiling nghỉ+16 (~77) vẫn loại được lúc ngồi yên.
    private static let restingMargin: Double = 16
    /// Đáy của đoạn phải xuống gần vùng nghỉ: min ≤ nghỉ + 14 (≈75). Giấc nhẹ hôm 04/10 đáy ~70 → lọt;
    /// ngồi yên lúc thức thường hiếm khi < 78 → loại. Kết hợp với cú tụt tương đối bên dưới.
    private static let nearRestingMargin: Double = 14
    /// Và phải **thấp hơn rõ** so với nền nhịp ban ngày (phân vị 65% = mức thức điển hình) ≥ 15 bpm
    /// — tín hiệu CHẮC nhất: 2 giấc thật đều tụt 20–40 nhịp so với nền.
    private static let belowBaseline: Double = 15
    /// Một giấc trưa phải kéo dài **≥ 10 phút** mới tính.
    private static let minDuration: TimeInterval = 10 * 60
    /// Dài quá **120 phút** thì không coi là "giấc trưa" (có thể là ốm nằm nghỉ / dữ liệu lỗi).
    private static let maxDuration: TimeInterval = 120 * 60
    /// Gộp hai đoạn nhịp-thấp cách nhau ≤ 5 phút (một nhịp lẻ nhỉnh lên không nên cắt đôi giấc).
    private static let mergeGap: TimeInterval = 5 * 60

    /// Dò các giấc trưa ước tính trong NGÀY `day` từ chuỗi nhịp tim `points`.
    /// - Parameters:
    ///   - points: nhịp tim theo thời gian trong ngày (intraday), thứ tự bất kỳ.
    ///   - resting: nhịp tim nghỉ của ngày (nếu có). Thiếu thì dùng phân vị thấp của chính ngày đó.
    ///   - day: ngày cần dò (để giới hạn khung 09–19h).
    /// - Returns: danh sách `NapSummary` với `estimated = true`.
    static func fromHeartRate(_ points: [(time: Date, bpm: Double)],
                              resting: Double?,
                              day: Date) -> [NapSummary] {
        let cal = Calendar.current
        // 1) Lọc về khung ban ngày của đúng `day`, sắp theo thời gian.
        let daypoints = points
            .filter { cal.isDate($0.time, inSameDayAs: day) }
            .filter { let h = cal.component(.hour, from: $0.time); return h >= dayStartHour && h < dayEndHour }
            .sorted { $0.time < $1.time }
        guard daypoints.count >= 3 else { return [] }

        // 2) Làm mượt bằng trung bình trượt ~5 phút (giảm nhiễu; dữ liệu thưa thì gần như giữ nguyên).
        let smoothed = movingAverage(daypoints, window: smoothingWindow)

        // 3) Ngưỡng "như lúc nghỉ": nghỉ + 3; không có nhịp nghỉ thì lấy phân vị 15% của ngày.
        let rest = resting ?? percentile(smoothed.map(\.bpm), 0.15)
        let ceiling = rest + restingMargin
        // Nền nhịp ban ngày = phân vị 65% (mức nhịp khi THỨC/hoạt động điển hình, không bị kéo xuống
        // bởi chính giấc trưa) — giấc trưa phải thấp hơn nền này ≥ 12 bpm mới coi là cú tụt thật.
        let baseline = percentile(smoothed.map(\.bpm), 0.65)

        // 4) Khoảng cách tối đa giữa 2 mẫu trong cùng một đoạn: nới theo nhịp lấy mẫu thật của nguồn
        //    (Fitbit/mock có thể 15 phút/mẫu) nhưng vẫn tôn trọng quy tắc gộp ≤ 5 phút cho dữ liệu dày.
        let dt = medianInterval(smoothed.map(\.time))
        let adjacency = max(mergeGap, dt * 1.5)

        // 5) Gom các đoạn liên tục có nhịp ≤ ceiling.
        var runs: [[(time: Date, bpm: Double)]] = []
        for p in smoothed where p.bpm <= ceiling {
            if var last = runs.last, let prev = last.last,
               p.time.timeIntervalSince(prev.time) <= adjacency {
                last.append(p)
                runs[runs.count - 1] = last
            } else {
                runs.append([p])
            }
        }

        // 6) Mỗi đoạn → một giấc nếu đủ dài, không quá dài, và thấp hơn nền rõ rệt.
        var out: [NapSummary] = []
        for run in runs {
            guard let first = run.first, let last = run.last else { continue }
            let duration = last.time.timeIntervalSince(first.time)
            guard duration >= minDuration, duration <= maxDuration else { continue }
            let avg = run.map(\.bpm).reduce(0, +) / Double(run.count)
            // CHỐT: đáy đoạn phải chạm sát mức nghỉ (ngủ thật) — loại lúc chỉ ngồi nghỉ (đáy còn cao).
            let minBpm = run.map(\.bpm).min() ?? avg
            guard minBpm <= rest + nearRestingMargin else { continue }
            // Và phải là cú tụt rõ khỏi nền hoạt động ban ngày.
            guard baseline - avg >= belowBaseline else { continue }
            out.append(NapSummary(start: first.time, end: last.time, stages: nil, estimated: true))
        }
        return out
    }

    // MARK: - Chẩn đoán (để hiểu vì sao hôm nay chưa ghi được giấc + canh ngưỡng đúng)

    struct Diagnostics {
        var resting: Double          // nhịp nghỉ app dùng
        var baseline: Double         // nền nhịp ban ngày (phân vị 65%)
        var lowestBpm: Double        // nhịp thấp nhất ban ngày (đã làm mượt)
        var lowestAt: Date?          // lúc thấp nhất
        var longestLowRunMinutes: Double  // đoạn nhịp ≤ (nghỉ+10) dài nhất
        var reachedResting: Bool     // đáy có chạm sát mức nghỉ không
        var belowBaselineEnough: Bool
        var reason: String           // câu tiếng Việt vì sao ghi/chưa ghi
    }

    /// Phân tích nhịp tim ban ngày để biết vì sao có/không ra giấc trưa (hiện cho người dùng + canh ngưỡng).
    static func diagnose(_ points: [(time: Date, bpm: Double)], resting: Double?, day: Date) -> Diagnostics? {
        let cal = Calendar.current
        let daypoints = points
            .filter { cal.isDate($0.time, inSameDayAs: day) }
            .filter { let h = cal.component(.hour, from: $0.time); return h >= dayStartHour && h < dayEndHour }
            .sorted { $0.time < $1.time }
        guard daypoints.count >= 3 else { return nil }
        let smoothed = movingAverage(daypoints, window: smoothingWindow)
        let rest = resting ?? percentile(smoothed.map(\.bpm), 0.15)
        let baseline = percentile(smoothed.map(\.bpm), 0.65)
        let ceiling = rest + restingMargin
        let dt = medianInterval(smoothed.map(\.time))
        let adjacency = max(mergeGap, dt * 1.5)

        // Đoạn ≤ ceiling dài nhất.
        var runs: [[(time: Date, bpm: Double)]] = []
        for p in smoothed where p.bpm <= ceiling {
            if var last = runs.last, let prev = last.last, p.time.timeIntervalSince(prev.time) <= adjacency {
                last.append(p); runs[runs.count - 1] = last
            } else { runs.append([p]) }
        }
        let longest = runs.max { ($0.last!.time.timeIntervalSince($0.first!.time)) < ($1.last!.time.timeIntervalSince($1.first!.time)) }
        let longestMin = longest.map { $0.last!.time.timeIntervalSince($0.first!.time) / 60 } ?? 0
        let runMin = longest?.map(\.bpm).min() ?? smoothed.map(\.bpm).min() ?? 0
        let runAvg = longest.map { $0.map(\.bpm).reduce(0, +) / Double($0.count) } ?? baseline
        let low = smoothed.min { $0.bpm < $1.bpm }

        let reached = runMin <= rest + nearRestingMargin
        let belowOK = baseline - runAvg >= belowBaseline
        let reason: String
        if longestMin < minDuration / 60 {
            reason = "Đoạn nhịp thấp dài nhất chỉ \(Int(longestMin)) phút (cần ≥ 10). Có thể giấc quá ngắn hoặc nhịp dao động."
        } else if !reached {
            reason = "Đáy nhịp \(Int(runMin)) chưa chạm sát mức nghỉ \(Int(rest)) (cần ≤ \(Int(rest + nearRestingMargin)))."
        } else if !belowOK {
            reason = "Nhịp chưa tụt đủ sâu so với nền ban ngày \(Int(baseline)) (cần thấp hơn ≥ 12)."
        } else {
            reason = "Đủ điều kiện — sẽ được ghi nhận."
        }
        return Diagnostics(resting: rest, baseline: baseline,
                           lowestBpm: low?.bpm ?? runMin, lowestAt: low?.time,
                           longestLowRunMinutes: longestMin,
                           reachedResting: reached, belowBaselineEnough: belowOK, reason: reason)
    }

    // MARK: - Helpers

    /// Trung bình trượt theo cửa sổ thời gian (căn giữa mỗi điểm).
    private static func movingAverage(_ pts: [(time: Date, bpm: Double)],
                                      window: TimeInterval) -> [(time: Date, bpm: Double)] {
        guard window > 0 else { return pts }
        let half = window / 2
        return pts.map { p in
            let near = pts.filter { abs($0.time.timeIntervalSince(p.time)) <= half }
            let avg = near.map(\.bpm).reduce(0, +) / Double(max(1, near.count))
            return (p.time, avg)
        }
    }

    /// Phân vị `q` (0…1) của một mảng số (dùng cho nhịp nghỉ thay thế & nền ban ngày).
    private static func percentile(_ values: [Double], _ q: Double) -> Double {
        let xs = values.sorted()
        guard !xs.isEmpty else { return 0 }
        let idx = Int((Double(xs.count - 1) * q).rounded())
        return xs[min(max(0, idx), xs.count - 1)]
    }

    /// Khoảng cách trung vị giữa các mốc thời gian liên tiếp (để ước lượng nhịp lấy mẫu của nguồn).
    private static func medianInterval(_ times: [Date]) -> TimeInterval {
        guard times.count >= 2 else { return 60 }
        var gaps: [TimeInterval] = []
        for i in 1..<times.count { gaps.append(times[i].timeIntervalSince(times[i - 1])) }
        gaps.sort()
        return gaps[gaps.count / 2]
    }
}
