# Phần 4: Thiết Lập Telegram (Trò Chuyện Từ Bất Kỳ Đâu)

*Kết nối Hermes với Telegram để truy cập trên di động, ghi âm thoại, trò chuyện nhóm, và giao nhận tác vụ theo lịch trình. Đây là adapter nhắn tin được thử nghiệm kỹ lưỡng nhất trong số 22+ adapter nhắn tin — bắt đầu từ đây, rồi mở rộng sang các adapter khác khi cần.*

---

## Cổng Kết Nối 22+ Nền Tảng

Tính đến v0.14.0 (tháng 5 năm 2026), gateway của Hermes cung cấp adapter/plugin cho **22+ nền tảng**. Tất cả đều dùng chung session DB, chung công tắc `/fast`, chung hệ thống Tool Gateway, và chung cơ chế giao nhận cron. v0.14 cũng cải thiện việc lấy lịch sử/tìm kiếm trên Discord, giúp các kênh server lớn hữu ích hơn như nguồn ngữ cảnh thay vì chỉ là trigger từng tin nhắn một.

| Chủ lực | Mới trong v0.9 | Doanh nghiệp / khu vực | Tự lưu trữ / tổng quát |
|----------|-------------|-----------------------|-----------------------|
| Telegram (phần này) | iMessage (BlueBubbles) | DingTalk | Signal |
| Discord | WeChat / Weixin | Feishu / Lark | Matrix |
| Slack | WeCom | Mattermost | SMS (Twilio) |
| Google Chat | QQBot | Microsoft Teams | Email (IMAP+SMTP) |
| LINE | SimpleX Chat | WhatsApp | |
| | Tencent Yuanbao | | Home Assistant |
| | | | Webhook (tổng quát) |

- Đối với **LINE, SimpleX, Teams, iMessage, WeChat, và Android/Termux**, xem [Phần 15](./part15-new-platforms.md).
- Đối với **khôi phục sự cố gateway** và kiểm tra tình trạng trên mọi nền tảng, xem [Phần 11](./part11-gateway-recovery.md).
- Đối với giao diện trình duyệt quản lý trạng thái của mọi nền tảng, xem [Phần 12](./part12-web-dashboard.md).

---

## Tại Sao Chọn Telegram Đầu Tiên

Agent của bạn chỉ hữu ích nếu bạn có thể truy cập nó. Ngồi trước terminal chỉ ổn cho đến khi bạn cần:

- Kiểm tra điều gì đó từ điện thoại khi không ở gần máy tính
- Nhận thông báo khi một tác vụ chạy lâu hoàn tất
- Dùng Hermes trong trò chuyện nhóm với team của bạn
- Gửi ghi âm thoại để tự động chuyển thành văn bản và xử lý
- Nhận kết quả tác vụ theo lịch trình (cron job) trên di động

Telegram là nền tảng nhắn tin tốt nhất cho bot Hermes — nó hỗ trợ văn bản, giọng nói, hình ảnh, tệp tin, nút bấm nội tuyến, và trò chuyện nhóm với thiết lập tối thiểu.

---

## Bước 1: Tạo Bot Qua BotFather

Mọi bot Telegram đều cần một API token từ [@BotFather](https://t.me/BotFather), công cụ quản lý bot chính thức của Telegram.

1. Mở Telegram và tìm **@BotFather**, hoặc truy cập [t.me/BotFather](https://t.me/BotFather)
2. Gửi `/newbot`
3. Chọn một **tên hiển thị** (ví dụ: "Hermes Agent") — có thể là bất kỳ tên gì
4. Chọn một **username** — phải là duy nhất và kết thúc bằng `bot` (ví dụ: `my_hermes_bot`)
5. BotFather sẽ trả lời với **API token** của bạn. Nó trông như thế này:

```
123456789:ABCdefGHIjklMNOpqrSTUvwxYZ
```

> **Giữ bí mật token bot của bạn.** Bất kỳ ai có token này đều có thể điều khiển bot của bạn. Nếu bị lộ, thu hồi ngay lập tức qua `/revoke` trong BotFather.

---

## Bước 2: Tùy Chỉnh Bot Của Bạn (Tùy Chọn)

Các lệnh BotFather sau đây cải thiện trải nghiệm người dùng:

| Lệnh | Mục đích |
|---------|---------|
| `/setdescription` | Văn bản "Bot này có thể làm gì?" hiển thị trước khi trò chuyện |
| `/setabouttext` | Văn bản ngắn trên trang hồ sơ của bot |
| `/setuserpic` | Tải lên ảnh đại diện cho bot của bạn |
| `/setcommands` | Định nghĩa menu lệnh (nút `/` trong trò chuyện) |

Đối với `/setcommands`, một bộ khởi đầu hữu ích:

```
help - Show help information
new - Start a new conversation
sethome - Set this chat as the home channel
status - Show agent status
```

---

## Bước 3: Chế Độ Riêng Tư (Quan Trọng Đối Với Nhóm)

Bot Telegram bật **chế độ riêng tư** theo mặc định. Đây là nguồn gây nhầm lẫn phổ biến nhất.

**Khi chế độ riêng tư BẬT**, bot của bạn chỉ có thể thấy:
- Các tin nhắn bắt đầu bằng lệnh `/`
- Các phản hồi trực tiếp đến tin nhắn của chính bot
- Tin nhắn dịch vụ (thành viên tham gia/rời nhóm, tin nhắn được ghim)

**Khi chế độ riêng tư TẮT**, bot nhận mọi tin nhắn trong nhóm.

### Cách Tắt Chế Độ Riêng Tư

1. Nhắn tin cho **@BotFather**
2. Gửi `/mybots`
3. Chọn bot của bạn
4. Vào **Bot Settings → Group Privacy → Turn off**

> **Bạn phải xóa và thêm lại bot vào bất kỳ nhóm nào** sau khi thay đổi cài đặt riêng tư. Telegram lưu cache trạng thái riêng tư khi một bot tham gia nhóm — nó sẽ không cập nhật cho đến khi bị xóa và thêm lại.

> **Cách khác:** Thăng cấp bot lên **quản trị viên nhóm**. Bot quản trị viên luôn nhận mọi tin nhắn bất kể cài đặt riêng tư.

---

## Bước 4: Tìm User ID Của Bạn

Hermes dùng ID người dùng Telegram dạng số để kiểm soát truy cập. User ID của bạn **không phải** là username — mà là một con số như `123456789`.

**Cách 1 (khuyến nghị):** Nhắn tin cho [@userinfobot](https://t.me/userinfobot) — nó sẽ trả lời ngay lập tức với user ID của bạn.

**Cách 2:** Nhắn tin cho [@get_id_bot](https://t.me/get_id_bot) — một lựa chọn đáng tin cậy khác.

Lưu lại con số này; bạn sẽ cần nó cho bước tiếp theo.

---

## Bước 5: Cấu Hình Hermes

### Tùy Chọn A: Thiết Lập Tương Tác (Khuyến Nghị)

```bash
hermes gateway setup
```

Chọn **Telegram** khi được hỏi. Trình hướng dẫn sẽ yêu cầu bot token và danh sách user ID được phép, sau đó tự ghi cấu hình cho bạn.

### Tùy Chọn B: Cấu Hình Thủ Công

Thêm nội dung sau vào `~/.hermes/.env`:

```bash
TELEGRAM_BOT_TOKEN=<your-bot-token-from-botfather>
TELEGRAM_ALLOWED_USERS=<your-numeric-user-id>    # Comma-separated for multiple users
```

> **Mẹo bảo mật:** Sau khi chỉnh sửa, chạy `chmod 600 ~/.hermes/.env` để hạn chế quyền truy cập tệp chỉ cho người dùng của bạn.

Đối với nhóm, cũng thêm ID chat nhóm (số âm, như `-1001234567890`):

```bash
TELEGRAM_ALLOWED_CHATS=-1001234567890
```

---

## Bước 6: Khởi Động Gateway

```bash
hermes gateway
```

Bot sẽ hoạt động trong vài giây. Gửi cho nó một tin nhắn trên Telegram để xác nhận.

---

## Quản Lý Gateway

```bash
# Check gateway status
hermes gateway status

# Stop the gateway
hermes gateway stop

# Restart after config changes
hermes gateway restart

# Run as a system service (auto-start on boot)
hermes gateway install   # Sets up systemd/launchd service
```

---

## Tính Năng Có Sẵn Trên Telegram

### Trò Chuyện Văn Bản
Hỗ trợ trò chuyện đầy đủ — bot xử lý tin nhắn của bạn giống như trên CLI.

### Tin Nhắn Thoại
Gửi một ghi âm thoại và Hermes sẽ:
1. Tự động chuyển thành văn bản bằng Whisper
2. Xử lý bản chuyển văn bản như một tin nhắn văn bản
3. Phản hồi bằng văn bản (hoặc giọng nói qua TTS)

### Phân Tích Hình Ảnh
Gửi một bức ảnh và Hermes sẽ phân tích nó bằng các mô hình thị giác. Mô tả những gì bạn muốn biết về hình ảnh trong phần chú thích.

### Tệp Đính Kèm
Gửi tài liệu, tệp mã nguồn, hoặc tệp dữ liệu — Hermes có thể đọc và xử lý chúng.

### Nút Bấm Nội Tuyến
Đối với các lệnh nguy hiểm, Hermes hiển thị nút xác nhận thay vì thực thi ngay lập tức.

### Lệnh Gạch Chéo
Bot hỗ trợ menu lệnh gốc của Telegram (nút `/` trong trò chuyện).

### Tin Nhắn Theo Lịch Trình
Kết quả cron job được giao trực tiếp đến chat Telegram của bạn:

```bash
# Deliver cron results to Telegram
hermes cron create --deliver telegram "Check server status every hour" --schedule "every 1h"
```

---

## Chế Độ Webhook (Dành Cho Triển Khai Trên Cloud)

Theo mặc định, Hermes dùng **long polling** — gateway thực hiện các yêu cầu gửi đi đến Telegram. Cách này phù hợp cho máy chủ cục bộ và luôn bật.

Đối với **triển khai trên cloud** (Fly.io, Railway, Render), **chế độ webhook** tốt hơn. Các nền tảng này tự động đánh thức khi có lưu lượng HTTP đến nhưng không đánh thức khi có kết nối đi.

### Cấu Hình

Thêm vào `~/.hermes/.env`:

```bash
TELEGRAM_WEBHOOK_URL=https://your-app.fly.dev
TELEGRAM_WEBHOOK_SECRET=<generate-with-command-below>
```

Tạo một secret mạnh — không bao giờ dùng giá trị dễ đoán:

```bash
openssl rand -hex 32
```

Sao chép kết quả và dán làm giá trị `TELEGRAM_WEBHOOK_SECRET` của bạn.

> **Cảnh báo:** Một webhook secret yếu hoặc mặc định sẽ cho phép kẻ tấn công giả mạo yêu cầu webhook Telegram và tiêm tin nhắn vào agent của bạn. Luôn dùng một giá trị ngẫu nhiên có độ an toàn mật mã học.

| | Polling (mặc định) | Webhook |
|---|---|---|
| Hướng | Gateway → Telegram | Telegram → Gateway |
| Phù hợp nhất cho | Máy chủ cục bộ, luôn bật | Nền tảng cloud |
| Cấu hình thêm | Không có | `TELEGRAM_WEBHOOK_URL` |
| Chi phí khi rảnh | Máy phải luôn bật | Máy có thể ngủ |

---

## Thiết Lập Đa Người Dùng

Để cho phép nhiều người dùng tương tác với bot:

```bash
TELEGRAM_ALLOWED_USERS=123456789,987654321,555555555
```

Mỗi người dùng có phiên trò chuyện riêng của mình. Bot theo dõi phiên theo từng user ID.

---

## Xử Lý Sự Cố

### Bot không phản hồi

1. Kiểm tra token đã được thiết lập (không in đầy đủ ra): `echo ${TELEGRAM_BOT_TOKEN:0:10}...`
2. Xác minh gateway đang chạy: `hermes gateway status`
3. Kiểm tra log: `hermes gateway logs`

### Bot trong nhóm nhưng không thấy tin nhắn

Chế độ riêng tư vẫn đang bật. Bạn phải:
1. Tắt chế độ riêng tư trong BotFather (`/mybots` → Bot Settings → Group Privacy → Turn off)
2. **Xóa bot khỏi nhóm**
3. **Thêm lại bot vào nhóm**

### Tin nhắn thoại không được chuyển thành văn bản

Hermes cần `ffmpeg` để chuyển đổi âm thanh. Trình cài đặt đã bao gồm sẵn, nhưng nếu bạn cài đặt thủ công:

```bash
sudo apt install ffmpeg   # Ubuntu/Debian
brew install ffmpeg        # macOS
```

### Giới hạn tốc độ

Telegram giới hạn bot ở mức 30 tin nhắn/giây đến các chat khác nhau và 20 tin nhắn/phút đến cùng một nhóm. Nếu bạn đang chạm giới hạn, thêm một độ trễ:

```bash
hermes config set telegram.rate_limit_delay 1
```

---

## Bước Tiếp Theo

- **Muốn agent tự cải thiện?** → [Phần 5: Kỹ Năng Tạo Nhanh](./part5-creating-skills.md)
