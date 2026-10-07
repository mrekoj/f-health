# Bật nguồn Google Health bằng project Google Cloud CỦA BẠN

Nguồn **Google Health API** (`health.googleapis.com`, bản `v4beta`) cho thêm **HRV, nhiệt độ da**, giai đoạn ngủ,
nhịp tim theo giờ… từ Fitbit/thiết bị Google. App gọi thẳng Google từ điện thoại (OAuth PKCE, token lưu
Keychain, tự làm mới) — **không có máy chủ trung gian**.

Mỗi người dùng **project Google Cloud riêng** + **OAuth Client ID riêng** gắn với **bundle id riêng** của mình.
Không dùng chung Client ID giữa các app (Client ID iOS gắn cứng với một bundle id).

Làm 1 lần, ~15 phút. Màn hình đồng ý + OAuth client **phải bấm tay** trong Console (không có lệnh).

## Bước 1 — Tạo project + bật API

1. Mở https://console.cloud.google.com bằng tài khoản Google **đang đồng bộ dữ liệu Fitbit/Google Health**
   (hoặc tài khoản quản trị của bạn, rồi thêm tài khoản kia làm *Test user* ở bước 2).
2. Góc trên → chọn project → **New Project** → tên `bbhealth` (tuỳ ý) → **Create** → chọn project vừa tạo.
3. **APIs & Services → Library** → tìm **Google Health API** → **Enable**.

Hoặc bằng `gcloud` (nếu đã cài và đăng nhập):

```bash
gcloud projects create bbhealth-$RANDOM --name="BBHealth"     # ghi lại PROJECT_ID in ra
gcloud config set project <PROJECT_ID>
gcloud services enable health.googleapis.com
```

## Bước 2 — Màn hình đồng ý (OAuth consent screen)

1. **APIs & Services → OAuth consent screen** (giao diện mới: **Google Auth Platform → Branding/Audience/Data access**).
2. **User type = External** → **Create**.
3. App name: tên app của bạn; *User support email* và *Developer contact*: **email của bạn** → **Save**.
4. **Scopes / Data access → Add or remove scopes** → dán 3 scope (đúng như app xin — `GoogleAuth.swift`):
   ```
   https://www.googleapis.com/auth/googlehealth.sleep.readonly
   https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly
   https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly
   ```
   → **Update** → **Save**.
5. **Test users / Audience → Add users** → thêm **mọi tài khoản Google sẽ đăng nhập trong app** (chính bạn, người
   nhà…) → **Save**.

Để chế độ **Testing** là dùng được (tối đa 100 test user). Nhược điểm: token hết hạn **~7 ngày** → phải bấm
Đăng nhập lại. Scope Google Health là **restricted** — muốn *Publish* cho người ngoài phải qua thẩm định của
Google (có thể kèm đánh giá bảo mật có phí). Dùng cá nhân/nhóm nhỏ: cứ để Testing.

## Bước 3 — OAuth Client ID loại iOS

1. **APIs & Services → Credentials → Create credentials → OAuth client ID**.
2. **Application type = iOS**.
3. **Bundle ID = đúng `PRODUCT_BUNDLE_IDENTIFIER` trong `Config/Local.xcconfig` của bạn** (vd `com.hoang.bbhealth`).
4. **Create** → copy **Client ID** dạng `123456789-abc...xyz.apps.googleusercontent.com`.

Không cần khai URL scheme: app tự suy ra redirect từ Client ID đảo ngược
(`com.googleusercontent.apps.123456789-abc…:/oauth2redirect`).

## Bước 4 — Đưa Client ID vào app (chọn 1)

- **Trong app:** tab **Cài đặt** → ô **Google OAuth Client ID** → dán.
- **Nạp sẵn khi build:** `Config/Local.xcconfig` → `GOOGLE_HEALTH_CLIENT_ID = 123456789-abc...apps.googleusercontent.com`
  → `xcodegen generate` → build lại.

Client ID **không phải khoá bí mật** (app iOS không dùng client secret), nhưng vẫn để trong `Local.xcconfig`
(gitignore) cho gọn, vì nó gắn với project của riêng bạn.

## Bước 5 — Đăng nhập

1. **Cài đặt → Nguồn dữ liệu**: chọn **Google Health** hoặc **Cả hai** (ưu tiên Google, thiếu lấy Apple).
2. **Đăng nhập Google** → chọn tài khoản đã thêm ở *Test users* → màn "Google hasn't verified this app" →
   **Continue** → tick đủ quyền → **Cho phép**.
3. Màn **Hôm nay** có thêm ô **HRV** và **Nhiệt độ da** (cần vài đêm đeo thiết bị liên tục).

## Lỗi hay gặp

| Lỗi | Sửa |
|---|---|
| `400` / "Đã xảy ra lỗi" ngay trang Google | Client ID dán sai (dính xuống dòng, dán nhầm khoá Gemini `AQ.`/`AIza…`). App chặn sẵn dạng sai, kiểm lại ô Client ID |
| `redirect_uri_mismatch` / `invalid_request` | Client ID không phải loại **iOS**, hoặc **Bundle ID** khai ở Google ≠ bundle id app đang chạy |
| `access_denied` / "app chưa được duyệt" | Tài khoản chưa nằm trong **Test users** |
| Phải đăng nhập lại sau ~1 tuần | Bình thường ở chế độ Testing |
| `403 … API not enabled` | Chưa **Enable Google Health API** cho đúng project |
| HRV / nhiệt độ da trống | Thiết bị cần vài đêm; mở app Google Health/Fitbit cho đồng bộ |

Trên **simulator** nguồn Google là **giả lập** (đăng nhập giả, số giả) — kiểm số thật trên iPhone.
