import Foundation

/// Lời giải thích đời thường cho từng chỉ số + dòng "BS dặn" / "Gợi ý".
/// Nội dung tư vấn lối sống chung. 🩺 = lời bác sĩ hay dặn (người dùng ghi lời BS của mình trong Hồ sơ); 💡 = gợi ý của trợ lý.
struct Explanation {
    /// 2–3 câu tiếng Việt đời thường: chỉ số này là gì, vì sao quan trọng với anh.
    let plain: String
    /// Dòng "BS dặn" (bắt buộc theo) — nil nếu BS không dặn cụ thể.
    let doctorNote: String?
    /// Dòng "Gợi ý" (trợ lý gợi ý, có thể điều chỉnh).
    let tip: String
}

/// Đánh giá một chỉ số giấc ngủ: nhãn, giá trị, mức, câu nhận xét, và có phải "BS dặn" không.
struct SleepMetricEval: Identifiable {
    let title: String
    let value: String
    let level: MetricLevel
    /// "vì sao quan trọng" + "nên làm gì" — tiếng Việt đời thường.
    let note: String
    /// true = bám lời BS dặn; false = gợi ý của trợ lý.
    let isDoctor: Bool
    var id: String { title }
}

/// Đánh giá một chỉ số nhịp tim: nhãn, giá trị, mức, câu nhận xét, và có phải "BS dặn" không.
struct HeartMetricEval: Identifiable {
    let title: String
    let value: String
    let level: MetricLevel
    let note: String
    let isDoctor: Bool
    var id: String { title }
}

enum Explanations {
    /// Đánh giá + tư vấn từng chỉ số nhịp tim của một ngày theo ngưỡng cá nhân của bạn.
    /// Giải thích mức cao/thấp **ảnh hưởng gì, có nguy hiểm không**, và **khi nào nên đi khám**.
    static func heartEvaluations(for d: HeartRateDetail) -> [HeartMetricEval] {
        var out: [HeartMetricEval] = []
        func hhmm(_ date: Date) -> String {
            let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: date)
        }

        // 1) Nhịp tim nghỉ — ý nghĩa + mức nguy hiểm.
        if let bpm = d.restingBpm {
            let level = Thresholds.restingHeartRate(bpm: bpm)
            let n = Int(bpm.rounded())
            out.append(HeartMetricEval(
                title: "Nhịp tim nghỉ",
                value: "\(n) lần/phút",
                level: bpm >= 100 ? .bad : level,
                note: {
                    if bpm >= 100 {
                        return "Trên 100 lần/phút lúc nghỉ gọi là **tim đập nhanh**. Nếu đang ngồi yên mà vẫn vậy — nhất là kèm hồi hộp, đau ngực hay khó thở — thì nên đi khám sớm. Rượu bia, thiếu ngủ và mất nước đều làm nhịp nghỉ cao lên."
                    }
                    switch level {
                    case .good: return "Nằm trong vùng tốt (≤ 70 lần/phút) — tim đang được nghỉ ngơi ổn, chưa có gì đáng lo. Giữ nếp ngủ đủ và tránh rượu bia để giữ mức này."
                    case .caution: return "Hơi cao hơn mức tốt. Nhịp nghỉ cao thường do **ngủ ít, rượu bia tối qua, căng thẳng hoặc mất nước** — tim phải làm việc nhiều hơn một chút nhưng **chưa nguy hiểm**. Ngủ đủ và bớt rượu bia vài hôm là nhịp hạ lại."
                    default: return "Cao. Một hôm sau khi thiếu ngủ hoặc uống rượu thì thường tự về; nhưng **nếu nhiều ngày liền trên 85 kèm mệt, hồi hộp** thì nên đo huyết áp và đi khám."
                    }
                }(),
                isDoctor: false))
        }

        // 2) Lúc cao nhất trong ngày — vận động hay bất thường?
        if d.hasIntraday, let hi = d.maxPoint {
            let n = Int(hi.bpm.rounded())
            out.append(HeartMetricEval(
                title: "Lúc cao nhất",
                value: "\(n) · \(hhmm(hi.time))",
                level: hi.bpm > 110 ? .caution : .good,
                note: hi.bpm > 110
                    ? "Có lúc tim đập khá nhanh. Nếu lúc đó anh **đang đi vội, vận động, uống cà phê hay căng thẳng** thì bình thường; nhưng nếu **đang ngồi yên mà tim vẫn nhanh**, kèm hồi hộp/đau ngực/choáng thì nên để ý và đi khám. Hãy **ghi chú sự kiện** vào đúng giờ đó để sau nhìn lại nguyên nhân."
                    : "Tim lên cao khi đi lại, vận động hay hồi hộp là **bình thường** — đó là tim đang đáp ứng tốt. Nếu nhớ lúc đó làm gì (đi nhanh, cà phê, họp căng) thì **ghi chú sự kiện** để sau đối chiếu.",
                isDoctor: false))
        }

        // 3) Lúc thấp nhất trong ngày — nghỉ sâu hay chậm quá?
        if d.hasIntraday, let lo = d.minPoint {
            let n = Int(lo.bpm.rounded())
            out.append(HeartMetricEval(
                title: "Lúc thấp nhất",
                value: "\(n) · \(hhmm(lo.time))",
                level: lo.bpm < 45 ? .caution : .good,
                note: lo.bpm < 45
                    ? "Nhịp xuống khá thấp. Lúc ngủ say nhịp chậm là bình thường; nhưng nếu **ban ngày lúc thức mà thấy chóng mặt, mệt lả hay thỉu đi** thì nên đi khám."
                    : "Nhịp hạ xuống thấp lúc ngủ/nghỉ sâu là **dấu hiệu tốt** — tim được thư giãn, hồi phục.",
                isDoctor: false))
        }

        // 4) HRV (nếu nguồn có).
        if let v = d.hrv {
            let level = Thresholds.heartRateVariability(ms: v)
            out.append(HeartMetricEval(
                title: "Biến thiên nhịp tim (HRV)",
                value: "\(Int(v.rounded())) ms",
                level: level,
                note: {
                    switch level {
                    case .good: return "Cao — cơ thể hồi phục tốt, thần kinh thư giãn. Giữ nếp ngủ, tránh rượu bia buổi tối."
                    case .caution: return "Ở mức vừa. Nhìn xu hướng vài ngày; nếu tụt dần thì để ý ngủ và rượu bia."
                    default: return "Thấp so với thường ngày. Hôm nay nên nghỉ ngơi nhiều hơn, uống đủ nước, tránh rượu bia."
                    }
                }(),
                isDoctor: false))
        }

        // 5) Khi nào cần đi khám — luôn hiện (tư vấn an toàn, gắn hồ sơ của bạn).
        out.append(HeartMetricEval(
            title: "Khi nào nên đi khám",
            value: "",
            level: .caution,
            note: "Đi khám sớm nếu gặp một trong các dấu hiệu: **tim đập nhanh/hồi hộp kéo dài lúc đang nghỉ**; nhịp nghỉ thường xuyên **trên 100 hoặc dưới 45 lần/phút**; hoặc kèm **đau tức ngực, khó thở, chóng mặt, ngất**. Nếu từng đo huyết áp cao — **nên đo lại tại nhà vài ngày** để chắc. Rượu bia và thiếu ngủ làm tim đập nhanh hơn, nên **giảm rượu bia và ngủ đủ** sẽ giúp nhịp tim ổn định. Ứng dụng chỉ để tham khảo, **không thay bác sĩ**.",
            isDoctor: true))

        return out
    }


    /// Đánh giá từng chỉ số của một đêm theo ngưỡng chung + ngưỡng cá nhân của bạn.
    /// `bedtimeStdevMin` = độ lệch giờ đi ngủ 7 đêm (phút); `hadAlcohol` = đêm đó có ghi rượu bia.
    static func sleepEvaluations(for d: SleepDetail, bedtimeStdevMin: Double?, hadAlcohol: Bool) -> [SleepMetricEval] {
        var out: [SleepMetricEval] = []
        func dec(_ v: Double, _ n: Int = 0) -> String {
            let f = NumberFormatter()
            f.locale = Locale(identifier: "vi_VN")
            f.minimumFractionDigits = n
            f.maximumFractionDigits = n
            return f.string(from: v as NSNumber) ?? "\(v)"
        }

        // 1) Tổng ngủ thật.
        let hours = d.asleepHours
        out.append(SleepMetricEval(
            title: "Tổng ngủ thật",
            value: "\(dec(hours, 1)) giờ",
            level: Thresholds.sleep(hours: hours),
            note: hours >= 7
                ? "Đủ giấc — dạ dày có thời gian phục hồi, cơ thể dễ tăng cân. Giữ nếp này."
                : "Chưa đủ 7 giờ. Ngủ đúng giờ, không thức khuya để dạ dày và người khỏe hơn.",
            isDoctor: true))

        // 2) Hiệu suất ngủ.
        let eff = d.efficiency
        out.append(SleepMetricEval(
            title: "Hiệu suất ngủ",
            value: "\(dec(eff))%",
            level: eff >= 85 ? .good : (eff >= 75 ? .caution : .bad),
            note: eff >= 85
                ? "Nằm trên giường bao nhiêu thì ngủ được bấy nhiêu — rất tốt."
                : "Nằm giường nhưng khó ngủ/hay trằn trọc. Tắt máy 22h, phòng tối và mát, không xem điện thoại trên giường.",
            isDoctor: false))

        // 3) Thời gian để thiu thiu.
        let lat = d.latencyMinutes
        out.append(SleepMetricEval(
            title: "Vào giấc (latency)",
            value: "\(dec(lat)) phút",
            level: lat <= 20 ? .good : (lat <= 30 ? .caution : .bad),
            note: lat <= 20
                ? "Đặt lưng xuống là ngủ được sớm — tốt."
                : "Lâu mới ngủ được. Tránh cà phê chiều, không ăn no muộn, thư giãn nhẹ trước khi ngủ.",
            isDoctor: false))

        // 4) Thức giữa đêm (dùng chung awakeCount/awakeMinutes với hypnogram & legend cho nhất quán).
        let awakeMin = d.awakeMinutes
        let goodAwake = d.awakeCount <= 2 && awakeMin <= 20
        out.append(SleepMetricEval(
            title: "Thức giữa đêm",
            value: d.awakeCount == 0 ? "Không thức" : "\(d.awakeCount) lần · \(dec(awakeMin)) phút",
            level: goodAwake ? .good : .caution,
            note: goodAwake
                ? "Giấc ngủ liền mạch — tốt."
                : "Thức nhiều lần. Xem tối qua có uống rượu bia hay ăn no muộn không; giữ phòng yên tĩnh.",
            isDoctor: false))

        // 5) Ngủ sâu.
        let deepP = d.percent(of: .deep)
        out.append(SleepMetricEval(
            title: "Ngủ sâu",
            value: "\(dec(d.minutes(of: .deep))) phút · \(dec(deepP))%",
            level: (13...23).contains(deepP) ? .good : .caution,
            note: "Ngủ sâu giúp phục hồi thể lực (người lớn thường 13–23%). Tập nhẹ ban ngày và ngủ đúng giờ giúp tăng ngủ sâu.",
            isDoctor: false))

        // 6) REM.
        let remP = d.percent(of: .rem)
        out.append(SleepMetricEval(
            title: "REM (mơ)",
            value: "\(dec(d.minutes(of: .rem))) phút · \(dec(remP))%",
            level: remP >= 20 ? .good : .caution,
            note: "REM giúp trí nhớ và tinh thần (thường 20–25%). Rượu bia buổi tối làm giảm REM rõ rệt.",
            isDoctor: false))

        // 7) Giờ đi ngủ ổn định (nếu có dữ liệu tuần).
        if let sd = bedtimeStdevMin {
            out.append(SleepMetricEval(
                title: "Giờ ngủ ổn định",
                value: "±\(dec(sd)) phút",
                level: sd <= 30 ? .good : (sd <= 60 ? .caution : .bad),
                note: sd <= 30
                    ? "Bạn đi ngủ khá đều giờ — rất tốt cho đồng hồ sinh học."
                    : "Giờ ngủ chênh lệch nhiều giữa các đêm. Cố định giờ lên giường trước 23h mỗi ngày.",
                isDoctor: true))
        }

        // 8) Tương quan rượu bia đêm đó.
        if hadAlcohol {
            out.append(SleepMetricEval(
                title: "Rượu bia đêm qua",
                value: "Có ghi",
                level: .caution,
                note: "Đêm qua có ghi rượu bia — thường làm nhịp tim cao hơn, ngủ nông và giảm REM. BS dặn không rượu bia; nếu có, tránh sau 21h.",
                isDoctor: true))
        }
        return out
    }

    // MARK: - Giấc ngủ trưa / ngủ ngày

    /// Mức chất lượng giấc trưa theo độ dài (người ngủ đêm kém nên tránh giấc trưa dài/muộn).
    /// <10 vàng (hơi ngắn) · 10–25 xanh (lý tưởng) · 26–45 vàng (hơi dài) · >45 đỏ (ảnh hưởng giấc đêm).
    static func napLevel(minutes: Int) -> MetricLevel {
        switch minutes {
        case ..<10: return .caution
        case 10...25: return .good
        case 26...45: return .caution
        default: return .bad
        }
    }

    /// Nhãn chip ngắn cho một giấc trưa.
    static func napQuality(minutes: Int) -> String {
        switch minutes {
        case ..<10: return "Hơi ngắn"
        case 10...25: return "Lý tưởng"
        case 26...45: return "Hơi dài"
        default: return "Dài"
        }
    }

    /// Câu đánh giá đời thường cho một giấc ngủ trưa (độ dài + giờ bắt đầu), gắn hồ sơ của bạn.
    static func napNote(minutes: Int, at start: Date) -> String {
        var s: String
        switch minutes {
        case ..<10:
            s = "Giấc \(minutes) phút — hơi ngắn, chủ yếu chợp mắt."
        case 10...25:
            s = "Giấc \(minutes) phút — giấc ngắn lý tưởng, giúp tỉnh táo mà không uể oải."
        case 26...45:
            s = "Giấc \(minutes) phút — hơi dài, dễ uể oải khi dậy (ngủ quán tính); giấc 10–20 phút tối ưu hơn."
        default:
            s = "Giấc \(minutes) phút — giấc dài, dễ ảnh hưởng giấc đêm. Nếu ngủ đêm chưa ổn, nên tránh ngủ trưa quá 30 phút và không ngủ trưa sau 15h."
        }
        let hour = Calendar.current.component(.hour, from: start)
        if hour >= 15 {
            s += " Ngủ trưa muộn (sau 15h) có thể làm khó ngủ tối."
        }
        return s
    }

    static func explanation(for metric: Metric) -> Explanation {
        switch metric {
        case .sleep:
            return Explanation(
                plain: "Đây là tổng thời gian anh ngủ thật đêm qua (không tính lúc trằn trọc hay thức giấc). Ngủ đủ thì dạ dày mới có thời gian phục hồi và cơ thể mới tích được cân. Đêm nào chỉ 4–5 tiếng là hôm sau dễ mệt, ăn kém.",
                doctorNote: "Ngủ đúng giờ, không thức khuya, giảm căng thẳng.",
                tip: "Tắt máy tính lúc 22h, lên giường 22h30–23h, dậy 6h30–7h. Mục tiêu ≥ 7 giờ ít nhất 5 đêm/tuần. Nếu hay thức giữa đêm, xem tối qua có uống rượu bia hay ăn no muộn không."
            )
        case .restingHeartRate:
            return Explanation(
                plain: "Nhịp tim nghỉ là số lần tim đập mỗi phút khi anh nằm yên, thường đo lúc ngủ. Số càng thấp và ổn định thì cơ thể càng được nghỉ ngơi tốt. Hôm nào tăng vọt so với mọi ngày thường là do rượu bia, ngủ kém, ốm hoặc căng thẳng.",
                doctorNote: nil,
                tip: "Chỉ để tham khảo, không cần lo từng ngày: mục tiêu là xu hướng đi xuống hoặc ổn định 60–75. Nếu nhiều ngày liền trên 85 kèm mệt, chóng mặt thì nên đi khám."
            )
        case .steps:
            return Explanation(
                plain: "Số bước anh đi trong ngày, Fitbit đếm tự động. Với người đang thiếu cân, đi bộ vừa phải giúp ăn ngon và ngủ sâu hơn, nhưng đi nhiều quá lại tốn calo cần để tăng cân.",
                doctorNote: nil,
                tip: "Đi bộ nhẹ 10–15 phút sau bữa tối là đủ tốt. Không cần cố chạy bộ hay đi thật nhiều; ưu tiên tập kháng lực nhẹ 3 buổi/tuần tại nhà."
            )
        case .bodyMass:
            return Explanation(
                plain: "Cân nặng mới nhất ghi trong ứng dụng Sức khoẻ. Màu ô so với mục tiêu cân trong Hồ sơ của bạn (tăng/giảm/giữ). Thay đổi an toàn thường khoảng 0,25–0,5 kg mỗi tuần.",
                doctorNote: "Ăn chia nhiều bữa nhỏ, đúng giờ; theo lời bác sĩ dặn trong Hồ sơ.",
                tip: "Cân mỗi sáng thứ 2, sau vệ sinh, trước ăn. Ăn đủ bữa theo Kế hoạch. Nếu 2 tuần liền cân đi ngược mục tiêu thì hỏi bác sĩ."
            )
        case .heartRateVariability:
            return Explanation(
                plain: "Biến thiên nhịp tim (HRV) đo khoảng cách giữa các nhịp tim đều hay không khi anh ngủ. Số cao và ổn định nghĩa là cơ thể hồi phục tốt, thần kinh thư giãn. Số này chỉ Google Health mới có (Fitbit đo lúc ngủ), ứng dụng Sức khoẻ của Apple chưa nhận được.",
                doctorNote: nil,
                tip: "Đừng lo từng đêm — hãy nhìn xu hướng của chính anh. HRV thường tụt sau hôm uống rượu bia, ngủ kém hoặc căng thẳng; đó là bằng chứng nhẹ nhàng để anh điều chỉnh. Đêm nào HRV thấp thì hôm sau nghỉ ngơi nhiều hơn."
            )
        case .skinTemperature:
            return Explanation(
                plain: "Đây là chênh lệch nhiệt độ da lúc ngủ so với mức nền bình thường của bạn (Fitbit tính sau vài đêm). Gần 0 là ổn. Lệch lên nhiều có thể do sắp ốm, uống rượu bia, phòng nóng hoặc ngủ kém. Chỉ Google Health mới có số này.",
                doctorNote: nil,
                tip: "Chênh trong khoảng ±0,4 °C là bình thường. Nếu ấm hơn nền rõ rệt vài đêm liền kèm mệt, hãy để ý xem có sắp cảm cúm không, giữ phòng ngủ thoáng mát và uống đủ nước."
            )
        case .respiratoryRate:
            return Explanation(
                plain: "Số lần anh hít thở mỗi phút lúc ngủ, Fitbit đo suốt đêm rồi lấy trung bình. Người lớn khoẻ thường 12–20 lần/phút và khá ổn định từ đêm này sang đêm khác. Đêm nào tăng rõ thường do sốt, sắp ốm, căng thẳng hoặc uống rượu bia tối hôm trước.",
                doctorNote: "Không rượu, bia — rượu bia làm thở nhanh, ngủ nông và hại dạ dày.",
                tip: "Nhìn xu hướng của chính anh hơn là từng đêm. Nếu vài đêm liền trên 20 kèm sốt, ho, khó thở thì nên đi khám. Tối giữ phòng thoáng, ăn xong 2–3 tiếng mới nằm để đỡ trào ngược."
            )
        case .oxygenSaturation:
            return Explanation(
                plain: "Tỉ lệ oxy trong máu lúc anh ngủ (đo ở cổ tay). Người khoẻ thường 95–100%. Số thấp nghĩa là cơ thể đang thiếu oxy trong lúc ngủ — hay gặp ở người ngáy to hoặc có lúc ngừng thở khi ngủ.",
                doctorNote: nil,
                tip: "Một đêm hơi thấp chưa đáng lo (đeo lỏng cũng làm sai số). Nếu nhiều đêm dưới 92%, hoặc người nhà thấy anh ngáy to, có lúc ngừng thở, sáng dậy vẫn mệt — hãy hỏi BS về chứng ngưng thở khi ngủ, vì nó cũng làm anh ngủ kém."
            )
        case .distance:
            return Explanation(
                plain: "Quãng đường anh đi bộ (và chạy, nếu có) trong ngày, Fitbit tính từ số bước. Khoảng 3 km mỗi ngày là đủ để tiêu hoá tốt và ngủ ngon hơn.",
                doctorNote: nil,
                tip: "Nếu đang cần tăng cân thì KHÔNG cần đi thật xa — đi nhiều lại tốn calo cần để tăng cân. Đi bộ chậm 10–15 phút sau bữa trưa và bữa tối là vừa đẹp cho dạ dày."
            )
        case .activeEnergy:
            return Explanation(
                plain: "Số calo cơ thể đốt thêm khi anh đi lại, vận động (không tính phần calo cơ thể tự đốt để thở, giữ ấm). Số này chỉ để tham khảo, app không chấm tốt/xấu.",
                doctorNote: "Ăn chia nhiều bữa nhỏ, đúng giờ — ăn đủ quan trọng hơn đốt calo.",
                tip: "Với người thiếu cân, mục tiêu là ĂN ĐỦ, không phải đốt nhiều. Hôm nào calo vận động cao (đi lại nhiều) thì thêm một bữa phụ: cốc sữa ấm, cháo yến mạch hay quả trứng."
            )
        case .activeHours:
            return Explanation(
                plain: "Số giờ trong ngày anh có đi lại ít nhất 250 bước (khoảng 2–3 phút đi bộ). Giống mục \"Hoạt động theo giờ\" của Google Health: mục tiêu 9 giờ, tức là cứ mỗi giờ đứng dậy đi lại một chút thay vì ngồi lì.",
                doctorNote: nil,
                tip: "Vận động rải đều các giờ tốt cho dạ dày và đường ruột hơn là dồn một lần đi thật nhiều. Cứ ngồi làm khoảng 50 phút thì đứng dậy rót nước, đi vài vòng — nhẹ nhàng, không tốn sức."
            )
        case .heartRateRange:
            return Explanation(
                plain: "Nhịp tim thấp nhất và cao nhất của bạn trong ngày. Thấp nhất thường lúc ngủ hoặc ngồi nghỉ, cao nhất thường lúc đi nhanh, leo cầu thang hay hồi hộp. Tim lên xuống theo việc anh làm là bình thường.",
                doctorNote: nil,
                tip: "Chạm vào ô để xem nhịp tim theo từng giờ. Nếu ngồi yên mà tim vẫn trên 100, hoặc kèm hồi hộp, đau ngực, chóng mặt thì nên đi khám và đo huyết áp tại nhà vài ngày."
            )
        case .liveHeartRate:
            return Explanation(
                plain: "Đây là nhịp tim đo ngay lúc này, vòng Fitbit gửi thẳng sang điện thoại qua Bluetooth khoảng mỗi giây một lần. Chỉ có số khi anh bật \u{201C}Chia sẻ nhịp tim\u{201D} trên vòng và để vòng gần điện thoại; tắt màn này là app ngừng đo. Vùng cường độ cho biết tim đang làm việc nặng cỡ nào so với mức tối đa theo tuổi trong Hồ sơ (≈ 220 − tuổi): Nghỉ ngơi → Nhẹ → Vừa → Gắng sức → Rất mạnh.",
                doctorNote: nil,
                tip: "Dùng để xem tim phản ứng thế nào khi đi bộ, tập nhẹ, uống cà phê hay lúc hồi hộp — rồi bấm \u{201C}Ghi chú sự kiện\u{201D} để lưu lại. Đây là số đo từ vòng đeo tay, không thay máy đo y tế. Nếu ngồi yên mà tim lên trên 100, hoặc kèm đau ngực, khó thở, chóng mặt thì nên dừng lại nghỉ và đi khám."
            )
        }
    }

    // MARK: - Thư viện bài thở (T-023, T-024)

    /// Giải thích nút "?" của thư viện bài thở: vì sao thở chậm giúp dịu, dùng khi nào, không thay thuốc.
    static let breathing = Explanation(
        plain: "Thở chậm khoảng 6 lần mỗi phút, nhất là khi thở ra dài hơn hít vào, là cách nhanh nhất để \u{201C}bấm phanh\u{201D} cho cơ thể. Hơi thở ra dài đánh thức phần thần kinh giúp nghỉ ngơi và tiêu hoá (thần kinh phó giao cảm): tim đập chậm lại, cơ bụng và dạ dày bớt co thắt, đầu óc dịu xuống. Khi thở chậm, nhịp tim còn lên xuống theo hơi thở — hít vào tim nhanh lên một chút, thở ra tim chậm lại (dao động nhịp tim theo hô hấp); lên xuống càng rõ là cơ thể càng đang thư giãn tốt.",
        doctorNote: "Giảm căng thẳng, ngủ đúng giờ — căng thẳng và mất ngủ làm dạ dày nặng thêm.",
        tip: "Ngồi hoặc nằm thoải mái, không cần cố hít thật sâu. Thấy chóng mặt thì dừng, thở bình thường một lúc hoặc chọn bài 5–5. Bài thở giúp thư giãn, KHÔNG thay thuốc hay lời dặn của bác sĩ; nếu hồi hộp, đau ngực, khó thở kéo dài thì đi khám."
    )

    /// Vì sao thư viện không có kiểu thở nhanh / thở mạnh.
    static let breathingExcluded = "App cố ý không đưa các kiểu thở nhanh, thở mạnh (như Wim Hof, Kapalabhati). Một thử nghiệm năm 2023 cho thấy chúng có thể làm tăng lo âu, gây choáng — không hợp mục tiêu làm dịu, và không hợp người thiếu cân hoặc huyết áp cao."

    /// Một câu đời thường về biên độ nhịp tim lên xuống theo hơi thở (lần/phút).
    static func breathSwingNote(_ swing: Double) -> (label: String, level: MetricLevel, note: String) {
        switch swing {
        case 6...:
            return ("Rõ", .good, "Nhịp tim lên xuống theo hơi thở rõ = cơ thể đang thư giãn tốt. Hít vào tim nhanh lên một chút, thở ra tim chậm lại — đó là dấu hiệu tốt.")
        case 3..<6:
            return ("Vừa", .caution, "Nhịp tim có lên xuống theo hơi thở nhưng chưa nhiều. Thử thở bằng bụng, thở ra chậm và dài hơn; tập đều vài hôm sẽ rõ hơn.")
        default:
            return ("Nhẹ", .unknown, "Nhịp tim gần như đứng yên theo hơi thở. Hay gặp khi đang mệt, căng thẳng, sau rượu bia — hoặc vòng đo chưa kịp. Không đáng lo; hãy thử lại lúc yên tĩnh hơn.")
        }
    }
}
