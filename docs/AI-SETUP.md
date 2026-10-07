# Trợ lý AI — tự lấy khoá, dán vào app

App **không nhúng khoá AI nào**. Mỗi người dùng tự chọn một trong các cách dưới, khoá lưu trong **Keychain**
của iPhone (không lên git, không gửi đi đâu ngoài hãng AI đã chọn). Vào **Cài đặt → Trợ lý AI**.

| Lựa chọn | Cần gì | Chi phí | Ghi chú |
|---|---|---|---|
| **Không dùng AI** | — | 0 | Báo cáo + nhận xét tự tính vẫn chạy; có nút *Sao chép cho AI* để dán sang app chat bất kỳ |
| **AI trên iPhone** (Apple Intelligence) | iPhone hỗ trợ Apple Intelligence, iOS 26, đã bật Apple Intelligence | 0 | Chạy trong máy, không gửi dữ liệu đi. Máy không hỗ trợ → mục này tự ẩn/báo không sẵn sàng |
| **Google Gemini** | Khoá AI Studio | Có gói miễn phí | Khuyên dùng để bắt đầu |
| **Claude (Anthropic)** | Khoá API console | Trả theo lượt (vài xu/báo cáo) | Thuê bao Claude.ai/Claude Code **không** cho khoá API |
| **OpenAI-tương-thích** | Khoá OpenAI / OpenRouter, hoặc Ollama/LM Studio trong mạng nhà (không cần khoá) | Tuỳ | Sửa *Base URL* trong màn Trợ lý AI |

## Gemini (miễn phí)

1. Mở https://aistudio.google.com/apikey bằng tài khoản Google của bạn.
2. **Create API key** → chọn/tạo project → copy khoá (dạng `AQ.…` với khoá mới, hoặc `AIza…` với khoá cũ).
3. App → **Cài đặt → Trợ lý AI** → hãng **Gemini** → **Dán & lưu** → **Kiểm tra kết nối**.
4. Model mặc định `gemini-3.8-flash`; quá tải (503) thì app tự thử model nhẹ hơn (3.5/3.1 Flash-Lite).

Lưu ý quyền riêng tư: gói **miễn phí** của Gemini cho phép Google dùng nội dung để cải thiện dịch vụ. App hiện
hộp xác nhận lần đầu gửi. Dữ liệu sức khoẻ nhạy cảm → cân nhắc gói trả phí hoặc AI trên iPhone.

## Claude

1. https://console.anthropic.com → **API Keys → Create Key** (cần nạp credit ở **Billing**).
2. App → hãng **Claude** → dán khoá `sk-ant-…` → Kiểm tra kết nối. Model mặc định `claude-opus-5-5`
   (đổi sang Sonnet/Haiku cho rẻ hơn).

## OpenAI / OpenRouter / Ollama

- OpenAI: https://platform.openai.com/api-keys → khoá `sk-…`; Base URL mặc định `https://api.openai.com/v1`.
- OpenRouter: Base URL `https://openrouter.ai/api/v1`, khoá OpenRouter, model dạng `hãng/model`.
- Ollama trong nhà: Base URL `http://<IP-máy-Mac>:11434/v1`, để trống khoá, model đã `ollama pull`.

## Dùng ở đâu trong app

- **Xu hướng → Báo cáo** (Ngày/Tuần/Tháng/90 ngày): *Nhờ AI phân tích* (nhanh) / *Phân tích sâu*; bài lưu theo kỳ,
  mở lại không tốn lượt.
- **Hỏi AI** (chat): AI tự gọi công cụ tra số liệu (một ngày, các đêm, nhịp tim theo giờ, nhật ký, hồ sơ).
- **Hôm nay → Lời khuyên sáng nay** (1 lần/ngày, tắt được) · nút **Hỏi AI** trong Giấc ngủ / Nhịp tim.

Nội dung gửi AI = **Hồ sơ của tôi** + số liệu kỳ đang xem. Điền hồ sơ kỹ (bệnh nền, lời BS dặn) thì lời khuyên sát hơn.

## Cờ debug khi phát triển (chỉ bản Debug)

Biến môi trường (Xcode → Edit Scheme → Run → Arguments → Environment, hoặc `SIMCTL_CHILD_…` khi `simctl launch`):

| Biến | Ý nghĩa |
|---|---|
| `BBH_AI_KIND` | `none` · `appleOnDevice` · `gemini` · `claude` · `openAICompatible` |
| `BBH_AI_KEY` | Khoá dùng tạm (không ghi vào Keychain) |
| `BBH_MOCK=1` | Ép dữ liệu giả trên iPhone thật |

```bash
SIMCTL_CHILD_BBH_AI_KIND=gemini SIMCTL_CHILD_BBH_AI_KEY="$GEMINI_KEY" \
  xcrun simctl launch <UDID> <bundle id> -BBHShowReport week -BBHAutoAI YES
```

Tham số khởi động (launch arguments) để mở thẳng màn khi thử/chụp ảnh — định nghĩa ở `DebugOptions`
(`Sources/BBHealth/App/BBHealthApp.swift`): `-BBHTab today|trends|plan|log|settings`, `-BBHShowReport day|week|month`,
`-BBHAutoAI`, `-BBHChat "câu hỏi"`, `-BBHShowExplain sleep`, `-BBHShowHeart`, `-BBHShowLive`, `-BBHShowBreath`,
`-BBHBreathLibrary`, `-BBHBreathPattern <id>`, `-BBHNow 09:10`. Đọc `DebugOptions` để biết đủ danh sách.

**Không bao giờ** commit khoá vào code, scheme hay file `.env` (đã có trong `.gitignore`).
