# Phần 13: Tool Gateway, Local Proxy, và Live Search

*Nếu bạn có gói thuê bao Nous Portal trả phí hoặc nhà cung cấp hỗ trợ OAuth, Hermes có thể biến nó thành các công cụ: cuộc gọi web/hình ảnh/TTS/trình duyệt được quản lý, một local proxy tương thích OpenAI, và tính năng tìm kiếm X trực tiếp hạng nhất.*

---

## Đây Là Gì

Trước đây, nếu bạn muốn Hermes tìm kiếm trên web, tạo hình ảnh, nói, hoặc điều khiển trình duyệt, bạn cần **bốn tài khoản riêng biệt**:

- Firecrawl / Exa / Tavily / Parallel cho tìm kiếm web
- FAL cho tạo hình ảnh
- OpenAI / ElevenLabs cho TTS
- Browser Use / Browserbase cho tự động hóa trình duyệt

Đó là bốn lần đăng ký, bốn API key, bốn trang thanh toán, và bốn giới hạn free-tier khác nhau.

**Nous Tool Gateway** gộp tất cả những thứ đó thành một dòng trong config của bạn. Nếu bạn là thuê bao trả phí của [Nous Portal](https://portal.nousresearch.com), việc sử dụng công cụ sẽ tính vào gói thuê bao của bạn — không cần key bổ sung nào.

| Công cụ | Upstream | Key trực tiếp mà bạn sẽ cần nếu không dùng gateway |
|------|----------|---------------------------------|
| Tìm kiếm & trích xuất web | Firecrawl | `FIRECRAWL_API_KEY`, `EXA_API_KEY`, `PARALLEL_API_KEY`, `TAVILY_API_KEY` |
| Tạo hình ảnh | FAL (FLUX 2 Pro + upscaling) | `FAL_KEY` |
| Chuyển văn bản thành giọng nói | OpenAI TTS | `VOICE_TOOLS_OPENAI_KEY`, `ELEVENLABS_API_KEY` |
| Tự động hóa trình duyệt | Browser Use | `BROWSER_USE_API_KEY`, `BROWSERBASE_API_KEY` |

Mỗi công cụ đều tùy chọn bật/tắt. Bạn có thể định tuyến **bất kỳ tổ hợp nào** qua gateway và giữ key trực tiếp cho phần còn lại — ví dụ, dùng gateway cho web + hình ảnh, dùng key ElevenLabs riêng cho TTS.

---

## Ai Được Dùng Tính Năng Này

Thuê bao trả phí của [Nous Portal](https://portal.nousresearch.com/manage-subscription). Tài khoản free-tier không có quyền truy cập gateway.

Kiểm tra trạng thái của bạn:

```bash
hermes status
```

Tìm phần **Nous Tool Gateway**. Nó hiển thị công cụ nào đang hoạt động qua gateway, công cụ nào đang dùng key trực tiếp, và công cụ nào chưa được cấu hình.

---

## Kích Hoạt Gateway

### Cách A: Trong Lúc Thiết Lập Model (Dễ Nhất)

Khi bạn chạy `hermes model` và chọn **Nous Portal** làm nhà cung cấp, Hermes sẽ tự động hỏi bạn có muốn kích hoạt Tool Gateway không:

```text
Your Nous subscription includes the Tool Gateway.
The Tool Gateway gives you access to web search, image generation,
text-to-speech, and browser automation through your Nous subscription.
No need to sign up for separate API keys — just pick the tools you want.

  ○ Web search & extract (Firecrawl)   — not configured
  ○ Image generation (FAL)             — not configured
  ○ Text-to-speech (OpenAI TTS)        — not configured
  ○ Browser automation (Browser Use)   — not configured
  ● Enable Tool Gateway
  ○ Skip
```

Chọn **Enable Tool Gateway**. Xong.

Nếu bạn đã có key trực tiếp cho một số công cụ, lời nhắc sẽ điều chỉnh tương ứng — bạn có thể bật gateway cho tất cả (các key hiện có vẫn nằm trong `.env` nhưng không được dùng lúc chạy), chỉ bật cho các công cụ chưa được cấu hình, hoặc bỏ qua hoàn toàn.

### Cách B: Từng Công Cụ Qua `hermes tools`

```bash
hermes tools
```

Chọn một danh mục (Web, Browser, Image Generation, hoặc TTS), sau đó chọn **Nous Subscription** làm nhà cung cấp. Việc này sẽ bật `use_gateway: true` cho công cụ đó trong `config.yaml`.

### Cách C: Cấu Hình Thủ Công

Chỉnh sửa `~/.hermes/config.yaml`:

```yaml
web:
  backend: firecrawl
  use_gateway: true

image_gen:
  use_gateway: true

tts:
  provider: openai
  use_gateway: true

browser:
  cloud_provider: browser-use
  use_gateway: true
```

---

## Cách Hoạt Động Của Thứ Tự Ưu Tiên

Với mỗi công cụ, runtime kiểm tra `use_gateway` trước:

- `use_gateway: true` → **luôn luôn** định tuyến qua gateway, ngay cả khi có key API trực tiếp trong `.env`
- `use_gateway: false` (hoặc không đặt) → dùng key trực tiếp nếu có, chỉ chuyển sang gateway khi không có key trực tiếp nào

Điều này có nghĩa là bạn có thể có cả `FAL_KEY` và một gói thuê bao Nous trong `.env` cùng lúc và xác định rõ ràng cái nào sẽ được dùng. Không cần xóa key, không cần comment dòng nào.

### Biến Môi Trường Cũ Đã Biến Mất

`HERMES_ENABLE_NOUS_MANAGED_TOOLS` từng là một cờ env ẩn trong v0.9. Nó đã biến mất trong v0.10 — được thay thế bằng cơ chế phát hiện dựa trên gói thuê bao rõ ràng cộng với cấu hình `use_gateway` theo từng công cụ. Nếu bạn từng đặt cờ đó, `hermes upgrade` sẽ tự động chuyển đổi giúp bạn.

---

## Xác Minh Nó Đang Hoạt Động

```bash
hermes status
```

Tìm:

```text
◆ Nous Tool Gateway
  Nous Portal   ✓ managed tools available
  Web tools     ✓ active via Nous subscription
  Image gen     ✓ active via Nous subscription
  TTS           ✓ active via Nous subscription
  Browser       ○ active via Browser Use key
  Modal         ○ available via subscription (optional)
```

Các dòng được đánh dấu "active via Nous subscription" được định tuyến qua gateway. Các dòng có key riêng sẽ hiển thị nhà cung cấp nào đang hoạt động.

Bạn cũng có thể xem mức sử dụng gateway trong tab **Analytics** của Dashboard (Phần 12) — các lệnh gọi gateway được tính vào gói thuê bao Nous của bạn và được tổng hợp cùng với mức sử dụng token của LLM.

---

## Chuyển Về Dùng Key Trực Tiếp

Tương tác:

```bash
hermes tools
# Pick the tool → choose a direct provider
```

Thủ công:

```yaml
web:
  backend: firecrawl
  use_gateway: false   # now uses FIRECRAWL_API_KEY from .env
```

Khi bạn chọn một nhà cung cấp không phải gateway trong `hermes tools`, `use_gateway` sẽ tự động được đặt thành `false` để tránh cấu hình mâu thuẫn.

---

## Local Proxy Tương Thích OpenAI

v0.14 bổ sung `hermes proxy`: một endpoint local tương thích OpenAI, được hỗ trợ bởi bất kỳ nhà cung cấp OAuth nào bạn đã đăng nhập — Claude Pro, ChatGPT Pro/Codex, hoặc SuperGrok. Đây là cách gọn gàng để cho phép Codex CLI, Aider, Cline, Continue, hoặc các script nội bộ tái sử dụng gói thuê bao mà không cần sao chép API key.

```bash
hermes model          # sign in to Claude / OpenAI / xAI OAuth first
hermes proxy --host 127.0.0.1 --port 11435
```

Sau đó trỏ các client tương thích OpenAI tới `http://127.0.0.1:11435/v1` với một dummy key cục bộ. Giữ nó chỉ ở loopback trừ khi bạn thêm xác thực thực sự phía trước.

---

## `x_search`: Tìm Kiếm X Hạng Nhất

Dùng `x_search` khi nguồn thông tin đáng tin cậy là một luồng bài đăng X/Twitter trực tiếp, bài đăng ra mắt, hoặc tài khoản của maintainer. Nó hỗ trợ xác thực X OAuth hoặc API key, và kết hợp tự nhiên với Grok 4.3 / SuperGrok OAuth.

```yaml
tools:
  x_search:
    enabled: true
    auth: oauth        # or api_key
    max_results: 25
```

Dùng tìm kiếm web rộng hơn cho tài liệu/blog; dùng `x_search` cho tín hiệu mạng xã hội thời gian thực.

---

## Gateway Tự Lưu Trữ / Doanh Nghiệp

Nếu bạn đang chạy endpoint gateway riêng của mình (triển khai doanh nghiệp, môi trường staging), ghi đè các giá trị mặc định trong `~/.hermes/.env`:

```bash
TOOL_GATEWAY_DOMAIN=nousresearch.com     # base domain for routing
TOOL_GATEWAY_SCHEME=https                # http or https (default: https)
TOOL_GATEWAY_USER_TOKEN=your-token       # auth token (normally auto-populated)
FIRECRAWL_GATEWAY_URL=https://...        # override a specific endpoint
```

Các biến env này luôn hiển thị bất kể trạng thái gói thuê bao — chúng ở đây để cơ sở hạ tầng tùy chỉnh hoạt động mà không cần thay đổi code.

---

## Câu Hỏi Thường Gặp

### Tôi có phải xóa các API key hiện có của mình không?
Không. Khi `use_gateway: true` được đặt, runtime bỏ qua key trực tiếp và định tuyến qua gateway. Key của bạn vẫn nằm trong `.env`. Chuyển về dùng chúng bất cứ lúc nào.

### Tôi có thể kết hợp gateway và key trực tiếp không?
Có — nó áp dụng theo từng công cụ. Dùng gateway cho web + hình ảnh, ElevenLabs cho TTS, Browserbase cho duyệt web là một thiết lập hoàn toàn bình thường.

### Điều gì xảy ra nếu gói thuê bao của tôi hết hạn?
Các công cụ định tuyến qua gateway sẽ ngừng hoạt động. Hãy gia hạn tại [portal.nousresearch.com](https://portal.nousresearch.com/manage-subscription) hoặc chuyển các công cụ đó sang key trực tiếp qua `hermes tools`.

### Nó có hoạt động trên Telegram / Discord / Slack / v.v. không?
Có. Gateway hoạt động ở cấp độ runtime của công cụ, không phải ở cấp độ điểm truy cập. Nó hoạt động giống nhau dù bạn đang dùng CLI, một nền tảng nhắn tin, một cron job, hay REST API của dashboard.

### Modal (terminal serverless) có được bao gồm không?
Không — Modal là một tiện ích bổ sung tùy chọn cho gói thuê bao. Cấu hình nó riêng qua `hermes setup terminal` hoặc trong `config.yaml`. Lời nhắc Tool Gateway không tự động bật nó.

### Gateway có tự động chuyển sang phương án dự phòng nếu upstream bị lỗi không?
Bản thân gateway là một proxy mỏng — lỗi sẽ trả về lỗi của upstream. Nếu bạn muốn khả năng phục hồi, hãy giữ một key trực tiếp làm phương án dự phòng (`use_gateway: false` + đặt `FIRECRAWL_API_KEY`) và bật nó lên khi gateway gặp sự cố.

---

## Cẩm Nang Chi Phí

Hướng dẫn sơ bộ để lựa chọn giữa gateway và key trực tiếp:

- **Tìm kiếm web nặng + duyệt web + hình ảnh trong cùng một tháng:** gateway hầu như luôn thắng — một gói thuê bao bao trọn cả bốn.
- **Chỉ TTS nặng (tạo âm thanh):** ElevenLabs trực tiếp thường rẻ hơn giá TTS OpenAI của gateway. Giữ TTS ngoài gateway.
- **Khối lượng thấp, đang thử nghiệm:** gateway là hoàn hảo — không cần đăng ký, không cần xoay xở free-tier, không có chi phí phát sinh bất ngờ.
- **Môi trường doanh nghiệp / bị quản lý chặt chẽ:** gateway tự lưu trữ với các biến env `TOOL_GATEWAY_*` trỏ tới proxy riêng của bạn.

---

## Tiếp Theo Là Gì

- **Giao diện local cho mọi thứ:** [Phần 12 — Bảng Điều Khiển Web Local](./part12-web-dashboard.md)
- **Phản hồi model nhanh hơn:** [Phần 14 — Chế Độ Nhanh & Trình Theo Dõi Nền](./part14-fast-mode-watchers.md)
- **Mở rộng sang iMessage / WeChat / Android:** [Phần 15 — Các Nền Tảng Mới](./part15-new-platforms.md)
