# Part 24: Ứng dụng Desktop Hermes — Một GUI thực sự trên cùng một Agent

<p align="center">
  <img src="./assets/desktop-app.png" alt="Hermes Desktop — ứng dụng gốc (native) cho macOS, Windows và Linux dành cho Hermes Agent" width="880">
</p>

*Phiên bản v0.16.0 "Surface Release" đã ra mắt **Hermes Desktop**: một ứng dụng gốc cho macOS/Windows/Linux chạy chính xác cùng một agent như CLI, TUI và gateway. Cùng config, cùng keys, cùng sessions, cùng skills, cùng memory — đây là "một bề mặt khác trên cùng một agent, không phải một bản fork." Hai phiên bản sau đó, nó đã phát triển thành một công cụ dùng hàng ngày thực thụ: v0.17 "Reach" bổ sung subagent watch-windows, thông báo gốc của hệ điều hành, chủ đề (theme) từ marketplace, và một terminal pane thực sự; v0.18 "Judgment" biến nó thành một buồng lái lập trình (coding cockpit) với **Projects** hạng nhất, một **multi-terminal panel**, và **memory graph**. Nếu bạn đã tránh Hermes vì không muốn sống trong terminal, đây chính là lối vào dành cho bạn.*

---

## 1. Cài đặt và Khởi chạy

Nếu Hermes đã được cài đặt, ứng dụng chỉ cách bạn một lệnh:

```bash
hermes desktop
```

Lần chạy đầu tiên sẽ tải xuống hoặc build gói desktop (ví dụ: `Hermes.app` trên macOS) và khởi chạy nó. Để build ứng dụng desktop như một phần của quá trình cài đặt mới, hãy truyền flag cài đặt:

```bash
# macOS / Linux
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --include-desktop
```

Trên **Windows**, trình cài đặt gốc đi kèm một bootstrap đã được ký (signed) có thể bao gồm ứng dụng desktop:

```powershell
iex (irm https://hermes-agent.nousresearch.com/install.ps1)
```

Sau khi cài đặt, nó hoạt động như bất kỳ chương trình desktop nào khác — ghim nó vào dock/taskbar và khởi chạy nó mà không cần terminal.

> **Cùng một bộ não, diện mạo mới.** Ứng dụng desktop giao tiếp với cùng một lõi agent như mọi thứ khác. Một session bạn bắt đầu trong ứng dụng sẽ xuất hiện trong `hermes sessions`, và một skill mà agent viết từ Telegram cũng có sẵn trong ứng dụng. Không có gì bị cô lập (siloed).

---

## 2. Bề mặt Chat (Chat Surface)

Cửa sổ chính là một chat streaming với **hoạt động công cụ trực tiếp (live tool activity)** — bạn xem các lệnh gọi tool chạy trực tiếp (inline) thay vì nhìn chằm chằm vào một spinner. Điểm nổi bật:

- **Lịch sử dùng chung trên các bề mặt (surfaces)** — desktop, CLI, TUI và messaging đều đọc/ghi cùng một sessions.
- **Kéo thả file (Drag-and-drop)** — thả một file vào ô soạn thảo (composer) để đính kèm nó.
- **Dán ảnh từ clipboard** — dán một ảnh chụp màn hình trực tiếp vào.
- **Thanh xem trước bên phải (right-hand preview rail)** — đầu ra đã render (files, hình ảnh, kết quả) mở bên cạnh chat thay vì bị cuộn mất.
- **Lịch sử composer và chỉnh sửa hàng đợi (queue editing)** — nhấn lên/xuống trong ô soạn thảo để gọi lại các tin nhắn trước đó và chỉnh sửa một tin nhắn đang chờ trong hàng đợi trước khi nó được gửi.
- **Bản nháp theo từng luồng (per-thread drafts)** (v0.17) — các tin nhắn viết dở được lưu giữ riêng cho từng cuộc hội thoại; chuyển đổi luồng (thread) mà không mất nội dung đang gõ.
- **Diff kiểu PR trong chat** (v0.18) — các thay đổi code được render dưới dạng diff có thể review trực tiếp (inline).
- **Thanh timeline hội thoại (conversation timeline rail)** (v0.18) — nhảy quanh các session dài từ một timeline có thể quét nhanh thay vì phải cuộn.
- **Cửa sổ theo dõi subagent (subagent watch-windows)** (v0.17) — mở một cửa sổ trực tiếp trên bất kỳ subagent nào đang chạy và xem nó làm việc thay vì chờ một bản tóm tắt.
- **Thông báo gốc của hệ điều hành (native OS notifications)** (v0.17) — nhận được thông báo khi một lần chạy dài kết thúc hoặc agent cần một sự phê duyệt (approval), ngay cả khi ứng dụng đang chạy nền.

---

## 3. Command Palette và Bàn phím

- **Command palette:** `Cmd+K` (macOS) / `Ctrl+K` (Windows/Linux) mở một command palette dạng fuzzy cho gần như mọi thứ — chuyển session, đổi model, mở settings, chạy lệnh.
- **Phím tắt có thể gán lại (rebindable shortcuts)** (v0.17): remap các phím theo ý thích.
- **Theme từ VS Code Marketplace** (v0.17): cài đặt bất kỳ theme VS Code nào và toàn bộ ứng dụng sẽ áp dụng nó. Thẩm mỹ terminal của bạn có thể theo bạn.
- **Zoom tùy chỉnh:** phóng to hoặc thu nhỏ toàn bộ UI.
- **Bộ chuyển ngôn ngữ (language switcher):** UI desktop được quốc tế hóa đầy đủ. v0.16 bổ sung **tiếng Trung giản thể (简体中文)**; tiếng Anh là mặc định. Chuyển đổi qua bộ chọn ngôn ngữ UI (`display.language`).

---

## 4. Bộ chọn Model (Model Picker)

Hermes không phụ thuộc vào model cụ thể (model-agnostic), và desktop giúp việc chuyển đổi trở nên đơn giản. **Bộ chọn model (model picker)** nằm trong ô soạn thảo (bên trái mic) và cho phép bạn thay đổi **model**, **reasoning effort**, và **fast mode** theo từng tin nhắn:

- Bộ chọn này **cố định theo từng thiết bị (sticky per device)** và **không bao giờ ghi đè mặc định profile của bạn** — thử nghiệm thoải mái mà không cần ghi lại config.
- Thiết lập mặc định thực tế của bạn trong **Settings → Model**, bao gồm cả các preset reasoning-effort và fast-mode theo từng model.
- Đây là cùng một danh mục (catalog) dạng fuzzy, được làm mới mỗi giờ mà bạn có trong TUI/CLI/web (xem [Part 9](./part9-custom-models.md) để biết về routing và aliases).

---

## 5. Thanh trạng thái (Status Bar) và Công tắc YOLO

Thanh trạng thái hiển thị trạng thái session trực tiếp và cung cấp một **công tắc YOLO theo từng session**. Bật YOLO sẽ bỏ qua các lời nhắc phê duyệt (approval prompts) cho session đó để agent chạy các tool mà không dừng lại để hỏi.

> **Hãy sử dụng YOLO một cách có chủ đích.** Nó thực sự hữu ích cho các vòng lặp đáng tin cậy, rủi ro thấp trên máy của chính bạn. **Không** bật nó cho bất kỳ session nào đọc đầu vào không đáng tin cậy (email, webhooks, chat công khai) hoặc có kết nối các tool mang tính phá hủy. Hãy đọc [Part 19: Security Playbook](./part19-security-playbook.md) trước, và giữ lớp phê duyệt (approval layer) bật cho bất cứ thứ gì chạm vào production.

---

## 6. Thiết lập nhanh lần đầu chạy qua Nous Portal

Lần khởi chạy đầu tiên cung cấp hai lộ trình:

- **Quick Setup** — `hermes portal` đăng nhập cho bạn qua [Nous Portal](https://portal.nousresearch.com) và chọn một model cho bạn. Cách nhanh nhất để đi từ số không đến một agent hoạt động mà không cần đụng đến YAML hay tìm kiếm API keys.
- **Full Setup** — UI onboarding đầy đủ: providers và keys, models, tools, MCP servers, gateway và sessions. xAI Grok OAuth là hạng nhất (first-class) ở đây.

Bạn có thể mở lại onboarding bất cứ lúc nào từ Settings.

---

## 7. Kết nối tới một Hermes Từ xa (Remote)

Ứng dụng desktop không nhất thiết phải chạy agent tại chỗ (locally). Nó có thể kết nối tới một **Hermes gateway từ xa (remote)** qua một WebSocket bảo mật (`/api/ws`):

- **Auth:** OAuth hoặc username/password.
- **Remote host theo từng profile:** trỏ mỗi profile đến một máy Hermes khác nhau.
- **Session đa profile đồng thời:** chạy nhiều profile cùng lúc, và liên kết giữa chúng bằng các tham chiếu `@session` xuyên profile (cross-profile).

Mô hình này là "**GUI mỏng tại chỗ (local), agent nặng ở xa (remote)**" — giữ một ứng dụng nhẹ trên laptop của bạn trong khi agent, tools và memory sống trên một workstation, một DGX Spark, hoặc một VPS. (Kết hợp điều này với [Part 21: Remote Sandboxes](./part21-remote-sandboxes.md) và [Part 25: NVIDIA & Local Hardware](./part25-nvidia-local.md).)

---

## 8. Projects — Buồng lái lập trình (Coding Cockpit) của v0.18

v0.18 đã đưa **Projects** trở thành hạng nhất (first-class). Một project là một workspace theo từng profile với:

- Một **thanh bên project (project sidebar)** và các trang project chuyên dụng.
- Một **coding rail** — kế hoạch của agent, các kiểm tra (checks) đang chạy, và hoạt động file bên cạnh chat.
- Một **review pane** — đọc diff giống như một PR trước khi bạn chấp nhận nó.
- **Quản lý worktree** — các thay đổi của mỗi project sống trong một git worktree tách biệt, để các project chạy song song không giẫm đạp lên nhau.
- **Liên kết Session–project** — các session gắn với một project, để lịch sử của một codebase luôn nằm ở một nơi.

Kết hợp với **multi-terminal panel** (nhiều terminal có tên riêng cho mỗi project), đây là thứ gần nhất với một IDE mà Hermes desktop có — ngoại trừ việc agent là người lái. Kết hợp nó với các hợp đồng xác minh và hoàn thành (verification and completion contracts) từ [Part 26](./part26-moa-verification.md#2-verification--done-means-proven-not-claimed) để "accept" có nghĩa là "các kiểm tra đã pass," chứ không phải "trông có vẻ hợp lý."

---

## 9. Đồ thị Bộ nhớ (Memory Graph)

Settings → Memory mở ra **memory graph** của v0.18: một timeline dạng hướng tâm (radial), có thể tua (playable) của mọi memory và skill mà agent đã tích lũy — tua qua thời gian và xem đồ thị phát triển. Đây là đối trọng GUI của `/journey` ([Part 26](./part26-moa-verification.md#3-learn-and-journey--self-improvement-you-can-see)): nhấp vào bất kỳ node nào để chỉnh sửa hoặc xóa nó. Hãy thực hiện một lượt cắt tỉa (pruning pass) hàng tháng; những memory sai sẽ tích lũy dồn lại (compound).

---

## 10. Sessions, Files và Giọng nói (Voice)

- **Sessions:** lưu trữ (archive), tìm kiếm, và **tìm kiếm theo id (search-by-id)**; chạy các session đa profile đồng thời với các liên kết `@session` xuyên profile.
- **File browser:** thiết lập thư mục làm việc ban đầu bằng `hermes desktop --cwd PATH` hoặc biến môi trường `HERMES_DESKTOP_CWD`.
- **Voice:** nhấp vào mic để nói; macOS sẽ yêu cầu quyền truy cập microphone một lần.
- **Remote media relay** (v0.17): khi kết nối tới một gateway từ xa, hình ảnh và file được tạo ra trên máy từ xa sẽ được truyền (stream) ngược trở lại ứng dụng thay vì bị mắc kẹt trên server.

### Các Pane Quản lý (Management Panes)

Ngoài chat, ứng dụng còn có các pane chuyên dụng cho **Skills**, **Cron**, **Profiles**, **Messaging**, và **Agents**, cộng thêm một **Command Center** — cùng những bề mặt (surfaces) mà bạn từng vận hành từ [web admin panel](./part12-web-dashboard.md), giờ đây là native.

---

## 11. Cập nhật

Ứng dụng kiểm tra cập nhật trong nền và cung cấp **cập nhật một chạm (one-click update)**; cập nhật thủ công cũng hoạt động. Điều này phản ánh lại luồng **check-before-update** của gateway (xác minh trước khi pull) được giới thiệu cùng với trang System trong web admin panel — xem [Part 12](./part12-web-dashboard.md).

---

## 12. Gỡ cài đặt

Gỡ bỏ ứng dụng từ **Settings → About → Danger zone**, hoặc từ CLI:

```bash
hermes uninstall --gui    # remove the desktop GUI only
hermes uninstall          # remove GUI + agent, keep your data
hermes uninstall --full   # remove everything, including data
```

---

## 13. Các Flag của `hermes desktop`

Để phát triển và khắc phục sự cố (troubleshooting), `hermes desktop` chấp nhận:

| Flag | Chức năng |
|------|--------------|
| `--skip-build` | Khởi chạy mà không rebuild gói (bundle) |
| `--force-build` | Bắt buộc rebuild trước khi khởi chạy |
| `--build-only` | Build gói (bundle) rồi thoát (không khởi chạy) |
| `--source` | Chạy từ source thay vì từ một bản build đã đóng gói |
| `--cwd PATH` | Thiết lập thư mục làm việc ban đầu |
| `--hermes-root PATH` | Trỏ đến một thư mục gốc cài đặt Hermes cụ thể |
| `--ignore-existing` | Bỏ qua một instance đang chạy sẵn |
| `--fake-boot` | Khởi động UI mà không khởi động agent (dành cho phát triển UI) |

---

## Khi nào nên dùng Desktop so với CLI/TUI

- **Desktop** — bạn muốn một GUI thực sự: kéo thả, dán ảnh, một preview rail, Projects với diff có thể review, memory graph, chuyển đổi model bằng cách trỏ-và-nhấp (point-and-click), và cập nhật một chạm. Tuyệt vời cho người dùng không quen terminal và để kết nối tới một agent từ xa.
- **TUI** (`hermes --tui`) — bạn sống trong terminal nhưng muốn có tool card trực tiếp, `/steer`, xếp hàng (queueing), và một composer cố định (sticky). Xem [Part 22](./part22-latest-power-moves.md).
- **CLI** (`hermes`) — scripting, cron, CI, và các thao tác nhanh một lần (one-shots).

Bên dưới vẫn là cùng một agent — hãy chọn bề mặt phù hợp với thời điểm và chuyển đổi bất cứ khi nào bạn muốn.
