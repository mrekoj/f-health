# BBHealth (f-health) — luật cho trợ lý code AI

App iOS sức khoẻ tiếng Việt (SwiftUI, iOS 17+, HealthKit, Google Health API, Trợ lý AI). Repo **dùng chung**:
mỗi người build app riêng (Team/bundle riêng), đóng góp qua PR. Đọc `README.md`, `CONTRIBUTING.md`, `docs/SETUP.md`.

## Dữ liệu riêng — bắt buộc
- KHÔNG đưa vào code/docs/ảnh/commit: tên, email, SĐT, hồ sơ bệnh, số đo thật, tên bác sĩ/bệnh viện, Team ID,
  bundle id riêng, Key ID/Issuer ASC, khoá AI, Client ID Google, đường dẫn máy cá nhân.
- Cấu hình riêng: `Config/Local.xcconfig` (gitignore). Hồ sơ riêng: `Resources/Private/OwnerProfile.json` (gitignore).
- Ngưỡng/mục tiêu/lời khuyên theo người: đọc từ `HealthProfile` (`HealthProfileStore.current`, `Thresholds`), không viết cứng.
- Không thêm dòng `Co-Authored-By` hay dấu vết AI vào commit/PR.

## Build & test
- `project.yml` (xcodegen) → `xcodegen generate` → build:
  `xcodebuild -project BBHealth.xcodeproj -scheme BBHealth -destination 'id=<UDID>' -parallel-testing-enabled NO build`
- Dùng simulator **có sẵn** theo `id=<UDID>` (`xcrun simctl list devices available`). KHÔNG `xcrun simctl create`,
  không xoá/erase simulator, không dùng `-destination 'name=…'`, luôn `-parallel-testing-enabled NO`.
- `BBHealth.xcodeproj` là file sinh ra — không sửa tay, không commit. Sửa `project.yml` rồi generate lại.
- HealthKit không có số thật trên simulator → app tự dùng provider giả (`MockHealthStoreProvider`,
  `MockGoogleHealthProvider`). Mở thẳng màn để kiểm/chụp bằng launch args `-BBH…` (`DebugOptions` trong `App/BBHealthApp.swift`).
- Ảnh chụp đưa vào repo: chỉ từ simulator (dữ liệu giả), để ở `docs/screenshots/`.

## Kiến trúc
- Nguồn dữ liệu: protocol `HealthStoreProvider` — `HKHealthStoreProvider` (Apple), `GoogleHealthProvider`
  (`health.googleapis.com/v4beta`, OAuth PKCE qua `ASWebAuthenticationSession`, token Keychain, tự refresh),
  `CompositeProvider` (ưu tiên Google, thiếu lấy Apple), `Mock*`. Chọn nguồn ở tab Cài đặt.
- AI: `AIClient` (stream SSE, sự kiện text/toolCall) — Gemini/Claude/OpenAI-tương-thích (khoá người dùng, Keychain),
  `OnDeviceAIClient` (FoundationModels); `HealthDataTools` cho AI tự tra số liệu; `HealthReportBuilder` → `HealthReportText`.
- Lưu trữ: SwiftData (`LogEntry`, `NapLog`, `HeartEvent`, `LiveSession`, `AIAnalysis`, `AIChatMessage`), UserDefaults
  (cài đặt, hồ sơ), Keychain (token/khoá). Không máy chủ, không tài khoản.
- HealthKit: chỉ đọc + ghi cân nặng.

## Nguyên tắc giao diện
Chữ to, mỗi màn ≤ 4 ô chính, màu xanh/vàng/đỏ theo ngưỡng cá nhân (từ Hồ sơ), mọi chỉ số có nút "?" giải thích
2–3 câu tiếng Việt đời thường + "BS dặn"/"Gợi ý". Không thuật ngữ tiếng Anh trên màn hình. App chỉ tư vấn lối sống,
luôn nhắc "không thay bác sĩ".

## Quy ước
- Định danh code tiếng Anh; chữ hiển thị + mô tả commit tiếng Việt: `<loại>(<phạm vi>): <mô tả>`.
- Nhánh `feat/…`/`fix/…` → PR vào `main`, 1 review. Không push thẳng `main`. Không nộp App Store khi nhóm chưa thống nhất.
