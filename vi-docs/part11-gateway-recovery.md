# Phần 11: Khôi phục Gateway (Khi mọi thứ hỏng lúc 3 giờ sáng)

*Gateway là thân não. Khi nó sập, mọi thứ đều dừng lại.*

---

## Gateway làm gì

Gateway (`hermes gateway`) là tiến trình chạy liên tục, có nhiệm vụ:
- Nhận tin nhắn từ Telegram, Discord, Slack, CLI
- Định tuyến chúng đến agent
- Quản lý session và context
- Chạy các cron job

Nếu gateway chết, agent của bạn sẽ không thể truy cập được.

## Phát hiện sự cố sập

```bash
# Kiểm tra xem gateway có đang chạy không
hermes status

# Hoặc trực tiếp
ps aux | grep hermes-gateway

# Kiểm tra log
tail -50 ~/.hermes/logs/gateway.log
```

## Các nguyên nhân sập thường gặp

### 1. Tràn cửa sổ ngữ cảnh (Context Window Overflow)

**Triệu chứng:** Gateway chết giữa chừng khi phản hồi, log hiển thị lỗi đếm token.

**Cách khắc phục:** Giảm việc chèn context trong `~/.hermes/.env`:

```bash
# Giảm ngưỡng context tối đa (mặc định thường là mức tối đa của model)
MAX_CONTEXT_TOKENS=80000

# Bật nén sớm hơn
CONTEXT_COMPRESSION_THRESHOLD=70
```

### 2. Hết bộ nhớ (OOM - Out of Memory)

**Triệu chứng:** Gateway bị OOM killer giết, `dmesg` hiển thị `Out of memory: Killed process`.

**Cách khắc phục:**

```bash
# Kiểm tra mức sử dụng bộ nhớ
free -h

# Nếu dùng model cục bộ qua Ollama, chúng sẽ ngốn VRAM/RAM
# Chuyển Ollama sang một máy riêng hoặc giảm kích thước model

# Giới hạn bộ nhớ cho gateway
# Trong service systemd hoặc script khởi chạy:
systemctl edit hermes-gateway
# Thêm: MemoryMax=4G
```

### 3. Nhà cung cấp API bị sập

**Triệu chứng:** Gateway vẫn chạy nhưng mọi phản hồi đều thất bại, log hiển thị lỗi kết nối.

**Cách khắc phục:** Cấu hình các nhà cung cấp dự phòng (xem Phần 9):

```yaml
model_fallback:
  - provider: cerebras
    model: qwen-3-32b
  - provider: openrouter
    model: anthropic/claude-sonnet-5
  - provider: local
    model: nemotron:latest
```

### 4. Đầy ổ đĩa

**Triệu chứng:** Gateway không thể ghi file session, log, hoặc cơ sở dữ liệu bộ nhớ.

**Cách khắc phục:**

```bash
# Kiểm tra dung lượng ổ đĩa
df -h

# Dọn dẹp các file session cũ (an toàn để xóa)
find ~/.hermes/sessions -mtime +30 -delete

# Dọn dẹp log cũ
find ~/.hermes/logs -mtime +7 -delete

# Kiểm tra dung lượng dữ liệu LightRAG
du -sh ~/.hermes/skills/research/lightrag/data/
```

### 5. Vòng lặp sập (Crash Loop)

**Triệu chứng:** Gateway khởi động, sập ngay lập tức, rồi lặp lại.

**Cách khắc phục:**

```bash
# Kiểm tra log sập gần nhất
tail -100 ~/.hermes/logs/gateway.log

# Nguyên nhân thường gặp: file session bị hỏng
# Di chuyển các session ra ngoài tạm thời
mv ~/.hermes/sessions ~/.hermes/sessions.bak
mkdir ~/.hermes/sessions

# Khởi động lại
hermes gateway

# Nếu nó hoạt động, vấn đề nằm ở một session bị hỏng
# Di chuyển từng session trở lại để tìm ra session lỗi
```

## Tự động khôi phục (systemd)

Thiết lập systemd để tự động khởi động lại gateway:

```ini
# /etc/systemd/system/hermes-gateway.service
[Unit]
Description=Hermes Agent Gateway
After=network.target

[Service]
Type=simple
User=terp
WorkingDirectory=/home/terp/.hermes
ExecStart=/home/terp/.hermes/venv/bin/python -m hermes_gateway
Restart=always
RestartSec=5
MemoryMax=4G

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable hermes-gateway
sudo systemctl start hermes-gateway

# Kiểm tra trạng thái
sudo systemctl status hermes-gateway

# Xem log
journalctl -u hermes-gateway -f
```

## Tự động khôi phục (Dự phòng bằng Cron)

Nếu bạn không thể dùng systemd, hãy dùng một cron watchdog:

```bash
# Thêm vào crontab -e
* * * * * pgrep -f "hermes.*gateway" > /dev/null || (cd ~/.hermes && nohup ./venv/bin/python -m hermes_gateway >> logs/watchdog.log 2>&1 &)
```

Kiểm tra mỗi phút. Nếu gateway không chạy, nó sẽ khởi động gateway.

## Kiểm tra tình trạng (Health Check)

Script nhanh để xác minh mọi thứ đang hoạt động bình thường:

```bash
#!/bin/bash
# ~/.hermes/scripts/health-check.sh

# Gateway có đang chạy không?
if ! pgrep -f "hermes.*gateway" > /dev/null; then
    echo "CRITICAL: Gateway not running"
    exit 1
fi

# Chúng ta có thể truy cập API không? (gateway chỉ nên lắng nghe trên localhost)
if ! curl -s http://localhost:8642/health > /dev/null 2>&1; then
    echo "CRITICAL: Gateway not responding"
    exit 1
fi

# Dung lượng ổ đĩa có ổn không?
USAGE=$(df -Ph ~/.hermes | awk 'NR==2 {print $5}' | tr -d '%')
if [ "$USAGE" -gt 90 ]; then
    echo "WARNING: Disk usage at ${USAGE}%"
    exit 1
fi

echo "OK"
```

---

*Gateway nên nhàm chán. Nếu nó thú vị, tức là có gì đó không ổn.*
