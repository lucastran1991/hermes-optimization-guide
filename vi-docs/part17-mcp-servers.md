# Phần 17: Máy Chủ MCP — Trang Bị Cho Hermes Bất Kỳ Công Cụ Nào Mà Không Cần Viết Code Kết Nối

*Model Context Protocol (MCP) là "cổng USB-C của các agent AI" — một cách chuẩn hóa để bất kỳ máy chủ công cụ nào cũng có thể kết nối với bất kỳ agent nào. Hermes đã hỗ trợ MCP một cách gốc (native) kể từ [v0.7.0](https://github.com/NousResearch/hermes-agent/releases/tag/v2026.4.3). Đây là phần hướng dẫn mà không ai đọc cho đến khi họ nhận ra rằng họ có thể ngừng viết bộ chuyển đổi công cụ (tool adapter) bằng tay.*

---

## Tại Sao Điều Này Quan Trọng

Trước khi có MCP, mỗi framework agent đều có schema gọi công cụ (tool-calling) riêng. Bạn viết một công cụ GitHub cho Hermes, rồi viết lại cho Claude Code, rồi lại viết lại lần nữa cho Cursor. Cả ba đều gọi cùng một GitHub API.

MCP (được giới thiệu bởi Anthropic, hiện là chuẩn mực trên thực tế (de facto standard) trên Claude Code, Cursor, GitHub Copilot, Devin, và Hermes) định nghĩa:

- **Tool discovery** (khám phá công cụ) — một định dạng JSON chuẩn để mô tả đầu vào và đầu ra
- **Transports** (giao thức truyền tải) — stdio (tiến trình con cục bộ) và HTTP (máy chủ từ xa)
- **Bi-directional sampling** (lấy mẫu hai chiều) — các máy chủ MCP có thể yêu cầu agent thực hiện một lệnh gọi LLM thay mặt cho chúng

Hermes cắm thẳng vào hệ sinh thái này. Chỉ cần trỏ nó đến bất kỳ máy chủ MCP nào — do cộng đồng xây dựng hay do bạn tự tạo — thì các công cụ đó sẽ xuất hiện ngay cạnh các công cụ tích hợp sẵn của Hermes mà không cần thay đổi bất kỳ dòng code nào. Đây là giờ đầu tư hiệu quả nhất bạn có thể bỏ ra để tối ưu hóa agent của mình.

---

## MCP Phù Hợp Với Hermes Như Thế Nào

```
┌────────────────────────────────────────────────────┐
│  Hermes Agent                                       │
│  ┌──────────────────────────────────────────────┐  │
│  │  Built-in tools (terminal, skills, memory)   │  │
│  └──────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────┐  │
│  │  MCP Client                                  │  │
│  │  ├─ github-mcp     (stdio, subprocess)      │  │
│  │  ├─ postgres-mcp   (stdio, subprocess)      │  │
│  │  ├─ mem0-mcp       (http, remote)           │  │
│  │  └─ your-mcp       (stdio or http)          │  │
│  └──────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────┘
```

Hermes tự động khám phá (auto-discover) các công cụ khi khởi động và đăng ký nhận các cập nhật động — nếu một máy chủ MCP thêm một công cụ mới giữa phiên làm việc, Hermes sẽ nhận diện nó mà không cần khởi động lại.

---

## Cấu Hình

Các máy chủ MCP được khai báo dưới khóa `mcp_servers` trong `~/.hermes/config.yaml`.

### Máy Chủ stdio (Tiến Trình Con Cục Bộ)

```yaml
mcp_servers:
  github:
    command: npx
    args: ["-y", "@modelcontextprotocol/server-github"]
    env:
      GITHUB_PERSONAL_ACCESS_TOKEN: ${GITHUB_TOKEN}

  filesystem:
    command: npx
    args: ["-y", "@modelcontextprotocol/server-filesystem", "/home/you/projects"]

  postgres:
    command: npx
    args: ["-y", "@modelcontextprotocol/server-postgres", "${DATABASE_URL}"]
```

Hermes khởi chạy tiến trình con (subprocess) khi bắt đầu, truyền dữ liệu JSON-RPC qua stdio, và tắt nó khi thoát. Khởi động lại Hermes sau khi thêm một máy chủ stdio mới.

### Máy Chủ HTTP / SSE (Từ Xa)

```yaml
mcp_servers:
  mem0:
    url: https://mcp.mem0.ai/sse
    headers:
      Authorization: Bearer ${MEM0_API_KEY}

  cloudflare:
    url: https://observability.mcp.cloudflare.com/sse
    headers:
      Authorization: Bearer ${CLOUDFLARE_API_TOKEN}
```

Các máy chủ HTTP có thể thêm/xóa công cụ theo thời gian thực. Hermes xử lý việc kết nối lại bằng cơ chế exponential backoff.

### Kích Hoạt Có Phạm Vi (Scoped Enablement)

Một số máy chủ khá "ồn ào" (chatty) — bạn không muốn mọi công cụ mà chúng cung cấp đều được tải vào mọi cuộc hội thoại. Hãy giới hạn phạm vi của chúng:

```yaml
mcp_servers:
  postgres:
    command: npx
    args: ["-y", "@modelcontextprotocol/server-postgres", "${DATABASE_URL}"]
    enabled_for:                     # Only load in these sessions
      - profile: engineering
      - channel: "#data-questions"
    tools_allowlist:                 # Only expose these tools
      - query
      - describe_table
```

Nếu không có `tools_allowlist`, mọi công cụ mà máy chủ cung cấp đều sẽ khả dụng.

---

## Các Máy Chủ MCP Đáng Cài Đặt Ngay Hôm Nay

Đây là những máy chủ sẽ "tự trả giá" (đem lại giá trị) chỉ trong một ngày sử dụng:

> **Thực tế năm 2026:** MCP cũng là một ranh giới trong chuỗi cung ứng (supply-chain boundary). Hãy ưu tiên các máy chủ chính thức, cố định (pin) phiên bản gói, giới hạn thư mục gốc của hệ thống tệp, và giữ `allow_sampling: false` trừ khi máy chủ thực sự cần gọi một LLM.

| Server | Nó thêm gì | Tại sao bạn cần nó |
|--------|--------------|-----------------|
| **@modelcontextprotocol/server-github** | Issues, PR, tìm kiếm repo, diff nhánh | Hermes trở thành một đồng đội am hiểu code |
| **@modelcontextprotocol/server-filesystem** | Đọc/ghi/tìm kiếm tệp có giới hạn phạm vi | An toàn hơn so với việc cấp quyền truy cập terminal |
| **@modelcontextprotocol/server-postgres** | SQL chỉ đọc (read-only) | Trả lời câu hỏi "trong database có gì?" mà không cần lộ DSN |
| **@modelcontextprotocol/server-sqlite** | Phân tích SQLite cục bộ | Rất phù hợp cho tệp log, ảnh chụp nhanh (snapshot) dữ liệu phân tích |
| **@modelcontextprotocol/server-puppeteer** | Tự động hóa trình duyệt | Bổ sung cho tính năng Browser Use của Tool Gateway; hãy sandbox nó thật chặt chẽ |
| **@modelcontextprotocol/server-memory** | Bộ nhớ dạng đồ thị tri thức (knowledge-graph) | Kết hợp với [Phần 3 LightRAG](./part3-lightrag-setup.md) để tăng độ dự phòng |
| **mcp.mem0.ai** | Bộ nhớ dài hạn được lưu trữ (hosted) | Bộ nhớ đa thiết bị dùng chung giữa Hermes + Claude Code |
| **Cloudflare Observability MCP** | Truy vấn log/dữ liệu phân tích của Worker | Nếu bạn chạy bất kỳ thứ gì trên Cloudflare |
| **@supabase/mcp-server-supabase** | Supabase RPC + Postgres + storage | Một cấu hình duy nhất cho toàn bộ backend |
| **linear-mcp** | CRUD issue của Linear | Biến Hermes thành người được giao xử lý issue |
| **stripe-mcp** | Đọc dữ liệu Stripe (khách hàng, gói đăng ký) | Phân loại (triage) hỗ trợ ngay từ Telegram |
| **@notionhq/notion-mcp-server** | Trang + cơ sở dữ liệu Notion | Wiki công ty làm ngữ cảnh nền tảng (grounded context) |
| **@browserbase/mcp** | Dịch vụ trình duyệt headless dạng as-a-service | Cào dữ liệu (scraping) những trang mà Firecrawl không xử lý được |
| **@chroma-core/chroma-mcp** | Vector của ChromaDB | Hoạt động song song cùng LightRAG |

Để xem danh mục đầy đủ, hãy tham khảo [MCP Registry](https://registry.modelcontextprotocol.io/) và danh sách `awesome-mcp-servers` trên GitHub.

---

## Viết Máy Chủ MCP Của Riêng Bạn (Nhanh Chóng)

Một máy chủ MCP Node tối giản chỉ khoảng ~30 dòng. Python cũng tương tự. Chỉ cần trỏ Hermes đến nó giống như bất kỳ máy chủ stdio nào khác.

```javascript
// my-mcp/index.js
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

const server = new Server(
  { name: "my-mcp", version: "0.1.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler("tools/list", async () => ({
  tools: [{
    name: "deploy_staging",
    description: "Deploys current git HEAD to the staging environment",
    inputSchema: {
      type: "object",
      properties: { service: { type: "string" } },
      required: ["service"]
    }
  }]
}));

server.setRequestHandler("tools/call", async (req) => {
  if (req.params.name === "deploy_staging") {
    const result = await deployStaging(req.params.arguments.service);
    return { content: [{ type: "text", text: result }] };
  }
});

await server.connect(new StdioServerTransport());
```

Đăng ký nó:

```yaml
mcp_servers:
  ops:
    command: node
    args: ["/home/you/mcp/my-mcp/index.js"]
```

Giờ đây `deploy_staging` là một công cụ mà Hermes có thể gọi từ bất kỳ giao diện nào — CLI, Telegram, iMessage, Discord — mà không cần đụng đến code của Hermes.

---

## Sampling: Cho Phép Máy Chủ MCP Gọi LLM

Đây là tính năng đột phá (killer feature) của MCP và là lý do nó đặc biệt quan trọng đối với các agent. Các máy chủ MCP có thể yêu cầu Hermes thực hiện suy luận (inference) LLM thông qua `sampling/createMessage`:

- Một MCP scraper lấy về một trang lộn xộn → yêu cầu LLM của Hermes trích xuất dữ liệu có cấu trúc → trả dữ liệu có cấu trúc đó về cho agent.
- Một MCP đánh giá bảo mật (security-review) đọc một diff → yêu cầu LLM phân loại mức độ nghiêm trọng → trả về một nhãn phân loại (triage label).
- Một MCP dịch thuật đọc một tệp → yêu cầu LLM bản địa hóa (localize) nó → ghi ra kết quả.

Hermes xử lý yêu cầu suy luận bằng nhà cung cấp (provider) đang hoạt động và đo lường số token theo phiên hiện tại. Bật sampling cho một máy chủ:

```yaml
mcp_servers:
  scraper:
    command: node
    args: ["./scraper-mcp.js"]
    allow_sampling: true              # Off by default
    sampling_model: gpt-5-mini        # Optional: pin a cheaper model for sampling
```

**Lưu ý bảo mật:** Sampling đồng nghĩa với việc một máy chủ MCP có thể "đốt" token của bạn. Chỉ bật tính năng này cho các máy chủ mà bạn tin tưởng. Xem [Phần 19](./part19-security-playbook.md#layer-5-mcp-and-plugin-trust).

---

## Giám Sát Lưu Lượng MCP

```bash
/mcp list                            # Show registered servers + tool counts
/mcp reload                          # Reload servers without restarting Hermes
/mcp disable github                  # Temporarily unregister
/mcp enable github                   # Bring it back
```

[Web Dashboard](./part12-web-dashboard.md) có một tab **MCP Servers** hiển thị trạng thái kết nối, danh sách công cụ, các lệnh gọi gần đây, và log lỗi cho từng máy chủ. Đây là cách nhanh nhất để debug một MCP hoạt động sai.

Đặt `HERMES_MCP_LOG=debug` trong tệp `.env` của bạn để lấy đầy đủ các trace JSON-RPC trong `~/.hermes/logs/mcp.log`. Hãy tắt tính năng này ở môi trường production — các trace bao gồm cả tham số và kết quả của công cụ.

---

## Khi Nào MCP Là Thừa Thãi

MCP thêm một tiến trình (hoặc một bước nhảy mạng - network hop) cho mỗi công cụ. Đối với những thứ đã có sẵn bên trong Hermes, đừng phí công:

- **Lệnh terminal** — chỉ cần dùng công cụ `terminal` tích hợp sẵn.
- **Chỉnh sửa tệp** — các công cụ tệp tích hợp sẵn nhanh hơn filesystem MCP nếu các tệp là cục bộ.
- **Skills** — nếu quy trình làm việc mang tính tất định (deterministic), một [skill](./part5-creating-skills.md) sẽ rẻ hơn để duy trì.

Hãy dùng MCP khi bạn muốn:
- Một công cụ đã có sẵn máy chủ được cộng đồng duy trì (GitHub, Slack, Postgres, v.v.)
- Một công cụ mà bạn muốn chia sẻ với các agent khác (Claude Code, Cursor, Copilot)
- Một công cụ cần runtime riêng (Node/Go/Rust) mà bạn không muốn nhúng trực tiếp vào Hermes

---

## Xử Lý Sự Cố

| Triệu chứng | Nguyên nhân khả dĩ | Cách khắc phục |
|---------|--------------|-----|
| `MCP server 'github' failed to start` | `npx` không nằm trong PATH của môi trường gateway | Dùng đường dẫn tuyệt đối trong `command:` hoặc đặt `PATH` trong `env:` |
| Máy chủ hiển thị đã kết nối nhưng có 0 công cụ | Quyền truy cập — biến môi trường của máy chủ thiếu token xác thực | Kiểm tra các mục `env:` và đảm bảo các `${VARS}` được tham chiếu tồn tại trong `.env` |
| Công cụ hiện trong CLI nhưng không hiện trong Telegram | Tiến trình gateway có môi trường (env) riêng — khởi động lại nó sau khi thay đổi cấu hình | `hermes gateway restart` |
| Liên tục kết nối lại trên máy chủ HTTP | SSE timeout phía sau reverse proxy | Đặt `proxy_read_timeout 300s` trong nginx/Caddy |
| `sampling not permitted` trong log máy chủ | `allow_sampling: false` (mặc định) | Đặt `allow_sampling: true` trong khối cấu hình của máy chủ |

---

## Tiếp Theo Là Gì

- [Phần 18: Ủy Quyền Cho Các Agent Lập Trình](./part18-coding-agents.md) — sử dụng Claude Code, Codex, và Gemini CLI làm các sub-agent được gọi thông qua Hermes (một số cũng đi kèm máy chủ MCP)
- [Phần 19: Sổ Tay Bảo Mật](./part19-security-playbook.md) — mô hình tin cậy (trust model) của MCP, giới hạn sampling, và cách các MCP không đáng tin được cách ly (quarantine)
- [Phần 12: Bảng Điều Khiển Web](./part12-web-dashboard.md) — bảng điều khiển (panel) MCP Servers
