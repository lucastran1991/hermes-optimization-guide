# Phần 16: Sao lưu, Nhập, và `/debug` — Bộ Công Cụ Khôi Phục Của Bạn

*Sao lưu/nhập hạng nhất, các gói debug, kiểm tra trước khi cập nhật (preflight), và các chi tiết tăng cường bảo mật bạn cần trước khi để Hermes chạy không giám sát.*

---

## `hermes backup` và `hermes import`

### Tại Sao Đây Là Một Vấn Đề Lớn

Cho đến v0.9, việc di chuyển một bản cài đặt Hermes giữa các máy có nghĩa là chạy `rsync -a ~/.hermes user@new-host:`. Cách này phần lớn hoạt động tốt — ngoại trừ:

- Các đường dẫn tuyệt đối được nhúng cứng vào cấu hình (Docker mounts, đường dẫn log, đường dẫn script skill)
- Các endpoint provider đặc thù theo máy (Ollama cục bộ, LightRAG chỉ dùng trong LAN)
- Khóa file DB phiên SQLite nếu máy nguồn vẫn đang chạy
- Các secret mà bạn thực sự không muốn sao chép (khóa dev cũ, API key provider đã vô hiệu hóa)

`hermes backup` tạo ra một archive di động xử lý tất cả những vấn đề đó. `hermes import` sẽ áp dụng lại nó trên máy mới với cơ chế giải quyết xung đột tương tác.

### Tạo Một Bản Sao Lưu

```bash
hermes backup
```

Tạo ra file `~/.hermes/backups/hermes-YYYY-MM-DD-HHMMSS.tar.zst` chứa:

| Đường dẫn | Có bao gồm | Ghi chú |
|------|----------|-------|
| `config.yaml` | có | Các đường dẫn đặc thù theo máy (Docker mounts, URL provider cục bộ) được viết lại thành placeholder di động |
| `.env` | có (được ẩn (redacted) theo mặc định) | Giá trị secret bị xóa về rỗng; tên khóa được giữ lại. Truyền `--include-secrets` để bao gồm giá trị dạng plaintext (dùng cẩn thận) |
| `memories/` | có | Tất cả các file memory |
| `skills/` | có | Tất cả các skill bao gồm script thực thi và tài liệu tham chiếu |
| `sessions.db` | có | DB SQLite được dump qua `VACUUM INTO` nên vẫn nhất quán ngay cả khi gateway đang chạy |
| `plugins/` | có | Cả plugin CLI và dashboard |
| `logs/` | không, theo mặc định | Dùng `--include-logs` nếu bạn cần chúng để debug |
| `auth.json` | không | Không bao giờ được sao lưu — hãy xác thực lại trên máy mới |

### Các Tùy Chọn

| Cờ | Mô tả |
|------|-------------|
| `--output <path>` | Ghi vào một đường dẫn cụ thể thay vì thư mục backups mặc định |
| `--include-secrets` | Bao gồm giá trị `.env` dạng plaintext (mặc định: được ẩn) |
| `--include-logs` | Bao gồm `logs/` trong archive |
| `--exclude <path>` | Loại trừ một subpath cụ thể (có thể lặp lại) |
| `--no-sessions` | Bỏ qua `sessions.db` (hữu ích khi chia sẻ thư viện skill/memory) |

### Các Công Thức Thường Dùng

**Sao lưu di động đầy đủ để di chuyển sang máy mới:**

```bash
hermes backup --include-secrets --output ~/hermes-$(hostname).tar.zst
```

Hãy coi archive đó như một kho lưu trữ mật khẩu (password manager vault) — nó chứa mọi khóa.

**Chia sẻ skill + memory với đồng đội (không có secret, không có session):**

```bash
hermes backup --no-sessions --output ~/hermes-share.tar.zst
```

An toàn để gửi email. Chứa kiến thức prompting và các skill quy trình của bạn, không có gì riêng tư.

**Sao lưu theo lịch vào một ổ đĩa được gắn (mounted drive):**

```bash
hermes cron create \
  --deliver local \
  --schedule "0 3 * * *" \
  "run: hermes backup --output /mnt/backups/hermes-\$(date +%F).tar.zst"
```

---

### Nhập Một Bản Sao Lưu

Trên máy đích:

```bash
hermes import ~/hermes-2026-04-17-030000.tar.zst
```

Trình nhập sẽ đi qua từng phần một cách tương tác:

```text
config.yaml
  ✓ No existing config. Importing.

.env
  ⚠ 12 existing keys, 18 in backup.
    [m] Merge (keep existing for duplicates)
    [r] Replace (backup overrides everything)
    [s] Skip
    [d] Diff before deciding
  Choice [m]:

memories/
  ⚠ 47 existing files, 52 in backup, 14 differ.
    [m] Merge (newer file wins)
    [r] Replace
    [s] Skip
    [d] Diff each conflicting file
  Choice [m]:

skills/
  ✓ Non-conflicting, importing 23 skills.

sessions.db
  ⚠ Existing sessions.db has 1,247 sessions. Backup has 892.
    [m] Merge (session IDs already deduped — safe)
    [r] Replace
    [s] Skip
  Choice [m]:
```

### Các Tùy Chọn

| Cờ | Mô tả |
|------|-------------|
| `--dry-run` | In ra những gì sẽ xảy ra mà không đụng vào đĩa |
| `--strategy <merge\|replace\|skip>` | Giá trị mặc định không tương tác cho tất cả xung đột |
| `--only <path>` | Chỉ nhập một subpath (ví dụ: `--only skills/`) |
| `--rewrite-paths` | Quét lại cấu hình để tìm các đường dẫn không tồn tại trên máy này và nhắc bạn sửa chúng |

### Ghi Chú Đa Nền Tảng

- **DB Sessions** — việc merge được khử trùng lặp theo UUID phiên; không có rủi ro va chạm.
- **Skill có shell script** — quyền Unix (`+x`) được giữ nguyên bên trong archive. Trên Windows, dù sao bạn cũng cần WSL để chạy các skill dựa trên script.
- **Viết lại đường dẫn cấu hình** — khi nhập, Hermes phát hiện các đường dẫn lỗi thời (ví dụ `/home/alice/...` trên một máy mà `alice` không tồn tại) và nhắc bạn sửa chúng trước khi ghi.
- **Dữ liệu LightRAG** — nằm ngoài `~/.hermes`, nên không có trong bản sao lưu. Hãy sao lưu `~/.hermes/lightrag` riêng bằng `tar` hoặc nạp lại (re-ingest) trên máy mới.

---

## `/debug` và `hermes debug share`

### Quy Trình Chẩn Đoán Mới

Khi có gì đó bất thường xảy ra, quy trình cũ là: grep qua `~/.hermes/logs/`, dán 800 dòng vào một GitHub issue, và hy vọng rằng bạn đã lấy đúng dòng cần thiết. Quy trình hiện đại là:

```text
You → /debug
  Collecting diagnostics…
  ✓ Agent version: v0.14.0 (v2026.5.16)
  ✓ Platform: Linux 6.8.0 / Python 3.12.3
  ✓ Gateway: running (3 adapters connected)
  ✓ Last 200 lines of agent.log
  ✓ Last 200 lines of errors.log
  ✓ Config snapshot (secrets redacted)
  ✓ Active session metadata (no message content)

  Bundle: ~/.hermes/debug/debug-2026-04-17-030000.tar.gz

  Upload with: hermes debug share ~/.hermes/debug/debug-2026-04-17-030000.tar.gz
```

Sau đó:

```bash
hermes debug share ~/.hermes/debug/debug-2026-04-17-030000.tar.gz
```

Việc này sẽ tải gói lên endpoint debug công khai của Hermes và trả về một URL ngắn mà bạn có thể dán vào báo cáo lỗi. Việc tải lên:

- Ẩn (redact) tất cả secret `.env` trước khi rời khỏi máy của bạn
- Loại bỏ nội dung tin nhắn theo mặc định — chỉ giữ metadata (session ID, model, số lượng tin nhắn, tool calls)
- Hết hạn sau 14 ngày
- Chỉ có thể đọc được bởi nhân viên hỗ trợ Nous có link

### Những Gì Được Bao Gồm

| Phần | Nội dung |
|---------|---------|
| `system.json` | HĐH, Python, phiên bản Hermes, các extra đã cài đặt |
| `config.yaml` | Cấu hình của bạn, với giá trị `.env` được ẩn |
| `logs/agent.log` | N dòng cuối cùng (mặc định 200, dùng `--lines` để thay đổi) |
| `logs/errors.log` | N dòng cuối cùng |
| `logs/gateway.log` | N dòng cuối cùng |
| `gateway-state.json` | Các nền tảng đã kết nối, PID, thời gian sự kiện cuối cùng |
| `session-metadata.json` | Session ID, model, số lượng tin nhắn (không có nội dung) |
| `pip-freeze.txt` | Phiên bản chính xác của các dependency |

### Tùy Chọn Bổ Sung (Opt-In)

```bash
/debug --full
```

Bao gồm nội dung tin nhắn của phiên đang hoạt động, các đối số tool call gần đây của phiên, và các cặp request/response LLM (với auth header đã bị loại bỏ). Chỉ sử dụng khi một lỗi thực sự cần tái tạo lại đúng chuỗi prompt của bạn — nó tiết lộ nhiều thông tin hơn so với gói mặc định.

### Không Có Bước Chia Sẻ

`/debug` luôn tạo ra gói cục bộ. `hermes debug share` là một bước riêng biệt. Nếu bạn không muốn tải lên, chỉ cần tự đính kèm trực tiếp file tarball vào một GitHub issue.

---

## Context Engine Có Thể Cắm (Pluggable) + `/compress <topic>`

Được đề cập chi tiết hơn trong [Phần 14](./part14-fast-mode-watchers.md). Tóm tắt:

### Context engine tùy chỉnh

Bản thay thế cắm-và-chạy (plug-and-play) cho những gì được inject vào mỗi lượt (turn) của agent:

```yaml
# ~/.hermes/config.yaml
context_engine: my-custom-engine
```

Dùng nó để lọc memory theo dự án, tóm tắt trước đầu ra của tool, lấy dữ liệu từ LightRAG hoặc một vector DB riêng, v.v. Xem Phần 14 để biết một cách triển khai tối giản.

### `/compress <topic>`

Trình nén ngữ cảnh (context compressor) (Phần 6) giờ đây nhận một chủ đề tập trung (focus topic) tùy chọn:

```text
You → /compress migration to Fly.io
  Compressing 47 messages with focus: "migration to Fly.io".
  Kept 6 messages verbatim, summarized 41 into 2 bullet blocks.
```

Giữ lại chi tiết liên quan đến chủ đề và nén mạnh mẽ mọi thứ còn lại. Hoàn hảo để cứu vãn một phiên debug dài sau khi bạn đã giải quyết được vấn đề và muốn giữ lại dấu vết quyết định nhưng loại bỏ 200 tool call khám phá.

---

## Ghi Chú Tăng Cường Bảo Mật

Một số thay đổi tăng cường bảo mật đã xuất hiện trong các bản phát hành "everywhere" + "gateway" đáng được nêu ra rõ ràng:

### Ẩn dữ liệu (redaction) và blocklist cứng (hardline blocklist) từ v0.13+

Hermes v0.13+ bật tính năng ẩn secret theo mặc định và giữ lại blocklist cứng cho các lệnh không nên được khôi phục thông qua các prompt phê duyệt (approval) thông thường. Hãy giữ denylist riêng của bạn nữa, nhưng đừng dựa vào việc "model sẽ biết cái này nguy hiểm" đối với các lệnh xóa thư mục home, thu thập credential, hoặc truy cập các dịch vụ metadata.

Các bổ sung denylist tùy chỉnh hữu ích:

```yaml
security:
  approval:
    denylist:
      - 'rm\s+-rf\s+(/|~|\$HOME)'
      - 'curl\s+.+\|\s*(sh|bash)'
      - '169\.254\.169\.254'
      - 'cat\s+~?/?\.?ssh/'
      - 'aws\s+s3\s+sync\s+.+\s+s3://'
      - 'ssh-keyscan'
```

### `hermes update --check` trước khi nâng cấp

Trước một lần nâng cấp lớn:

```bash
hermes update --check
hermes backup
```

Bước kiểm tra trước (preflight) phát hiện các sự không tương thích rõ ràng và bản sao lưu cho bạn một điểm khôi phục (rollback point) cho `HERMES_HOME`.

### Secret webhook được xác thực khi khởi động

Mọi adapter dựa trên webhook (Telegram, BlueBubbles, WeCom, Feishu, WeChat, Webhook chung) giờ đây xác thực secret ký (signing secret) của nó khi gateway khởi động. Một secret bị thiếu/rỗng/yếu sẽ tạo ra lỗi khởi động thay vì âm thầm chấp nhận các request giả mạo.

Tạo các secret mạnh:

```bash
openssl rand -hex 32
```

### Bảo vệ SSRF trên media gửi đi (outbound)

WeChat, Telegram, và BlueBubbles tải xuống media đến (inbound) thông qua một bộ xác thực (validator) chặn:
- Các IP riêng tư/loopback (`10.0.0.0/8`, `192.168.0.0/16`, `127.0.0.0/8`, v.v.)
- Các địa chỉ link-local (`169.254.0.0/16`)
- Các endpoint metadata (`169.254.169.254` — AWS/GCP IMDS)
- `file://`, `data://`, và các scheme không phải HTTP khác

Chỉ đặt `HERMES_ALLOW_PRIVATE_MEDIA_URLS=true` trên các mạng đáng tin cậy nơi agent của bạn thực sự cần fetch từ một host nội bộ.

### Giá trị biến môi trường được ẩn trong tất cả log

Mọi dòng log giờ đây chạy qua một bộ ẩn dữ liệu (redactor) theo mặc định, thay thế giá trị của các biến môi trường secret đã biết bằng `<redacted:VAR_NAME>` trước khi in ra. Ngăn chặn việc rò rỉ secret ngoài ý muốn tới các công cụ tổng hợp log (log aggregator) hoặc các gói debug được chia sẻ.

### `sudo` và `rm -rf` vẫn yêu cầu phê duyệt rõ ràng

Không có gì mới, nhưng đáng nhắc lại: các lệnh nguy hiểm vẫn kích hoạt UI phê duyệt (`ask` / `yolo` / `deny`) bất kể service tier, nền tảng gateway, hay cron runner. `/fast` không bỏ qua việc phê duyệt.

### Bỏ qua phê duyệt cho các subagent đáng tin cậy

Các subagent được sinh ra bởi orchestrator giờ đây kế thừa tư thế phê duyệt (approval posture) của phiên cha theo mặc định. Nếu phiên cha đang ở chế độ `yolo` (mọi tool call được tự động phê duyệt), thì subagent cũng vậy. Nếu phiên cha ở chế độ `ask`, các subagent sẽ nhắc người dùng đối với các lệnh gọi nguy hiểm. Ghi đè theo từng lần ủy quyền (delegation):

```python
delegate_task(
    goal="Research X",
    approvals="ask",        # override inherited posture
    toolsets=["file"],
)
```

---

## Tiếp Theo Là Gì

Bây giờ bạn đã thấy phần backup/debug trong bề mặt tính năng hiện tại:

- [Phần 12 — Web Dashboard](./part12-web-dashboard.md)
- [Phần 13 — Nous Tool Gateway](./part13-tool-gateway.md)
- [Phần 14 — Fast Mode & Background Watchers](./part14-fast-mode-watchers.md)
- [Phần 15 — Các Nền Tảng Mới (Teams, LINE, SimpleX, iMessage, WeChat, Android)](./part15-new-platforms.md)
- [Phần 23 — Tenacity Stack](./part23-tenacity-stack.md)

Nếu bạn cài đặt mới trên v0.14.0 và đã đi qua [Phần 1](./part1-setup.md) cùng loạt bài này, bạn đang chạy cấu hình Hermes mạnh mẽ nhất từ trước đến nay.
