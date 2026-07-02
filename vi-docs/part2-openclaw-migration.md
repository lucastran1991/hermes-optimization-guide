# Phần 2: Di chuyển từ OpenClaw (Đừng bỏ lại kiến thức của bạn)

*Chuyển toàn bộ skills, memory, config, và tính cách từ OpenClaw sang Hermes chỉ với một lệnh.*

---

## Tại Sao Phải Di Chuyển

Hermes là phiên bản kế thừa của OpenClaw. Nếu bạn đã dành nhiều tuần hoặc nhiều tháng để xây dựng skills, các file memory, và cấu hình trong OpenClaw, công cụ di chuyển sẽ mang tất cả những thứ đó sang một cách tự động.

**Những gì sẽ được chuyển:**

| Nội dung | Vị trí trong OpenClaw | Đích đến trong Hermes |
|------|------------------|-------------------|
| Tính cách | `workspace/SOUL.md` | `~/.hermes/SOUL.md` |
| Hướng dẫn | `workspace/AGENTS.md` | Workspace đích mà bạn chỉ định |
| Memory | `workspace/MEMORY.md` + `workspace/memory/*.md` | `~/.hermes/memories/MEMORY.md` (đã gộp, loại trùng lặp) |
| Hồ sơ người dùng | `workspace/USER.md` | `~/.hermes/memories/USER.md` |
| Skills | `workspace/skills/`, `~/.openclaw/skills/` | `~/.hermes/skills/openclaw-imports/` |
| Cấu hình model | `agents.defaults.model` | `config.yaml` |
| Khóa của provider | `models.providers.*.apiKey` | `~/.hermes/.env` (với `--migrate-secrets`) |
| Provider tùy chỉnh | `models.providers.*` | `config.yaml → custom_providers` |
| Số lượt tối đa | `agents.defaults.timeoutSeconds` | `agent.max_turns` (timeoutSeconds / 10) |

> **Lưu ý:** Bản ghi phiên làm việc (session transcripts), định nghĩa cron job, và dữ liệu riêng của plugin sẽ không được chuyển. Đây là những thứ đặc thù của OpenClaw và có định dạng khác trong Hermes.

---

## Di Chuyển Nhanh

```bash
# Xem trước những gì sẽ xảy ra (không thay đổi file nào)
hermes claw migrate --dry-run

# Chạy toàn bộ quá trình di chuyển (bao gồm cả API keys)
hermes claw migrate

# Loại trừ API keys (an toàn hơn cho các máy dùng chung)
hermes claw migrate --preset user-data
```

Công cụ di chuyển sẽ đọc từ `~/.openclaw/` theo mặc định. Nếu bạn có các thư mục cũ `~/.clawdbot/` hoặc `~/.moldbot/`, chúng sẽ được tự động phát hiện.

---

## Các Tùy Chọn Di Chuyển

| Tùy chọn | Chức năng | Mặc định |
|--------|-------------|---------|
| `--dry-run` | Xem trước mà không ghi bất cứ thứ gì | tắt |
| `--preset full` | Bao gồm API keys và secrets | có |
| `--preset user-data` | Loại trừ API keys | không |
| `--overwrite` | Ghi đè các file Hermes hiện có khi có xung đột | bỏ qua |
| `--migrate-secrets` | Bao gồm API keys một cách tường minh | bật khi dùng `--preset full` |
| `--source <path>` | Thư mục OpenClaw tùy chỉnh | `~/.openclaw/` |
| `--workspace-target <path>` | Nơi đặt `AGENTS.md` | thư mục hiện tại |
| `--skill-conflict <mode>` | `skip`, `overwrite`, hoặc `rename` | `skip` |
| `--yes` | Bỏ qua bước xác nhận | tắt |

---

## Hướng Dẫn Từng Bước

### 1. Chạy Thử (Dry Run) Trước Tiên

Luôn xem trước trước khi thực hiện thật:

```bash
hermes claw migrate --dry-run
```

Lệnh này sẽ hiển thị chính xác những file nào sẽ được tạo, ghi đè, hoặc bỏ qua. Hãy xem kỹ kết quả đầu ra.

### 2. Chạy Di Chuyển

```bash
hermes claw migrate
```

Công cụ sẽ:
1. Phát hiện bản cài đặt OpenClaw của bạn
2. Ánh xạ các khóa cấu hình sang các khóa tương ứng trong Hermes
3. Gộp các file memory (loại bỏ các mục trùng lặp)
4. Sao chép skills vào `~/.hermes/skills/openclaw-imports/`
5. Di chuyển API keys (nếu dùng `--preset full`)
6. Báo cáo những gì đã thực hiện

### 3. Xử Lý Xung Đột

Nếu một skill đã tồn tại trong Hermes với cùng tên:

- **`--skill-conflict skip`** (mặc định): Giữ nguyên phiên bản trong Hermes, bỏ qua việc nhập
- **`--skill-conflict overwrite`**: Thay thế phiên bản trong Hermes bằng phiên bản của OpenClaw
- **--skill-conflict rename`**: Tạo một bản sao `-imported` bên cạnh phiên bản trong Hermes

```bash
# Ví dụ: đổi tên khi xung đột để bạn có thể so sánh
hermes claw migrate --skill-conflict rename
```

### 4. Kiểm Tra Sau Khi Di Chuyển

```bash
# Kiểm tra tính cách đã được nạp
cat ~/.hermes/SOUL.md

# Kiểm tra các mục memory đã được gộp
cat ~/.hermes/memories/MEMORY.md | head -50

# Kiểm tra skills đã được nhập
ls ~/.hermes/skills/openclaw-imports/

# Kiểm thử agent
hermes chat -q "What do you remember about me?"
```

---

## Những Gì Không Được Chuyển

| Mục | Lý do | Cần làm gì |
|------|-----|-----------|
| Bản ghi phiên làm việc (Session transcripts) | Khác định dạng | Lưu trữ thủ công nếu cần |
| Định nghĩa cron job | Bộ lập lịch khác nhau | Tạo lại bằng `hermes cron` |
| Cấu hình plugin | Hệ thống plugin đã thay đổi | Cấu hình lại trong Hermes |
| Các tính năng đặc thù của OpenClaw | Có thể chưa tồn tại | Kiểm tra tài liệu Hermes để tìm tính năng tương đương |

---

## Bảng Ánh Xạ Khóa Cấu Hình

Để tham khảo, đây là cách cấu hình OpenClaw ánh xạ sang Hermes:

| Cấu hình OpenClaw | Cấu hình Hermes | Ghi chú |
|----------------|---------------|-------|
| `agents.defaults.model` | `model` | Chuỗi hoặc `{primary, fallbacks}` |
| `agents.defaults.timeoutSeconds` | `agent.max_turns` | Chia cho 10, giới hạn tối đa 200 |
| `agents.defaults.verboseDefault` | `agent.verbose` | off / on / full |
| `agents.defaults.thinkingDefault` | `reasoning.mode` | off / low / high |
| `models.providers.*.baseUrl` | `custom_providers.*.base_url` | Ánh xạ trực tiếp |
| `models.providers.*.apiType` | `custom_providers.*.api_type` | openai → chat_completions, anthropic → anthropic_messages |

---

## Xử Lý Sự Cố

### "No OpenClaw installation found"

Hãy đảm bảo dữ liệu OpenClaw của bạn nằm ở `~/.openclaw/`. Nếu nó nằm ở nơi khác:

```bash
hermes claw migrate --source /path/to/your/openclaw
```

### Các mục memory trông bị trùng lặp

Quá trình di chuyển loại bỏ trùng lặp dựa trên độ tương đồng nội dung, nhưng nếu memory OpenClaw của bạn có các mục gần giống nhau, chúng có thể không được gộp hoàn hảo. Hãy dọn dẹp thủ công:

```bash
# Chỉnh sửa memory trực tiếp
nano ~/.hermes/memories/MEMORY.md
```

### Skills bị lỗi import

Skills của OpenClaw có thể tham chiếu đến các module hoặc pattern không tồn tại trong Hermes. Hãy mở file skill và kiểm tra các import:

```bash
cat ~/.hermes/skills/openclaw-imports/skill-name/SKILL.md
```

Hầu hết các skill hoạt động bình thường vì chúng là các hướng dẫn dựa trên markdown. Các skill có code import các module đặc thù của OpenClaw cần được cập nhật thủ công.

---

## Bước Tiếp Theo

- **Muốn memory thông minh hơn?** → [Phần 3: Thiết Lập LightRAG](./part3-lightrag-setup.md)
- **Cần truy cập từ điện thoại?** → [Phần 4: Thiết Lập Telegram](./part4-telegram-setup.md)
- **Muốn agent tự cải thiện?** → [Phần 5: Tạo Skill Ngay Lập Tức](./part5-creating-skills.md)
