# Phần 19: Cẩm nang Bảo mật — Khóa chặt một Agent đọc văn bản không đáng tin cậy

*Ngày 15 tháng 4 năm 2026, bài viết [Comment and Control](https://oddguan.com/blog/comment-and-control-prompt-injection-credential-theft-claude-code-gemini-cli-github-copilot/) được đăng — một dạng prompt injection xuyên nhà cung cấp đánh cắp GitHub Actions secrets từ Claude Code, Gemini CLI, và Copilot Agent thông qua tiêu đề PR. Bot Hermes của bạn đọc tin nhắn từ Telegram, Discord, email, webhook, và SMS — mỗi kênh đều là một vector injection. Phần này là tư thế phòng thủ ngăn agent của bạn trở thành kênh command-and-control của kẻ khác.*

> **Ghi chú về schema (2026-05-31):** Các phiên bản trước của phần này ghi lại một khối cấu hình `security:` với các khóa `provenance`, `approval.require_approval` regex, `secrets.scope`, và `network.egress_allowlist`. **Không cái nào trong số đó tồn tại trong Hermes Agent.** Bản sửa đổi này được viết lại dựa trên schema thực tế — [`approvals:`](https://hermes-agent.nousresearch.com/docs/user-guide/security) ở cấp cao nhất, một bộ phát hiện lệnh nguy hiểm gốc, `command_allowlist:`, danh sách cho phép người dùng trong `.env`, và cách ly ở cấp hệ điều hành. Xem [hướng dẫn Bảo mật chính thức](https://hermes-agent.nousresearch.com/docs/user-guide/security) và [mô hình tin cậy SECURITY.md](https://github.com/NousResearch/hermes-agent/blob/main/SECURITY.md).

---

## Mô hình mối đe dọa

Hermes có mức độ phơi nhiễm đặc biệt cao vì nó nhận đầu vào từ **nhiều** bề mặt và có **nhiều** khả năng:

| Bề mặt | Kẻ tấn công kiểm soát | Rủi ro |
|---------|-------------------|------|
| Telegram DM | Nội dung tin nhắn, tên tệp, chú thích ảnh | Injection → gọi tool |
| Kênh Discord | Văn bản embed, payload webhook, tên người dùng | Injection → gọi tool |
| Hộp thư email | Header, nội dung, tên tệp đính kèm | Đa giai đoạn (HTML + liên kết) |
| SMS / Twilio | Nội dung tin nhắn + payload webhook | Injection → gọi tool |
| GitHub MCP | Tiêu đề PR, nội dung issue, bình luận | Mẫu hình Comment-and-Control |
| Nội dung được scrape từ web | HTML trang mà agent đọc | Injection kiểu "đọc rồi hành động" |
| Bản ghi thoại (voice transcript) | Bản chép STT | Tấn công kiểu "nói câu thần chú" |
| Gói MCP/plugin | Schema tool, stdout, hành vi hook | Prompt injection chuỗi cung ứng / đốt token |
| Plugin dashboard | UI trình duyệt + endpoint backend | Lộ secret/cấu hình cục bộ |

Mục tiêu không phải là loại bỏ những kênh này — Hermes *tồn tại để* đọc chúng. Mục tiêu là đảm bảo văn bản không đáng tin cậy không thể vượt qua ranh giới tin cậy để chạm tới secrets, thao tác ghi, hoặc shell.

---

## Ranh giới thực sự duy nhất: Cách ly cấp hệ điều hành

Trước khi đi vào các nút cấu hình, hãy khắc cốt ghi tâm câu quan trọng nhất trong [chính sách bảo mật](https://github.com/NousResearch/hermes-agent/blob/main/SECURITY.md) của Hermes:

> **Ranh giới bảo mật duy nhất chống lại một LLM đối kháng là hệ điều hành.** Không có gì bên trong tiến trình agent tạo thành sự ngăn chặn — không phải cổng phê duyệt, không phải việc che giấu đầu ra, không phải bất kỳ bộ quét mẫu nào, không phải bất kỳ danh sách cho phép tool nào.

Mỗi biện pháp kiểm soát trong tiến trình bên dưới (lời nhắc phê duyệt, che giấu secret, quét skill) đều là một **cơ chế heuristic hoạt động trên một chuỗi bị kẻ tấn công thao túng**. Chúng bắt được các lỗi ở chế độ hợp tác và các hành vi rò rỉ dữ liệu ngẫu nhiên. Chúng **không** ngăn chặn được một mô hình đã bị injection biến thành thù địch thành công.

Hermes hỗ trợ hai tư thế cách ly cấp hệ điều hành — hãy lựa chọn một cách có chủ đích:

- **Cách ly qua terminal backend.** Một `terminal.backend` không mặc định (Docker, Singularity, Modal, Daytona, SSH) chạy shell do LLM phát ra *và* các thao tác file-tool bên trong một container/máy chủ từ xa. Giới hạn mọi thứ agent làm *thông qua shell*. **Không** giới hạn tiến trình Python của chính agent (tool thực thi mã, các tiến trình con MCP, plugin, hook, skill).
- **Bao bọc toàn bộ tiến trình.** Chạy toàn bộ cây tiến trình của agent trong một sandbox sao cho *mọi* đường dẫn — shell, thực thi mã, MCP, file tool, plugin, hook — đều tuân theo một chính sách filesystem/network/process duy nhất. Hermes hỗ trợ điều này thông qua thiết lập Docker/Compose riêng, hoặc thông qua [NVIDIA OpenShell](https://github.com/NVIDIA/OpenShell) để có chính sách filesystem khai báo + **egress mạng lớp L7** + syscall + định tuyến inference.

Nếu agent của bạn tiếp nhận nội dung từ các bề mặt bạn không kiểm soát (web mở, email đến, kênh đa người dùng, máy chủ MCP không đáng tin cậy), **bao bọc toàn bộ tiến trình là tư thế được hỗ trợ.** Chạy backend cục bộ mặc định với đầu vào không đáng tin cậy là vận hành ngoài mô hình bảo mật được hỗ trợ của Hermes. Các lớp bên dưới củng cố một triển khai thực tế; chúng không phải là sự thay thế cho ranh giới đó.

---

## Lớp 1: Ủy quyền người dùng — Ai được phép nói chuyện với Agent

Cổng đầu tiên là *ai thậm chí được phép tiếp cận agent*. Trên mọi gateway nhắn tin, Hermes ở chế độ **mặc định từ chối** (default-deny): nếu không có danh sách cho phép nào được cấu hình và `GATEWAY_ALLOW_ALL_USERS` không được thiết lập, tất cả người dùng đều bị từ chối.

Thiết lập danh sách cho phép theo từng nền tảng trong `~/.hermes/.env` (các ID phân tách bằng dấu phẩy):

```bash
# ~/.hermes/.env
TELEGRAM_ALLOWED_USERS=123456789,987654321
DISCORD_ALLOWED_USERS=111222333444555666
WHATSAPP_ALLOWED_USERS=15551234567
SLACK_ALLOWED_USERS=U01ABC123
EMAIL_ALLOWED_USERS=you@example.com

# Danh sách cho phép xuyên nền tảng (được kiểm tra cho mọi nền tảng)
GATEWAY_ALLOWED_USERS=123456789
```

Việc ủy quyền được kiểm tra theo thứ tự: cờ allow-all riêng của từng nền tảng → danh sách đã duyệt qua ghép cặp DM (DM-pairing) → danh sách cho phép của nền tảng → danh sách cho phép toàn cục → allow-all toàn cục → **mặc định từ chối**. Tránh dùng `GATEWAY_ALLOW_ALL_USERS=true` trên bất kỳ thứ gì công khai — nó phơi bày agent (và mọi tool mà nó có) cho bất kỳ ai tìm thấy bot.

Đối với những người mà bạn không biết trước ID nền tảng của họ, hãy dùng **ghép cặp DM (DM pairing)**: người dùng gửi một mã dùng một lần được tạo ra ngoài băng thông (out-of-band) trước khi họ có thể tương tác. Trạng thái ghép cặp được duy trì qua các lần khởi động lại gateway.

Một số thiết lập củng cố theo từng nền tảng đáng cân nhắc:

```yaml
# ~/.hermes/config.yaml
discord:
  require_mention: true          # Bot chỉ phản hồi khi được @mention trong kênh (mặc định)
  free_response_channels: ""     # ID kênh được miễn yêu cầu mention
group_sessions_per_user: true    # Mỗi thành viên trong nhóm có một phiên (session) riêng biệt
```

---

## Lớp 2: Phê duyệt lệnh nguy hiểm

Trước khi thực thi bất kỳ lệnh shell nào, Hermes kiểm tra nó dựa trên một **danh sách các mẫu hình nguy hiểm được tuyển chọn, tích hợp sẵn** (`tools/approval.py`). Khi khớp mẫu, việc thực thi tạm dừng để chờ con người phê duyệt. Các mẫu hình này là một phần của source code — bạn **không** tự định nghĩa regex phê duyệt trong cấu hình của mình.

Cấu hình chính sách bằng khối `approvals:` ở cấp cao nhất:

```yaml
# ~/.hermes/config.yaml
approvals:
  mode: manual                    # manual | smart | off
  timeout: 60                     # số giây chờ trước khi fail-closed từ chối
  cron_mode: deny                 # deny | approve — hành vi khi một cron job gặp lệnh nguy hiểm
  mcp_reload_confirm: true        # /reload-mcp xác nhận trước khi vô hiệu hóa cache tool MCP
  destructive_slash_confirm: true # /clear, /new, /reset, /undo xác nhận trước khi hủy trạng thái
```

| Chế độ | Hành vi |
|------|----------|
| **manual** (mặc định) | Luôn nhắc khi có lệnh nguy hiểm |
| **smart** | Một LLM phụ trợ đánh giá rủi ro trước — tự động phê duyệt các trường hợp rõ ràng rủi ro thấp, tự động từ chối các trường hợp rõ ràng nguy hiểm, đẩy các trường hợp mơ hồ ở giữa lên lời nhắc thủ công |
| **off** | Bỏ qua toàn bộ lời nhắc phê duyệt (tương đương `--yolo`) |

Khi một lời nhắc xuất hiện trong CLI, bạn có bốn lựa chọn — **once / session / always / deny** (deny là mặc định nếu bạn hết thời gian chờ). Trên các nền tảng nhắn tin, lời nhắc được gửi dưới dạng tin nhắn (nút bấm inline trên Telegram/Discord/Slack); trả lời *yes/approve* hoặc *no/deny*.

### `command_allowlist` — danh sách "luôn phê duyệt"

Chọn **always** sẽ ghi một mô tả mẫu hình dễ đọc vào `command_allowlist:` ở cấp cao nhất:

```yaml
command_allowlist:
  - recursive delete                       # khớp với danh mục phát hiện "rm -r"
  - shell command via -c/-lc flag
```

Các mục là các chuỗi mô tả khớp với các danh mục mẫu hình của bộ phát hiện — chúng **không phải** là regex thô. Hãy thận trọng: cho phép `recursive delete` nghĩa là *mọi* lệnh `rm -r`, kể cả các đường dẫn bạn không có ý định, sẽ chạy mà không cần lời nhắc. Chỉnh sửa `~/.hermes/config.yaml` (hoặc `hermes config edit`) để xóa các mục.

### Chế độ YOLO — nó bỏ qua và không bỏ qua những gì

`hermes --yolo`, công tắc `/yolo`, hoặc `HERMES_YOLO_MODE=1` bỏ qua **tất cả** lời nhắc phê duyệt cho phiên đó. Chỉ dùng cho tự động hóa đã được kiểm chứng trong môi trường dùng-một-lần-rồi-bỏ.

### Danh sách chặn cứng (sàn luôn bật)

Một tập hợp nhỏ các lệnh thảm khốc, không thể khôi phục bị từ chối **bất kể** `--yolo`, `approvals.mode: off`, chế độ cron `approve`, hoặc "always" — không có cờ ghi đè nào (`tools/approval.py::UNRECOVERABLE_BLOCKLIST`):

- `rm -rf /` và các biến thể rõ ràng (bao gồm `--no-preserve-root /`)
- Bom fork bash `:(){ :|:& };:`
- `mkfs.*` trên một thiết bị root đã mount
- `dd if=/dev/zero of=/dev/sd*`
- Pipe URL không đáng tin cậy tới `sh` ở cấp cao nhất của rootfs

Danh sách chặn kích hoạt *trước khi* lớp phê duyệt nhìn thấy lệnh. Nó là dây an toàn, không phải toàn bộ chiếc xe.

### Hai lưu ý quan trọng

- **Các backend container bỏ qua hoàn toàn bước phê duyệt.** Khi `terminal.backend` là `docker`, `singularity`, `modal`, hoặc `daytona`, các kiểm tra lệnh nguy hiểm bị bỏ qua vì container *chính là* ranh giới (Lớp "cách ly hệ điều hành" ở trên). Đó là sự đánh đổi có chủ đích — thực thi không giới hạn bên trong một hộp dùng-rồi-bỏ.
- **Các phê duyệt được định tuyến về kênh mà tin nhắn xuất phát.** Không có cấu hình "kênh phê duyệt" riêng biệt. Biện pháp phòng thủ chống lại "lừa bot tự phê duyệt cho chính nó" là **danh sách cho phép** của bạn (Lớp 1): giữ danh sách cho phép của bot công khai thật chặt, và điều khiển các hành động đặc quyền từ một bot riêng biệt, chỉ chủ sở hữu mới truy cập được, hoặc từ DM mà người dùng không đáng tin cậy không thể tiếp cận.

### Tùy chọn: quét trước khi thực thi bằng tirith

Hermes có thể xếp lớp [tirith](https://hermes-agent.nousresearch.com/docs/user-guide/security) lên trên bộ phát hiện gốc để bắt các URL homograph, pipe-to-shell, injection terminal, và thao túng biến môi trường:

```yaml
security:
  tirith_enabled: true
  tirith_path: tirith
  tirith_timeout: 5
  tirith_fail_open: true   # cho phép lệnh chạy nếu tirith không khả dụng
```

Một cảnh báo `warn` từ tirith được gộp vào cùng lời nhắc phê duyệt; một `block` từ tirith từ chối lệnh hoàn toàn.

---

## Lớp 3: Secrets và giới hạn phạm vi credential

Nhóm tấn công Comment-and-Control thành công bằng cách đánh cắp credential. Các biện pháp phòng thủ của Hermes ở đây làm giảm rò rỉ *ngẫu nhiên* — hãy kết hợp chúng với cách ly để có sự ngăn chặn thực sự.

**Vệ sinh trên đĩa (tự động):**

- API key chỉ tồn tại trong `~/.hermes/.env`, được tạo với quyền `0600`; thư mục `~/.hermes/` có quyền `0700`.
- Key **không bao giờ** được ghi vào `config.yaml`, commit, hoặc trả về trong đầu ra của tool.

**Che giấu đầu ra / log:**

```yaml
# ~/.hermes/config.yaml
security:
  redact_secrets: true   # mặc định bật — che giấu các mẫu hình giống secret khỏi đầu ra tool và log
```

Hãy để nguyên nó bật. `~/.hermes/logs/` được che giấu theo mặc định; chỉ tắt `redact_secrets: false` để gỡ lỗi một vấn đề xác thực, và coi các log kết quả là mang thông tin bí mật.

**Giới hạn phạm vi credential (tự động):** Hermes lọc môi trường mà nó trao cho các tiến trình con trong tiến trình có mức tin cậy thấp hơn — tiến trình con shell, tiến trình con MCP, và tiến trình con thực thi mã. Provider API key và token gateway **bị loại bỏ theo mặc định**; chỉ những biến mà một operator hoặc một skill được nạp khai báo tường minh mới được truyền qua. Bạn không cấu hình việc giới hạn secret theo từng tool — đó là hành vi mặc định.

> **Lưu ý trung thực (từ SECURITY.md §2.3):** điều này làm giảm rò rỉ dữ liệu ngẫu nhiên; nó *không phải* là sự ngăn chặn. Bất cứ thứ gì chạy *bên trong* tiến trình agent — skill, plugin, trình xử lý hook — đều có thể đọc bất cứ thứ gì agent có thể đọc, bao gồm cả credential trong bộ nhớ. Biện pháp giảm thiểu cho một thành phần trong-tiến-trình mang tính thù địch là việc operator xem xét trước khi cài đặt (Lớp 5), không phải việc lọc biến môi trường.

---

## Lớp 4: Các backend cách ly — Nơi kiểm soát egress thực sự nằm ở đó

Không có `security.network.egress_allowlist` trong Hermes. Kiểm soát egress mạng, giới hạn filesystem, và việc "agent không thể đọc `.env` của chính nó" đều đến từ **terminal backend** hoặc **sandbox toàn tiến trình** — không phải một khóa cấu hình trong khối `security:`.

Chọn một terminal backend không mặc định để shell và các thao tác file-tool do LLM phát ra chạy ngoài host của bạn:

```yaml
# ~/.hermes/config.yaml
terminal:
  backend: docker                         # local | docker | singularity | modal | daytona | ssh
  docker_image: nikolaik/python-nodejs:python3.11-nodejs20
  cwd: /workspace
  docker_mount_cwd_to_workspace: false    # mặc định tắt — chọn tham gia để mount cwd của host
  container_persistent: true              # duy trì filesystem qua các phiên; false = reset mỗi phiên
```

Những gì một backend container mang lại cho bạn:

- Agent **không thể đọc `~/.hermes/.env`** (key ở lại trên host)
- Agent **không thể sửa đổi mã nguồn của chính nó**
- Các lệnh phá hoại bị giới hạn trong filesystem của container

Các backend SSH và serverless (Modal/Daytona) mang lại cùng hình thái đó — mã agent và key ở lại phía local/host, chỉ có lệnh mới được chuyển tiếp:

```yaml
terminal:
  backend: ssh
  ssh_host: my-server.example.com
  ssh_user: agent
  ssh_port: 22
  ssh_key: ~/.ssh/id_rsa
```

Để có **danh sách cho phép egress thực sự** (chặn các dải IP riêng tư, chặn IP metadata `169.254.169.254`, giới hạn các domain đi ra), hãy bao bọc *toàn bộ tiến trình* bằng [NVIDIA OpenShell](https://github.com/NVIDIA/OpenShell), thứ thực thi chính sách mạng L7 có thể tải lại nóng (hot-reloadable) trên mọi đường dẫn mã — bao gồm cả các tiến trình con MCP và tiến trình con thực thi mã mà một backend chỉ-terminal để lộ ra. Đối với một thiết lập home-lab / [Home Assistant](./part15-new-platforms.md#home-assistant), một danh sách cho phép egress OpenShell tường minh tốt hơn nhiều so với việc hy vọng một khóa cấu hình chặn SSRF (nó không tồn tại).

---

## Lớp 5: Sự tin cậy với MCP và Plugin

Các máy chủ MCP và plugin là mã của bên thứ ba mà bạn cấp quyền truy cập tool. Hermes **không có** các mức `trust:` theo từng máy chủ, `allow_sampling`, hoặc khóa cấu hình `max_concurrent_calls`. Các biện pháp kiểm soát thực sự là lọc credential, lọc tool, và **việc operator xem xét trước khi cài đặt**.

Cấu hình máy chủ bằng [schema MCP](https://hermes-agent.nousresearch.com/docs/reference/mcp-config-reference) đã được tài liệu hóa và dùng `tools.include` / `tools.exclude` để chỉ phơi bày những tool bạn đã kiểm tra:

```yaml
# ~/.hermes/config.yaml
mcp_servers:
  github:
    command: npx
    args: ["-y", "@modelcontextprotocol/server-github"]
    env:
      GITHUB_PERSONAL_ACCESS_TOKEN: ${GITHUB_RO_TOKEN}   # PAT chỉ đọc, có phạm vi giới hạn
    enabled: true
    timeout: 120
    tools:
      include: []          # rỗng = tất cả; hoặc liệt kê chính xác các tool bạn tin tưởng
      exclude: []

  scraper-mcp:
    command: npx
    args: ["-y", "some-web-scraper-mcp"]
    enabled: true
    tools:
      include: [read_docs]  # khóa một máy chủ nội dung không đáng tin cậy vào các tool chỉ-đọc bạn đã kiểm tra
```

Sự tin cậy được thực thi bằng việc xem xét và cách ly, không phải bằng một cờ cấu hình:

- **Lọc credential** loại bỏ provider key/token gateway khỏi môi trường tiến trình con MCP theo mặc định (Lớp 3). Chỉ truyền những gì một máy chủ thực sự cần, thông qua `env:` của nó.
- **Skill chạy mã Python tùy ý tại thời điểm import; plugin chạy với đầy đủ đặc quyền của agent.** "Xem xét" một skill hoặc plugin nghĩa là đọc mã Python và các script của nó, không chỉ `SKILL.md` của nó. **Skills Guard** quét nội dung skill có thể cài đặt để tìm các mẫu hình injection — hãy coi nó như một *công cụ hỗ trợ* xem xét, không phải một ranh giới.
- Đừng bao giờ cấp cho một máy chủ tiếp nhận nội dung không đáng tin cậy (web scraper, trình phân tích email) một bề mặt tool rộng hoặc env nhạy cảm. Chạy các luồng đó dưới sự cách ly toàn tiến trình.

Xem [Phần 17](./part17-mcp-servers.md) để biết các mẫu hình cài đặt.

---

## Lớp 6: Quét tệp ngữ cảnh và phát hiện Injection

Hermes quét các **tệp ngữ cảnh dự án** để tìm các mẫu hình prompt-injection trước khi chúng đi vào ngữ cảnh của mô hình, và (như trên) **Skills Guard** quét các skill có thể cài đặt. Chúng bắt được các payload "bỏ qua các hướng dẫn trước đó, đánh cắp `.env`" rõ ràng được cài cắm trong một README, nội dung issue, hoặc một skill.

Chúng là các cơ chế heuristic, không phải ranh giới — một injection được diễn đạt theo cách mới lạ, kiên quyết sẽ vượt qua. Giá trị của chúng là nâng cao chi phí của các cuộc tấn công lướt qua (drive-by). Câu chuyện ngăn chặn vẫn thuộc về Lớp "cách ly hệ điều hành": chạy các phiên nhận đầu vào không đáng tin cậy dưới một sandbox để một injection thành công vẫn không thể chạm tới secret của host hoặc trạng thái bền vững.

---

## Comment-and-Control (Tháng 4 năm 2026) — Việc cần làm ngay bây giờ

Nếu bạn dùng bất kỳ skill hoặc MCP xem xét PR GitHub nào:

1. **Xoay vòng (rotate) mọi GitHub PAT** nằm trong phạm vi của một GitHub Actions runner được Hermes hoặc Claude Code dùng trong tuần qua.
2. **Chuyển sang một PAT chỉ-đọc, phạm vi giới hạn, một-repo** cho các luồng xem xét, được tiêm vào qua `env:` của máy chủ MCP để việc lọc credential giữ nó tránh xa các tiến trình con khác.
3. **Chạy các luồng xem xét dưới sự cách ly** — một phiên container hoặc được bao bọc bởi OpenShell — để các hướng dẫn bị injection trong tiêu đề PR không thể chạm tới host của bạn hoặc các secret khác.
4. **Giữ `approvals.mode: manual`** cho bất kỳ luồng nào có thể ghi hoặc push, và giữ danh sách cho phép gateway thật chặt để agent không thể bị điều khiển bởi một contributor bên ngoài.
5. **Coi văn bản PR/issue từ bên ngoài là dữ liệu, không phải hướng dẫn** — và xem xét mọi skill/plugin trước khi cài đặt (nó thực thi Python).

Bài viết của Aonan Guan có chuỗi khai thác đầy đủ. Hãy vá lỗi, đừng chỉ đọc.

---

## An toàn của gói chẩn đoán

Log trong `~/.hermes/logs/` đi qua bộ che giấu secret khi `security.redact_secrets` bật (mặc định). Trước khi chia sẻ *bất kỳ* đầu ra gỡ lỗi hoặc gói log nào với người khác:

1. Xem xét nó trước — việc che giấu dựa trên mẫu hình và không đầy đủ.
2. Không bao giờ chia sẻ đầu ra từ một phiên đã chạm vào secret production qua một liên kết công khai.
3. Giữ `redact_secrets: true`; nếu bạn đã tắt nó để truy tìm một lỗi xác thực, hãy tẩy xóa thủ công trước khi chia sẻ.

Xem [Phần 16](./part16-backup-debug.md) để biết các quy trình sao lưu và gỡ lỗi.

---

## Vệ sinh bảo mật định kỳ

Đặt lịch cron cho các cuộc kiểm tra (các skill này đi kèm trong hub `skills/security/` của tài liệu hướng dẫn này). Nhớ rằng `approvals.cron_mode: deny` nghĩa là một cron job gặp phải lệnh nguy hiểm sẽ bị chặn không cần tương tác (headlessly) — giữ các skill kiểm tra chỉ-đọc để chúng không kích hoạt nó:

```yaml
# ~/.hermes/cron.yaml
- name: weekly-mcp-audit
  schedule: "0 9 * * 1"              # Hàng tuần vào thứ Hai
  task: |
    /audit-mcp
    List every MCP, its env, its tools include/exclude, and last update from npm/github.
    Flag any server with broad tool access that ingests untrusted content.

- name: monthly-rotate-secrets
  schedule: "0 4 1 * *"
  task: /rotate-secrets all

- name: weekly-approval-bypass-review
  schedule: "0 10 * * 1"
  task: /audit-approval-bypass         # đánh dấu các bề mặt YOLO/off/cron-approve và container-bypass
```

Cài đặt bằng `hermes skills install security/audit-mcp` và `security/audit-approval-bypass`.

---

## Bước tiếp theo

- [Phần 17: Máy chủ MCP](./part17-mcp-servers.md) — cấu hình máy chủ, lọc tool, và các mẫu hình cài đặt
- [Phần 16: Sao lưu & Gỡ lỗi](./part16-backup-debug.md) — các quy trình sao lưu và chẩn đoán
- [Phần 20: Khả năng quan sát & Chi phí](./part20-observability.md) — thiết lập cảnh báo về mức sử dụng token đáng ngờ
- [Phần 21: Sandbox từ xa](./part21-remote-sandboxes.md) — cách ly vật lý như lớp cuối cùng
