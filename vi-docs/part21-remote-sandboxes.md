# Phần 21: Sandbox Từ Xa & Đồng Bộ File Hàng Loạt — SSH, Modal, Daytona, Vercel

*Chạy Hermes trên một VPS $5 thì tuyệt vời cho việc chat. Chạy các tác vụ coding nặng ở đó thì không. Phần này thiết lập mô hình "điện thoại lái, sandbox từ xa mạnh mẽ làm việc": Hermes sống trên VPS nhỏ của bạn, ủy quyền việc thực thi cho một sandbox dùng-một-lần trên SSH/Modal/Daytona/Vercel, đồng bộ file theo cả hai chiều, và phá hủy nó khi rảnh rỗi.*

---

## Mô Hình

```
Your phone (Telegram)
        │
        ▼
Hermes on $5 VPS  ─────────────►  Remote sandbox ($0 when idle)
- Memory                            - Whole workspace in /home/runner/
- Skills                            - Coding agents (Claude/Codex/etc)
- Conversation state                - Build tools, Docker, GPU
        ▲                                │
        │                                │
        └─── bulk file sync on teardown ─┘
```

Hermes tải workspace của bạn lên khi tác vụ bắt đầu, ủy quyền công việc, sau đó chỉ tải xuống phần chênh lệch (diff) khi phá hủy. Sandbox chết đi, Hermes giữ lại trạng thái — và VPS $5 của bạn không bao giờ cần đến 32GB RAM mà sandbox đã chạy.

---

## Chọn Backend Của Bạn

| Backend | Tính phí | Chi phí khi rảnh | Phù hợp cho |
|---------|---------|-----------|----------|
| **SSH** | Hạ tầng của bạn | Tùy chi phí host của bạn | Homelab / máy dev luôn bật |
| **Modal** | Tính theo giây compute | $0 (ngủ đông) | Tác vụ coding bùng nổ, công việc GPU |
| **Daytona** | Tính theo giây workspace | $0 (ngủ đông) | Workspace dev tồn tại lâu dài |
| **Vercel Sandbox** | Theo lượt chạy / tính phí nền tảng | $0 khi không dùng | Build webapp và các tác vụ `execute_code` cô lập |
| **Fly Machines** | Tính theo giây | $0 (dừng) | Sandbox theo khu vực gần người dùng của bạn |
| **E2B** | Tính theo giây | $0 | Sandbox Python dùng-một-lần nhanh |
| **Local Docker** | Phần cứng của bạn | Không áp dụng | Testing / phát triển |

Hermes hỗ trợ sẵn (native) cho SSH, Modal, Daytona, và Vercel Sandbox. Fly Machines và E2B hoạt động qua các plugin nhẹ.

---

## Backend SSH (Homelab / Máy Dev Luôn Bật)

### Điều Kiện Tiên Quyết

- Quyền truy cập SSH vào host từ xa với xác thực bằng key (không có yêu cầu nhập mật khẩu)
- Máy từ xa có `python3`, `rsync`, `tar`, `git`
- Cấu hình SSH của bạn dùng `ControlMaster` + `ControlPath` để tái sử dụng kết nối (minh họa bên dưới)

### Cấu Hình

```yaml
# ~/.hermes/config.yaml
sandboxes:
  dev-box:
    backend: ssh
    host: dev.local
    user: hermes
    identity_file: ~/.ssh/hermes_ed25519
    workdir: /home/hermes/sandboxes
    control_master: auto              # Reuses connection for bulk sync
    control_persist: 600
    sync:
      push: ~/.hermes                 # Uploaded at sandbox create
      pull_on_teardown: true
      pull_paths:
        - .hermes
        - projects                    # Grabs any code changes made in-sandbox
      ignore:
        - .git
        - node_modules
        - __pycache__
        - "*.log"
        - .env                      # Excludes ~/.hermes/.env — without this, `push: ~/.hermes`
                                     # above syncs live provider API keys to the remote
                                     # sandbox host. See part19-security-playbook.md
                                     # ("keys stay on the host").
```

### Sử Dụng Nó

```
/sandbox start dev-box
/claude-code refactor src/auth/ to use JWT rotation
/sandbox stop dev-box                # Syncs changes back, then stops
```

Bên dưới, khi phá hủy:

1. Hermes chạy `tar cf - -C ~/.hermes .` trên máy từ xa
2. Truyền dữ liệu (pipe) qua SSH ControlMaster về máy local
3. Giải nén vào một thư mục staging
4. So sánh (diff) với các hash SHA-256 của những gì đã được push ban đầu
5. Chỉ áp dụng lại các file đã thay đổi vào `~/.hermes`, với `fcntl.flock` để tuần tự hóa nếu có sandbox khác đang chạy đồng thời
6. An toàn với SIGINT — nhấn Ctrl-C trong lúc đồng bộ sẽ rollback một cách sạch sẽ

Đây là phần gia cố (hardening) đã giúp sandbox từ xa đủ an toàn cho công việc coding thực sự. Trước khi có tính năng đồng bộ dựa trên diff, bạn hoặc phải rsync mọi thứ mỗi lần (chậm) hoặc mất các chỉnh sửa được thực hiện từ xa khi phá hủy.

---

## Backend Modal (Bùng Nổ / Serverless)

Modal cho sandbox ngủ đông về mức 0 giữa các lần chạy và khởi động lại trong khoảng ~2 giây. Lý tưởng cho việc sử dụng coding agent theo kiểu bùng nổ.

```bash
pip install modal
modal token new
```

```yaml
sandboxes:
  modal-big:
    backend: modal
    image:
      from: python:3.12
      apt_install: [git, ripgrep, build-essential]
      pip_install: [claude-code-cli, aider-chat]
    cpu: 4
    memory: 16384
    gpu: null                        # Set to "T4" / "A10G" / "H100" if you need one
    timeout: 3600
    sync:
      push: ~/.hermes
      pull_on_teardown: true
      pull_paths: [.hermes, projects]
```

Đồng bộ sử dụng mẫu `exec tar cf -` → `proc.stdout.read()` → file local của Modal — cùng logic diff/apply như SSH.

Mẹo tiết kiệm chi phí: đặt `timeout: 300` và một `idle_shutdown:` ngắn cho các sandbox điều khiển bằng chat; Modal tính phí theo từng giây runtime thực tế.

### Sandbox GPU Cho Tác Vụ Voice / Hình Ảnh

Nếu bạn đã tắt [Tool Gateway](./part13-tool-gateway.md) và tự chạy pipeline image-gen hoặc voice của riêng mình, một sandbox GPU sẽ rẻ hơn so với việc giữ một GPU VPS luôn bật:

```yaml
sandboxes:
  gpu-a10g:
    backend: modal
    image:
      from: nvcr.io/nvidia/pytorch:24.10-py3
      pip_install: [diffusers, transformers]
    gpu: "A10G"
    timeout: 600
    commands:
      - /generate_image    # Route image gen to this sandbox
      - /speech_synth
```

Hermes định tuyến các lệnh gọi tool một cách trong suốt — người dùng không hề biết rằng thời gian tồn tại của sandbox đang diễn ra.

---

## Backend Daytona (Workspace Tồn Tại Lâu Dài)

Daytona là lựa chọn kiểu "giống GitHub Codespaces cho code của riêng bạn". Kết hợp với Hermes khi bạn muốn workspace tồn tại xuyên suốt các phiên làm việc:

```yaml
sandboxes:
  workspace:
    backend: daytona
    workspace_id: hermes-dev
    auto_create: true                # Create if it doesn't exist
    image: daytonaio/workspace-project:latest
    hibernate_after: 900
    sync:
      push: ~/.hermes
      pull_on_teardown: false        # Work persists, no need to sync every time
      pull_on_command: "/sync-home"  # Manual sync when you want it
```

Kết hợp với [Gemini API key hoặc Vertex AI](./part9-custom-models.md#google-api-key-or-vertex-ai-gemini-oauth-is-gone) để đọc ngữ cảnh dài (long-context) với chi phí rẻ bên trong sandbox.

---

## Vercel Sandbox (Build Web / Thực Thi Code Cô Lập)

Vercel Sandbox hiện là một backend hỗ trợ sẵn cho `execute_code` và các lượt chạy kiểu terminal. Sử dụng khi tác vụ có hình dạng webapp: cài dependency, chạy build, kiểm tra kết quả sinh ra, và vứt bỏ môi trường đi.

```yaml
sandboxes:
  vercel-web:
    backend: vercel
    project: my-webapp
    timeout: 1800
    sync:
      push: ~/projects/my-webapp
      pull_on_teardown: true
      pull_paths:
        - .
      ignore:
        - node_modules
        - .next
        - dist
```

Đây không phải là thứ thay thế cho Daytona nếu bạn muốn một workspace dev tồn tại lâu dài. Hãy coi nó như một mục tiêu thực thi sạch cho các bản build, test, và các script cô lập ngắn.

---

## Fly Machines (Theo Khu Vực / Độ Trễ Thấp)

Đối với người dùng ở các khu vực cụ thể, Fly Machines mang lại độ trễ dưới 100ms từ một PoP gần đó:

```yaml
sandboxes:
  fly-sin:
    backend: fly_machines             # Plugin, not core
    app: hermes-sandbox
    region: sin                       # Singapore
    size: performance-2x
    auto_stop: true
    stopped_shutdown_at: 120
```

Hữu ích khi bạn muốn sandbox nằm gần về mặt vật lý với người dùng iOS / Telegram của mình để giảm độ trễ round-trip.

---

## E2B (Sandbox Python Dùng-Một-Lần)

E2B cho bạn một sandbox Linux sạch trong khoảng ~500ms. Phù hợp nhất cho phân tích dữ liệu / chạy code không rõ nguồn gốc:

```yaml
sandboxes:
  e2b-scratch:
    backend: e2b
    template: python                  # E2B template
    metadata:
      purpose: data-analysis
    timeout: 300
```

Hermes định tuyến bất kỳ lệnh gọi tool nào được đánh dấu `/sandbox e2b` vào template này. Việc phá hủy diễn ra tự động.

---

## Các Mô Hình Kết Hợp Nhiều Sandbox

### Mô Hình A: Máy Dev Chính-Phụ + Sandbox Ngắn Hạn

- **Chính (Primary):** máy dev SSH với workspace tồn tại lâu dài của bạn
- **Phụ (Replica):** sandbox Modal được khởi tạo cho mỗi lần ủy quyền

```
/sandbox start dev-box
/delegate (runs in modal-big, reads from dev-box via git)
/sandbox stop dev-box
```

Hoạt động tốt khi mỗi lần ủy quyền coding agent chạy trên một nhánh (branch) tính năng dựa trên git. Sandbox là stateless (không lưu trạng thái); dev-box là nguồn dữ liệu chân lý duy nhất.

### Mô Hình B: Workspace Daytona Theo Từng Dự Án

```
/project open myapp       → daytona workspace "myapp"
/project open sideproject → daytona workspace "sideproject"
```

Mỗi dự án có workspace riêng với dependency, biến môi trường (env), và trạng thái git riêng. Hermes ghi nhớ workspace nào đang hoạt động theo từng topic Telegram.

### Mô Hình C: MCP Server Được Đưa Vào Sandbox

Định tuyến các MCP server không tin cậy (xem [Phần 19](./part19-security-playbook.md#layer-5-mcp-and-plugin-trust)) vào một sandbox:

```yaml
mcp_servers:
  random-scraper:
    trust: untrusted
    run_in_sandbox: e2b-scratch       # Isolate execution
```

Sandbox chặn đứng mọi hành vi độc hại — ngay cả khi scraper bị xâm hại, nó cũng không thể chạm vào máy chủ của bạn.

---

## Khả Năng Quan Sát: `hermes sandbox status`

```
$ hermes sandbox status
NAME         BACKEND   STATE      AGE      CPU   MEM      COST
dev-box      ssh       connected  3h 12m   0.4   2.1 GB   $0 (your infra)
modal-big    modal     running    0m 42s   3.8   14.2 GB  $0.09
workspace    daytona   hibernated 0m 0s    -     -        $0
```

[Web Dashboard](./part12-web-dashboard.md) có một bảng điều khiển Sandboxes với cùng thông tin này cộng thêm: log dạng streaming, tổng chi phí theo từng sandbox trong tháng, lịch sử đồng bộ, và một nút "đồng bộ ngược rồi dừng" chỉ với một cú click.

---

## Xử Lý Sự Cố

| Triệu Chứng | Cách Khắc Phục |
|---------|-----|
| "sandbox teardown timed out during sync" | Tăng `sync.timeout: 600` — dành cho workspace lớn qua SSH chậm |
| "sync conflict: host file also changed" | Mặc định là ghi đè lần cuối cùng thắng (last-write-wins); đặt `sync.conflict: prompt` để giải quyết tương tác |
| "SSH ControlMaster socket in use" | Một tiến trình Hermes khác trên máy đang chạy; dùng `hermes sandbox ps` để tìm nó |
| "Modal sandbox cold-start keeps timing out" | Làm nóng trước (pre-warm) bằng `hermes sandbox warm modal-big` trước khi làm việc tương tác |
| "Daytona hibernate → resume corrupts git state" | Đặt `.git` vào `pull_paths` để Hermes giữ bản sao chính thức (canonical) |
| "File-sync uploads .venv every time" | Thêm nó vào `ignore:` — bị bỏ sót theo mặc định trong một số template |

Bật `HERMES_SANDBOX_LOG=debug` để lấy đầy đủ log truy vết lệnh tar/ssh.

---

## Tiếp Theo Là Gì

- [Phần 18: Coding Agents](./part18-coding-agents.md) — ủy quyền Claude Code / Codex / Gemini CLI *vào* các sandbox này
- [Phần 19: Security Playbook](./part19-security-playbook.md) — cô lập các MCP không tin cậy trong sandbox
- [Phần 20: Observability & Cost](./part20-observability.md) — theo dõi chi phí sandbox-hour cùng với chi tiêu LLM
- [Phần 1: Setup](./README.md#part-1-setup-stop-fumbling-with-installation) — cài đặt VPS cơ bản mà các phần này mở rộng
