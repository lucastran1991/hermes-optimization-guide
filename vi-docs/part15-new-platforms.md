# Phần 15: Các Nền Tảng Nhắn Tin (iMessage qua Photon, WhatsApp Cloud, Teams, LINE, SimpleX, Google Chat, WeChat, Android)

*Cổng gateway của Hermes giờ đây là một plugin host. v0.9 đã giúp Hermes "có mặt khắp nơi"; v0.11/v0.12 bổ sung QQBot, Tencent Yuanbao, và Microsoft Teams; v0.13 bổ sung Google Chat; v0.14 kết nối Teams đầu-cuối và bổ sung LINE + SimpleX Chat; v0.15 bổ sung ntfy; và v0.17 "Reach" bổ sung cùng lúc ba yêu cầu lớn nhất — **iMessage không cần Mac (Photon)**, một adapter **WhatsApp Business Cloud API chính thức**, và mạng agent-to-agent **Raft**.*

---

## Danh Sách 25+ Nền Tảng

Tính đến v0.17, gateway cung cấp sẵn các adapter tích hợp cùng các nền tảng do plugin cung cấp:

| Nền tảng | Chế độ | Ghi chú |
|----------|------|-------|
| Telegram | Polling + Webhook | Adapter chủ lực — xem [Phần 4](./part4-telegram-setup.md) |
| Discord | WebSocket (bot) | Slash commands, voice/media, DM + server |
| Slack | Socket / Events API | Threads, tải lên tệp, blocks |
| **Google Chat** | App / webhook | **Mới trong v0.13**, mặt trận chat gốc của Workspace |
| **LINE** | Messaging API | **Mới trong v0.14**, mặt trận mobile-first cho Nhật Bản/Hàn Quốc/Đài Loan |
| **SimpleX Chat** | Chat phi tập trung | **Mới trong v0.14**, chat ưu tiên quyền riêng tư, không có user ID |
| WhatsApp (cá nhân) | Web API | Đăng nhập bằng mã QR, cần node luôn bật |
| **iMessage (Photon)** | Relay Photon Spectrum | **Mới trong v0.17** — không cần Mac |
| **iMessage (BlueBubbles)** | Webhook | Phương án tự lưu trữ thay thế (cần Mac luôn bật) |
| **WhatsApp Business Cloud API** | Webhook chính thức của Meta | **Mới trong v0.17** — không cần node QR |
| **Raft** | Mạng agent | **Mới trong v0.17** — trò chuyện với agent khác, không phải con người |
| **Weixin (WeChat cá nhân)** | Long-poll | **Mới trong v0.9** |
| **WeCom (WeChat Doanh Nghiệp)** | Webhook | **Mới trong v0.9** |
| **QQBot** | WebSocket/Webhook | Bổ sung sau đợt rà soát nền tảng v0.9 ban đầu |
| **Tencent Yuanbao** | Gateway gốc | **Mới trong v0.12**, gửi văn bản + media |
| **Microsoft Teams** | Graph + webhook + runtime + delivery | Đầu-cuối trong v0.14 |
| Signal | REST qua signal-cli | Bridge tự lưu trữ |
| DingTalk | Webhook | IM doanh nghiệp, Trung Quốc/APAC |
| Feishu / Lark | Webhook | IM doanh nghiệp, ByteDance |
| SMS (Twilio) | Webhook | SMS thuần túy |
| Mattermost | WebSocket | Phương án thay thế Slack tự lưu trữ |
| Matrix | Client-server | Chat liên hợp (federated) |
| Email (IMAP+SMTP) | Polling | Email thuần túy |
| Home Assistant | WebSocket | Trigger giọng nói + tự động hóa |
| Webhook (chung) | HTTP POST | Kết nối với bất cứ thứ gì |

Tất cả đều tuân thủ:
- Kiểm soát truy cập Allowlist / allow-all / pairing
- `/fast` Fast Mode (Phần 14)
- Định tuyến Tool Gateway (Phần 13)
- Đích gửi Cron
- Cơ sở dữ liệu phiên (session) dùng chung (Phần 7)
- Các hook plugin trước khi dispatch

Phần này bao gồm các adapter của v0.9, các mặt trận mới hơn từ v0.12–v0.17, và **Android / Termux** — chạy chính bản thân agent trên điện thoại.

> **Telegram trở nên phong phú hơn trong v0.17:** adapter Telegram đã nâng cấp lên tin nhắn phong phú của Bot API 10.1 — đầu ra được định dạng kèm media, bật mặc định. Nếu phản hồi của bot bạn đột nhiên trông đẹp hơn, đó là lý do; nếu một client gặp lỗi khi xử lý chúng, có thể tắt theo từng gateway.

## Cập Nhật 2026 (v0.17): iMessage Không Cần Mac, WhatsApp Chính Thức, và Raft

### iMessage qua Photon Spectrum — mặc định mới

Yêu cầu #1 kể từ v0.9 — iMessage mà không cần dành riêng một máy Mac — đã ra mắt trong v0.17 dưới dạng platform plugin xây dựng trên nhóm số điện thoại được quản lý của **Photon Spectrum**:

```bash
hermes photon login    # device-code OAuth — xác thực và bạn sẽ hoạt động ngay
```

Đăng nhập, và Hermes sẽ sống trong các bong bóng chat màu xanh: DM, hiển thị markdown, phản ứng emoji, media gửi đi — qua một kênh gRPC-native (không cần webhook), không cần máy chủ macOS, không cần Full Disk Access, và không cần phần cứng luôn bật. Miễn phí để bắt đầu, không cần tự lưu trữ gì cả. Các kiểm soát truy cập (pairing, allowlist, `/fast`, gửi cron) hoạt động giống như mọi gateway khác.

Về mặt vận hành:

- **Dùng Photon** nếu bạn chỉ muốn Hermes trên iMessage. Đây là con đường được hỗ trợ chính thức, không cần phần cứng, và được định vị là người kế nhiệm của bridge BlueBubbles.
- **Giữ BlueBubbles** (bên dưới) nếu bạn cần luồng tin nhắn hoàn toàn tự lưu trữ — Photon là một dịch vụ relay, nên lưu lượng iMessage của bạn sẽ đi qua hạ tầng của họ. Với lập trường ưu tiên quyền riêng tư tối đa, bridge dựa trên Mac vẫn là câu trả lời.

### WhatsApp Business Cloud API — con đường chính thức

Adapter WhatsApp cũ điều khiển WhatsApp Web bằng đăng nhập QR và một node luôn bật — ổn cho sử dụng cá nhân, nhưng mong manh cho môi trường sản xuất. v0.17 bổ sung một adapter cho **Business Cloud API chính thức của Meta**: dựa trên webhook, không cần trông coi phiên trình duyệt, và hợp pháp cho mục đích kinh doanh. Nếu bạn đang xây dựng bất cứ thứ gì hướng đến khách hàng trên WhatsApp, hãy dùng cái này; giữ adapter Web cho các tài khoản cá nhân.

### Raft — agent của bạn có thêm đồng đội

Raft là một kênh mà đối phương là **một agent khác**, không phải con người. Một adapter đóng gói sẵn kết nối Hermes với [Raft](https://raft.build) như một agent bên ngoài thông qua một wake-channel bridge: đặt `RAFT_PROFILE`, chạy bridge, và Raft có thể đánh thức Hermes để xử lý tin nhắn. Thiết kế theo hướng privacy-by-contract — payload đánh thức chỉ mang metadata (event ID, timestamp), không bao giờ chứa nội dung tin nhắn. Tuy vậy: hãy coi mọi tin nhắn Raft đến là **đầu vào không đáng tin cậy** — cùng lập trường như một nhóm chat công khai: profile cách ly (quarantine), không có công cụ ghi (write tools), yêu cầu phê duyệt cho bất cứ điều gì chạm vào máy của bạn. [Phần 19](./part19-security-playbook.md) áp dụng gấp đôi ở đây.

## Cập Nhật 2026: Teams, LINE, SimpleX, Google Chat, QQBot, và Yuanbao

### Microsoft Teams

Teams không còn chỉ là bằng chứng cho kiến trúc plugin của v0.12. Trong v0.14, xác thực Graph, trình lắng nghe webhook, runtime pipeline, và cơ chế gửi đi (delivery) đã được kết nối với nhau, để Teams có thể trở thành một mặt trận chat doanh nghiệp thực thụ.

```yaml
gateways:
  teams:
    enabled: true
    tenant_id: ${MICROSOFT_TENANT_ID}
    client_id: ${MICROSOFT_TEAMS_CLIENT_ID}
    client_secret: ${MICROSOFT_TEAMS_CLIENT_SECRET}
    allowed_teams:
      - ${MICROSOFT_TEAMS_ADMIN_TEAM}
    trust_label: medium
```

Giữ việc phê duyệt trong một kênh admin riêng tư, không phải trong cùng team/kênh nơi các yêu cầu không đáng tin cậy được gửi đến.

### LINE

Sử dụng LINE khi người dùng của bạn ở Nhật Bản, Hàn Quốc, Đài Loan, hoặc trong một quy trình làm việc ưu tiên tiêu dùng/di động. Vận hành nó giống như Telegram: một bot/kênh admin cho việc phê duyệt, ID người dùng được phép nghiêm ngặt, và không có công cụ ghi trong các phòng công khai.

```yaml
gateways:
  line:
    enabled: true
    channel_access_token: ${LINE_CHANNEL_ACCESS_TOKEN}
    channel_secret: ${LINE_CHANNEL_SECRET}
    allowed_user_ids:
      - ${LINE_ADMIN_USER_ID}
```

### SimpleX Chat

SimpleX là lựa chọn ưu tiên quyền riêng tư: không có ID người dùng toàn cục, không có đồ thị định danh trung tâm. Điều này tốt cho quyền riêng tư nhưng khó khăn hơn cho việc vận hành. Yêu cầu pairing, lưu giữ nhãn liên hệ cục bộ, và không dùng nó làm kênh phê duyệt duy nhất cho đến khi việc khôi phục/sao lưu được kiểm chứng.

```yaml
gateways:
  simplex:
    enabled: true
    profile: simplex-admin
    require_pairing: true
    trust_label: medium
```

### Google Chat

Google Chat là lựa chọn Workspace sạch sẽ nhất cho các đội nhóm Google Workspace không muốn có một mặt trận Slack/Discord riêng biệt. Hãy coi các space như các nhóm chat: dùng allowlist, không bao giờ phê duyệt các hành động nhạy cảm trong cùng phòng đã yêu cầu chúng, và định tuyến các phê duyệt sản xuất đến một DM/kênh admin riêng tư.

Lập trường điển hình:

```yaml
gateways:
  google_chat:
    enabled: true
    project_id: ${GOOGLE_CLOUD_PROJECT}
    credentials_json: ${GOOGLE_CHAT_CREDENTIALS_JSON}
    allowed_spaces:
      - ${GOOGLE_CHAT_ADMIN_SPACE}
    trust_label: medium
```

Giữ các space công khai/hướng khách hàng trong profile cách ly cho đến khi việc ánh xạ định danh và định tuyến phê duyệt được kiểm chứng.

### QQBot

Sử dụng QQBot khi cộng đồng của bạn đã sinh sống trên QQ và bạn muốn cùng mô hình phê duyệt/phiên như Telegram hoặc Discord. Mặc định coi các nhóm QQ là đầu vào không đáng tin cậy: giữ allowlist chặt chẽ, yêu cầu phê duyệt cho các công cụ tệp/mạng, và dùng [Phần 19](./part19-security-playbook.md) để tăng cường chống prompt-injection.

### Tencent Yuanbao

Yuanbao giờ đây là một adapter gateway gốc với khả năng gửi văn bản và media. Nó thuộc cùng nhóm với Weixin/WeCom: mạnh mẽ trong các quy trình làm việc tại Trung Quốc/APAC, nhưng vận hành khác biệt so với các bot SaaS phương Tây. Kiểm chứng giới hạn kích thước media và ánh xạ định danh trước khi dùng nó cho các phê duyệt sản xuất.


## iMessage qua BlueBubbles (Phương Án Tự Lưu Trữ Thay Thế)

### Vì Sao Bạn Vẫn Có Thể Chọn Cách Này

> **Hầu hết mọi người nên dùng Photon ngay bây giờ** (`hermes photon login`, ở trên) — nó không cần Mac. BlueBubbles vẫn là lựa chọn đúng khi bạn muốn luồng tin nhắn không bao giờ rời khỏi phần cứng mà bạn sở hữu.

[BlueBubbles](https://bluebubbles.app/) là một máy chủ macOS mã nguồn mở miễn phí, cung cấp một REST API + luồng webhook trên nền cơ sở dữ liệu gốc của Messages.app. Nếu bạn có một máy Mac luôn bật, bạn sẽ có một bot iMessage tự lưu trữ hoàn toàn với đầy đủ media, phản ứng (reactions), chỉ báo đang gõ (typing indicators), và biên nhận đã đọc (read receipts).

### Điều Kiện Tiên Quyết

- Một máy **macOS 10.15+** luôn bật (một Mac mini hoặc MacBook dự phòng đều hoạt động tốt)
- Apple ID đã đăng nhập vào Messages.app trên máy đó, đang thực sự gửi + nhận iMessage
- Homebrew

### Bước 1: Cài Đặt BlueBubbles Server

```bash
brew install --cask bluebubbles
open /Applications/BlueBubbles.app
```

> Ứng dụng không được ký (Apple đã vô hiệu hóa tài khoản dev). Nếu macOS chặn nó, nhấp chuột phải trong Finder → **Open** → xác nhận.

### Bước 2: Cấp Quyền

System Settings → Privacy & Security, cấp cho BlueBubbles:

- **Full Disk Access** — bắt buộc (nó đọc `~/Library/Messages/chat.db`)
- **Accessibility** — tùy chọn, bật helper Private API cho phản ứng, chỉ báo đang gõ, và biên nhận đã đọc

### Bước 3: Ghi Lại Server URL và Mật Khẩu

BlueBubbles Server → **Settings → API**, ghi lại:

- **Server URL** (ví dụ `http://192.168.1.10:1234`)
- **Server Password**

### Bước 4: Cấu Hình Hermes

```bash
hermes gateway setup
```

Chọn **BlueBubbles (iMessage)**, dán URL + mật khẩu.

Hoặc cấu hình thủ công trong `~/.hermes/.env`:

```bash
BLUEBUBBLES_SERVER_URL=http://192.168.1.10:1234
BLUEBUBBLES_PASSWORD=your-server-password
```

### Bước 5: Ủy Quyền Người Dùng (Chọn Một)

**DM Pairing (khuyến nghị):**

Khi ai đó nhắn iMessage đến Apple ID của bạn, Hermes tự động trả lời với một mã pairing. Phê duyệt nó:

```bash
hermes pairing approve bluebubbles <CODE>
hermes pairing list    # xem các pairing đang chờ + đã phê duyệt
```

**Ủy quyền trước cho người dùng cụ thể** trong `.env`:

```bash
BLUEBUBBLES_ALLOWED_USERS=user@icloud.com,+15551234567
```

**Truy cập mở** (không khuyến nghị — iMessage của bạn có thể sẽ bị spam):

```bash
BLUEBUBBLES_ALLOW_ALL_USERS=true
```

### Bước 6: Khởi Động Gateway

```bash
hermes gateway run
```

Hermes sẽ đăng ký một webhook với BlueBubbles Server và lắng nghe. Tin nhắn đầu tiên nên khứ hồi (round-trip) trong vài giây.

### Tham Chiếu Biến Môi Trường

| Biến | Mặc định | Mục đích |
|----------|---------|---------|
| `BLUEBUBBLES_SERVER_URL` | — | Server URL (bắt buộc) |
| `BLUEBUBBLES_PASSWORD` | — | Mật khẩu server (bắt buộc) |
| `BLUEBUBBLES_WEBHOOK_HOST` | `127.0.0.1` | Địa chỉ bind của trình lắng nghe webhook |
| `BLUEBUBBLES_WEBHOOK_PORT` | `8645` | Cổng của trình lắng nghe webhook |
| `BLUEBUBBLES_WEBHOOK_PATH` | `/bluebubbles-webhook` | Đường dẫn URL webhook |
| `BLUEBUBBLES_HOME_CHANNEL` | — | Số điện thoại/email cho việc gửi cron |
| `BLUEBUBBLES_ALLOWED_USERS` | — | Danh sách người dùng được ủy quyền, phân tách bằng dấu phẩy |
| `BLUEBUBBLES_ALLOW_ALL_USERS` | `false` | Cho phép tất cả người dùng |
| `BLUEBUBBLES_SEND_READ_RECEIPTS` | `true` | Tự động đánh dấu tin nhắn là đã đọc |

### Tính Năng

- **Văn bản, hình ảnh, tin nhắn thoại, video, tài liệu** theo cả hai chiều
- **Phản ứng Tapback** (love / like / dislike / laugh / emphasize / question) — yêu cầu Private API
- **Chỉ báo đang gõ** — yêu cầu Private API
- **Biên nhận đã đọc** — yêu cầu Private API
- **Định vị chat bằng email hoặc số điện thoại** — Hermes tự động phân giải thành GUID của BlueBubbles
- **Gửi theo cron** — `hermes cron create --deliver bluebubbles …`

### Private API (Tùy Chọn Nhưng Hữu Ích)

Cài đặt gói helper: [docs.bluebubbles.app/helper-bundle/installation](https://docs.bluebubbles.app/helper-bundle/installation). Không có nó, văn bản + media cơ bản vẫn hoạt động — chỉ có phản ứng, chỉ báo đang gõ, và biên nhận đã đọc là cần đến nó.

### Lưu Ý Về Bảo Mật

BlueBubbles cấp quyền truy cập API vào **toàn bộ lịch sử iMessage** của bạn. Hãy coi mật khẩu server như mật khẩu root. Giữ BlueBubbles trên mạng LAN của bạn (hoặc sau Tailscale / WireGuard) thay vì công khai nó ra bên ngoài. Nếu bạn phải công khai nó, hãy dùng Ngrok / Cloudflare Tunnel kèm xác thực.

### Các Sự Cố Thường Gặp

- **"Cannot reach server"** — Mac đang ngủ, BlueBubbles không chạy, tường lửa đang chặn cổng
- **Tin nhắn không đến** — webhook chưa được đăng ký. Kiểm tra BlueBubbles Server → Settings → API → Webhooks. Đảm bảo URL webhook trỏ về đúng máy đang chạy Hermes.
- **"Private API helper not connected"** — chỉ cần thiết cho phản ứng/chỉ báo đang gõ/biên nhận. Cài đặt gói helper hoặc bỏ qua nếu bạn không cần những thứ đó.

---

## WeChat (Weixin, 微信)

### Vì Sao Điều Này Quan Trọng

WeChat là nền tảng nhắn tin cá nhân thống trị tại Trung Quốc và phần lớn châu Á - Thái Bình Dương. Adapter Weixin mới sử dụng iLink Bot API công khai của Tencent, không yêu cầu endpoint công khai, và đăng nhập qua mã QR — đúng trải nghiệm người dùng mà mọi người đã quen dùng với Web WeChat.

> Đối với WeChat doanh nghiệp/enterprise, xem phần WeCom bên dưới. Hai nền tảng này tách biệt nhau.

### Điều Kiện Tiên Quyết

- Một tài khoản WeChat cá nhân
- Các gói Python `aiohttp` và `cryptography`
- Tùy chọn: `qrcode` để hiển thị mã QR trên terminal trong quá trình thiết lập

```bash
pip install aiohttp cryptography
pip install qrcode   # tùy chọn — để hiển thị QR trên terminal
```

### Bước 1: Chạy Trình Hướng Dẫn Thiết Lập

```bash
hermes gateway setup
```

Chọn **Weixin**. Trình hướng dẫn sẽ:

1. Yêu cầu một mã QR từ iLink Bot API
2. Hiển thị nó trên terminal (hoặc in ra một URL đến hình ảnh)
3. Quét bằng ứng dụng di động WeChat → nhấn **Confirm Login**
4. Lưu thông tin xác thực vào `~/.hermes/weixin/accounts/`

Khi thành công:

```text
微信连接成功，account_id=your-account-id
```

Trình hướng dẫn lưu giữ `account_id`, `token`, và `base_url`. Bạn không cần đụng vào chúng nữa.

### Bước 2: Thiết Lập Kiểm Soát Truy Cập (Tùy Chọn)

Trong `~/.hermes/.env`:

```bash
WEIXIN_ACCOUNT_ID=your-account-id

# Chính sách truy cập DM: open, allowlist, disabled, hoặc pairing
WEIXIN_DM_POLICY=open

# Hoặc giới hạn ở người dùng cụ thể
WEIXIN_ALLOWED_USERS=user_id_1,user_id_2

# Đích cho cron/thông báo
WEIXIN_HOME_CHANNEL=chat_id
WEIXIN_HOME_CHANNEL_NAME=Home
```

### Bước 3: Khởi Động

```bash
hermes gateway
```

Adapter khôi phục thông tin xác thực đã lưu, kết nối đến iLink, và bắt đầu long-polling.

### Tính Năng

- **Vận chuyển long-poll** — không cần endpoint công khai, webhook, hay WebSocket
- **Đăng nhập bằng mã QR** — quét một lần, lưu giữ qua các lần khởi động lại
- **Nhắn tin DM và nhóm**
- **Media** — hình ảnh, video, tệp, tin nhắn thoại
- **CDN mã hóa AES-128-ECB** — tự động mã hóa/giải mã cho mọi lần truyền media
- **Định dạng lại markdown** — headers, bảng, khối mã được viết lại để dễ đọc trên WeChat
- **Chia nhỏ thông minh (smart chunking)** — một bong bóng duy nhất khi dưới giới hạn; chỉ chia tại ranh giới logic khi quá khổ
- **Chỉ báo đang gõ**
- **Bảo vệ SSRF** — URL media gửi đi được kiểm chứng trước khi tải xuống
- **Loại bỏ tin nhắn trùng lặp** — cửa sổ trượt 5 phút
- **Tự động thử lại kèm backoff** — chịu được các lỗi API tạm thời
- **Lưu giữ context token** — tính liên tục của phản hồi được lưu trên đĩa qua các lần khởi động lại

### Tham Chiếu Cấu Hình Đầy Đủ

Trong `config.yaml` dưới `platforms.weixin.extra`:

| Khóa | Mặc định | Mô tả |
|-----|---------|-------------|
| `account_id` | — | ID tài khoản iLink Bot (bắt buộc) |
| `token` | — | Token iLink Bot (bắt buộc, tự động lưu từ đăng nhập QR) |
| `base_url` | `https://ilinkai.weixin.qq.com` | URL cơ sở của iLink API |
| `cdn_base_url` | `https://novac2c.cdn.weixin.qq.com/c2c` | CDN cơ sở cho media |
| `dm_policy` | `open` | `open`, `allowlist`, `disabled`, hoặc `pairing` |

> **Người dùng Windows:** Windows gốc không được hỗ trợ cho adapter WeChat. Hãy dùng WSL2.

### Các Sự Cố Thường Gặp

- **QR hết hạn trước khi bạn quét** — chạy lại `hermes gateway setup` và giữ điện thoại sẵn sàng
- **"Login confirmed but no messages"** — kiểm tra `dm_policy`. `disabled` sẽ âm thầm loại bỏ mọi DM
- **Tải media thất bại** — bảo vệ SSRF đang chặn một URL nội bộ/riêng tư. Chỉ đặt `WEIXIN_ALLOW_PRIVATE_MEDIA_URLS=true` trên các mạng đáng tin cậy.

---

## WeCom (WeChat Doanh Nghiệp, 企业微信)

Adapter riêng biệt cho các triển khai doanh nghiệp. Việc thiết lập dựa trên webhook thay vì QR vì các bot WeCom chạy như các ứng dụng doanh nghiệp hạng nhất.

### Thiết Lập Nhanh

1. Trong bảng quản trị WeCom, tạo một bot mới dưới **Apps & Mini Programs → Bots**.
2. Ghi lại `corp_id`, `agent_id`, và `secret`.
3. Đặt một callback URL trỏ đến instance Hermes của bạn (phải là HTTPS, công khai, và phản hồi được bắt tay xác minh của WeCom).
4. Thêm vào `~/.hermes/.env`:

```bash
WECOM_CORP_ID=your-corp-id
WECOM_AGENT_ID=1000001
WECOM_SECRET=your-secret
WECOM_TOKEN=your-callback-token
WECOM_ENCODING_AES_KEY=your-43-char-aes-key
WECOM_ALLOWED_USERS=user_id_1,user_id_2
```

5. Chạy `hermes gateway` — trình xử lý webhook sẽ mở `/wecom/callback` và kiểm chứng chữ ký WeCom trên mọi sự kiện đến.

Bề mặt tính năng là một tập con của Weixin — DM và @mention trong chat nhóm, văn bản + media, và bot trả lời người dùng.

---

## Android / Termux (Chạy Hermes *Trên* Điện Thoại Của Bạn)

### Đây Là Gì

v0.9 bổ sung một con đường đã được kiểm thử để chạy chính CLI Hermes trực tiếp trên Android qua [Termux](https://termux.dev/). Không phải "kết nối đến Hermes từ điện thoại của bạn" — đó là việc của các adapter nhắn tin. **Đây là chạy toàn bộ agent cục bộ ngay trên điện thoại.**

Tuyệt vời cho:
- Công việc thực địa ngoại tuyến nơi bạn không muốn round-trip đến một server
- Một trợ lý tự chứa không bao giờ rời khỏi túi bạn
- Quản trị viên homelab muốn có `hermes` trong bộ công cụ SSH của họ trên bất kỳ thiết bị nào

### Gói Đã Kiểm Thử (Những Gì Bạn Nhận Được)

Con đường cài đặt Termux cố tình thu hẹp tập tính năng xuống những gì đã được kiểm chứng hoạt động tốt trên Android:

- ✅ Hermes CLI
- ✅ Hỗ trợ Cron
- ✅ Hỗ trợ terminal nền / PTY
- ✅ Gateway Telegram (chạy nền theo kiểu best-effort)
- ✅ Hỗ trợ MCP
- ✅ Nhà cung cấp bộ nhớ Honcho
- ✅ Hỗ trợ ACP

- ❌ Các phần mở rộng `.[all]` (nhiều thứ biên dịch thất bại trên Android)
- ❌ `voice` (bị chặn bởi `faster-whisper → ctranslate2` vốn không có wheel cho Android)
- ❌ Tự động khởi tạo trình duyệt / Playwright
- ❌ Cách ly terminal dựa trên Docker (Docker không chạy trên Android gốc)
- ⚠️  Duy trì chạy nền — Android có thể tạm dừng các job Termux; các lần chạy gateway là best-effort, không phải một dịch vụ được quản lý

### Trình Cài Đặt Một Dòng

Bên trong Termux:

```bash
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
```

Trên Termux, trình cài đặt sẽ:

- Dùng `pkg` cho các gói hệ thống
- Tạo venv bằng `python -m venv`
- Cài đặt `.[termux]` bằng `pip` (dưới một tệp constraints riêng cho Termux)
- Liên kết `hermes` vào `$PREFIX/bin` để nó luôn nằm trên PATH qua các phiên
- Bỏ qua bước khởi tạo trình duyệt / WhatsApp chưa được kiểm thử

### Cài Đặt Thủ Công (Nếu Dòng Lệnh Một Lệnh Thất Bại)

```bash
pkg update && pkg upgrade
pkg install python git libjpeg-turbo libandroid-support rust build-essential
python -m venv ~/hermes-venv
source ~/hermes-venv/bin/activate
git clone https://github.com/NousResearch/hermes-agent.git
cd hermes-agent
python -m pip install -e '.[termux]' -c constraints-termux.txt
```

Thêm venv vào PATH của Termux để `hermes` luôn khả dụng:

```bash
echo 'export PATH="$HOME/hermes-venv/bin:$PATH"' >> ~/.bashrc
```

### Lần Chạy Đầu Tiên

```bash
hermes
```

Đặt một model bằng `hermes model` — OpenRouter, Nous Portal, hoặc bất kỳ endpoint tương thích OpenAI nào đều hoạt động. Để dùng ngoại tuyến, trỏ đến một server model cục bộ trên mạng LAN của bạn (LM Studio, Ollama, vLLM chạy trên một máy desktop) — điện thoại là giao diện của bạn, phần việc nặng nhọc vẫn nằm trên GPU.

### Giữ Nó Hoạt Động Ở Chế Độ Nền

Android tích cực tạm dừng các ứng dụng chạy nền. Hai chiến thuật:

**Termux:Boot + Termux:Wake-Lock** — cài đặt từ F-Droid, thêm một lệnh wake-lock vào khởi động gateway của bạn để Android không đóng băng nó:

```bash
termux-wake-lock
hermes gateway
```

**Đừng dùng Android như một server.** Đối với nhiệm vụ gateway luôn bật, hãy đặt Hermes trên một VPS 5 đô la hoặc một máy Linux tại nhà và trò chuyện với nó từ điện thoại của bạn qua Telegram / iMessage. Termux tuyệt vời như một agent tương tác trên điện thoại của bạn, không phải như một gateway sản xuất.

### Đã Kiểm Thử vs. Chưa Kiểm Thử Trên Android

Nếu bạn muốn một tính năng nằm ngoài gói đã kiểm thử, bạn thường có thể khiến nó hoạt động với thêm công sức — nhưng đó là trách nhiệm của bạn. Báo cáo issue kèm `[termux]` trong tiêu đề nếu bạn gặp phải điều gì đó có thể tái hiện được.

---

## Tiếp Theo Là Gì

- **Đi sâu vào Telegram:** [Phần 4 — Thiết Lập Telegram](./part4-telegram-setup.md)
- **Giao diện cho mọi thứ:** [Phần 12 — Bảng Điều Khiển Web](./part12-web-dashboard.md)
- **Độ tin cậy trên các liên kết di động:** [Phần 11 — Khôi Phục Gateway](./part11-gateway-recovery.md)
