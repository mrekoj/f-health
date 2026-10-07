# Resources/Private — dữ liệu riêng, KHÔNG commit

Thư mục này nằm trong `.gitignore` (trừ file này và file mẫu). Đặt ở đây:

- `OwnerProfile.json` — hồ sơ sức khoẻ của chính bạn. Có file → app dùng làm hồ sơ mặc định
  (vẫn sửa được trong app: Cài đặt → Hồ sơ của tôi). Không có → app chạy với hồ sơ trống.

Cách tạo: `cp Resources/Private/OwnerProfile.example.json Resources/Private/OwnerProfile.json`,
sửa nội dung, rồi chạy lại `xcodegen generate` (để file được đóng gói vào app).

Lưu ý: app chỉ dùng file này khi **chưa** lưu hồ sơ trong máy. Nếu đã sửa hồ sơ trong app,
vào Hồ sơ của tôi → "Về mặc định" để nạp lại từ file.
