# RELEASE — đưa app CỦA BẠN lên TestFlight

Mỗi người phát hành **app riêng** dưới **tài khoản Apple Developer + App Store Connect (ASC) của mình**, với bundle id
trong `Config/Local.xcconfig`. Có 2 cách: **A. bấm trong Xcode** (dễ, khuyên dùng lần đầu) hoặc **B. script 1 lệnh**.

## Chuẩn bị (1 lần)

1. Tham gia **Apple Developer Program** (trả phí). Ghi **Team ID**.
2. `Config/Local.xcconfig` đã có `DEVELOPMENT_TEAM` + `PRODUCT_BUNDLE_IDENTIFIER` riêng → `xcodegen generate`.
3. Chạy app lên iPhone thật 1 lần bằng Xcode (Automatic signing) → Xcode tự đăng ký **bundle id** + bật **HealthKit**
   trên App ID của team bạn.
4. **Tạo app record** trên ASC (API không tạo được, phải bấm tay):
   1. https://appstoreconnect.apple.com → **Apps** → **+** → **New App**.
   2. Platform **iOS** · Name: tên app (phải duy nhất trên App Store — vd `BBHealth Hoàng`) · Primary language **Vietnamese**.
   3. **Bundle ID**: chọn đúng bundle id của bạn · **SKU**: tuỳ ý (vd `bbhealth-001`) · **Full Access** → **Create**.

Số build: `CURRENT_PROJECT_VERSION` trong `project.yml` phải **tăng** mỗi lần upload (version `MARKETING_VERSION`).
Script B tự tăng; cách A thì sửa `project.yml` → `xcodegen generate` trước khi Archive.

## A. Archive trong Xcode

1. Thanh trên chọn **Any iOS Device (arm64)**.
2. **Product → Archive** (ký Automatic bằng team của bạn, Xcode tự tạo cert/profile phân phối nếu cần).
3. Cửa sổ **Organizer** → chọn bản vừa archive → **Distribute App** → **App Store Connect** → **Upload** → Next… → Upload.
4. Chờ 5–30 phút: ASC → app → **TestFlight** → build hiện *Processing* rồi *Ready to Submit / Missing Compliance*.
   App đã khai `ITSAppUsesNonExemptEncryption = false` nên thường không hỏi; nếu hỏi → chọn *None of the algorithms*.
5. **TestFlight → Internal Testing → +** tạo nhóm, thêm người trong team ASC → build → họ cài qua app **TestFlight**.

## B. Script 1 lệnh — `scripts/release-testflight.sh`

Script: ký qua ASC API (bundle id + HealthKit + profile App Store) → tăng số build → `xcodegen` → `xcodebuild archive`
→ export IPA (ký tay) → upload (`xcrun altool`, lỗi thì thử `fastlane`) → chờ xử lý → khai encryption + gắn nhóm nội bộ.

### B1. Tạo khoá App Store Connect API (của bạn)

1. ASC → **Users and Access → Integrations → App Store Connect API → Team Keys → +**. Tên tuỳ ý, quyền **Admin**
   (hoặc *App Manager*; tạo profile cần Admin).
2. Tải file **`AuthKey_<KEY_ID>.p8`** (chỉ tải được 1 lần). Ghi **Key ID** và **Issuer ID** (trên đầu trang).
3. Cất khoá ngoài repo:
   ```bash
   mkdir -p ~/.appstoreconnect/private_keys
   mv ~/Downloads/AuthKey_*.p8 ~/.appstoreconnect/private_keys/
   chmod 600 ~/.appstoreconnect/private_keys/AuthKey_*.p8
   ```
4. Cần **chứng chỉ Apple Distribution** trong Keychain máy Mac: Xcode → **Settings → Accounts** → team → **Manage
   Certificates → + → Apple Distribution** (bỏ qua nếu đã Archive bằng cách A trước đó).

### B2. Biến môi trường (thêm vào `~/.zshrc` cho tiện — KHÔNG đặt trong repo)

```bash
export ASC_KEY_ID=XXXXXXXXXX                              # Key ID
export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx # Issuer ID
# tuỳ chọn:
# export ASC_KEY_PATH=~/path/AuthKey_XXXXXXXXXX.p8        # nếu không để ở ~/.appstoreconnect/private_keys/
# export ASC_DIST_CERT_ID=...                             # mặc định: cert Apple Distribution mới nhất của team
# export ASC_PROFILE_NAME=BBHealth-AppStore               # tên provisioning profile App Store
# export BBH_TESTERS="ban@example.com,dongnghiep@example.com"   # tester nội bộ (phải là user trong team ASC)
```

Team + bundle id script đọc từ `Config/Local.xcconfig`.

### B3. Chạy

```bash
python3 -m pip install --user cryptography     # tuỳ chọn; không có thì script dùng openssl
python3 scripts/asc_testflight.py app-id       # in app id = đã có app record (thiếu → làm "Tạo app record")
python3 scripts/asc_testflight.py group        # tạo nhóm nội bộ + thêm BBH_TESTERS (1 lần)
scripts/release-testflight.sh                  # upload; xong nhớ commit project.yml nếu muốn giữ số build
```

Tuỳ chọn: `MARKETING_VERSION=1.1 scripts/release-testflight.sh` (đổi version) · `SKIP_BUMP=1` (giữ số build) ·
`UPLOAD_WITH=fastlane` · `WAIT_MIN=30`. Log: `build/archive.log`, `build/export.log`.
Đổi capability/entitlements → chạy `python3 scripts/asc_signing.py` (không `--keep-profile`) để tạo lại profile.

Công cụ dùng: `xcodebuild` (archive/export), `xcrun altool --upload-app` bằng khoá API, dự phòng
`fastlane run upload_to_testflight` (cần `brew install fastlane`). Không dùng `notarytool` (chỉ cho app macOS).

> Số build trong `project.yml` là của chung repo. Mỗi người có app ASC riêng nên số build độc lập — khi mở PR,
> **đừng commit** thay đổi `CURRENT_PROJECT_VERSION` do script tăng (xem CONTRIBUTING).

## Link TestFlight cho người ngoài (external)

1. Cần **Privacy Policy URL**: sửa mẫu trong `web/` (thay email liên hệ), đăng lên chỗ có HTTPS của **bạn**
   (GitHub Pages, Cloudflare Pages…). Không dùng trang/tên miền của người khác.
2. ASC → app → **App Information** → Privacy Policy URL. **TestFlight → Test Information**: mô tả, email phản hồi,
   thông tin liên hệ cho Apple review.
3. **External Testing → +** nhóm → thêm build → **Submit for Review** (lần đầu vài giờ–1 ngày) → bật **Public Link**.

Không nộp App Store (bản phát hành chính thức) nếu nhóm chưa thống nhất.
