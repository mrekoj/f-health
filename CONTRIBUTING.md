# CONTRIBUTING — mỗi người app riêng, code chung qua PR

## Mô hình

- **`mrekoj/f-health` là nguồn chung (upstream).** Mọi người — kể cả người viết code đầu tiên — đóng góp vào đây qua
  **Pull Request**. Không ai push thẳng `main`.
- **Mỗi người một app riêng**: Team Apple, bundle id, tên app, project Google, khoá AI, tài khoản App Store Connect
  **của mình**, đặt trong file riêng không lên git (`Config/Local.xcconfig`, `Resources/Private/`, Keychain, biến môi trường).
- Code, giao diện, nội dung giải thích chung → PR. Hồ sơ sức khoẻ cá nhân → **không bao giờ** vào repo.

## Quy trình

```bash
git checkout main && git pull
git checkout -b feat/ten-ngan-gon          # feat/… fix/… docs/… chore/…
# … sửa code …
xcodegen generate
xcodebuild -project BBHealth.xcodeproj -scheme BBHealth -destination 'id=<UDID>' -parallel-testing-enabled NO build
git add -p && git commit
git push -u origin feat/ten-ngan-gon
gh pr create --base main --fill            # hoặc mở PR trên github.com
```

- **1 người review** đồng ý mới merge (người khác người mở PR). Merge kiểu **Squash and merge**, xoá nhánh sau merge.
- Repo private của tài khoản cá nhân: **chủ repo** bật luật bảo vệ `main` (Settings → Branches → Add rule `main`:
  *Require a pull request before merging* + *Require approvals: 1*). Chưa bật thì cả nhóm tự giữ quy ước trên.
- Muốn giữ bản riêng có tuỳ biến không đóng góp được: fork/nhánh riêng, thỉnh thoảng `git pull` từ `main` về.

## Quy ước commit

`<loại>(<phạm vi>): <mô tả tiếng Việt ngắn>` — loại: `feat` `fix` `refactor` `docs` `chore` `test`.

```
feat(sleep): thêm biểu đồ giờ ngủ theo tuần
fix(google): làm mới token khi hết hạn giữa chừng
```

Định danh code (tên biến, hàm, kiểu) bằng tiếng Anh; chữ trên màn hình bằng tiếng Việt đời thường.

## TUYỆT ĐỐI KHÔNG commit

| Không commit | Để ở đâu |
|---|---|
| `Config/Local.xcconfig` (Team ID, bundle id, Client ID) | máy bạn (gitignore) |
| `Resources/Private/OwnerProfile.json`, mọi hồ sơ/số đo/bệnh án thật | máy bạn (gitignore) |
| Khoá `AuthKey_*.p8`, Key ID/Issuer ID, khoá Gemini/Claude/OpenAI, token | `~/.appstoreconnect/`, biến môi trường, Keychain |
| `BBHealth.xcodeproj` | sinh lại bằng `xcodegen generate` |
| Ảnh chụp có số liệu sức khoẻ thật | chỉ chụp trên **simulator** (dữ liệu giả) |
| Tên/email/SĐT thật, tên bác sĩ, bệnh viện trong code hay nội dung | dùng chữ chung chung; thông tin riêng đặt trong Hồ sơ |
| Thay đổi `CURRENT_PROJECT_VERSION` do script release tự tăng | bỏ khỏi PR (`git checkout project.yml`) |

Trước khi push, tự rà:

```bash
git status --short                                  # không thấy Local.xcconfig / Private/
git diff main --stat
git grep -n -I -E 'AuthKey_[A-Z0-9]|BEGIN [P]RIVATE KEY|AIza[0-9A-Za-z_-]{30}|sk-ant-[a-z0-9]|@g[m]ail[.]com' || echo "sạch"
```

## Checklist PR

- [ ] Build simulator **BUILD SUCCEEDED** (đã `xcodegen generate`).
- [ ] Chạy thử màn đã sửa trên simulator; ảnh chụp (nếu có) chỉ dùng dữ liệu giả.
- [ ] Không có file/dữ liệu riêng (bảng trên), không đổi số build.
- [ ] Chữ mới trên màn hình bằng tiếng Việt, chỉ số mới có nút **?** giải thích.
- [ ] Ngưỡng/mục tiêu đọc từ **Hồ sơ** (`Thresholds`/`HealthProfileStore`), không viết cứng số của riêng ai.
- [ ] Cập nhật tài liệu `docs/` nếu đổi cách cài đặt/cấu hình.
- [ ] Mô tả PR: làm gì, vì sao, cách kiểm.

## Đồng bộ app riêng với nguồn chung

```bash
git checkout main && git pull origin main
xcodegen generate     # rồi build/Run như thường; Local.xcconfig + Private/ của bạn không bị đụng
```

Nếu bạn từng có bản code riêng trước khi có f-health: đưa thông tin cá nhân vào `Resources/Private/OwnerProfile.json`
(hoặc Hồ sơ trong app), rồi dùng `main` của f-health làm gốc; phần code riêng muốn giữ → mở PR như trên.
