import SwiftUI

/// 5 tab: Hôm nay · Ghi nhanh · Xu hướng · Kế hoạch · Cài đặt.
struct RootTabView: View {
    @State private var tab = DebugOptions.initialTab
    @State private var pending = PendingNavigation.shared

    var body: some View {
        TabView(selection: $tab) {
            TodayView()
                .tabItem { Label("Hôm nay", systemImage: "sun.max.fill") }
                .tag("today")
            QuickLogView()
                .tabItem { Label("Ghi nhanh", systemImage: "square.and.pencil") }
                .tag("log")
            TrendsView()
                .tabItem { Label("Xu hướng", systemImage: "chart.line.uptrend.xyaxis") }
                .tag("trends")
            PlanView()
                .tabItem { Label("Kế hoạch", systemImage: "fork.knife") }
                .tag("plan")
            SettingsView()
                .tabItem { Label("Cài đặt", systemImage: "gearshape.fill") }
                .tag("settings")
        }
        .tint(Theme.brand)
        // Chạm thông báo "Báo cáo tuần" → sang Xu hướng (TrendsView tự mở Báo cáo tuần).
        .onChange(of: pending.openWeeklyReport) { if pending.openWeeklyReport { tab = "trends" } }
    }
}

/// Màn giữ chỗ cho tính năng chưa làm — trạng thái trống có minh hoạ.
struct ComingSoonView: View {
    let title: String
    let symbol: String
    let headline: String
    let note: String
    let tint: Color
    let features: [(String, String)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, Theme.Space.page)
                        .padding(.top, Theme.Space.l)
                    EmptyStateView(symbol: symbol, title: headline, message: note, tint: tint, features: features)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 36)
                        .padding(.bottom, Theme.Space.xxl)
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

#Preview {
    RootTabView()
}
