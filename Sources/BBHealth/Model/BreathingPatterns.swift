import Foundation

/// **Thư viện bài thở** (T-024): 7 kiểu thở chậm có cơ sở khoa học, mỗi bài là một chuỗi pha
/// (hít / hít thêm / giữ / thở ra / giữ) lặp lại. Nội dung giải thích viết đời thường, kèm lưu ý cho các
/// vấn đề hay gặp (dạ dày/trào ngược, ngủ kém, căng thẳng, huyết áp hơi cao).
///
/// Cố ý KHÔNG có các kiểu thở nhanh / thở mạnh (tăng thông khí) — xem `Explanations.breathingExcluded`.

/// Một pha trong một nhịp thở.
struct BreathPhase: Equatable {
    enum Kind: Equatable {
        /// Hít vào (vòng tròn phình).
        case inhale
        /// Hít thêm một hơi ngắn ở đỉnh (thở dài theo chu kỳ) — vòng phình thêm chút.
        case inhaleTop
        /// Giữ hơi sau khi hít (vòng to, đứng yên).
        case holdIn
        /// Thở ra (vòng xẹp).
        case exhale
        /// Nghỉ sau khi thở ra (vòng nhỏ, đứng yên).
        case holdOut

        var isHold: Bool { self == .holdIn || self == .holdOut }
    }

    let kind: Kind
    let seconds: Double
    /// Chữ to trên vòng tròn, vd "Hít vào…".
    let cue: String
    /// Gợi ý nhỏ dưới chữ to, vd "phình bụng".
    let sub: String?

    init(_ kind: Kind, _ seconds: Double, _ cue: String? = nil, sub: String? = nil) {
        self.kind = kind
        self.seconds = seconds
        self.cue = cue ?? Self.defaultCue(kind)
        self.sub = sub
    }

    static func defaultCue(_ kind: Kind) -> String {
        switch kind {
        case .inhale: return "Hít vào…"
        case .inhaleTop: return "Hít thêm…"
        case .holdIn, .holdOut: return "Giữ…"
        case .exhale: return "Thở ra…"
        }
    }

    /// Tên ngắn của pha cho dòng nhịp ("Hít 4 · giữ 7 · thở 8").
    var shortLabel: String {
        switch kind {
        case .inhale: return "hít"
        case .inhaleTop: return "hít thêm"
        case .holdIn, .holdOut: return "giữ"
        case .exhale: return "thở"
        }
    }
}

/// Mức bằng chứng khoa học của một bài.
enum BreathEvidence {
    case strong, moderateStrong, moderate, limited

    var label: String {
        switch self {
        case .strong: return "Mạnh"
        case .moderateStrong: return "Vừa–Mạnh"
        case .moderate: return "Vừa"
        case .limited: return "Còn ít"
        }
    }

    /// Màu chip: Mạnh / Vừa–Mạnh = xanh, Vừa = vàng, Còn ít = xám.
    var level: MetricLevel {
        switch self {
        case .strong, .moderateStrong: return .good
        case .moderate: return .caution
        case .limited: return .unknown
        }
    }
}

/// Một bài thở trong thư viện.
struct BreathingPattern: Identifiable, Equatable {
    let id: String
    let name: String
    /// Nhịp viết gọn, vd "4–6", "4–7–8".
    let shortPattern: String
    let phases: [BreathPhase]
    let defaultMinutes: Int
    let minuteOptions: [Int]
    /// Một câu: bài này để làm gì.
    let purpose: String
    /// Dùng khi nào.
    let bestFor: [String]
    /// Cách làm.
    let howTo: String
    let evidenceLevel: BreathEvidence
    /// 2–3 câu đời thường + tên nghiên cứu trong ngoặc.
    let evidenceNote: String
    let cautions: [String]
    /// Lưu ý cho các vấn đề hay gặp (dạ dày/trào ngược, khó ngủ, căng thẳng).
    let forYou: String
    /// Ghi chú về con số sau bài (vd bài có nín thở).
    let measureNote: String?
    /// Gắn chip "Hợp với anh".
    var fitsYou = false
    /// Dòng nhịp tự viết (khi chuỗi pha tự sinh khó đọc, vd thở luân phiên).
    var rhythmOverride: String?

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }

    // MARK: Thời gian

    /// Thời lượng 1 vòng pha (giây).
    var cycleSeconds: Double { phases.reduce(0) { $0 + $1.seconds } }

    /// Số lần hít vào trong 1 vòng pha (thở luân phiên = 2).
    var inhalesPerCycle: Int { max(1, phases.filter { $0.kind == .inhale }.count) }

    /// Thời gian 1 nhịp thở (giây) — dùng để tính "lên xuống theo hơi thở".
    var breathPeriod: Double { cycleSeconds / Double(inhalesPerCycle) }

    /// Có pha giữ hơi không.
    var hasHolds: Bool { phases.contains { $0.kind.isHold } }

    /// Dòng nhịp dễ đọc: "Hít 4 · giữ 7 · thở 8".
    var rhythmText: String {
        if let rhythmOverride { return rhythmOverride }
        let parts = phases.map { "\($0.shortLabel) \(Self.secondsText($0.seconds))" }
        let s = parts.joined(separator: " · ")
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    static func secondsText(_ s: Double) -> String {
        s == s.rounded() ? "\(Int(s))" : String(format: "%.1f", s).replacingOccurrences(of: ".", with: ",")
    }

    /// Vị trí trong bài ở giây thứ `t` (tính từ lúc bắt đầu).
    struct Position {
        /// Số thứ tự pha tính từ đầu bài (tăng mãi) — đổi số = đổi pha.
        let globalIndex: Int
        /// Vị trí pha trong vòng.
        let index: Int
        let phase: BreathPhase
        /// Đã qua bao nhiêu giây trong pha.
        let elapsed: Double
        /// Còn bao nhiêu giây trong pha.
        let remaining: Double
        /// Số nhịp thở đã bắt đầu (1, 2, 3…).
        let breathNumber: Int
    }

    func position(at t: TimeInterval) -> Position {
        let cycle = max(0.1, cycleSeconds)
        let time = max(0, t)
        let k = Int(time / cycle)
        let inCycle = time - Double(k) * cycle
        var acc = 0.0
        var inhalesBefore = 0
        for (i, p) in phases.enumerated() {
            if p.kind == .inhale { inhalesBefore += 1 }
            if inCycle < acc + p.seconds || i == phases.count - 1 {
                let elapsed = min(p.seconds, inCycle - acc)
                return Position(globalIndex: k * phases.count + i, index: i, phase: p,
                                elapsed: elapsed, remaining: max(0, p.seconds - elapsed),
                                breathNumber: k * inhalesPerCycle + max(1, inhalesBefore))
            }
            acc += p.seconds
        }
        // Không tới đây (phases rỗng) — trả pha giả.
        return Position(globalIndex: 0, index: 0, phase: BreathPhase(.inhale, 4),
                        elapsed: 0, remaining: 4, breathNumber: 1)
    }

    /// Thời lượng thật của bài: làm tròn tới hết vòng pha gần nhất để bài kết thúc sau một hơi thở ra.
    func totalSeconds(minutes: Int) -> TimeInterval {
        let cycle = max(0.1, cycleSeconds)
        let n = max(1, (Double(minutes * 60) / cycle).rounded())
        return n * cycle
    }

    /// Số nhịp thở trọn vẹn trong `duration` giây.
    func breaths(in duration: TimeInterval) -> Int {
        guard cycleSeconds > 0 else { return 0 }
        return Int(duration / breathPeriod)
    }
}

// MARK: - Danh mục 7 bài

extension BreathingPattern {
    static let defaultID = "slow46"

    static func find(_ id: String?) -> BreathingPattern? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    static let all: [BreathingPattern] = [slow46, even55, belly, cyclicSigh, box, fourSevenEight, alternateNostril]

    private static let holdMeasureNote = "Bài có nín thở nên con số \u{201C}lên xuống theo hơi thở\u{201D} ít ý nghĩa — xem \u{201C}nhịp tim hạ từ … → …\u{201D} là chính."

    /// 1. Thở chậm 4–6 (mặc định).
    static let slow46 = BreathingPattern(
        id: "slow46",
        name: "Thở chậm 4–6",
        shortPattern: "4–6",
        phases: [
            BreathPhase(.inhale, 4, sub: "nhẹ nhàng bằng mũi"),
            BreathPhase(.exhale, 6, sub: "chậm, dài hơn lúc hít"),
        ],
        defaultMinutes: 5, minuteOptions: [3, 5, 10],
        purpose: "Làm dịu thần kinh, hạ nhịp tim và giúp hạ huyết áp nhẹ.",
        bestFor: ["Trước khi ngủ", "Sau cuộc họp căng thẳng", "Tập đều 5–10 phút mỗi ngày"],
        howTo: "Ngồi hoặc nằm thoải mái. Hít vào nhẹ 4 giây, thở ra chậm 6 giây — khoảng 6 nhịp thở mỗi phút. Không nín thở, không cần hít thật sâu.",
        evidenceLevel: .strong,
        evidenceNote: "Thở chậm khoảng 6 nhịp mỗi phút là nền tảng của cách tập \u{201C}phản hồi sinh học\u{201D} theo nhịp tim. Nhiều tổng quan và phân tích gộp cho thấy cách thở này giảm lo âu, tăng độ dao động nhịp tim và hạ huyết áp; thở ra dài hơn hít vào kích phần thần kinh nghỉ ngơi (phó giao cảm) mạnh hơn. (Zaccaro 2018; Laborde 2022)",
        cautions: ["Thấy hụt hơi hoặc chóng mặt thì chuyển sang bài 5–5."],
        forYou: "Hợp với người đau dạ dày, trào ngược vì không nín thở, không ép bụng. Cũng hợp với người huyết áp hơi cao.",
        measureNote: nil,
        fitsYou: true
    )

    /// 2. Thở chậm 5–5 (cân bằng).
    static let even55 = BreathingPattern(
        id: "even55",
        name: "Thở chậm 5–5",
        shortPattern: "5–5",
        phases: [
            BreathPhase(.inhale, 5),
            BreathPhase(.exhale, 5),
        ],
        defaultMinutes: 5, minuteOptions: [3, 5, 10],
        purpose: "Như bài 4–6 nhưng hít và thở đều nhau, dễ theo hơn.",
        bestFor: ["Khi thở 4–6 thấy hụt hơi", "Trước khi ngủ, sau lúc căng thẳng"],
        howTo: "Hít vào 5 giây, thở ra 5 giây, đều như con lắc. Không nín thở, không cần hít thật sâu.",
        evidenceLevel: .strong,
        evidenceNote: "Cùng nhóm \u{201C}thở cộng hưởng\u{201D} khoảng 6 nhịp mỗi phút với bài 4–6, nên có chung nền bằng chứng: giảm lo âu, tăng độ dao động nhịp tim, hạ huyết áp. (Zaccaro 2018; Laborde 2022)",
        cautions: [],
        forYou: "Ai cũng dùng được — chọn bài này những hôm mệt, thấy 4–6 khó theo.",
        measureNote: nil
    )

    /// 3. Thở bụng (cơ hoành) 4–6.
    static let belly = BreathingPattern(
        id: "belly",
        name: "Thở bụng",
        shortPattern: "4–6",
        phases: [
            BreathPhase(.inhale, 4, sub: "phình bụng, vai không nhấc"),
            BreathPhase(.exhale, 6, sub: "hóp bụng nhẹ"),
        ],
        defaultMinutes: 5, minuteOptions: [3, 5, 10],
        purpose: "Giảm trào ngược, ợ nóng và làm dịu căng thẳng.",
        bestFor: ["Sau bữa ăn ít nhất 1 giờ", "Trước khi ngủ", "Khi thấy nóng rát ngực, ợ nóng"],
        howTo: "Nằm hoặc ngồi thẳng, đặt một tay lên bụng. Hít vào 4 giây cho bụng phình lên dưới tay, vai không nhấc. Thở ra 6 giây, bụng hóp nhẹ vào. Không nín thở.",
        evidenceLevel: .moderateStrong,
        evidenceNote: "Tập thở bằng cơ hoành làm khoẻ phần cơ hoành ôm quanh thực quản — chỗ giúp chặn dịch dạ dày trào lên. Vài thử nghiệm cho thấy tập đều giúp giảm triệu chứng trào ngược và giảm nhu cầu dùng thuốc. (Eherer 2012; Halland 2021)",
        cautions: ["Không tập ngay sau khi ăn no — đợi ít nhất 1 giờ.", "Hóp bụng nhẹ thôi, không gồng ép."],
        forYou: "Hợp nhất với người đau dạ dày, trào ngược. Nhớ đừng tập ngay sau bữa ăn no.",
        measureNote: nil,
        fitsYou: true
    )

    /// 4. Thở dài theo chu kỳ (hít 2 + hít thêm 1, thở ra dài).
    static let cyclicSigh = BreathingPattern(
        id: "sigh",
        name: "Thở dài theo chu kỳ",
        shortPattern: "2+1–7",
        phases: [
            BreathPhase(.inhale, 2, sub: "bằng mũi"),
            BreathPhase(.inhaleTop, 1, sub: "một hơi ngắn, nhẹ thôi"),
            BreathPhase(.exhale, 7, sub: "bằng miệng, thật dài"),
        ],
        defaultMinutes: 5, minuteOptions: [3, 5, 10],
        purpose: "Hạ nhịp tim nhanh nhất và làm tâm trạng nhẹ hơn.",
        bestFor: ["Khi hồi hộp, tim đập nhanh đột ngột", "Trước khi phát biểu hay vào họp", "Tập 5 phút mỗi ngày"],
        howTo: "Hít vào bằng mũi 2 giây, rồi hít thêm một hơi ngắn 1 giây cho phổi căng hẳn. Sau đó thở ra bằng miệng thật chậm, dài 6–7 giây. Lặp lại.",
        evidenceLevel: .moderateStrong,
        evidenceNote: "Thử nghiệm ngẫu nhiên của Đại học Stanford năm 2023 trên 108 người, tập 5 phút mỗi ngày trong 1 tháng: thở dài theo chu kỳ cải thiện tâm trạng và làm nhịp thở chậm lại tốt hơn cả thở hộp và thiền chánh niệm. (Balban và cộng sự, 2023)",
        cautions: ["Hơi hít thêm chỉ nhẹ thôi, không gắng sức."],
        forYou: "Hợp những lúc hồi hộp, căng thẳng trước việc khó. Hít thêm nhẹ thôi, không gắng.",
        measureNote: nil,
        rhythmOverride: "Hít 2 · hít thêm 1 · thở 7"
    )

    /// 5. Thở hộp 4–4–4–4.
    static let box = BreathingPattern(
        id: "box",
        name: "Thở hộp",
        shortPattern: "4–4–4–4",
        phases: [
            BreathPhase(.inhale, 4),
            BreathPhase(.holdIn, 4, sub: "giữ hơi, vai thả lỏng"),
            BreathPhase(.exhale, 4),
            BreathPhase(.holdOut, 4, sub: "nghỉ, chưa hít vào"),
        ],
        defaultMinutes: 3, minuteOptions: [2, 3, 5],
        purpose: "Lấy lại bình tĩnh và tập trung thật nhanh.",
        bestFor: ["Trước việc căng thẳng: họp, gọi điện khó", "Ban ngày, khi cần tỉnh táo"],
        howTo: "Ngồi thẳng lưng. Hít vào 4 giây — giữ hơi 4 giây — thở ra 4 giây — nghỉ 4 giây, như đi quanh 4 cạnh một chiếc hộp.",
        evidenceLevel: .moderate,
        evidenceNote: "Hay dùng trong huấn luyện quân đội và đội cứu hộ để giữ bình tĩnh. Vài nghiên cứu nhỏ cho thấy giảm căng thẳng; trong thử nghiệm Stanford 2023 bài này có hiệu quả nhưng kém hơn thở dài theo chu kỳ. (Balban và cộng sự, 2023)",
        cautions: [
            "Có nín thở sau khi hít vào → tăng áp lực trong bụng, có thể gây ợ hoặc khó chịu khi dạ dày đầy.",
            "Thấy choáng thì bỏ pha giữ, chỉ hít – thở đều.",
        ],
        forYou: "Chỉ tập lúc bụng rỗng, ngồi thẳng — pha nín thở làm tăng áp lực bụng, dễ ợ nếu bị trào ngược.",
        measureNote: holdMeasureNote
    )

    /// 6. Thở 4–7–8 (dễ ngủ).
    static let fourSevenEight = BreathingPattern(
        id: "478",
        name: "Thở 4–7–8 (dễ ngủ)",
        shortPattern: "4–7–8",
        phases: [
            BreathPhase(.inhale, 4, sub: "bằng mũi"),
            BreathPhase(.holdIn, 7, sub: "giữ hơi, đếm chậm"),
            BreathPhase(.exhale, 8, sub: "bằng miệng, xì nhẹ"),
        ],
        defaultMinutes: 3, minuteOptions: [2, 3],
        purpose: "Giúp dễ vào giấc.",
        bestFor: ["Khi đã nằm trên giường, chuẩn bị ngủ", "Làm 4–8 nhịp thở (2–3 phút)"],
        howTo: "Nằm thoải mái. Hít vào bằng mũi 4 giây, giữ hơi 7 giây, rồi thở ra bằng miệng 8 giây, có thể \u{201C}xì\u{201D} nhẹ qua môi.",
        evidenceLevel: .limited,
        evidenceNote: "Rất phổ biến nhờ bác sĩ Andrew Weil, nhưng nghiên cứu còn nhỏ (vd một nghiên cứu năm 2022 trên người trẻ thấy nhịp tim và huyết áp hạ ngay sau khi thở). Tác dụng chủ yếu có lẽ nhờ thở ra dài và việc đếm làm đầu óc dịu lại.",
        cautions: [
            "Giữ 7 giây khá lâu — mới tập có thể chóng mặt; khi đó rút còn 4–4–8.",
            "Không tập ngay sau khi ăn (dễ trào ngược).",
        ],
        forYou: "Hợp với người khó ngủ. Không tập ngay sau ăn; nằm nghiêng trái sẽ dễ chịu hơn cho dạ dày.",
        measureNote: holdMeasureNote
    )

    /// 7. Thở mũi luân phiên 4–4.
    static let alternateNostril = BreathingPattern(
        id: "alternate",
        name: "Thở mũi luân phiên",
        shortPattern: "4–4",
        phases: [
            BreathPhase(.inhale, 4, sub: "bịt mũi phải · hít bằng mũi trái"),
            BreathPhase(.exhale, 4, sub: "bịt mũi trái · thở ra mũi phải"),
            BreathPhase(.inhale, 4, sub: "giữ tay · hít bằng mũi phải"),
            BreathPhase(.exhale, 4, sub: "bịt mũi phải · thở ra mũi trái"),
        ],
        defaultMinutes: 5, minuteOptions: [3, 5, 10],
        purpose: "Dịu và cân bằng, giúp hạ huyết áp nhẹ và tập trung hơn.",
        bestFor: ["Giữa ngày làm việc", "Trước khi ngủ"],
        howTo: "Ngồi thẳng, dùng ngón tay bịt nhẹ một bên mũi. Bịt mũi phải, hít vào mũi trái 4 giây → bịt mũi trái, thở ra mũi phải 4 giây → hít vào mũi phải 4 giây → bịt mũi phải, thở ra mũi trái 4 giây. Không nín thở. Làm theo chữ nhỏ dưới vòng tròn.",
        evidenceLevel: .moderate,
        evidenceNote: "Nhiều nghiên cứu nhỏ và phân tích gộp về thở luân phiên hai bên mũi cho thấy giảm huyết áp, nhịp tim và cải thiện khả năng chú ý.",
        cautions: ["Đang nghẹt mũi thì bỏ qua bài này.", "Cần dùng một tay để bịt mũi."],
        forYou: "Hợp những lúc căng thẳng giữa giờ làm. Hôm nghẹt mũi thì chọn bài 4–6 hoặc thở bụng.",
        measureNote: nil,
        rhythmOverride: "Hít 4 · thở 4, đổi bên mũi"
    )

    /// Chọn bài theo tình huống (bảng ngắn trong sheet "?" của thư viện).
    static let chooser: [(situation: String, ids: [String])] = [
        ("Trước khi ngủ", ["slow46", "belly", "478"]),
        ("Hồi hộp đột ngột", ["sigh"]),
        ("Cần tập trung", ["box", "alternate"]),
        ("Ợ nóng, nóng rát ngực (sau ăn ≥ 1 giờ)", ["belly"]),
    ]
}
