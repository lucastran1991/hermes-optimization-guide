# Phần 12: Bảng Điều Khiển Web Cục Bộ (Ngừng Chỉnh Sửa YAML)

*Được giới thiệu trong v0.9 và nâng cấp đáng kể qua v0.14. Bảng điều khiển giờ đây là một trung tâm điều khiển dựa trên trình duyệt cho cấu hình, Chat/TUI, Kanban, plugin, hồ sơ (profiles), và phân tích — không chỉ là một trình chỉnh sửa YAML.*

---

## Tại Sao Điều Này Quan Trọng

Trước v0.9, việc quản lý Hermes có nghĩa là: chỉnh sửa `config.yaml`, xuất các biến môi trường, grep qua log, và dùng CLI để kiểm tra phiên làm việc (session). Tuyệt vời cho người dùng có kinh nghiệm. Tệ hại cho bất kỳ ai mới bắt đầu.

**Bảng điều khiển web** (`hermes dashboard`) thay thế hầu hết những thứ đó bằng một giao diện trình duyệt duy nhất:

- Trạng thái trực tiếp của gateway và tất cả các adapter nền tảng tích hợp sẵn/plugin
- Chat trên trình duyệt được hỗ trợ bởi `hermes --tui` thực sự
- Trình chỉnh sửa dựa trên biểu mẫu cho mọi trường cấu hình (tất cả hơn 150 trường, được tự động phát hiện từ `DEFAULT_CONFIG`)
- Tab Models để cấu hình mô hình chính + mô hình phụ trợ
- Trình quản lý API key cho các nhà cung cấp, công cụ, và nền tảng
- Tìm kiếm toàn văn bản trên các phiên làm việc trước đây (FTS5)
- Trình theo dõi log với bộ lọc theo cấp độ/thành phần
- Phân tích mức sử dụng và chi phí (phân tích token + chi phí hàng ngày, theo từng mô hình)
- Quản lý cron job
- Bảng Kanban, trạng thái worker/task, bình luận, chặn, và bàn giao
- Trình duyệt Skills, Curator, plugin, hồ sơ, và bộ công cụ với nút bật/tắt

Mọi thứ chạy trên `127.0.0.1` — không có dữ liệu nào rời khỏi máy của bạn.

---

## Bắt Đầu Nhanh

```bash
hermes dashboard
```

Vậy là xong. Nó khởi động một máy chủ cục bộ và mở `http://127.0.0.1:9119` trong trình duyệt mặc định của bạn.

### Cài Đặt Các Phụ Thuộc (Một Lần)

Bảng điều khiển sử dụng FastAPI + Uvicorn + một frontend React. Tab Chat cũng cần hỗ trợ PTY:

```bash
pip install 'hermes-agent[web,pty]'
```

Nếu bạn đã cài đặt với `hermes-agent[all]`, bạn đã hoàn tất. Gói mở rộng `web` mang lại FastAPI/Uvicorn; `pty` cho phép tab Chat sinh ra `hermes --tui` phía sau một pseudo-terminal trên Linux/macOS/WSL. Frontend tự động build khi khởi chạy lần đầu nếu có `npm`.

### Các Tùy Chọn

| Cờ (Flag) | Mặc định | Mô tả |
|------|---------|-------------|
| `--port` | `9119` | Cổng để phục vụ |
| `--host` | `127.0.0.1` | Địa chỉ ràng buộc (bind) |
| `--no-open` | — | Không tự động mở trình duyệt |
| `--insecure` | tắt | Cho phép ràng buộc không phải localhost; nguy hiểm nếu không có proxy/xác thực |
| `--tui` | tắt | Bật tab Chat ngay trên trình duyệt; cũng có thể bật qua `HERMES_DASHBOARD_TUI=1` |

```bash
# Cổng tùy chỉnh
hermes dashboard --port 8080

# Ràng buộc tới tất cả các interface (dùng cẩn thận — xem ghi chú bảo mật bên dưới)
hermes dashboard --host 0.0.0.0

# Khởi động mà không mở trình duyệt
hermes dashboard --no-open
```

> **Bảo mật:** Bảng điều khiển đọc và ghi vào file `.env` của bạn. Nó **không có cơ chế xác thực riêng**. Giữ nó trên `127.0.0.1`. Nếu bạn buộc phải công khai nó (ví dụ: một homelab), hãy đặt nó phía sau một reverse proxy có xác thực hoặc dùng SSH port-forwarding: `ssh -L 9119:127.0.0.1:9119 user@your-server`.

---

## Tổng Quan Các Trang

### Status

Tổng quan trực tiếp tự động làm mới mỗi 5 giây:

- Phiên bản agent + ngày phát hành
- Trạng thái gateway — đang chạy/đã dừng, PID, mọi nền tảng đã kết nối với trạng thái riêng của nó
- Các phiên đang hoạt động — mọi thứ còn sống trong 5 phút gần nhất
- Các phiên gần đây — 20 phiên gần nhất, kèm mô hình, số lượng tin nhắn, mức sử dụng token, và bản xem trước

Đây là trang bạn để mở trên màn hình thứ hai.

### Chat

Tab Chat nhúng chính process `hermes --tui` thực sự thông qua xterm.js. Điều đó quan trọng: các lệnh slash, lời nhắc phê duyệt, lời nhắc clarify/sudo/secret, skin, streaming markdown, thẻ tool-call, `/resume`, `/steer`, `/queue`, và các bản sửa lỗi TUI đều tự động xuất hiện ở đây vì bảng điều khiển không duy trì một triển khai chat thứ hai.

Yêu cầu:

- Node.js cho gói TUI Ink
- `ptyprocess` qua `pip install 'hermes-agent[pty]'`
- Hỗ trợ POSIX PTY: Linux, macOS, hoặc WSL cho PTY nhúng; Windows gốc đang ở giai đoạn beta trong v0.14 và có thể vẫn cần WSL cho Chat trên dashboard

Mẹo: khởi chạy từ trang Sessions bằng biểu tượng play để tiếp tục trực tiếp một phiên trước đó vào `/chat?resume=<id>`.

### Config

Trình chỉnh sửa dựa trên biểu mẫu cho `config.yaml`. Các trường được tự động phát hiện từ `DEFAULT_CONFIG` và được nhóm vào các tab:

- **model** — mô hình mặc định, nhà cung cấp, base URL, cài đặt reasoning
- **terminal** — backend (local / docker / ssh / modal), thời gian chờ (timeout), tùy chọn shell
- **display** — skin, hiển thị tiến trình công cụ, cài đặt spinner
- **agent** — số lần lặp tối đa, thời gian chờ gateway, `service_tier` (Fast Mode), hành vi `/goal`
- **delegation** — giới hạn subagent, mức độ reasoning
- **memory** — nhà cung cấp, cài đặt chèn ngữ cảnh
- **approvals** — chế độ lệnh nguy hiểm (`ask` / `yolo` / `deny`)
- **plugins** — danh sách cho phép plugin được bật/tắt
- **curator** — lịch trình, ngưỡng cắt tỉa (pruning), hành vi ghim/lưu trữ
- **kanban** — vị trí board, hồ sơ worker, ngân sách thử lại (retry budget), chính sách thu hồi heartbeat cũ

Danh sách thả xuống (dropdown) cho các trường có giá trị đã biết (terminal backend, skin, chế độ phê duyệt). Nút bật/tắt cho boolean. Ô nhập văn bản cho mọi thứ khác.

Hành động:
- **Save** — ghi vào `config.yaml` ngay lập tức
- **Reset to defaults** — xem trước việc khôi phục lại mọi thứ (vẫn cần Save)
- **Export** — tải cấu hình hiện tại dưới dạng JSON
- **Import** — tải lên một file JSON để thay thế các giá trị

> Các thay đổi cấu hình có hiệu lực ở phiên agent tiếp theo hoặc khi khởi động lại gateway. Trang này chỉnh sửa chính xác cùng một file như `hermes config set` và gateway.

### API Keys

Trình chỉnh sửa `.env` mà bạn sẽ thực sự dùng. Các key được nhóm theo danh mục:

- **Nhà cung cấp LLM** — OpenRouter, Anthropic, OpenAI, z.ai/GLM, Kimi, MiniMax, Xiaomi MiMo, Arcee, v.v.
- **API key công cụ** — Browserbase, Firecrawl, Tavily, ElevenLabs, FAL, v.v.
- **Nền tảng nhắn tin** — Telegram, Discord, Slack, BlueBubbles, WeChat, v.v.
- **Cài đặt agent** — các biến môi trường không bí mật như `API_SERVER_ENABLED`

Mỗi hàng hiển thị liệu một key đã được thiết lập hay chưa (bản xem trước đã che khuất), một mô tả một dòng, và một liên kết đến trang key của nhà cung cấp.

Các key nâng cao/hiếm khi dùng mặc định được ẩn sau một nút bật/tắt để giữ giao diện gọn gàng.

### Sessions

Duyệt và tìm kiếm đầy đủ trên mọi phiên bạn từng chạy, trên mọi nền tảng.

- **Search** — tìm kiếm toàn văn bản FTS5 trên nội dung tin nhắn. Kết quả trùng khớp được tô sáng và tự động cuộn khi mở rộng.
- **Expand** — tải toàn bộ lịch sử tin nhắn với Markdown + tô sáng cú pháp, mã màu theo vai trò (user / assistant / system / tool).
- **Tool calls** — các khối có thể thu gọn hiển thị tên hàm và đối số JSON cho mỗi lời gọi công cụ.
- **Delete** — xóa một phiên và các tin nhắn của nó bằng biểu tượng thùng rác.

Mỗi hàng hiển thị tiêu đề, biểu tượng nền tảng nguồn (CLI, Telegram, Discord, Slack, cron, BlueBubbles, WeChat), mô hình, số lượng tin nhắn, số lượng tool call, và thời gian kể từ lần hoạt động cuối. Các phiên đang hoạt động sẽ nhấp nháy.

### Logs

Các file log của agent, gateway, và lỗi với bộ lọc và theo dõi trực tiếp.

- **File** — chuyển đổi giữa `agent`, `errors`, `gateway`
- **Level** — ALL / DEBUG / INFO / WARNING / ERROR
- **Component** — all / gateway / agent / tools / cli / cron
- **Lines** — 50 / 100 / 200 / 500
- **Auto-refresh** — thăm dò (polling) theo dõi trực tiếp mỗi 5 giây
- Mã màu theo mức độ nghiêm trọng (lỗi màu đỏ, cảnh báo màu vàng, debug mờ)

### Analytics

Mức sử dụng và chi phí, được tính toán từ lịch sử phiên. Chọn một khoảng thời gian (7 / 30 / 90 ngày):

- Thẻ tóm tắt — tổng token đầu vào/đầu ra, tỷ lệ trúng cache, chi phí ước tính hoặc thực tế, số lượng phiên với mức trung bình hàng ngày
- Biểu đồ token hàng ngày — thanh xếp chồng đầu vào/đầu ra, di chuột để xem chi tiết chính xác và chi phí
- Bảng phân tích hàng ngày — ngày, số phiên, token, tỷ lệ trúng cache, chi phí
- Phân tích theo từng mô hình — mỗi mô hình được sử dụng, số phiên, token, chi phí

Nếu bạn đang dùng Nous Portal Tool Gateway (Phần 13), mức sử dụng công cụ của gateway cũng hiển thị ở đây.

### Models

Dùng trang này trước khi bạn chỉnh sửa YAML định tuyến (routing) bằng tay. Nó hiển thị:

- Lựa chọn mô hình/nhà cung cấp chính
- Các mô hình phụ trợ cho nén, thị giác (vision), tạo tiêu đề, tìm kiếm phiên, và curator
- Dữ liệu chọn lựa OpenRouter/Nous từ xa khi có sẵn
- Phân tích mức sử dụng theo từng mô hình để "mặc định rẻ, chọn dùng đắt" luôn minh bạch

Đây là cách nhanh nhất để ngừng lãng phí mô hình tốt nhất của bạn vào các bản tóm tắt nền.

### Cron

Tạo và quản lý các lời nhắc agent đã lên lịch.

- **Create** — tên, prompt, biểu thức cron (ví dụ `0 9 * * *`), đích giao hàng (local / Telegram / Discord / Slack / email)
- **Job list** — tên, xem trước prompt, lịch trình, huy hiệu trạng thái, đích giao hàng, lần chạy cuối, lần chạy tiếp theo
- **Pause / Resume** — chuyển đổi trạng thái hoạt động
- **Trigger now** — chạy một job ngay lập tức, ngoài lịch trình bình thường của nó
- **Delete** — xóa vĩnh viễn

Điều này thay thế luồng CLI `hermes cron create …` cũ cho hầu hết mọi người.

### Skills

Duyệt, tìm kiếm, và bật/tắt mọi skill và bộ công cụ.

- **Search** — lọc theo tên, mô tả, hoặc danh mục
- **Category filter** — nhấp vào các pill để thu hẹp (MLOps, MCP, Red Teaming, AI, v.v.)
- **Toggle** — bật/tắt từng skill riêng lẻ theo phiên
- **Toolsets** — phần riêng biệt hiển thị các bộ công cụ tích hợp sẵn (file, web, browser), với trạng thái hoạt động/không hoạt động, yêu cầu thiết lập, và danh sách các công cụ mà mỗi bộ cung cấp

### Plugins

Plugin được vận chuyển ở trạng thái tắt. Dùng bảng điều khiển để xem lại những gì đã được phát hiện từ các nguồn bundled, user, project, pip, và Nix trước khi bật bất cứ thứ gì có hook/công cụ.

Các lựa chọn tốt để bật đầu tiên:

- `observability/langfuse` — theo dõi (trace) các lời gọi LLM/công cụ tới Langfuse
- `spotify` — công cụ phát/hàng đợi/tìm kiếm gốc
- `google_meet` — tham gia, phiên âm, nói, và theo dõi các cuộc gọi Meet
- `hermes-achievements` — thành tích trên bảng điều khiển từ lịch sử phiên thực tế

Các plugin cục bộ trong dự án nằm dưới `.hermes/plugins/` nên giữ ở trạng thái tắt trừ khi bạn tin tưởng repository đó.

### Curator

v0.12 bổ sung các điều khiển Curator cho việc vệ sinh thư viện skill: chạy dry-run, kiểm tra các đề xuất lưu trữ/hợp nhất, ghim các skill quan trọng, và xem lại các skill đã lưu trữ trước khi khôi phục hoặc xóa. Xem [Phần 5](./part5-creating-skills.md#curator-v012-keep-the-skill-library-from-rotting) và [Phần 22](./part22-latest-power-moves.md#1-turn-on-curator-before-your-skill-library-becomes-noise).

---

## `/reload` — Áp Dụng Thay Đổi `.env` Ngay Lập Tức

Khi bạn thay đổi một API key trong bảng điều khiển (hoặc chỉnh sửa `~/.hermes/.env` trực tiếp), bạn không cần khởi động lại một phiên CLI đang hoạt động nữa.

Trong bất kỳ CLI tương tác nào:

```text
You → /reload
  Reloaded .env (3 var(s) updated)
```

Lệnh đó đọc lại `~/.hermes/.env` vào môi trường process đang chạy. Hoàn hảo khi bạn thêm một key nhà cung cấp mới và muốn chuyển sang dùng nó mà không mất phiên làm việc của mình.

---

## REST API (Cho Tự Động Hóa)

Frontend của bảng điều khiển chỉ là một client của một REST API được tài liệu hóa đầy đủ. Bạn có thể viết script để tương tác trực tiếp với nó — tiện lợi cho các bảng điều khiển homelab, phím tắt Raycast/Alfred, các bộ xuất dữ liệu Grafana, v.v.

| Endpoint | Mô tả |
|----------|-------------|
| `GET /api/status` | Phiên bản agent, trạng thái gateway, trạng thái nền tảng, số phiên đang hoạt động |
| `GET /api/sessions` | 20 phiên gần đây nhất kèm metadata |
| `GET /api/sessions/{id}` | Lịch sử tin nhắn đầy đủ cho một phiên |
| `GET /api/config` | `config.yaml` hiện tại dưới dạng JSON |
| `GET /api/config/defaults` | Giá trị cấu hình mặc định |
| `GET /api/config/schema` | Schema cho mọi trường cấu hình (loại, mô tả, danh mục, tùy chọn) |
| `PUT /api/config` | Lưu một cấu hình mới. Body: `{"config": {...}}` |
| `GET /api/env` | Mọi biến môi trường đã biết cùng trạng thái đã/chưa thiết lập, giá trị đã che khuất, mô tả |
| `PUT /api/env` | Thiết lập một biến. Body: `{"key": "VAR_NAME", "value": "secret"}` |
| `DELETE /api/env` | Xóa một biến |
| `GET /api/logs` | Theo dõi các file log với bộ lọc |
| `GET /api/analytics` | Phân tích mức sử dụng và chi phí cho một khoảng thời gian |
| `GET /api/cron/jobs` | Liệt kê các cron job |
| `POST /api/cron/jobs` | Tạo một cron job |
| `POST /api/cron/jobs/{id}/trigger` | Kích hoạt một job ngay lập tức |
| `GET /api/skills` | Liệt kê skill và bộ công cụ |

Các yêu cầu không được xác thực và chỉ lắng nghe trên `127.0.0.1` — tin tưởng vào ranh giới máy cục bộ.

---

## Dashboard Plugins (Mở Rộng Giao Diện)

Bảng điều khiển có thể mở rộng bằng plugin. Một plugin có thể thêm tab riêng của nó, gọi API hiện có, và tùy chọn đăng ký các endpoint backend mới — tất cả mà không cần chạm vào mã nguồn của bảng điều khiển.

### Plugin Tối Thiểu

```bash
mkdir -p ~/.hermes/plugins/my-plugin/dashboard/dist
```

`~/.hermes/plugins/my-plugin/dashboard/manifest.json`:

```json
{
  "name": "my-plugin",
  "label": "My Plugin",
  "icon": "Sparkles",
  "version": "1.0.0",
  "tab": { "path": "/my-plugin", "position": "after:skills" },
  "entry": "dist/index.js"
}
```

`~/.hermes/plugins/my-plugin/dashboard/dist/index.js`:

```javascript
(function () {
  var SDK = window.__HERMES_PLUGIN_SDK__;
  var React = SDK.React;
  var Card = SDK.components.Card;
  var CardHeader = SDK.components.CardHeader;
  var CardTitle = SDK.components.CardTitle;
  var CardContent = SDK.components.CardContent;

  function MyPage() {
    return React.createElement(Card, null,
      React.createElement(CardHeader, null,
        React.createElement(CardTitle, null, "My Plugin")),
      React.createElement(CardContent, null,
        React.createElement("p", { className: "text-sm text-muted-foreground" },
          "Hello from my custom dashboard tab!")));
  }

  window.__HERMES_PLUGINS__.register("my-plugin", MyPage);
})();
```

Làm mới bảng điều khiển — tab của bạn sẽ xuất hiện trong thanh điều hướng.

Plugin nằm cạnh các plugin CLI/gateway hiện có dưới `~/.hermes/plugins/`. Bạn có thể vận chuyển một plugin vừa cung cấp một công cụ CLI *vừa* một tab bảng điều khiển từ cùng một thư mục.

### Cấu Trúc Plugin

```
~/.hermes/plugins/my-plugin/
├── plugin.yaml              # tùy chọn — manifest plugin CLI/gateway hiện có
├── __init__.py              # tùy chọn — hook CLI/gateway hiện có
└── dashboard/               # phần mở rộng bảng điều khiển
    ├── manifest.json        # bắt buộc — cấu hình tab, biểu tượng, điểm vào
    ├── dist/
    │   ├── index.js         # bắt buộc — gói JS đã build sẵn
    │   └── style.css        # tùy chọn — CSS tùy chỉnh
    └── plugin_api.py        # tùy chọn — các route API backend
```

---

## Khắc Phục Sự Cố

### "Missing web dependencies" (Thiếu phụ thuộc web)

```bash
pip install hermes-agent[web]
```

Hoặc cài đặt lại với `[all]` để có mọi phần mở rộng tùy chọn.

### "Frontend not built" (Frontend chưa được build)

Bảng điều khiển cố gắng tự động build frontend khi khởi chạy lần đầu nếu `npm` có trong PATH. Nếu không thể, hãy build thủ công:

```bash
cd ~/.hermes/hermes-agent/hermes_agent/web_dashboard/frontend
npm install && npm run build
```

### "Port 9119 already in use" (Cổng 9119 đã được sử dụng)

```bash
hermes dashboard --port 9200
```

### Bảng điều khiển hiển thị dữ liệu cũ

Nhấn nút làm mới trình duyệt. Status thăm dò mỗi 5 giây; các trang khác tải lại khi điều hướng.

### Đã thay đổi cấu hình nhưng không có hiệu lực

Cấu hình được đọc khi bắt đầu phiên và khi khởi động gateway. Đối với một phiên CLI đang hoạt động, chạy `/reload` để áp dụng các thay đổi `.env`. Đối với các thay đổi trong config.yaml, hãy bắt đầu một phiên mới hoặc khởi động lại gateway.

---

## Tiếp Theo Là Gì

- **Tiết kiệm trên API key:** [Phần 13 — Nous Tool Gateway](./part13-tool-gateway.md)
- **Tăng tốc phản hồi:** [Phần 14 — Fast Mode & Background Watchers](./part14-fast-mode-watchers.md)
- **Mở rộng phạm vi tiếp cận:** [Phần 15 — Các Nền Tảng Mới (Teams, LINE, SimpleX, iMessage, WeChat, Android)](./part15-new-platforms.md)
