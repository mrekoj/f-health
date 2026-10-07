import SwiftUI
import SwiftData

/// Màn **Giấc ngủ trưa**: danh sách các giấc đã tự ghi + thống kê 7/30 ngày.
/// Dữ liệu lấy từ SwiftData `NapLog` (do `NapAutoLogger` tự lưu). Không ghi tay.
struct NapHistoryView: View {
    @Query(sort: \NapLog.start, order: .reverse) private var naps: [NapLog]
    @State private var rangeDays = 7
    @State private var showInfo = false
    @State private var settings = AppSettings.shared
    @State private var diag: NapDetector.Diagnostics?   // chẩn đoán "vì sao hôm nay chưa ghi"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                rangePicker
                statsCard
                if visibleNaps.isEmpty {
                    emptyView
                } else {
                    napsCard
                }
                if let diag { diagnosticView(diag) }
                deviceNote
            }
            .padding(.horizontal, Theme.Space.page)
            .padding(.bottom, Theme.Space.xxl)
        }
        .task {
            let p = HealthStoreFactory.make(for: settings.source)
            diag = try? await p.napDiagnostics(for: Date())
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Giấc ngủ trưa")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HelpButton(title: "Giấc ngủ trưa") { showInfo = true }
            }
        }
        .sheet(isPresented: $showInfo) { NapInfoSheet() }
    }

    // MARK: - Dữ liệu theo khoảng

    private var cutoff: Date {
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: -(rangeDays - 1), to: cal.startOfDay(for: Date())) ?? Date.distantPast
    }
    /// Các giấc trong khoảng đang chọn (để thống kê + danh sách).
    private var visibleNaps: [NapLog] { naps.filter { $0.start >= cutoff } }
    private var totalMinutes: Int { visibleNaps.reduce(0) { $0 + $1.minutes } }
    private var avgMinutes: Int {
        visibleNaps.isEmpty ? 0 : Int((Double(totalMinutes) / Double(visibleNaps.count)).rounded())
    }

    // MARK: - Chọn khoảng

    private var rangePicker: some View {
        Picker("Khoảng", selection: $rangeDays) {
            Text("7 ngày").tag(7)
            Text("30 ngày").tag(30)
        }
        .pickerStyle(.segmented)
        .padding(.top, Theme.Space.s)
    }

    // MARK: - Thống kê

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: Theme.Space.m) {
                tile("Số giấc", value: "\(visibleNaps.count)", unit: "giấc")
                tile("Tổng", value: "\(totalMinutes)", unit: "phút")
                tile("Mỗi giấc", value: visibleNaps.isEmpty ? "—" : "\(avgMinutes)", unit: "phút")
            }
            Text(remark)
                .font(.caption).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.sleep)
    }

    private func tile(_ title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
            Text(value).font(.number(24)).foregroundStyle(Theme.textPrimary)
            Text(unit).font(.caption2).foregroundStyle(Theme.textTertiary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.sleep.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.small))
    }

    private var remark: String {
        if visibleNaps.isEmpty {
            return "Chưa có giấc trưa nào được ghi trong \(rangeDays) ngày qua. Vòng Fitbit thường chỉ ghi giấc đủ dài."
        }
        if avgMinutes > 45 {
            return "Các giấc trưa đang khá dài (trung bình \(avgMinutes) phút). Nếu ngủ đêm chưa ổn, thử rút ngắn còn 10–20 phút để tối dễ ngủ hơn."
        }
        if avgMinutes >= 26 {
            return "Trung bình mỗi giấc \(avgMinutes) phút — hơi dài một chút; giấc 10–20 phút sẽ tỉnh táo hơn mà không uể oải."
        }
        return "Trung bình mỗi giấc \(avgMinutes) phút — độ dài hợp lý. Giữ thói quen ngủ trưa ngắn và tránh ngủ sau 15h."
    }

    // MARK: - Danh sách giấc

    private var napsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(visibleNaps.enumerated()), id: \.element.id) { idx, nap in
                napRow(nap)
                if idx < visibleNaps.count - 1 {
                    Divider().padding(.leading, Theme.Space.l)
                }
            }
        }
        .card()
    }

    private func napRow(_ nap: NapLog) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(weekday(nap.start)).font(.caption).foregroundStyle(Theme.textSecondary)
                    Text(dayMonth(nap.start)).font(.number(17, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                }
                .frame(width: 58, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(nap.minutes)").font(.number(22)).foregroundStyle(nap.level.color)
                        Text("phút").font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    Text(TodayViewModel.time(nap.start)).font(.caption2).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 4) {
                    NapChip(minutes: nap.minutes, compact: true)
                    if nap.estimated { EstimatedTag() }
                }
            }
            Text(nap.note)
                .font(.caption).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, Theme.Space.l)
    }

    // MARK: - Trạng thái trống (thành thật về giới hạn thiết bị)

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "powersleep").font(.system(size: 54)).foregroundStyle(Theme.sleep)
            Text("Chưa ghi nhận giấc ngủ trưa nào")
                .font(.title3.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text("App tự lưu khi vòng Fitbit ghi được giấc ngủ ban ngày, hoặc khi nhịp tim tụt rõ về mức nghỉ đủ lâu (ước tính). Giấc quá ngắn vẫn có thể bỏ sót.")
                .font(.callout).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity).padding(.top, 50).padding(.horizontal, Theme.Space.l)
    }

    /// Dòng chẩn đoán hôm nay (giúp hiểu vì sao có/không ghi + để canh ngưỡng cho đúng).
    private func diagnosticView(_ d: NapDetector.Diagnostics) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Phân tích nhịp tim hôm nay", systemImage: "stethoscope")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
            Text("Nhịp nghỉ app dùng: \(Int(d.resting)) · nền ban ngày: \(Int(d.baseline))")
                .font(.caption).foregroundStyle(Theme.textSecondary)
            Text("Nhịp thấp nhất: \(Int(d.lowestBpm))" + (d.lowestAt.map { " lúc \(hm($0))" } ?? "")
                 + " · đoạn nhịp thấp dài nhất: \(Int(d.longestLowRunMinutes)) phút")
                .font(.caption).foregroundStyle(Theme.textSecondary)
            Text(d.reason).font(.caption.weight(.medium)).foregroundStyle(Theme.caution)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surfaceMuted.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.small))
    }

    private func hm(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
    }

    private var deviceNote: some View {
        Label("App tự đọc phiên ngủ Fitbit và ước tính thêm từ nhịp tim khi Fitbit bỏ sót (nhãn “ước tính”, độ dài chỉ gần đúng). Không cần ghi tay.",
              systemImage: "info.circle")
            .font(.caption).foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }

    // MARK: - Định dạng ngày

    private func weekday(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "vi_VN"); f.dateFormat = "EEE"
        return f.string(from: d).capitalized
    }
    private func dayMonth(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "vi_VN"); f.dateFormat = "d/M"
        return f.string(from: d)
    }
}
