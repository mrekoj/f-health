# SETUP — dựng BBHealth từ máy Mac trắng

Làm lần lượt. Mỗi khối lệnh copy–dán vào Terminal được. Mất ~20 phút (chưa tính tải Xcode).

## 0. Cần có

| Thứ | Ghi chú |
|---|---|
| Mac Apple Silicon, macOS mới | Đã kiểm với macOS 27 |
| **Xcode 26 trở lên** | App Store → Xcode. Cần SDK iOS 26 (phần AI trên máy dùng `FoundationModels`). Đã kiểm Xcode 26.5 |
| Homebrew | https://brew.sh |
| Tài khoản Apple | Chạy **simulator**: không cần. Chạy **iPhone thật**: Apple ID bất kỳ. **TestFlight**: tài khoản **Apple Developer Program trả phí** (99 USD/năm) |
| iPhone iOS 17+ | Để xem số thật từ Apple Health / Google Health |

## 1. Cài công cụ

```bash
xcode-select --install 2>/dev/null; sudo xcodebuild -license accept
brew install xcodegen git
xcodegen --version     # đã kiểm 2.45.x
```

Mở Xcode 1 lần cho nó cài thêm thành phần, và vào **Xcode → Settings → Components** tải **iOS Simulator**
nếu chưa có.

## 2. Lấy mã nguồn

```bash
mkdir -p ~/Workspace && cd ~/Workspace
git clone https://github.com/mrekoj/f-health.git
cd f-health
```

## 3. Cấu hình riêng của bạn — `Config/Local.xcconfig`

```bash
cp Config/Local.xcconfig.example Config/Local.xcconfig
open -e Config/Local.xcconfig
```

Sửa 3 dòng (file này **không** lên git):

```
DEVELOPMENT_TEAM = ABCDE12345            // Team ID của bạn
PRODUCT_BUNDLE_IDENTIFIER = com.yourname.bbhealth   // bundle id RIÊNG, không trùng người khác
APP_DISPLAY_NAME = BBHealth              // tên dưới icon (tuỳ ý)
```

- **Team ID** ở đâu: Xcode → **Settings → Accounts** → thêm Apple ID → chọn team → cột *Team ID*; hoặc
  https://developer.apple.com/account → **Membership details**. Chỉ chạy simulator thì để nguyên cũng được.
- **Bundle id**: dạng tên miền đảo ngược, **mỗi người một cái** (vd `com.hoang.bbhealth`, `com.cuong.bbhealth`).
  Bundle id đã đăng ký ở team người khác thì team bạn không dùng được.

(Tuỳ chọn) dòng `GOOGLE_HEALTH_CLIENT_ID` — xem [GOOGLE-HEALTH-SETUP.md](GOOGLE-HEALTH-SETUP.md).

## 4. Sinh project Xcode

```bash
xcodegen generate
```

Ra `BBHealth.xcodeproj` (không commit — luôn sinh lại từ `project.yml`). **Mỗi lần** đổi `project.yml`,
`Config/*.xcconfig`, thêm/xoá file Swift hoặc thêm `Resources/Private/OwnerProfile.json` → chạy lại lệnh này.

## 5. Chạy trên simulator

**Cách Xcode:** `open BBHealth.xcodeproj` → thanh trên chọn scheme **BBHealth** + một **iPhone simulator** → **⌘R**.

**Cách dòng lệnh** (thay `<UDID>` bằng id simulator của bạn):

```bash
xcrun simctl list devices available | grep iPhone        # lấy UDID một iPhone có sẵn
xcodebuild -project BBHealth.xcodeproj -scheme BBHealth \
  -destination 'id=<UDID>' -parallel-testing-enabled NO \
  -derivedDataPath build/DerivedData build
# → ** BUILD SUCCEEDED **
xcrun simctl boot <UDID> 2>/dev/null; open -a Simulator
APP=build/DerivedData/Build/Products/Debug-iphonesimulator/BBHealth.app
xcrun simctl install <UDID> "$APP"
xcrun simctl launch <UDID> "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist")"
```

> Dùng simulator **có sẵn** (`id=<UDID>`), đừng dùng `name=…` (có công cụ tự tạo simulator mới khi sai tên).

Trên simulator app **tự dùng dữ liệu giả** (Apple + Google đều giả lập) nên mọi màn đều có số. Lần đầu: hồ sơ
trống → thẻ **"Điền hồ sơ của bạn"** ở màn Hôm nay.

## 6. Hồ sơ sức khoẻ của bạn (tuỳ chọn)

Cách 1 — trong app: **Cài đặt → Hồ sơ của tôi** (hoặc bấm thẻ "Điền hồ sơ"). Lưu trong máy.

Cách 2 — file riêng, tiện khi cài lại app nhiều lần:

```bash
cp Resources/Private/OwnerProfile.example.json Resources/Private/OwnerProfile.json
open -e Resources/Private/OwnerProfile.json      # sửa tên, năm sinh, mục tiêu, bệnh nền, lời BS dặn…
xcodegen generate                                 # để file được đóng gói vào app
```

`Resources/Private/` nằm trong `.gitignore` — **không bao giờ** lên git. Các giá trị `sex`: `male|female|other`;
`weightDirection`: `gain|lose|keep`; `updatedAt` dạng `2026-01-01T00:00:00Z`.

## 7. Chạy trên iPhone thật

1. Cắm iPhone vào Mac (lần đầu bấm **Tin cậy** trên iPhone). iPhone: **Cài đặt → Quyền riêng tư & Bảo mật →
   Chế độ nhà phát triển → Bật** (máy khởi động lại).
2. Đảm bảo `Config/Local.xcconfig` có **Team ID** và **bundle id riêng** → `xcodegen generate`.
3. Xcode → chọn target **BBHealth** → tab **Signing & Capabilities**: *Automatically manage signing* đã bật, Team
   là team của bạn (lấy từ xcconfig). Không có lỗi đỏ là được.
4. Chọn iPhone ở thanh trên → **⌘R**. Lần đầu app xin quyền **Sức khoẻ** → **Bật tất cả**.
5. Số thật lấy từ app **Sức khoẻ** (Fitbit/Google Health/Apple Watch phải đồng bộ vào Apple Health trước), hoặc
   bật nguồn Google Health (mục 9).

Ép dùng số giả trên iPhone thật: Xcode → **Product → Scheme → Edit Scheme → Run → Arguments** → biến
`BBH_MOCK` = `1`.

## 8. Capabilities (quyền đặc biệt)

Đã khai sẵn trong `project.yml` → `Resources/BBHealth.entitlements`. Với *Automatically manage signing*, Xcode
tự bật trên App ID của bạn khi build lên máy thật.

| Capability | Bắt buộc? | Ghi chú |
|---|---|---|
| **HealthKit** (+ *Background Delivery*) | Có | Đọc ngủ/nhịp tim/bước/cân…, ghi cân. Background Delivery để tự lưu giấc ngủ trưa khi app ở nền |
| Bluetooth | Có (không phải capability) | Chỉ cần câu xin quyền `NSBluetoothAlwaysUsageDescription` — đã có |
| **App Groups** | Chỉ khi làm widget | Widget chưa có trong `main`. Khi thêm: tạo App Group `group.<bundle id>` ở developer.apple.com, thêm vào cả app + widget |
| **iCloud (iCloud Drive)** | Chưa dùng | App hiện xuất file vào app **Tệp** (thư mục app), chưa ghi thẳng iCloud Drive |

Nếu Xcode báo thiếu capability: tab **Signing & Capabilities** → **+ Capability** → thêm **HealthKit** → tick
**Background Delivery**. (Đừng sửa tay `BBHealth.entitlements` — xcodegen ghi đè; sửa ở `project.yml`.)

## 9. Nguồn Google Health / Trợ lý AI (tuỳ chọn)

- Google Health (HRV, nhiệt độ da, số chi tiết hơn): [GOOGLE-HEALTH-SETUP.md](GOOGLE-HEALTH-SETUP.md).
- Trợ lý AI: [AI-SETUP.md](AI-SETUP.md).

## 10. Lên TestFlight

[RELEASE.md](RELEASE.md). Lỗi: [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## Kiểm tra nhanh đã dựng đúng

```bash
git status --short          # KHÔNG được thấy Config/Local.xcconfig hay Resources/Private/OwnerProfile.json
git check-ignore -v Config/Local.xcconfig Resources/Private/OwnerProfile.json
```
