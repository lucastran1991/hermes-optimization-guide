# Phần 1: Cài đặt (Đừng Loay Hoay Với Việc Cài Đặt Nữa)

*Từ con số không đến một agent hoạt động trong chưa đầy 5 phút. Bao gồm những gì tài liệu chính thức không nói tới.*

---

## Cài Đặt

Chỉ một lệnh duy nhất. Vậy là xong. Hermes cũng được phát hành trên PyPI, vì vậy hãy dùng trình cài đặt để có đầy đủ stack cục bộ, hoặc dùng `pip install hermes-agent` để có đường đi CLI gọn nhẹ nhất. Thích dùng GUI hơn? Cài [ứng dụng desktop](./part24-desktop-app.md) — cùng một agent, cùng cấu hình, cùng khóa (keys).

### Linux / macOS / WSL2

```bash
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash

# Lean path when you already manage Python yourself:
pip install hermes-agent
```

> **Mẹo bảo mật:** Việc pipe script trực tiếp từ internet vào bash sẽ thực thi chúng mà không cần xem trước. Nếu bạn muốn kiểm tra trước:
> ```bash
> curl -fsSL https://hermes-agent.nousresearch.com/install.sh -o install.sh
> less install.sh   # Review the script
> bash install.sh
> ```

### Windows (bản gốc)

Hermes giờ đã có trình cài đặt Windows gốc (native) đẳng cấp. Trong PowerShell:

```powershell
iex (irm https://hermes-agent.nousresearch.com/install.ps1)
```

[WSL2](https://learn.microsoft.com/en-us/windows/wsl/install) vẫn là một lựa chọn tốt nếu bạn thích môi trường Linux cho công việc gateway.

### Ứng dụng desktop

Muốn dùng GUI thay vì terminal? Cài [ứng dụng Hermes Desktop](./part24-desktop-app.md) (macOS/Windows/Linux) — hoặc thêm nó vào bản cài CLI bằng `--include-desktop`. Nó chạy cùng một agent, cấu hình, và khóa. Tham quan đầy đủ tại [Phần 24](./part24-desktop-app.md).

### Trình Cài Đặt Làm Gì

Trình cài đặt xử lý mọi thứ tự động:

- Cài **uv** (trình quản lý gói Python nhanh)
- Cài **Python 3.11** thông qua uv (không cần sudo)
- Cài **Node.js v22** (cho tự động hóa trình duyệt)
- Cài **ripgrep** (tìm kiếm file nhanh) và **ffmpeg** (chuyển đổi audio)
- Cài gói PyPI hoặc clone repo Hermes khi bạn chọn chế độ source
- Thiết lập virtual environment
- Tạo lệnh toàn cục `hermes`
- Chạy trình hướng dẫn thiết lập (setup wizard) để cấu hình nhà cung cấp LLM

Yêu cầu tiên quyết duy nhất là **Git**. Mọi thứ còn lại đều được xử lý sẵn cho bạn.

### Sau Khi Cài Đặt

```bash
source ~/.bashrc   # or: source ~/.zshrc
hermes             # Start chatting!
```

---

## Cấu Hình Lần Đầu Chạy

Trình hướng dẫn thiết lập (`hermes setup`) sẽ dẫn bạn qua:

### 1. Chọn Model Của Bạn (mang theo bất kỳ model nào)

```bash
hermes model        # fuzzy-search every provider Hermes knows about
```

**Hermes không phụ thuộc vào một model cụ thể (model-agnostic)** — bộ chọn tìm kiếm mờ (fuzzy-search) trên một danh mục được làm mới mỗi giờ, nên bạn không bao giờ bị kẹt với danh sách của bản phát hành trước. Bạn không cần phải cam kết chỉ với một nhà cung cấp:

- **API đám mây (Cloud APIs)** — Anthropic, OpenAI, Google, xAI / Grok (OAuth), Moonshot / Kimi, z.ai / GLM, MiniMax, Cerebras, Groq, và nhiều hơn nữa. Thiết lập biến `*_API_KEY` tương ứng hoặc đăng nhập bằng OAuth.
- **Một khóa cho tất cả** — OpenRouter (`OPENROUTER_API_KEY`) tiếp cận hàng trăm model với cơ chế dự phòng (fallback) tự động.
- **Cục bộ / riêng tư** — Ollama, LM Studio, hoặc llama.cpp mà không cần khóa. Xem [Phần 25: NVIDIA & Phần Cứng Cục Bộ](./part25-nvidia-local.md).
- **Nous Portal** — `hermes portal` chạy một **Quick Setup** có hướng dẫn, giúp bạn đăng nhập và chọn model cho bạn.

Cấu hình **nhiều nhà cung cấp (multiple providers)** với cơ chế dự phòng tự động — nếu một cái bị lỗi, Hermes sẽ chuyển sang cái tiếp theo. Định tuyến (Routing), bí danh (aliases), và chuỗi dự phòng (fallback chains) được trình bày trong [Phần 9](./part9-custom-models.md).

### 2. Thiết Lập API Keys Của Bạn

```bash
hermes auth
```

Lệnh này mở một menu tương tác để thêm API keys cho từng nhà cung cấp. Các khóa được lưu trong `~/.hermes/.env` — không bao giờ được commit vào git.

> **Mẹo:** Bạn cũng có thể thiết lập khóa thủ công bằng trình soạn thảo văn bản:
> ```bash
> nano ~/.hermes/.env    # Add: ANTHROPIC_API_KEY=<your-key-here>
> chmod 600 ~/.hermes/.env   # Restrict access to your user only
> ```
>
> **Tránh dùng `echo` để nối thêm thông tin bí mật (secrets)** — lệnh (bao gồm cả khóa) sẽ được lưu trong lịch sử shell của bạn (`~/.bash_history`). Hãy dùng trình soạn thảo hoặc `hermes auth` thay thế. Luôn chạy `chmod 600 ~/.hermes/.env` để ngăn những người dùng khác trên hệ thống đọc được API keys của bạn.

### 3. Cấu Hình Bộ Công Cụ (Toolsets)

```bash
hermes tools
```

Lệnh này mở một TUI tương tác để bật/tắt các nhóm công cụ:

- **core** — Đọc/ghi file, terminal, tìm kiếm web
- **web** — Tự động hóa trình duyệt, trích xuất web
- **browser** — Điều khiển trình duyệt đầy đủ (yêu cầu Node.js)
- **code** — Sandbox thực thi code
- **delegate** — Tạo sub-agent để xử lý công việc song song
- **skills** — Khám phá và tạo skill
- **memory** — Tìm kiếm và quản lý bộ nhớ (memory)

> **Khuyến nghị:** Tối thiểu nên bật `core`, `web`, `skills`, và `memory`. Thêm `browser` và `code` nếu bạn cần tự động hóa hoặc thực thi trong sandbox.

---

## Các Tùy Chọn Cấu Hình Chính

Sau khi thiết lập ban đầu, tinh chỉnh thêm bằng `hermes config set`:

### Cài Đặt Model

```bash
# Set primary model
hermes config set model anthropic/claude-sonnet-5

# Set fallback model (used when primary is rate-limited)
hermes config set fallback_models '["openrouter/anthropic/claude-sonnet-5"]'
```

### Hành Vi Của Agent

```bash
# Max turns per conversation (default: 90)
hermes config set agent.max_turns 90

# Verbose mode: off, on, or full
hermes config set agent.verbose off

# Quiet mode (less terminal output)
hermes config set agent.quiet_mode true
```

### Quản Lý Ngữ Cảnh (Context)

```bash
# Enable prompt caching (reduces cost on repeated context)
hermes config set prompt_caching.enabled true

# Context compression (auto-summarize old messages)
hermes config set context_compression.enabled true
```

---

## Vị Trí Các File

Mọi thứ đều nằm trong `~/.hermes/`:

```
~/.hermes/
├── config.yaml          # Main configuration
├── .env                 # API keys (never commit this)
├── SOUL.md             # Agent personality (injected every message)
├── memories/           # Long-term memory entries
├── skills/             # Skills (auto-discovered)
├── skins/              # CLI themes
├── audio_cache/        # TTS audio files
├── logs/               # Session logs
└── hermes-agent/       # Source code (git repo)
```

> **Quan trọng:** `SOUL.md` được chèn vào mỗi tin nhắn. Giữ nó dưới 1 KB. Mỗi byte đều tốn độ trễ (latency) và token.

> **Bảo mật:** File `.env` chứa API keys của bạn. Hạn chế quyền truy cập của nó để chỉ mình bạn có thể đọc được:
> ```bash
> chmod 600 ~/.hermes/.env
> ```

---

## Xác Minh Thiết Lập Của Bạn

```bash
# Check everything is working
hermes status

# Quick test
hermes chat -q "Say hello and confirm you're working"
```

Kết quả mong đợi: Hermes phản hồi với một lời chào, xác nhận kết nối model, tính khả dụng của công cụ, và việc khởi tạo phiên làm việc (session).

---

## Cập Nhật

```bash
hermes update
```

Lệnh này kéo về code mới nhất, cập nhật các dependency, di chuyển (migrate) cấu hình, và khởi động lại gateway. Hãy chạy nó thường xuyên — Hermes phát hành các cải tiến liên tục. Trang **System** của bảng quản trị web (web admin panel) thêm bước **check-before-update** và tính năng **Debug Share** chỉ với một cú click để hỗ trợ, còn [ứng dụng desktop](./part24-desktop-app.md) tự kiểm tra ở chế độ nền và cập nhật chỉ với một cú click.

---

## Bước Tiếp Theo

- **Đến từ OpenClaw?** → [Phần 2: Di Chuyển Từ OpenClaw](./part2-openclaw-migration.md)
- **Muốn bộ nhớ thông minh hơn?** → [Phần 3: Thiết Lập LightRAG](./part3-lightrag-setup.md)
- **Cần truy cập trên di động?** → [Phần 4: Thiết Lập Telegram](./part4-telegram-setup.md)
- **Muốn agent tự cải thiện?** → [Phần 5: Tạo Skill Tức Thời](./part5-creating-skills.md)
- **Thích dùng GUI hơn?** → [Phần 24: Ứng Dụng Hermes Desktop](./part24-desktop-app.md)
- **Chạy trên GPU của riêng bạn?** → [Phần 25: NVIDIA & Phần Cứng Cục Bộ](./part25-nvidia-local.md)
