# Phần 8: Các mẫu hình Subagent & Orchestrator (Ngừng tự làm mọi thứ)

*Một agent không thể làm tốt mọi việc. Hãy ủy quyền.*

---

## Ý tưởng cốt lõi

Hermes là orchestrator (bộ điều phối). Nó quyết định phải làm gì, sau đó ủy quyền việc thực thi cho các subagent chuyên biệt. Mỗi subagent chạy độc lập — có context riêng, tool riêng, session riêng.

**Khi nào nên ủy quyền:**
- Các tác vụ nặng về suy luận (debug, review code, nghiên cứu)
- Các tác vụ sẽ làm tràn ngập context của bạn với dữ liệu trung gian
- Các luồng công việc độc lập chạy song song (nghiên cứu A và B đồng thời)

**Khi nào KHÔNG nên ủy quyền:**
- Các lệnh gọi tool đơn lẻ (chỉ cần gọi tool trực tiếp)
- Các tác vụ đơn giản chỉ cần 1-2 bước
- Các tác vụ cần tương tác với người dùng (subagent không thể dùng clarify)

## delegate_task — Tool chính

```python
# Single task
delegate_task(
    goal="Debug why the API returns 403 on POST requests",
    context="File: src/api/client.py. Error started after adding auth headers. Token is valid.",
    toolsets=["terminal", "file"]
)

# Parallel batch
delegate_task(
    tasks=[
        {
            "goal": "Research LightRAG alternatives for graph RAG",
            "toolsets": ["web"]
        },
        {
            "goal": "Benchmark current LightRAG search latency",
            "context": "Path: ~/.hermes/skills/research/lightrag/",
            "toolsets": ["terminal"]
        },
        {
            "goal": "Check if our embedding model has a newer version",
            "toolsets": ["web"]
        }
    ]
)
```

**Chi tiết quan trọng:**
- Subagent KHÔNG có bộ nhớ về cuộc hội thoại của bạn. Truyền mọi thứ qua `context`.
- Kết quả trả về dưới dạng bản tóm tắt. Các lệnh gọi tool trung gian không bao giờ đi vào context của bạn.
- Mỗi subagent có phiên terminal riêng của nó.
- Số lần lặp tối đa mặc định: 50. Giảm xuống cho các tác vụ đơn giản (`max_iterations=10`).

## Ủy quyền chạy nền (Background Delegation) (v0.17) và Fan-Out (v0.18)

Theo mặc định, `delegate_task` sẽ chặn (block) session của bạn cho đến khi subagent trả về kết quả. Thêm `background=True` thì nó trả về **handle ngay lập tức** — bạn tiếp tục trò chuyện, và kết quả sẽ quay lại cuộc hội thoại như một lượt mới khi hoàn tất:

```python
delegate_task(goal="Deep-dive the competitor's pricing page", background=True)
```

v0.18 mở rộng điều này cho các batch — **background fan-out**. Triển khai các subagent song song và nhận **một lượt hội thoại tổng hợp khi tất cả đều hoàn tất**:

```python
delegate_task(
    tasks=[
        {"goal": "Audit src/auth for the token-refresh bug"},
        {"goal": "Audit src/billing for the same pattern"},
        {"goal": "Check upstream issues for known reports"},
    ],
    background=True,
)
```

Thanh trạng thái CLI/TUI theo dõi các subagent chạy nền, và ứng dụng desktop có thể mở một **watch-window** (cửa sổ theo dõi) trực tiếp cho bất kỳ subagent nào trong số đó ([Part 24](./part24-desktop-app.md)). Quy tắc chung:

- **Foreground (chạy trước)** khi bước tiếp theo phụ thuộc vào kết quả.
- **Background (chạy nền)** cho nghiên cứu, kiểm toán (audit), và các nhánh theo dõi mà bạn vốn phải chờ.
- **Kanban** ([Part 23](./part23-tenacity-stack.md)) khi công việc cần sống sót qua các lần khởi động lại hoặc liên quan đến con người — subagent chạy nền sẽ chết cùng với process.

## Mẫu hình CEO/COO/Worker

```
CEO (bạn + Hermes main agent)
  │
  ├── COO (delegate_task cho việc lập kế hoạch/review)
  │     └── Trả về: chiến lược, kế hoạch, ghi chú review
  │
  └── Workers (delegate_task cho việc thực thi)
        ├── Worker 1: Xây dựng tính năng A
        ├── Worker 2: Xây dựng tính năng B
        └── Worker 3: Viết test
```

**CEO:** Đưa ra quyết định, giao việc, review kết quả.
**COO:** Nghiên cứu, lập kế hoạch, review code. Một subagent, nặng về suy luận.
**Workers:** Thực thi các tác vụ cụ thể song song. Nhiều subagent, nặng về hành động.

## ACP Subagent (Claude Code, Codex)

Đối với các tác vụ lập trình, hãy ủy quyền cho các coding agent chuyên dụng qua ACP:

```python
# Claude Code
delegate_task(
    goal="Implement the user settings page with React",
    context="Repo at /home/terp/my-app. Use existing component library in src/components/",
    acp_command="claude",
    acp_args=["--acp", "--stdio", "--model", "claude-sonnet-5"]
)

# Codex
delegate_task(
    goal="Refactor database layer to use connection pooling",
    context="File: src/db/connection.py. Currently opens new connection per query.",
    acp_command="codex"
)
```

**Khi nào dùng ACP so với delegate_task thông thường:**
- Các ACP agent (Claude Code, Codex) giỏi hơn về lập trình — gọi tool, chỉnh sửa file, chạy test
- delegate_task thông thường phù hợp hơn cho nghiên cứu, phân tích, và các workflow đa tool
- Các ACP agent nhanh hơn cho việc chỉnh sửa một file đơn lẻ

## SWE-1.6 qua Windsurf Cascade

Đối với các tác vụ lập trình phức tạp, hãy sử dụng SWE-1.6 của Windsurf:

```python
# Send a coding task to Windsurf Cascade
# Requires Windsurf running with --remote-debugging-port=9222
subprocess.run([
    "python", 
    "~/.hermes/skills/autonomous-ai-agents/windsurf-cascade/scripts/cascade_send.py",
    "Build a React dashboard with real-time WebSocket updates"
])
```

**Mẫu hình orchestrator:** Hermes xử lý API, dữ liệu, quyết định. SWE-1.6 xử lý UI, component, sửa lỗi. Mỗi bên làm việc mà nó giỏi nhất.

## Quy tắc song song hóa

| Kịch bản | Cách tiếp cận |
|----------|----------|
| 3 tác vụ nghiên cứu độc lập | Batch `delegate_task` với mảng `tasks` (`background=True` nếu muốn tiếp tục làm việc khác) |
| 1 tác vụ lập trình phức tạp | ACP subagent (Claude Code hoặc Codex) |
| Nhiều thay đổi code ở các file khác nhau | SWE-1.6 qua Cascade |
| Một lệnh gọi API đơn lẻ | Chỉ cần gọi tool, đừng ủy quyền |
| Tác vụ cần input từ người dùng | Tự làm, không thể ủy quyền công việc mang tính tương tác |

## Các lỗi thường gặp

| Lỗi | Cách khắc phục |
|---------|-----|
| Ủy quyền một lệnh gọi tool đơn lẻ | Chỉ cần gọi tool trực tiếp |
| Không truyền đủ context cho subagent | Subagent không biết gì cả — hãy truyền đường dẫn file, thông báo lỗi, ràng buộc |
| Ủy quyền các tác vụ tuần tự để chạy song song | Nếu task B phụ thuộc vào kết quả của task A, hãy chạy chúng tuần tự |
| Đặt max_iterations quá cao | Các tác vụ đơn giản không cần 50 lần lặp — dùng 10-15 |
| Quên rằng subagent không thể dùng clarify | Nếu một tác vụ có thể cần làm rõ, hãy tự làm |

---

## Tiếp theo là gì

Hệ thống subagent đã phát triển rất nhanh. Tiếp tục với:

- **[Part 18: Ủy quyền cho Coding Agent](./part18-coding-agents.md)** — mẫu hình OpenClaw (các topic Telegram gắn theo thread → các runtime Claude Code / Codex / Gemini CLI bền vững). Print-mode so với interactive, ACP-as-server, cô lập git branch, quy tắc định tuyến.
- **[Part 17: MCP Server](./part17-mcp-servers.md)** — cung cấp cho subagent các tool luôn đồng bộ giữa Hermes, Claude Code, và Cursor.
- **[Part 21: Remote Sandbox](./part21-remote-sandboxes.md)** — chạy subagent của bạn trên Modal/Daytona/SSH để một VPS 5 đô có thể điều khiển một workspace mạnh mẽ.
- **[Part 20: Observability (Khả năng quan sát)](./part20-observability.md)** — trace mọi lệnh gọi subagent trong Langfuse, cùng với phân tích chi phí theo từng skill.

---

*Mẫu hình orchestrator là cách bạn mở rộng quy mô. Một bộ não, nhiều bàn tay.*
