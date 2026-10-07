# TROUBLESHOOTING — lỗi hay gặp

### 1. `xcodegen: command not found` / project không có file mới
`brew install xcodegen`. Thêm/xoá file Swift, sửa `project.yml` hay `Config/*.xcconfig` → **luôn** chạy lại
`xcodegen generate` (`.xcodeproj` không nằm trong git, sinh lại mới đúng).

### 2. `Signing for "BBHealth" requires a development team`
Chưa có `Config/Local.xcconfig` hoặc `DEVELOPMENT_TEAM` trống → `cp Config/Local.xcconfig.example Config/Local.xcconfig`,
điền Team ID → `xcodegen generate`. (Simulator build không cần team.)

### 3. `Failed to register bundle identifier` / `The app identifier "…" cannot be registered to your development team`
Bundle id đã thuộc team khác (vd bạn để `com.example.bbhealth` hoặc dùng trùng của người khác). Đặt bundle id
**riêng** trong `Config/Local.xcconfig` → `xcodegen generate`.

### 4. `Provisioning profile … doesn't include the com.apple.developer.healthkit entitlement` / HealthKit báo lỗi quyền
Xcode → target → **Signing & Capabilities** → **+ Capability → HealthKit**, tick **Background Delivery** → build lại
(Automatic signing tự cập nhật profile). Dùng script release: chạy `python3 scripts/asc_signing.py` (không kèm
`--keep-profile`) để tạo lại profile App Store có HealthKit. Một số capability có thể không có với Apple ID miễn phí.

### 5. Trên simulator không thấy số thật / iPhone thật toàn số 0
Simulator **luôn** dùng dữ liệu giả (đúng thiết kế). iPhone thật: app **Sức khoẻ → Chia sẻ → Ứng dụng → BBHealth** →
bật hết quyền đọc; kiểm tra thiết bị đã đồng bộ vào Apple Health. Muốn số giả trên máy thật: `BBH_MOCK=1` (SETUP §7).

### 6. Đăng nhập Google báo `400` / `redirect_uri_mismatch` / `access_denied`
Xem bảng cuối [GOOGLE-HEALTH-SETUP.md](GOOGLE-HEALTH-SETUP.md): Client ID phải loại **iOS**, Bundle ID khớp app,
tài khoản nằm trong **Test users**, API đã Enable. Hết hạn sau ~7 ngày ở chế độ Testing là bình thường.

### 7. Gemini `404` (model not found)
Project/khoá mới không được dùng model đời cũ (vd `gemini-2.5-*`). Cài đặt → Trợ lý AI → chọn model **3.x**
(`gemini-3.8-flash`, `gemini-3.5-flash-lite`).

### 8. Gemini `503` / `429` (quá tải / hết hạn mức)
503 "high demand": app tự chuyển model nhẹ hơn; thử lại sau. 429: hết hạn mức miễn phí theo phút/ngày của project
→ chờ, dùng Flash-Lite, hoặc bật billing cho project AI Studio.

### 9. `Kiểm tra kết nối` báo 401/403
Khoá sai/thiếu ký tự, khoá thuộc hãng khác (dán khoá Gemini vào ô Claude…), hoặc tài khoản Claude/OpenAI chưa nạp
credit. Dán lại khoá — app tự cắt khoảng trắng.

### 10. AI trên iPhone "không sẵn sàng"
Cần iPhone hỗ trợ Apple Intelligence + iOS 26 + đã bật Apple Intelligence (Cài đặt → Apple Intelligence & Siri) và
mô hình đã tải xong. Máy khác dùng Gemini/Claude.

### 11. Script release: `Đặt ASC_KEY_ID` / `Không thấy file khoá` / `Thiếu Config/Local.xcconfig`
Làm đủ [RELEASE.md](RELEASE.md) mục B1–B2. `exit 3` = chưa tạo **app record** trên App Store Connect.

### 12. Export IPA `Error packaging up the application` / `Copy failed`
Khoá API không có quyền cloud signing → script ký tay (đúng). Cần cert **Apple Distribution** trong Keychain +
profile do `asc_signing.py` tạo. `Copy failed` do rsync Homebrew — script đã ép `/usr/bin/rsync`.

### 13. Build lỗi ở `FoundationModels` / `OnDeviceAIClient`
Cần **Xcode 26+** (SDK iOS 26). Xcode cũ hơn không build được.

### 14. Hồ sơ trong `OwnerProfile.json` không hiện
Thêm file xong phải `xcodegen generate` rồi build lại. App chỉ dùng file khi **chưa** lưu hồ sơ trong máy — vào
**Hồ sơ của tôi → Về mặc định** để nạp lại. JSON sai (thiếu trường, `sex`/`weightDirection` sai giá trị, `updatedAt`
không phải ISO-8601) thì app bỏ qua file → hồ sơ trống.
