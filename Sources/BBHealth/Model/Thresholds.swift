import SwiftUI

/// Mức đánh giá theo ngưỡng cá nhân: tốt (xanh lá mềm) · cần chú ý (hổ phách) · nên cải thiện (san hô).
enum MetricLevel {
    case good, caution, bad, unknown

    var color: Color {
        switch self {
        case .good: return Theme.good
        case .caution: return Theme.caution
        case .bad: return Theme.improve
        case .unknown: return Theme.neutral
        }
    }

    var label: String {
        switch self {
        case .good: return "Tốt"
        case .caution: return "Cần chú ý"
        case .bad: return "Nên cải thiện"
        case .unknown: return "Chưa có số"
        }
    }
}

/// Các chỉ số trên màn Hôm nay. HRV và nhiệt độ da chỉ hiện khi nguồn Google có số.
enum Metric: String, CaseIterable, Identifiable {
    case sleep, restingHeartRate, steps, bodyMass, heartRateVariability, skinTemperature
    // T-020: sinh hiệu & vận động (mục "Sinh hiệu & vận động" ở Hôm nay).
    case respiratoryRate, oxygenSaturation, distance, activeEnergy, activeHours, heartRateRange
    // T-021: nhịp tim trực tiếp qua Bluetooth từ vòng.
    case liveHeartRate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep: return "Giấc ngủ"
        case .restingHeartRate: return "Nhịp tim nghỉ"
        case .steps: return "Bước chân"
        case .bodyMass: return "Cân nặng"
        case .heartRateVariability: return "Biến thiên nhịp tim"
        case .skinTemperature: return "Nhiệt độ da"
        case .respiratoryRate: return "Nhịp thở"
        case .oxygenSaturation: return "Oxy máu"
        case .distance: return "Quãng đường"
        case .activeEnergy: return "Calo vận động"
        case .activeHours: return "Giờ vận động"
        case .heartRateRange: return "Nhịp tim trong ngày"
        case .liveHeartRate: return "Nhịp tim trực tiếp"
        }
    }

    var unit: String {
        switch self {
        case .sleep: return "giờ"
        case .restingHeartRate: return "lần/phút"
        case .steps: return "bước"
        case .bodyMass: return "kg"
        case .heartRateVariability: return "ms"
        case .skinTemperature: return "°C"
        case .respiratoryRate: return "lần/phút"
        case .oxygenSaturation: return "%"
        case .distance: return "km"
        case .activeEnergy: return "kcal"
        case .activeHours: return "/ 9 giờ"
        case .heartRateRange: return "lần/phút"
        case .liveHeartRate: return "lần/phút"
        }
    }

    var symbol: String {
        switch self {
        case .sleep: return "bed.double.fill"
        case .restingHeartRate: return "heart.fill"
        case .steps: return "figure.walk"
        case .bodyMass: return "scalemass.fill"
        case .heartRateVariability: return "waveform.path.ecg"
        case .skinTemperature: return "thermometer.medium"
        case .respiratoryRate: return "lungs.fill"
        case .oxygenSaturation: return "drop.fill"
        case .distance: return "map.fill"
        case .activeEnergy: return "flame.fill"
        case .activeHours: return "clock.badge.checkmark.fill"
        case .heartRateRange: return "heart.text.square.fill"
        case .liveHeartRate: return "dot.radiowaves.left.and.right"
        }
    }

    /// Màu riêng của chỉ số (nhuộm nền thẻ, icon).
    var tint: Color {
        switch self {
        case .sleep: return Theme.sleep
        case .restingHeartRate: return Theme.heart
        case .steps: return Theme.steps
        case .bodyMass: return Theme.weight
        case .heartRateVariability: return Theme.hrv
        case .skinTemperature: return Theme.temp
        case .respiratoryRate: return Theme.breath
        case .oxygenSaturation: return Theme.oxygen
        case .distance: return Theme.steps
        case .activeEnergy: return Theme.energy
        case .activeHours: return Theme.brand
        case .heartRateRange: return Theme.heart
        case .liveHeartRate: return Theme.heart
        }
    }
}

/// Ngưỡng cá nhân — mục tiêu (ngủ/bước/cân/tuổi) đọc từ **Hồ sơ của tôi** (`HealthProfileStore`,
/// mặc định trống — người dùng tự điền). Các ngưỡng sinh hiệu còn lại là
/// mức tham khảo chung. Không phải chuẩn y khoa.
enum Thresholds {
    /// Giờ ngủ: ≥ mục tiêu xanh · thiếu < 1 giờ vàng · thiếu nhiều đỏ (mặc định 7 / 6–7 / < 6).
    static func sleep(hours: Double?) -> MetricLevel {
        guard let h = hours else { return .unknown }
        if h >= sleepGoalHours { return .good }
        if h >= sleepGoalHours - 1 { return .caution }
        return .bad
    }

    /// Nhịp tim nghỉ: ≤70 xanh · 71–85 vàng · >85 đỏ.
    static func restingHeartRate(bpm: Double?) -> MetricLevel {
        guard let b = bpm else { return .unknown }
        if b <= 70 { return .good }
        if b <= 85 { return .caution }
        return .bad
    }

    /// Bước: ≥ mục tiêu xanh · ≥ nửa mục tiêu vàng · dưới nữa đỏ (mặc định 6.000 / 3.000).
    static func steps(_ count: Int?) -> MetricLevel {
        guard let c = count else { return .unknown }
        if c >= stepsGoal { return .good }
        if c >= stepsGoal / 2 { return .caution }
        return .bad
    }

    /// Cân — theo hướng mục tiêu trong hồ sơ:
    /// tăng cân: ≥ mục tiêu xanh · thiếu ≤ 3 kg vàng · thiếu nhiều đỏ (mặc định 53 / 50–53 / < 50);
    /// giảm cân: ngược lại; giữ cân: lệch ≤ 1 kg xanh · ≤ 3 kg vàng.
    static func bodyMass(kg: Double?) -> MetricLevel {
        guard let k = kg else { return .unknown }
        let goal = weightGoalKg
        switch HealthProfileStore.current.weightDirection {
        case .gain:
            if k >= goal { return .good }
            if k >= goal - 3 { return .caution }
            return .bad
        case .lose:
            if k <= goal { return .good }
            if k <= goal + 3 { return .caution }
            return .bad
        case .keep:
            let d = abs(k - goal)
            if d <= 1 { return .good }
            if d <= 3 { return .caution }
            return .bad
        }
    }

    /// HRV (ms): càng cao càng hồi phục tốt. ≥40 xanh · 25–40 vàng · <25 đỏ (tham khảo theo xu hướng).
    static func heartRateVariability(ms: Double?) -> MetricLevel {
        guard let v = ms else { return .unknown }
        if v >= 40 { return .good }
        if v >= 25 { return .caution }
        return .bad
    }

    /// Nhiệt độ da: chênh lệch so với nền. |Δ|≤0,4 xanh · ≤0,9 vàng · >0,9 đỏ (có thể sắp ốm/thiếu ngủ).
    static func skinTemperature(delta: Double?) -> MetricLevel {
        guard let v = delta else { return .unknown }
        let a = abs(v)
        if a <= 0.4 { return .good }
        if a <= 0.9 { return .caution }
        return .bad
    }

    // MARK: - Sinh hiệu & vận động (T-020)

    /// Nhịp thở lúc ngủ (lần/phút): 12–20 xanh · 10–12 hoặc 20–24 vàng · < 10 hoặc > 24 đỏ.
    static func respiratoryRate(_ v: Double?) -> MetricLevel {
        guard let v else { return .unknown }
        if v < 10 || v > 24 { return .bad }
        if v >= 12 && v <= 20 { return .good }
        return .caution
    }

    /// Oxy máu (SpO2 %) lúc ngủ: ≥ 95 xanh · 92–94 vàng · < 92 đỏ.
    static func oxygenSaturation(_ v: Double?) -> MetricLevel {
        guard let v else { return .unknown }
        if v >= 95 { return .good }
        if v >= 92 { return .caution }
        return .bad
    }

    /// Quãng đường (mục tiêu nhẹ — anh thiếu cân, không cần đi nhiều): ≥ 3 km xanh · 1–3 vàng · < 1 đỏ.
    static func distance(km: Double?) -> MetricLevel {
        guard let v = km else { return .unknown }
        if v >= 3 { return .good }
        if v >= 1 { return .caution }
        return .bad
    }

    /// Giờ vận động (số giờ có ≥ 250 bước, như Google Health): ≥ 9 xanh · 5–8 vàng · < 5 đỏ.
    static func activeHours(_ h: Int?) -> MetricLevel {
        guard let h else { return .unknown }
        if h >= 9 { return .good }
        if h >= 5 { return .caution }
        return .bad
    }

    /// Calo vận động: KHÔNG chấm điểm (anh thiếu cân — đốt nhiều không phải mục tiêu).
    static func activeEnergy(_ kcal: Double?) -> MetricLevel { .unknown }

    /// Nhịp tim trong ngày (dải thấp–cao): đỏ khi lúc thấp nhất < 40 hoặc cao nhất > 150 (khi ngồi yên
    /// hiếm gặp), vàng khi thấp < 45 hoặc cao > 120, còn lại xanh. Chỉ tham khảo — vận động làm tim lên cao.
    static func heartRateRange(min lo: Double?, max hi: Double?) -> MetricLevel {
        guard let lo, let hi else { return .unknown }
        if lo < 40 || hi > 150 { return .bad }
        if lo < 45 || hi > 120 { return .caution }
        return .good
    }

    // MARK: - Nhịp tim trực tiếp (T-021)

    /// Tuổi theo hồ sơ — dùng ước nhịp tim tối đa ≈ 220 − tuổi.
    static var ownerAge: Int { max(10, HealthProfileStore.current.age) }

    /// Vùng cường độ theo % nhịp tối đa (220 − tuổi; vd 36 tuổi ≈ 184):
    /// < 50% Nghỉ ngơi · 50–60% Nhẹ · 60–70% Vừa · 70–85% Gắng sức · ≥ 85% Rất mạnh.
    static func liveHeartRateZone(bpm: Int, age: Int = ownerAge) -> LiveHeartZone {
        let maxHR = Double(max(220 - age, 100))
        let pct = Double(bpm) / maxHR
        switch pct {
        case ..<0.50: return .rest
        case ..<0.60: return .light
        case ..<0.70: return .moderate
        case ..<0.85: return .hard
        default: return .peak
        }
    }

    /// Các mức ngưỡng để hiện trong sheet giải thích.
    static func bands(for metric: Metric) -> [(level: MetricLevel, range: String)] {
        switch metric {
        case .sleep:
            let g = TodayViewModel.decimal(sleepGoalHours, digits: sleepGoalHours.rounded() == sleepGoalHours ? 0 : 1)
            let c = TodayViewModel.decimal(sleepGoalHours - 1, digits: sleepGoalHours.rounded() == sleepGoalHours ? 0 : 1)
            return [(.good, "≥ \(g) giờ"), (.caution, "\(c)–\(g) giờ"), (.bad, "< \(c) giờ")]
        case .restingHeartRate: return [(.good, "≤ 70"), (.caution, "71–85"), (.bad, "> 85")]
        case .steps:
            let g = TodayViewModel.grouped(stepsGoal), h = TodayViewModel.grouped(stepsGoal / 2)
            return [(.good, "≥ \(g)"), (.caution, "\(h)–\(g)"), (.bad, "< \(h)")]
        case .bodyMass:
            let g = TodayViewModel.decimal(weightGoalKg, digits: 0)
            switch HealthProfileStore.current.weightDirection {
            case .gain:
                let lo = TodayViewModel.decimal(weightGoalKg - 3, digits: 0)
                return [(.good, "≥ \(g) kg"), (.caution, "\(lo)–\(g) kg"), (.bad, "< \(lo) kg")]
            case .lose:
                let hi = TodayViewModel.decimal(weightGoalKg + 3, digits: 0)
                return [(.good, "≤ \(g) kg"), (.caution, "\(g)–\(hi) kg"), (.bad, "> \(hi) kg")]
            case .keep:
                return [(.good, "\(g) ± 1 kg"), (.caution, "± 3 kg"), (.bad, "lệch > 3 kg")]
            }
        case .heartRateVariability: return [(.good, "≥ 40 ms"), (.caution, "25–40 ms"), (.bad, "< 25 ms")]
        case .skinTemperature: return [(.good, "±0,4 °C"), (.caution, "±0,9 °C"), (.bad, "> ±0,9")]
        case .respiratoryRate: return [(.good, "12–20"), (.caution, "20–24"), (.bad, "> 24 · < 10")]
        case .oxygenSaturation: return [(.good, "≥ 95%"), (.caution, "92–94%"), (.bad, "< 92%")]
        case .distance: return [(.good, "≥ 3 km"), (.caution, "1–3 km"), (.bad, "< 1 km")]
        case .activeEnergy: return []
        case .activeHours: return [(.good, "≥ 9 giờ"), (.caution, "5–8 giờ"), (.bad, "< 5 giờ")]
        case .heartRateRange: return [(.good, "45–120"), (.caution, "< 45 · > 120"), (.bad, "< 40 · > 150")]
        // Vùng cường độ có 5 bậc (không phải tốt/xấu) → hiện riêng trong màn trực tiếp.
        case .liveHeartRate: return []
        }
    }

    /// Mục tiêu — đọc từ hồ sơ (mặc định 7 giờ · 6.000 bước · 53 kg).
    static var sleepGoalHours: Double { HealthProfileStore.current.sleepGoalHours }
    static var stepsGoal: Int { HealthProfileStore.current.stepsGoal }
    static var weightGoalKg: Double { HealthProfileStore.current.weightGoalKg }
    /// Chuỗi mục tiêu để ghép câu ("7 giờ", "6.000", "53 kg").
    static var sleepGoalText: String {
        TodayViewModel.decimal(sleepGoalHours, digits: sleepGoalHours.rounded() == sleepGoalHours ? 0 : 1) + " giờ"
    }
    static var stepsGoalText: String { TodayViewModel.grouped(stepsGoal) }
    static var weightGoalText: String { TodayViewModel.decimal(weightGoalKg, digits: 0) + " kg" }
}

/// Vùng cường độ của nhịp tim trực tiếp (tên tiếng Việt, màu xanh → đỏ).
enum LiveHeartZone: Int, CaseIterable, Identifiable {
    case rest, light, moderate, hard, peak

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .rest: return "Nghỉ ngơi"
        case .light: return "Nhẹ"
        case .moderate: return "Vừa"
        case .hard: return "Gắng sức"
        case .peak: return "Rất mạnh"
        }
    }

    /// Khoảng % nhịp tối đa (để hiện thang vùng).
    var percentRange: ClosedRange<Double> {
        switch self {
        case .rest: return 0...0.50
        case .light: return 0.50...0.60
        case .moderate: return 0.60...0.70
        case .hard: return 0.70...0.85
        case .peak: return 0.85...1.0
        }
    }

    /// Khoảng bpm theo tuổi (vd "< 92", "92–110", "≥ 156").
    func bpmRangeText(age: Int = Thresholds.ownerAge) -> String {
        let maxHR = Double(max(220 - age, 100))
        let lo = Int((percentRange.lowerBound * maxHR).rounded())
        let hi = Int((percentRange.upperBound * maxHR).rounded())
        switch self {
        case .rest: return "< \(hi)"
        case .peak: return "≥ \(lo)"
        default: return "\(lo)–\(hi - 1)"
        }
    }

    var color: Color {
        switch self {
        case .rest: return Theme.good
        case .light: return Theme.brand
        case .moderate: return Theme.caution
        case .hard: return Theme.energy
        case .peak: return Theme.improve
        }
    }

    /// Mức tương ứng cho chip trạng thái chung.
    var level: MetricLevel {
        switch self {
        case .rest, .light: return .good
        case .moderate, .hard: return .caution
        case .peak: return .bad
        }
    }

    /// Một câu đời thường cho vùng này.
    var note: String {
        switch self {
        case .rest: return "Tim đang nghỉ — như lúc ngồi yên, đọc sách, nằm nghỉ."
        case .light: return "Vận động nhẹ — như đi bộ chậm, làm việc nhà nhẹ."
        case .moderate: return "Vận động vừa — như đi bộ nhanh, vẫn nói chuyện được."
        case .hard: return "Gắng sức — thở dốc, nói câu dài thấy mệt. Đừng giữ lâu."
        case .peak: return "Rất mạnh — gần sức tối đa. Nếu đang ngồi yên mà tim lên vùng này thì nên dừng lại, nghỉ ngơi."
        }
    }
}
