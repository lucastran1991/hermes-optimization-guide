# Phần 14: Fast Mode & Background Watchers

*Hàng đợi suy luận ưu tiên (priority-tier), sự kiện tiến trình nền theo thời gian thực, và các điều khiển TUI mới hơn giúp các phiên làm việc dài có thể điều khiển được thay vì bị kẹt.*

---

## Fast Mode (`/fast`)

### Nó Là Gì

Cả OpenAI và Anthropic đều vận hành **hàng đợi xử lý ưu tiên** cho lưu lượng nhạy cảm về độ trễ. Chi phí trên mỗi token cao hơn, nhưng độ trễ p50 và p99 thấp hơn đáng kể — đặc biệt là khi tải cao trên các mô hình reasoning.

`/fast` bật/tắt tầng ưu tiên đó theo từng phiên. Trên các mô hình OpenAI/Codex và Anthropic được hỗ trợ, việc bật nó lên sẽ chèn `service_tier: "priority"` vào các request gửi đi.

### Khi Nào Nên Dùng

- **Các phiên CLI tương tác** nơi bạn đang chờ từng phản hồi (coding, debugging).
- **Trả lời tin nhắn** nơi câu trả lời chậm là trải nghiệm người dùng tệ (Telegram, iMessage, WeChat).
- **Các workflow dùng nhiều subagent** nơi độ trễ của orchestrator bị chồng chất (Phần 8).
- **Bất cứ khi nào tầng mặc định bị giới hạn tốc độ (rate-limited)** — tầng ưu tiên có pool riêng.

Đừng dùng nó cho:
- Các job batch cron hoặc các lần chạy nghiên cứu qua đêm nơi độ trễ không quan trọng.
- Bất cứ khi nào bạn đang cố giảm thiểu chi phí và tầng mặc định là đủ tốt.

### Cách Bật/Tắt

Trong bất kỳ phiên tương tác nào (CLI hoặc nền tảng nhắn tin):

```text
You → /fast
  Fast mode: ON (service_tier=priority)
```

Nó sẽ được duy trì cho đến khi bạn tắt nó:

```text
You → /fast
  Fast mode: OFF (service_tier=default)
```

### Hoặc Thiết Lập Toàn Cục

Trong `~/.hermes/config.yaml`:

```yaml
agent:
  service_tier: priority   # default, priority, or flex
```

Điều này làm cho Fast Mode trở thành mặc định cho mọi phiên mới. Lệnh slash `/fast` vẫn có thể ghi đè theo từng phiên.

### Nó Hoạt Động Ở Đâu

- ✅ CLI tương tác (`hermes`)
- ✅ Mọi nền tảng gateway kể từ v0.9 — Telegram, Discord, Slack, WhatsApp, Signal, iMessage (BlueBubbles), WeChat, Matrix, Email, SMS, DingTalk, Feishu, WeCom, Mattermost, Home Assistant, Webhooks
- ✅ Cron jobs (đặt `agent.service_tier: priority` trong config)
- ✅ Subagents (`delegate_task` kế thừa tầng của agent cha)
- ❌ Các mô hình Local/Ollama (không tồn tại tầng ưu tiên)
- ❌ Các biến thể OpenRouter miễn phí (hậu tố `:free` buộc dùng tầng mặc định)

### Lưu Ý Về Giá

Tầng ưu tiên đắt hơn trên mỗi token. Theo dõi tab **Analytics** trên dashboard (Phần 12) để xem chênh lệch chi phí theo ngày sau khi bật nó. Nếu bạn bất ngờ với một hóa đơn, nguyên nhân phổ biến nhất là để `agent.service_tier: priority` bật toàn cục cho các cron job không cần nó.

---

## `/steer`, `/queue`, và Các Turn Nền

TUI mới hơn giúp việc kiểm soát công việc chạy dài dễ dàng hơn nhiều:

| Lệnh | Dùng khi | Mẫu |
|---------|-------------|---------|
| `/steer <instruction>` | Agent đang chạy giữa chừng nhưng đi lệch hướng | "Continue, but don't edit generated files" |
| `/queue <prompt>` | Bạn muốn tác vụ tiếp theo bắt đầu sau khi tác vụ hiện tại xong | "After tests pass, summarize the risk" |
| `/background <prompt>` | Bắn công việc đi mà không chặn chat chính | "Research alternatives while I keep coding" |
| `/busy` | Bạn muốn kiểm tra Hermes đang làm gì | Kiểm tra các lần chạy/subagent đang hoạt động |
| `/indicator` | Feed spinner/hoạt động quá ồn hoặc quá im ắng | Bật/tắt kiểu chỉ báo bận (busy indicator) |

Thực hành tốt nhất:

1. Dùng `/steer` cho **các ràng buộc**, không phải mục tiêu hoàn toàn mới.
2. Dùng `/queue` cho các công việc tiếp theo phụ thuộc.
3. Dùng `/background` cho nghiên cứu hoặc giám sát độc lập.
4. Nếu lần chạy có đụng đến file, giữ các prompt tiếp theo đủ cụ thể để Hermes có thể tránh ghi đè lên chính các chỉnh sửa của nó.

Đây là giải pháp thay thế thực tế cho việc liên tục ngắt và nhắc lại toàn bộ nhiệm vụ.

---

## Giám Sát Tiến Trình Nền (`watch_patterns`)

### Vấn Đề Này Giải Quyết Điều Gì

Một phần lớn công việc của agent là "chạy một thứ gì đó dài và chờ tín hiệu" — khởi động một dev server và chờ `listening on port`, khởi động một build và chờ lỗi, chạy một bộ test suite và chờ dòng tóm tắt.

Trước v0.9, agent chỉ có hai lựa chọn:

1. Chạy tiến trình ở foreground, chặn vòng lặp agent, mất khả năng làm bất cứ việc gì khác.
2. Chạy nó ở background, sau đó **poll** (thăm dò) output log mỗi vài giây, điều này gây lãng phí và tạo ra độ trễ.

`watch_patterns` khiến lựa chọn 2 hoạt động đúng đắn. Bạn truyền vào một pattern (hoặc vài pattern) khi khởi động một tiến trình nền, và agent nhận được một sự kiện thời gian thực ngay khi output khớp — không cần polling.

### Cách Dùng Cơ Bản

Bên trong một phiên agent:

```
Start the dev server in the background. Watch for "listening on port"
to know it's ready, and for "EADDRINUSE" or "error" so you can surface
failures immediately.
```

Hermes sử dụng công cụ `terminal_run` với `watch_patterns`:

```json
{
  "command": "npm run dev",
  "background": true,
  "watch_patterns": [
    { "pattern": "listening on port \\d+", "label": "ready" },
    { "pattern": "EADDRINUSE|\\berror\\b", "label": "failure", "severity": "error" }
  ]
}
```

Mỗi dòng khớp được chuyển đến agent như một **sự kiện**, không phải một bản snapshot log đã được poll — nó được chèn vào turn tiếp theo giống như một kết quả tool.

### Các Trường Của Pattern

| Trường | Bắt buộc | Mô tả |
|-------|----------|-------------|
| `pattern` | có | Regex `re` của Python, được khớp với từng dòng của stdout/stderr |
| `label` | không | Thẻ (tag) dễ đọc để agent biết *watcher nào* đã kích hoạt |
| `severity` | không | `info` (mặc định), `warning`, hoặc `error` — ảnh hưởng đến cách agent phản ứng |
| `max_matches` | không | Dừng theo dõi sau N lần khớp. Mặc định: không giới hạn |
| `stop_process_on_match` | không | Kết thúc tiến trình khi pattern khớp |

### Các Công Thức Hữu Ích

#### Chờ dev server sẵn sàng, sau đó chạy E2E test

```json
{
  "command": "pnpm run dev",
  "background": true,
  "watch_patterns": [
    { "pattern": "Local:\\s+http://", "label": "ready", "max_matches": 1 }
  ]
}
```

Một khi `ready` kích hoạt, agent biết nó có thể tiếp tục với các test.

#### Fail nhanh khi có lỗi biên dịch

```json
{
  "command": "cargo build --release",
  "background": true,
  "watch_patterns": [
    { "pattern": "error\\[E\\d+\\]", "label": "rustc_error", "severity": "error", "stop_process_on_match": true }
  ]
}
```

#### Tail một file log mãi mãi, cảnh báo trên các dòng cụ thể

```json
{
  "command": "tail -F /var/log/app.log",
  "background": true,
  "watch_patterns": [
    { "pattern": "\\b5\\d\\d\\b", "label": "5xx", "severity": "warning" },
    { "pattern": "OOMKilled",      "label": "oom", "severity": "error" }
  ]
}
```

Kết hợp cái này với một gateway nền tảng nhắn tin (Phần 4 / Phần 15) và bạn có một pipeline cảnh báo production giá rẻ với zero hạ tầng.

### Kiểm Tra Những Gì Đang Chạy

Liệt kê các tiến trình nền có watcher đang hoạt động:

```bash
/background list
```

hoặc qua CLI:

```bash
hermes background list
```

Mỗi hàng hiển thị PID, lệnh, thời gian hoạt động (uptime), số lượng watcher, và số lần khớp gần đây. Click vào một hàng (trong dashboard) để tail output trực tiếp.

### Kết Thúc Một Tiến Trình Nền

```bash
/background kill <pid>
```

Hoặc dùng trang Logs của dashboard để tìm tiến trình và click vào biểu tượng terminate.

---

## Pluggable Context Engine

Một tính năng liên quan-nhưng-tách-biệt cũng được phát hành trong v0.9.0: context engine — thứ quyết định những gì được chèn vào mỗi turn của agent — giờ đây là một **slot có thể cắm được (pluggable)** thông qua `hermes plugins`.

Bạn có thể thay thế bằng một context engine tùy chỉnh có thể:

- Lọc bộ nhớ theo cách khác (ví dụ: chỉ chèn các mục bộ nhớ được gắn thẻ `@project:my-project`)
- Tóm tắt output của tool trước khi chèn (một bước xử lý sơ bộ bằng mô hình local giá rẻ)
- Chèn ngữ cảnh theo miền cụ thể (lấy từ LightRAG, một vector DB riêng, CRM của bạn, v.v.)

### Engine Tùy Chỉnh Tối Thiểu

`~/.hermes/plugins/my-context/plugin.yaml`:

```yaml
name: my-context
version: 1.0.0
provides:
  context_engine:
    entrypoint: my_context:build_context
```

`~/.hermes/plugins/my-context/my_context.py`:

```python
from hermes_agent.context import ContextBundle, DefaultContextEngine

default_engine = DefaultContextEngine()

def build_context(session, turn) -> ContextBundle:
    bundle = default_engine.build_context(session, turn)

    # Inject an extra block every turn
    bundle.extras.append({
        "role": "system",
        "content": "## Project context\n" + _load_project_context(session),
    })

    # Filter memory to the active project only
    active_project = session.metadata.get("project")
    if active_project:
        bundle.memory = [m for m in bundle.memory if m.tags.get("project") == active_project]

    return bundle

def _load_project_context(session):
    # Read a file, query an API, hit LightRAG — whatever you want.
    ...
```

Bật nó lên:

```yaml
# ~/.hermes/config.yaml
context_engine: my-context
```

Các phiên mới sẽ dùng engine tùy chỉnh. Các phiên hiện có vẫn giữ engine mặc định cho đến khi khởi động lại.

---

## `/compress <topic>` — Nén Có Định Hướng

Bộ nén ngữ cảnh (context compressor) hiện có (Phần 6) giờ đã chấp nhận một chủ đề trọng tâm (focus topic):

```text
You → /compress project migration to Fly.io
  Compressing 47 messages with focus: "project migration to Fly.io"
  Kept 6 messages verbatim, summarized 41 into 2 bullet blocks.
```

Nếu không có chủ đề, nó chạy với các phương pháp heuristic mặc định. Với một chủ đề, bộ tóm tắt sẽ giữ lại chi tiết liên quan đến chủ đề đó và nén mạnh phần còn lại. Hữu ích khi bạn đã ở giờ thứ 3 của một phiên và muốn giữ lại toàn bộ chi tiết migration nhưng bỏ đi 200 lần gọi tool bạn đã chạy để tạo fixture.

---

## `/goal` — Khóa Mục Tiêu Bền Vững

v0.13 đã thêm `/goal`, và v0.14 kết hợp nó với `/handoff` trực tiếp cho việc chuyển giao mô hình/hồ sơ (profile) cho phiên bản vòng lặp dài của vấn đề này: không phải "nén ngữ cảnh này," mà là "tiếp tục làm việc cho đến khi mục tiêu quan sát được này hoàn thành."

```text
/goal Migrate the gateway to Google Chat, run checks, and leave a PR link.
```

Dùng nó khi agent nên tiếp tục qua các lần gọi tool và các cập nhật trung gian cho đến khi điều kiện thoát được thỏa mãn. Đối với công việc đa agent, kết hợp nó với [bảng Kanban ở Phần 23](./part23-tenacity-stack.md); đối với một phiên tập trung đơn lẻ, `/goal` là đủ.

---

## Tiếp Theo Là Gì

- **Lưu key + tinh gọn thiết lập:** [Phần 13 — Nous Tool Gateway](./part13-tool-gateway.md)
- **Mở rộng phạm vi:** [Phần 15 — Các Nền Tảng Mới (Teams, LINE, SimpleX, iMessage, WeChat, Android)](./part15-new-platforms.md)
- **Khôi phục sau sự cố:** [Phần 16 — Sao Lưu, Debug, và Context Có Thể Cắm Được](./part16-backup-debug.md)
