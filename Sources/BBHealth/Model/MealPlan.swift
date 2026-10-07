import Foundation

/// Một bữa trong lịch ăn mẫu ngày văn phòng (chia nhiều bữa nhỏ — sửa theo nhu cầu của bạn).
struct Meal: Identifiable {
    var id: String { name }
    let time: String
    let name: String
    /// Các lựa chọn món (chọn 1).
    let options: [String]
    /// Ghi chú kèm (nếu có).
    let note: String?
    let kcal: String
    let symbol: String
    /// Khung giờ ăn tính theo phút trong ngày — để biết bữa đã qua / đang tới.
    let startMinute: Int
    let endMinute: Int

    /// Toàn bộ gợi ý dạng một đoạn.
    var suggestion: String {
        (options.joined(separator: "; hoặc ") + ".") + (note.map { " " + $0 } ?? "")
    }
}

enum MealPlan {
    /// 6 bữa/ngày: 3 chính + 3 phụ. Tổng ~2.350–2.650 kcal.
    static let officeDay: [Meal] = [
        Meal(time: "7h00", name: "Bữa sáng",
             options: ["Cháo yến mạch nấu sữa + 1 trứng gà",
                       "Phở gà (không chanh, tương ớt)",
                       "Bánh mì mềm + trứng ốp la + 1 ly sữa"],
             note: nil,
             kcal: "500–550", symbol: "sunrise.fill",
             startMinute: 6 * 60 + 30, endMinute: 8 * 60 + 30),
        Meal(time: "9h30", name: "Phụ sáng",
             options: ["1 hộp sữa hạt (óc chó/hạnh nhân) 250 ml",
                       "Sữa chua ít đường, không chua + granola"],
             note: nil,
             kcal: "250–300", symbol: "cup.and.saucer.fill",
             startMinute: 9 * 60 + 30, endMinute: 10 * 60 + 15),
        Meal(time: "12h00", name: "Bữa trưa",
             options: ["Cơm mềm + cá/thịt kho nhạt mềm (cá kho tộ nhạt, thịt kho tàu, thịt băm hấp trứng) + canh rau củ nấu chín kỹ (bí đỏ, mồng tơi, su su)"],
             note: "Không rau sống.",
             kcal: "650–700", symbol: "fork.knife",
             startMinute: 12 * 60, endMinute: 12 * 60 + 45),
        Meal(time: "15h00", name: "Phụ chiều",
             options: ["Chuối tây chín + 1 ly sữa",
                       "Khoai lang/khoai tây luộc + sữa",
                       "Bánh flan"],
             note: nil,
             kcal: "250–300", symbol: "takeoutbag.and.cup.and.straw.fill",
             startMinute: 15 * 60, endMinute: 15 * 60 + 45),
        Meal(time: "18h30", name: "Bữa tối",
             options: ["Cháo thịt băm hoặc cháo cá",
                       "Cơm mềm + canh + món hấp (đậu phụ hấp, cá hấp)"],
             note: "Ăn xong trước 19h30.",
             kcal: "550–600", symbol: "sunset.fill",
             startMinute: 18 * 60 + 30, endMinute: 19 * 60 + 30),
        Meal(time: "21h00", name: "Phụ tối nhẹ",
             options: ["1 ly sữa ấm nhỏ",
                       "1 hộp sữa chua ít chua",
                       "Bánh mì mềm phết bơ đậu phộng"],
             note: "Ăn xong ≥ 2 giờ mới đi ngủ.",
             kcal: "150–200", symbol: "moon.stars.fill",
             startMinute: 21 * 60, endMinute: 21 * 60 + 30),
    ]

    static let totalKcal = "2.350–2.650"

    /// Danh sách kiêng MẪU (dạ dày/trào ngược) — sửa theo lời bác sĩ của bạn.
    static let forbidden: [String] = ["Bún", "Chuối tiêu", "Rau sống", "Đồ chua", "Đồ cay", "Rượu bia", "Nước có ga"]
    static let forbiddenNote = "Đồ chua gồm dấm, chanh, me. Không nằm ngay sau ăn (đợi 2–3 giờ); ăn chậm, nhai kỹ."

    enum MealStatus { case past, current, upcoming }

    static func minuteOfDay(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// Bữa tiếp theo (hoặc đang tới giờ). Sau bữa phụ tối → bữa sáng mai.
    static func nextMeal(at date: Date) -> (meal: Meal, isNow: Bool, minutesUntil: Int, tomorrow: Bool) {
        let now = minuteOfDay(date)
        if let m = officeDay.first(where: { $0.endMinute > now }) {
            let isNow = now >= m.startMinute
            return (m, isNow, max(0, m.startMinute - now), false)
        }
        let first = officeDay[0]
        return (first, false, 24 * 60 - now + first.startMinute, true)
    }

    static func status(of meal: Meal, at date: Date) -> MealStatus {
        let next = nextMeal(at: date)
        if !next.tomorrow && next.meal.id == meal.id { return .current }
        return meal.endMinute <= minuteOfDay(date) ? .past : .upcoming
    }
}
