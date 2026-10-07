import Foundation

/// Số giả **tất định** theo ngày (cùng một ngày luôn ra cùng số) để màn Hôm nay và Xu hướng
/// trên simulator/preview trông tự nhiên và ổn định qua mỗi lần tải lại.
enum MockData {
    /// Số ngẫu nhiên ổn định trong [0,1) theo (ngày, kênh).
    private static func noise(_ date: Date, _ channel: Int) -> Double {
        let day = Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970 / 86_400)
        var x = UInt64(bitPattern: Int64(day &* 73_856_093 ^ channel &* 19_349_663))
        x ^= x >> 33; x = x &* 0xff51afd7ed558ccd; x ^= x >> 33
        return Double(x % 10_000) / 10_000
    }

    static func sleepHours(_ date: Date) -> Double {
        // Trung bình ~5,6h, cuối tuần khá hơn chút.
        let weekday = Calendar.current.component(.weekday, from: date)
        let base = (weekday == 1 || weekday == 7) ? 6.3 : 5.4
        return (base + noise(date, 1) * 1.4 - 0.3).rounded(toPlaces: 1)
    }

    static func awakeCount(_ date: Date) -> Int { Int(noise(date, 2) * 3.0) }

    static func restingHeartRate(_ date: Date) -> Double {
        (66 + noise(date, 3) * 12).rounded()
    }

    static func steps(_ date: Date) -> Int {
        Int(2_800 + noise(date, 4) * 4_400)
    }

    /// Cân tăng đều nhẹ theo thời gian quanh mục tiêu cân trong hồ sơ.
    static func weight(_ date: Date, latest: Date = Date()) -> Double {
        let daysAgo = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date),
                                                       to: Calendar.current.startOfDay(for: latest)).day ?? 0
        let trend = 48.4 - Double(daysAgo) * 0.02
        return (trend + noise(date, 5) * 0.4 - 0.2).rounded(toPlaces: 1)
    }

    static func hrv(_ date: Date) -> Double {
        (30 + noise(date, 6) * 20).rounded()
    }

    /// Chênh lệch nhiệt độ da so với nền (°C), quanh 0.
    static func skinTempDelta(_ date: Date) -> Double {
        (noise(date, 7) * 1.0 - 0.4).rounded(toPlaces: 1)
    }

    // MARK: - Sinh hiệu & vận động (T-020)

    /// Nhịp thở đêm ~14–18 lần/phút.
    static func respiratoryRate(_ date: Date) -> Double {
        (14 + noise(date, 220) * 4).rounded(toPlaces: 1)
    }

    /// Oxy máu đêm ~95–98 %.
    static func oxygenSaturation(_ date: Date) -> Double {
        (95 + noise(date, 221) * 3).rounded(toPlaces: 0)
    }

    /// Quãng đường ~ số bước × 0,7 m (bước chân người cao ~1,70 m) → 2–5 km, kèm dao động nhỏ.
    static func distanceKm(_ date: Date) -> Double {
        (Double(steps(date)) * 0.00070 + noise(date, 222) * 0.6).rounded(toPlaces: 1)
    }

    /// Calo vận động ~250–600 kcal, đi nhiều thì đốt nhiều.
    static func activeEnergyKcal(_ date: Date) -> Double {
        (180 + Double(steps(date)) * 0.045 + noise(date, 223) * 90).rounded()
    }

    /// Bước theo giờ: rải tổng bước của ngày vào các giờ thức (7h–22h), vài giờ đi nhiều (đi làm,
    /// sau bữa trưa/tối). Hôm nay chỉ tới giờ hiện tại (tôn trọng `-BBHNow` qua `date` mang HH:mm).
    static func hourlySteps(_ date: Date, now: Date = Date()) -> [(hour: Int, steps: Int)] {
        let cal = Calendar.current
        let clock = max(now, date)
        let lastHour = cal.isDate(date, inSameDayAs: now) ? cal.component(.hour, from: clock) : 23
        let total = Double(steps(date))
        // Trọng số mỗi giờ: ngủ ~0, giờ đi lại nhiều cao.
        let weights: [Double] = (0..<24).map { h in
            switch h {
            case 0..<6: return 0
            case 6: return 0.3
            case 7, 8: return 1.6                  // đi làm
            case 12, 13: return 1.4                 // đi ăn trưa
            case 17, 18: return 1.7                 // về nhà
            case 19, 20: return 1.2                 // đi bộ sau bữa tối
            case 21, 22: return 0.4
            case 23: return 0.05
            default: return 0.5 + noise(date, 230 + h) * 0.7 // giờ ngồi làm
            }
        }
        let sum = weights.reduce(0, +)
        return (0...max(0, lastHour)).map { h in
            (h, Int(total * weights[h] / sum * (0.8 + noise(date, 260 + h) * 0.4)))
        }
    }

    /// Nhịp tim theo giờ trong ngày (mỗi 15 phút): thấp lúc ngủ, cao buổi chiều — đường cong thực tế.
    /// Nếu là hôm nay thì chỉ sinh tới giờ hiện tại (chưa có số cho giờ chưa đến).
    static func intradayHeartRate(_ date: Date, now: Date = Date()) -> [(time: Date, bpm: Double)] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        // Hôm nay chỉ sinh tới "bây giờ"; tôn trọng giờ giả lập `-BBHNow` khi `date` mang HH:mm
        // (giống `daytimeSleeps`) để ảnh chụp màn ổn định, không phụ thuộc đồng hồ thật của máy.
        let clock = max(now, date)
        let end = cal.isDate(date, inSameDayAs: now) ? min(clock, dayEnd) : dayEnd
        guard end > start else { return [] }
        let resting = restingHeartRate(date)
        var out: [(time: Date, bpm: Double)] = []
        var t = start
        var i = 0
        while t < end {
            let hour = t.timeIntervalSince(start) / 3600 // 0…24
            // Chênh so với nhịp nghỉ theo giờ trong ngày.
            let curve: Double
            switch hour {
            case 0..<6:   curve = -8                              // ngủ sâu
            case 6..<9:   curve = (hour - 6) / 3 * 20 - 6        // thức dậy, tăng dần
            case 9..<12:  curve = 16                              // buổi sáng
            case 12..<17: curve = 24                              // buổi chiều cao nhất
            case 17..<21: curve = 14                              // chiều tối
            default:      curve = max(-6, 6 - (hour - 21) / 3 * 14) // tối muộn, hạ dần
            }
            let wobble = (noise(date, 200 + i) - 0.5) * 10
            var bpm = max(45, (resting + curve + wobble).rounded())
            // HÔM NAY: tái hiện một **giấc trưa ngắn mà Fitbit KHÔNG ghi thành phiên ngủ** — nhịp tim
            // tụt sát mức nghỉ khoảng 14:00–14:35 (giống ví dụ anh đưa: ~60 khi nghỉ 59) để
            // `NapDetector` bắt được thành một giấc "ước tính". `daytimeSleeps` hôm nay cố ý để trống.
            if cal.isDate(date, inSameDayAs: now),
               let napStart = cal.date(bySettingHour: 14, minute: 0, second: 0, of: start),
               let napEnd = cal.date(bySettingHour: 14, minute: 35, second: 0, of: start),
               t >= napStart, t < napEnd {
                bpm = (resting + 1).rounded()      // nhịp lúc chợp mắt: sát ngay trên mức nghỉ
            }
            out.append((t, bpm))
            t = t.addingTimeInterval(15 * 60)
            i += 1
        }
        return out
    }

    /// Dải thấp–cao nhịp tim + nhịp nghỉ của một ngày (cho chế độ Tuần/Tháng), tất định theo ngày.
    /// Thấp nhất quanh lúc ngủ, cao nhất lúc vận động buổi chiều — hợp lý quanh nhịp nghỉ.
    static func heartRateDailyRange(_ date: Date) -> (min: Double, max: Double, resting: Double) {
        let resting = restingHeartRate(date)
        let lo = max(45, resting - (6 + noise(date, 210) * 7))      // lúc ngủ sâu
        let hi = resting + (24 + noise(date, 211) * 34)             // vận động buổi chiều
        return (lo.rounded(), hi.rounded(), resting)
    }

    /// Sinh hypnogram hợp lý: chu kỳ ~90 phút, sâu nhiều nửa đầu, REM nhiều nửa cuối, vài lần thức ngắn.
    /// Một số đêm (gồm **hôm nay**) tái hiện đêm **ngắt quãng**: ngủ ~3h → thức dài ~2,5h → ngủ lại ~1–1.5h.
    static func sleepDetail(_ date: Date) -> SleepDetail {
        let s = sleepSummary(date)
        guard let bed = s.bedTime else { return SleepDetail(segments: []) }

        // Hôm nay luôn ngắt quãng (để kiểm trên sim); vài đêm khác cũng vậy cho giống thực tế.
        if Calendar.current.isDateInToday(date) || noise(date, 90) > 0.62 {
            return brokenNight(date: date, bed: bed)
        }

        guard let wake = s.wakeTime, wake > bed else { return SleepDetail(segments: []) }
        var segs: [SleepSegment] = []
        var t = bed
        func push(_ stage: SleepStage, _ minutes: Double) {
            guard minutes > 0, t < wake else { return }
            let end = min(wake, t.addingTimeInterval(minutes * 60))
            segs.append(SleepSegment(stage: stage, start: t, end: end))
            t = end
        }
        // Thiu thiu đầu giấc.
        push(.light, 6 + noise(date, 20) * 8)
        let total = wake.timeIntervalSince(t) / 60
        let cycleLen = 90.0
        let cycles = max(3, Int(total / cycleLen))
        let awakeTarget = awakeCount(date)
        var awakeDone = 0
        for i in 0..<cycles {
            let firstHalf = Double(i) < Double(cycles) / 2
            let deep = firstHalf ? 22 + noise(date, 30 + i) * 12 : 6 + noise(date, 30 + i) * 6
            let rem = firstHalf ? 8 + noise(date, 40 + i) * 6 : 16 + noise(date, 40 + i) * 12
            let light = 30 + noise(date, 50 + i) * 12
            push(.light, light * 0.5)
            push(.deep, deep)
            push(.light, light * 0.5)
            push(.rem, rem)
            // Chèn thức ngắn giữa vài chu kỳ.
            if awakeDone < awakeTarget && i > 0 && noise(date, 60 + i) > 0.4 {
                push(.awake, 4 + noise(date, 70 + i) * 8)
                awakeDone += 1
            }
        }
        // Lấp phần còn lại bằng nông.
        if t < wake { push(.light, wake.timeIntervalSince(t) / 60) }
        return SleepDetail(segments: SleepDetail.fillingAwakeGaps(segs))
    }

    /// Đêm **ngắt quãng**: ngủ ~3h đầu → **CHỪA một khoảng trống ~2,5h** (không push đoạn nào, để
    /// `fillingAwakeGaps` lấp thành THỨC — đúng cách Fitbit để trống lúc thức) → ngủ lại ~1–1.5h.
    /// Mục tiêu: tổng ngủ ~4–4.5h, thức ~2,5–3h, hiệu suất ~55–65%, `awakeCount` = 1.
    private static func brokenNight(date: Date, bed: Date) -> SleepDetail {
        var segs: [SleepSegment] = []
        var t = bed
        func push(_ stage: SleepStage, _ minutes: Double) {
            guard minutes > 0 else { return }
            let end = t.addingTimeInterval(minutes * 60)
            segs.append(SleepSegment(stage: stage, start: t, end: end))
            t = end
        }
        // ~3h ngủ đầu (nhiều ngủ sâu nửa đầu giấc).
        push(.light, 8 + noise(date, 20) * 6)
        push(.deep, 40 + noise(date, 31) * 14)
        push(.light, 28 + noise(date, 51) * 10)
        push(.rem, 14 + noise(date, 41) * 8)
        push(.deep, 24 + noise(date, 32) * 12)
        push(.light, 30 + noise(date, 52) * 10)
        // CHỪA GAP ~140–175 phút = thức dài giữa đêm. KHÔNG push gì, chỉ nhảy con trỏ thời gian.
        let gap = 140 + noise(date, 95) * 35
        t = t.addingTimeInterval(gap * 60)
        // Ngủ lại ~1–1.5h (nông + ít REM cuối giấc).
        push(.light, 24 + noise(date, 53) * 10)
        push(.rem, 16 + noise(date, 42) * 10)
        push(.light, 18 + noise(date, 54) * 8)
        return SleepDetail(segments: SleepDetail.fillingAwakeGaps(segs))
    }

    /// Giấc ngủ trưa/ngủ ngày giả **tất định** theo ngày: ~72% ngày có 1 giấc quanh 13:00 (12–28 phút),
    /// thỉnh thoảng thêm giấc chiều ngắn ~15:20 → để xem Card & màn Giấc ngủ trưa trên simulator.
    /// Chỉ trả giấc đã **kết thúc trước giờ hiện tại** (tôn trọng `-BBHNow` khi chụp màn).
    static func daytimeSleeps(_ date: Date, now: Date = Date()) -> [NapSummary] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        // Mốc giờ "bây giờ": lấy giá trị muộn hơn giữa đồng hồ thật và `date` (date mang HH:mm khi -BBHNow).
        let clock = max(now, date)
        var out: [NapSummary] = []
        // HÔM NAY cố ý KHÔNG có phiên ngủ Fitbit → để minh hoạ giấc trưa chỉ bắt được qua HR-dò
        // (xem dip nhịp tim 14:00–14:35 trong `intradayHeartRate`). Các ngày khác vẫn có phiên thật.
        if cal.isDate(date, inSameDayAs: now) { return [] }
        guard noise(date, 80) > 0.28 else { return [] }   // ~72% ngày có giấc trưa

        // Giấc chính quanh 13:00–13:35, dài 12–28 phút.
        let startMin = 13 * 60 + Int(noise(date, 81) * 35)
        let dur = 12 + Int(noise(date, 82) * 16)
        if let s = cal.date(byAdding: .minute, value: startMin, to: dayStart),
           let e = cal.date(byAdding: .minute, value: dur, to: s), e <= clock {
            out.append(NapSummary(start: s, end: e, stages: nil))
        }
        // ~15% ngày có thêm giấc chiều ngắn ~15:20, 10–30 phút (minh hoạ giấc dài/muộn).
        if noise(date, 83) > 0.85 {
            let s2 = 15 * 60 + 20
            if let s = cal.date(byAdding: .minute, value: s2, to: dayStart),
               let e = cal.date(byAdding: .minute, value: 10 + Int(noise(date, 84) * 24), to: s), e <= clock {
                out.append(NapSummary(start: s, end: e, stages: nil))
            }
        }
        return out
    }

    static func sleepSummary(_ date: Date) -> SleepSummary {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        let hours = sleepHours(date)
        let bedOffset = -(Int(noise(date, 8) * 40) + 60) // 22:20–23:00 hôm trước
        let bed = cal.date(byAdding: .minute, value: bedOffset, to: dayStart)
        let wake = bed.flatMap { cal.date(byAdding: .minute, value: Int(hours * 60), to: $0) }
        return SleepSummary(totalHours: hours, awakeCount: awakeCount(date), bedTime: bed, wakeTime: wake)
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let p = pow(10.0, Double(places))
        return (self * p).rounded() / p
    }
}
