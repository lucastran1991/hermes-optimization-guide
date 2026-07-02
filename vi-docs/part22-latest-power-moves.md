# Phần 22: Những Chiêu Thức Mạnh Mẽ Mới Nhất — Curator, TUI, Plugin, Tệp Ngữ Cảnh

*Nếu bạn đã biết Hermes nhưng bỏ lỡ làn sóng v0.11/v0.12, hãy đọc phần này trước để nắm về Curator, TUI, plugin, và vệ sinh ngữ cảnh (context hygiene). Đối với lớp độ bền + nền tảng của v0.13/v0.14 — Kanban, `/goal`, `/handoff`, Checkpoints v2, cron không cần agent, cài đặt qua PyPI, proxy, và các nền tảng mới — hãy chuyển tiếp đến [Phần 23](./part23-tenacity-stack.md). Những chiêu thức dùng hàng ngày từ v0.15 "Velocity" và v0.16 "Surface" — `/undo`, lựa chọn giao diện mặc định, bộ chọn model fuzzy, và các skill mặc định gọn nhẹ hơn — nằm ở [mục 8](#8-newer-power-moves-v015--v016), còn những điểm nhanh mới nhất của v0.17 "Reach" / v0.18 "Judgment" nằm ở [mục 9](#9-newer-power-moves-v017--v018). Về GUI gốc (native) và câu chuyện chạy cục bộ (local), xem [Phần 24](./part24-desktop-app.md) và [Phần 25](./part25-nvidia-local.md). Về những ý tưởng lớn của v0.18 — Mixture-of-Agents, xác minh (verification), `/learn`, `/journey` — xem [Phần 26](./part26-moa-verification.md).*

---

## 1. Bật Curator Trước Khi Thư Viện Skill Của Bạn Biến Thành Nhiễu

Các skill do agent tạo ra rất có giá trị cho đến khi thư viện bị lấp đầy bởi các bản trùng lặp, các cờ CLI (CLI flags) lỗi thời, và các ghi chú tác vụ dùng một lần. Curator là vòng lặp bảo trì của v0.12 dành cho việc đó.

```bash
hermes curator run --dry-run
hermes curator run
hermes curator enable
```

Sử dụng nó như sau:

- Ghim (pin) các runbook production và các skill mà bạn tự dựa vào.
- Để Curator lưu trữ (archive) các skill do agent tạo mà yếu/trùng lặp.
- Chạy dry-run sau khi nâng cấp hoặc thay đổi lớn về quy trình làm việc.
- Khôi phục các skill đã lưu trữ thay vì tạo lại chúng từ trí nhớ.

Curator nên cắt tỉa (prune) các skill, chứ không quyết định chính sách của dự án. Hãy đặt các quy tắc bền vững của dự án vào các tệp ngữ cảnh (context files).

> **Thay đổi ở v0.17:** vòng hợp nhất (consolidation) do LLM điều khiển của Curator giờ đây là **tùy chọn (opt-in)** — việc curation thông thường (lưu trữ các bản trùng lặp, cắt tỉa skill lỗi thời) tốn 0 token theo mặc định. Hãy bật consolidation một cách rõ ràng khi bạn muốn nó thực sự hợp nhất và viết lại các skill. Kết hợp Curator với `/journey` ([Phần 26](./part26-moa-verification.md#3-learn-and-journey--self-improvement-you-can-see)) để kiểm toán (audit) luôn cả phía bộ nhớ (memory).

---

## 2. Dùng TUI Làm Công Cụ Chính Hàng Ngày

`hermes --tui` giờ đây là giao diện chính dành cho power-user. Nó không chỉ là đầu ra đẹp hơn; nó thay đổi cách bạn điều khiển (steer) các lượt chạy dài.

```bash
hermes --tui
```

Những thói quen đáng để áp dụng:

- Dùng `/steer <constraint>` khi agent đang chạy giữa chừng nhưng bị lệch hướng.
- Dùng `/queue <next task>` cho các việc tiếp theo phụ thuộc lẫn nhau.
- Dùng `/background <prompt>` cho nghiên cứu hoặc giám sát độc lập.
- Dùng `/resume`, sau đó xóa các session cũ khỏi bộ chọn (picker) bằng phím `d`.
- Dùng `/reload` sau khi chỉnh sửa `.env`; tránh khởi động lại session chỉ để nạp lại các key.
- Bật/tắt `/mouse` nếu terminal/ConPTY của bạn chèn các sự kiện chuột ảo (phantom mouse events).

Nếu tab Chat trên dashboard được bật, nó sẽ nhúng cùng một TUI thông qua PTY, vì vậy việc cải thiện quy trình làm việc TUI của bạn cũng cải thiện luôn quy trình làm việc trên trình duyệt.

---

## 3. Dọn Dẹp Các Tệp Ngữ Cảnh (Context Files)

Hermes giờ đây đọc các tệp hướng dẫn agent phổ biến, bao gồm `.hermes.md`, `AGENTS.md`, `CLAUDE.md`, `SOUL.md`, và `.cursorrules`.

Dùng chúng cho các mục đích khác nhau:

| File | Đặt cái này vào đó | Tránh |
|------|----------------|-------|
| `.hermes.md` | Quy trình làm việc repo, lệnh, kỳ vọng phê duyệt (approval) đặc thù cho Hermes | Chính sách công ty chung chung |
| `AGENTS.md` | Hướng dẫn lập trình dùng chung cho nhiều agent | Phong cách/tính cách cá nhân |
| `SOUL.md` | Giọng điệu, ranh giới, sở thích bền vững | Lệnh build và tài liệu API |
| `.cursorrules` | Tương thích với editor/Cursor | Bí mật (secrets) hoặc thông tin xác thực |

Mẫu tốt nhất:

1. Giữ các hướng dẫn ở thư mục gốc ngắn gọn.
2. Chỉ thêm các tệp đặc thù cho thư mục con ở nơi hành vi thay đổi.
3. Lưu bí mật trong `.env` hoặc kho auth của provider, không bao giờ trong các tệp ngữ cảnh.
4. Dùng skill cho các quy trình, memory cho các sự kiện (facts), và các tệp ngữ cảnh cho chính sách.

---

## 4. Dùng Plugin Cho Tích Hợp, Không Phải Cho Script Dùng Một Lần

v0.12 đã biến plugin thành lớp trừu tượng đúng đắn cho tool, hook, slash command, tab dashboard, và các nền tảng gateway.

```bash
hermes plugins list
hermes plugins enable observability/langfuse
hermes plugins enable spotify
```

Các plugin đi kèm đáng để xem qua:

| Plugin | Vì sao nên bật |
|--------|---------------|
| `observability/langfuse` | Trace các lệnh gọi LLM/tool mà không cần viết hook tùy chỉnh |
| `spotify` | Phát nhạc gốc (native), hàng đợi, tìm kiếm, playlist, thiết bị |
| `google_meet` | Tham gia cuộc gọi, phiên âm (transcribe), nói, và tạo bản theo dõi (follow-up) |
| `hermes-achievements` | Thành tích trên dashboard từ lịch sử session |
| image-gen backends | Các tuyến (route) tạo ảnh OpenAI/Codex/xAI bổ sung |

Tư thế bảo mật (security posture):

- Plugin bị tắt theo mặc định; hãy giữ nguyên như vậy.
- Chỉ bật các plugin đi kèm/của người dùng đáng tin cậy.
- Chỉ bật các plugin cục bộ của dự án cho các repo đáng tin cậy.
- Hãy coi hook là thực thi code, không phải "chỉ là cấu hình."

---

## 5. Tách Riêng Model Chính Và Model Phụ Trợ

Dashboard và `hermes model` giờ đây cho phép cấu hình model phụ trợ (auxiliary). Hãy dùng nó.

| Công việc | Lựa chọn mặc định tốt |
|-----|--------------|
| Agent chính | Model coding/reasoning bạn ưa thích |
| Nén (compression) | Model rẻ, nhanh |
| Vision | Một model có khả năng xử lý ảnh thực sự |
| Tìm kiếm session | Model tóm tắt/tìm kiếm rẻ tiền |
| Tạo tiêu đề | Model rẻ nhất mà vẫn đáng tin cậy |
| Curator | Model rẻ với đủ ngữ cảnh (context) để xem xét skill |

Điều này tránh việc tiêu tốn token cao cấp (premium) cho tiêu đề, nén, và các việc dọn dẹp vặt (housekeeping).

---

## 6. Nối Chuỗi (Chain) Các Cron Job Thay Vì Lặp Lại Ngữ Cảnh

Cron không còn chỉ là "chạy prompt này mỗi sáng" nữa. Hãy dùng:

- `workdir` theo từng job cho các job nhận biết dự án (project-aware).
- `enabled_toolsets` theo từng job để giảm chi phí phụ trội (overhead) về tool/ngữ cảnh.
- `context_from` để đưa đầu ra của một job vào job tiếp theo.
- Gửi trực tiếp qua webhook cho các thông báo không cần LLM (zero-LLM).

Mẫu ví dụ:

```yaml
cron:
  jobs:
    collect-build-status:
      schedule: "*/30 * * * *"
      workdir: ~/projects/app
      enabled_toolsets: [terminal]
      prompt: "Run the build status check and summarize failures only."
    notify-build-status:
      schedule: "*/30 * * * *"
      context_from: collect-build-status
      deliver: telegram_private
      prompt: "Notify only if the upstream job found failures."
```

---

## 7. Danh Sách Kiểm Tra Nâng Cấp v0.12 Cho Các Bản Cài Đặt Hiện Có

Trước khi chuyển một thiết lập v0.9/v0.10 cũ sang stack giao diện/curator của v0.12:

```bash
hermes update --check
hermes backup
hermes --version
hermes doctor
```

Sau đó:

1. Mở `hermes dashboard`.
2. Cấu hình model chính + model phụ trợ.
3. Chỉ bật những plugin bạn thực sự cần.
4. Chạy `hermes curator run --dry-run`.
5. Kiểm thử một message gateway, một lệnh gọi tool, một skill, và một cron job.
6. Xem lại [Phần 19](./part19-security-playbook.md) trước khi bật quyền truy cập nền tảng trên diện rộng.
7. Sau đó chạy [Danh sách kiểm tra Foundation v0.14](./part23-tenacity-stack.md#8-upgrade-checklist-from-v013-to-v014).

---

## 8. Những Chiêu Thức Mạnh Mẽ Mới Hơn (v0.15 → v0.16)

Các bản phát hành Velocity và Surface đã bổ sung một số điều nhỏ mà bạn sẽ dùng đến hàng ngày:

### `/undo [N]` — lấy lại các lượt (turn)

Lỡ làm rối, hay gửi nhầm prompt? `/undo` sẽ tua lại lượt cuối cùng; `/undo N` tua lại `N` lượt cuối. Nó cũng **điền sẵn (prefill) tin nhắn cuối cùng của bạn** để bạn có thể chỉnh sửa và gửi lại thay vì phải gõ lại. Hoạt động giống nhau trên CLI, TUI, và các bề mặt (surface) nhắn tin.

```text
/undo        # undo the last turn
/undo 3      # undo the last three turns
```

### Chọn Giao Diện Mặc Định Của Bạn

`hermes chat` có thể mặc định là **CLI** hoặc **TUI** — thiết lập một lần và ghi đè theo từng lần gọi bằng `--cli`:

```bash
hermes config set interface tui   # or: cli
hermes chat --cli                 # one-off override
```

TUI cũng đã hợp nhất bộ chuyển model của nó dưới `/model` và bổ sung một overlay Sessions.

### Bộ Chọn Model Fuzzy Có Mặt Ở Khắp Nơi

Desktop, web, TUI, và CLI đều dùng chung một **bộ chọn model fuzzy**. Các provider có nhiều endpoint được nhóm lại, và danh mục (catalog) **làm mới mỗi giờ**, vì vậy các model mới xuất hiện mà không cần chờ một bản phát hành Hermes. Chỉ cần gõ một phần tên trong `hermes model` và chọn.

### Các Skill Mặc Định Gọn Nhẹ Hơn

v0.16 đã cắt gọn bộ skill tích hợp sẵn (built-in) để agent không phải mang theo phần thừa vô ích (dead weight). Một số skill đã trở thành **plugin gốc (native)** hoặc chuyển sang **MCP** (ví dụ, Spotify giờ là một plugin gốc; Linear là `hermes mcp install linear`), một số khác chuyển thành **tùy chọn (optional)**, và một cổng kiểm tra mức liên quan (relevance gate) mới `environments:` giúp ngăn các skill không liên quan bị nạp. Curator giờ đây cũng có thể cắt tỉa cả các skill **built-in**, chứ không chỉ các skill do agent tạo.

Nếu bạn từng dựa vào một skill mà nay đã biến mất, hãy kiểm tra xem nó có phải giờ là một plugin (`hermes plugins list`) hay một MCP server (`hermes mcp ...`) trước khi tạo lại nó.

### Tìm Kiếm Session Miễn Phí, Tức Thì

`session_search` giờ đây nhanh hơn ~4.500 lần và chạy cục bộ (locally) miễn phí — tìm kiếm lịch sử của riêng bạn không còn tốn token nữa. Kết hợp nó với tính năng tìm-theo-id của desktop (xem [Phần 24](./part24-desktop-app.md)) để quay lại công việc cũ nhanh chóng.

### Mở Rộng Công Việc Bền Vững Thành Một Swarm

Khi một board vượt quá khả năng của một worker đơn lẻ, `hermes kanban swarm` biến Kanban thành một nền tảng đa agent (multi-agent) (root, các worker song song, verifier/synthesizer có cổng kiểm soát, blackboard dùng chung, ghi đè model theo từng task). Chi tiết đầy đủ trong [Phần 23](./part23-tenacity-stack.md).

> **Lưu ý bảo mật:** v0.15 đã bổ sung **cơ chế phòng thủ Brainworm/promptware** chống lại các chỉ thị độc hại ẩn trong đầu ra của tool. Hãy giữ chúng luôn bật, và đọc [Phần 19](./part19-security-playbook.md) trước khi kết nối các đầu vào không đáng tin cậy.

---

## 9. Những Chiêu Thức Mạnh Mẽ Mới Hơn (v0.17 → v0.18)

Các bản phát hành Reach và Judgment đã bổ sung thêm một loạt công cụ dùng hàng ngày. Các tính năng nổi bật (MoA, xác minh (verification), `/learn`, `/journey`, background fan-out) có riêng một phần — [Phần 26](./part26-moa-verification.md) — nhưng những điều nhỏ này đáng để trở thành phản xạ (muscle memory):

### `/prompt` — soạn các prompt dài trong một editor thực thụ

Mở `$EDITOR` để bạn có thể viết một prompt nhiều dòng, định dạng markdown, và đưa nó vào hàng đợi như tin nhắn tiếp theo của bạn. Đây là lệnh QoL (quality-of-life) tốt nhất của v0.18 cho bất kỳ ai viết các bản mô tả tác vụ (task brief) chi tiết.

### `/reasoning full` — bỏ giới hạn suy luận (thinking) cho một session

Khi một session gặp phải điều gì đó thực sự khó, `/reasoning full` sẽ loại bỏ giới hạn ngân sách suy luận (thinking budget) cho session đó. Rẻ hơn so với việc chuyển sang một model lớn hơn chỉ vì một bước nan giải.

### `/timestamps` và `/history` có dấu thời gian

Bật/tắt dấu thời gian ngay trong các lượt (turn) và xem khi nào mọi việc thực sự xảy ra trong `/history` — điều cần thiết khi kiểm toán (audit) các lượt chạy tự động (autonomous) dài.

### Nén tại chỗ (in-place compaction) (không còn hỏng liên kết `@session` nữa)

Nén ngữ cảnh (context compression) giờ đây ghi lại session **dưới cùng một session id** theo mặc định, thay vì xoay vòng sang một id mới. Các session chạy dài giữ nguyên danh tính của chúng, vì vậy các tham chiếu `@session`, tích hợp, và liên kết desktop không còn âm thầm bị hỏng nữa.

### `image_generate` đã học được image-to-image

Truyền vào một ảnh đầu vào và một prompt biến đổi (transform) — thay đổi phong cách (restyle) ảnh chụp màn hình, áp logo, lặp lại (iterate) trên các bản nháp — trên mọi provider ảnh, từ bất kỳ bề mặt (surface) nào.

### Các thao tác hàng loạt (batch) của `memory`

Tool `memory` áp dụng nhiều thao tác thêm/cập nhật/xóa một cách nguyên tử (atomically) trong một lệnh gọi. Việc dọn dẹp hàng loạt (bulk cleanup) (hoặc một phiên cắt tỉa `/journey`) chỉ còn là một lượt round-trip thay vì mười lượt.

### Automation Blueprints Thay Vì Cron Thô

Các mẫu (template) automation có tham số hóa (parameterized), hiển thị dưới dạng một form dashboard, một slash command, hoặc một cuộc hội thoại thông thường ("thiết lập bản tóm tắt hàng ngày của tôi lúc 8 giờ sáng"). Hãy dùng chúng cho bất cứ điều gì mà trước đây bạn từng tự viết tay YAML cron; giữ cron thô cho các watchdog tất định (deterministic), không cần agent trong [Phần 23](./part23-tenacity-stack.md#5-use-no_agent-cron-for-watchdogs).

### Thiết Lập Blank Slate

Một chế độ onboarding tối giản (minimal-agent): bắt đầu từ con số không và chọn tham gia (opt in) từng tool một. Đây là lựa chọn mặc định đúng đắn cho các máy nhạy cảm về tuân thủ (compliance) hoặc bị khóa chặt (locked-down).

---

## Những Điều Nên Bỏ Qua

Một số lời khuyên cũ không còn đáng để tối ưu xung quanh nữa:

- Đừng xây dựng thiết lập Gemini của bạn dựa trên các provider OAuth Gemini-CLI cũ — chúng đã bị **loại bỏ trong v0.18**. Hãy dùng một Gemini API key, hoặc provider Vertex AI cho các đơn vị dùng GCP ([Phần 9](./part9-custom-models.md)).
- Đừng fork dashboard chỉ để có một tab tùy chỉnh; hãy viết một plugin dashboard.
- Đừng giữ một `SOUL.md` khổng lồ đầy quy trình; hãy dùng skill và Curator.
- Đừng dùng một model mặc định đắt tiền cho mọi tác vụ phụ trợ.
- Đừng phơi bày (expose) dashboard công khai mà không có một reverse proxy và lớp auth thực sự.
