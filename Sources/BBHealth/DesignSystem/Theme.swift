import SwiftUI
import UIKit

/// Hệ thiết kế BBHealth: màu (sáng/tối theo hệ thống), chữ, bo góc, khoảng cách, bóng đổ.
/// Tinh thần: ấm, dịu, đáng tin — nền kem ấm (sáng) / xanh đêm sâu (tối), xanh ngọc làm màu chủ đạo,
/// màu trạng thái dịu (không đỏ gắt).
enum Theme {

    // MARK: - Màu nền & chữ

    /// Nền trang: kem ấm / xanh đêm sâu.
    static let background = Color(light: 0xF7F2EA, dark: 0x0B1820)
    /// Bề mặt thẻ.
    static let surface = Color(light: 0xFFFDF9, dark: 0x13232C)
    /// Bề mặt phụ (ô trong thẻ, rãnh tiến độ).
    static let surfaceMuted = Color(light: 0xF1EBE1, dark: 0x1B2F39)
    /// Đường kẻ mảnh.
    static let hairline = Color(light: 0xE6DED2, dark: 0x233A45)

    static let textPrimary = Color(light: 0x1C2A2F, dark: 0xE8F1F0)
    static let textSecondary = Color(light: 0x5F6B6C, dark: 0x9EB2B4)
    static let textTertiary = Color(light: 0x8E9797, dark: 0x6F8588)

    // MARK: - Màu chủ đạo

    /// Xanh ngọc (teal) — màu thương hiệu.
    static let brand = Color(light: 0x14857F, dark: 0x45C6B8)
    static let brandDeep = Color(light: 0x0E6368, dark: 0x2FA89C)

    // MARK: - Màu trạng thái (dịu)

    /// Tốt — xanh lá mềm.
    static let good = Color(light: 0x3B9562, dark: 0x6DCB90)
    /// Cần chú ý — hổ phách.
    static let caution = Color(light: 0xB9791A, dark: 0xEDB24F)
    /// Nên cải thiện — san hô.
    static let improve = Color(light: 0xD0634B, dark: 0xF28C74)
    static let neutral = Color(light: 0x7A8687, dark: 0x8FA3A5)

    // MARK: - Màu theo chỉ số

    static let sleep = Color(light: 0x5A5FC4, dark: 0x9398F2)
    static let heart = Color(light: 0xCF5078, dark: 0xF18BA8)
    static let steps = Color(light: 0x1F8BB8, dark: 0x6BBCE6)
    static let weight = Color(light: 0x8E5CB8, dark: 0xC39BE8)
    static let meal = Color(light: 0xC0762A, dark: 0xF0AE62)
    static let hrv = Color(light: 0x0E8AA8, dark: 0x5FC6DE)
    static let temp = Color(light: 0xB85C3C, dark: 0xE9976E)
    /// T-020: nhịp thở (xanh lam dịu), oxy máu (đỏ máu dịu), calo (cam lửa).
    static let breath = Color(light: 0x3C7FC4, dark: 0x82B6EC)
    static let oxygen = Color(light: 0xC2414F, dark: 0xF08A94)
    static let energy = Color(light: 0xD06A1F, dark: 0xF5A35C)

    // MARK: - Khoảng cách, bo góc

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 28
        /// Lề hai bên màn.
        static let page: CGFloat = 18
    }

    enum Radius {
        static let chip: CGFloat = 10
        static let small: CGFloat = 14
        static let card: CGFloat = 24
    }

    /// Độ nhuộm màu nền thẻ theo chế độ sáng/tối.
    static func tintOpacity(_ scheme: ColorScheme) -> Double { scheme == .dark ? 0.13 : 0.075 }

    /// Bóng đổ nhẹ.
    static let shadow = Color(light: 0x6B5A40, dark: 0x000000, lightAlpha: 0.08, darkAlpha: 0.35)
}

// MARK: - Kiểu chữ

extension Font {
    /// Số to (SF Rounded).
    static func number(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    /// Nhãn nhỏ, rounded, đậm vừa.
    static let label = Font.system(.subheadline, design: .rounded).weight(.semibold)
    static let cardTitle = Font.system(.headline, design: .rounded)
    static let sectionTitle = Font.system(.title3, design: .rounded).weight(.bold)
}

// MARK: - Màu động sáng/tối

extension Color {
    init(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}
