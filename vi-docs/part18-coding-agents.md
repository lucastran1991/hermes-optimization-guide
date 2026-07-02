# Phần 18: Giao Việc Cho Các Coding Agent — Claude Code, Codex, Gemini CLI, OpenCode

*Nước cờ chủ lực của Hermes dành cho lập trình viên không phải là tự viết code — mà là **điều phối** các agent lập trình chuyên biệt ngay từ Telegram chat hoặc Kanban board của bạn. Điều khiển Claude Code, Codex, Gemini CLI, OpenCode, và các lane Kimi/GLM giá rẻ từ điện thoại trong khi Hermes giữ state, memory, approval, và các cổng review.*

---

## Tại Sao Nên Giao Việc Thay Vì Tự Làm

Hermes rất giỏi về suy luận, memory, hội thoại, và workflow. Nhưng nó *không* phải là công cụ tốt nhất cho việc sinh code đa file kéo dài. Các agent chuyên biệt về lập trình gồm:

| Agent | Điểm mạnh | Mô hình xác thực |
|-------|-----------|------------|
| **Claude Code** | Làm PR không cần giám sát tốt nhất, refactor lớn, viết test, review; Week 20+ agent view, `/goal`, và chế độ Opus 4.7 nhanh khiến nó thành lane cao cấp | OAuth Pro/Max hoặc `ANTHROPIC_API_KEY` |
| **Codex** (OpenAI) | Vòng lặp phản hồi sandbox nhanh, săn bug, sửa đổi nhỏ/vừa; v0.133+ mặc định xử lý goal tốt và chạy sạch qua `hermes proxy` | OAuth qua CLI `openai`, `OPENAI_API_KEY`, hoặc `hermes proxy` |
| **Gemini CLI** | Context 1M và quét đa phương thức repo/tài liệu; v0.43 cải thiện chỉnh sửa chính xác, import/export session, và hành vi OAuth trên Linux headless | OAuth qua `gemini auth`; với việc dùng model-provider thông thường, Hermes dùng `GEMINI_API_KEY` hoặc Vertex AI ([Phần 9](./part9-custom-models.md)) |
| **OpenCode** (anomalyco) | Mã nguồn mở, định tuyến đến Kimi K2.6 / GLM / MiMo với chi phí rẻ | Mang theo bất kỳ provider key nào |
| **Aider** | Chỉnh sửa git chính xác, tốn ít token nhất; hoạt động tốt qua `hermes proxy` | Mang theo bất kỳ provider key hoặc proxy cục bộ nào |

Hermes giữ state, memory, hội thoại, approval, vòng đời Kanban, và tích hợp nền tảng; mỗi chuyên gia làm việc mà nó giỏi nhất. Bạn có một control plane, nhiều agent.

---

## Điều Kiện Tiên Quyết

```bash
# Claude Code
npm install -g @anthropic-ai/claude-code
claude auth login                 # Hoặc set ANTHROPIC_API_KEY

# Codex
npm install -g @openai/codex-cli
codex auth login

# Gemini CLI
npm install -g @google/gemini-cli
gemini auth                       # Chỉ cần khi giao việc trực tiếp cho Gemini CLI

# OpenCode (ưu tiên biến thể Go cho Hermes)
curl -fsSL https://opencode.ai/install.sh | bash
opencode auth                     # BYOK

# Aider
pipx install aider-chat
```

Kiểm tra từ bên trong Hermes:

```
/skill claude-code
/skill codex
/skill gemini-cli
```

Mỗi skill chạy `--version` và `auth status` để xác nhận agent có thể truy cập được.

---

## Chế Độ 1: Print Mode (Ưu Tiên Cho Hầu Hết Các Tác Vụ)

Print mode là non-interactive — chạy một lần, trả về kết quả, thoát. Không có PTY, không cần quản lý prompt approval, capture stdout sạch sẽ. Lý tưởng cho 80% tác vụ dạng "đây là một thay đổi, quay lại khi xong."

### Từ Một Skill (Khuyến Nghị)

Hermes đi kèm skill `claude-code` xử lý việc thiết lập env, cờ allowed-tool, và khôi phục lỗi:

```
/claude-code refactor src/auth/ to use the new JWT rotation helper
```

Lệnh này sẽ chạy:

```bash
claude -p "refactor src/auth/ to use the new JWT rotation helper" \
       --allowedTools "Read,Edit,Bash" \
       --max-turns 20 \
       --output-format json
```

Capture JSON, phân tích file diff, đăng tóm tắt lại vào thread Telegram/Discord/Slack của bạn kèm link đến git diff.

### Giao Việc Song Song

Cần làm ba việc cùng lúc? Bắn cả ba đi luôn:

```
In parallel:
1. /claude-code write unit tests for src/payments/
2. /codex optimize the hot path in worker.ts
3. /gemini-cli audit dependencies in package.json for security
```

Hermes chạy chúng trong ba slot subagent độc lập, stream tiến trình, và tổng hợp kết quả.

### Định Tuyến Chi Phí Theo Loại Tác Vụ

Mỗi chuyên gia có một điểm mạnh riêng. Hãy để Hermes định tuyến:

| Tác vụ | Chuyên gia phù hợp | Lý do |
|------|-----------------------|-----|
| Refactor lớn trên 10+ file | Claude Code + Sonnet 5/Opus 4.7 | Giỏi nhất trong việc chỉnh sửa đa file kéo dài |
| Tái tạo lỗi + sửa lỗi trong một file duy nhất | Codex + GPT-5.5/Codex | Vòng quay sandbox nhanh |
| "Giải thích codebase này" | Gemini CLI + Gemini 3.1 Pro | Context 1M nuốt trọn cả repo |
| Chỉnh sửa hàng loạt với diff xác định | Aider | Tốn ít token nhất, gốc git |
| Bất cứ điều gì trong ngân sách hạn hẹp | OpenCode + Kimi K2.6 / GLM | Rẻ hơn nhiều so với các model hàng đầu cho các chỉnh sửa thường ngày |

Một `~/.hermes/config.yaml` hợp lý:

```yaml
delegation:
  default: claude-code
  routing:
    - match: { type: refactor, files_changed_gte: 5 }
      agent: claude-code
    - match: { type: bugfix, single_file: true }
      agent: codex
    - match: { type: explore, repo_tokens_gte: 200000 }
      agent: gemini-cli
    - match: { type: dependency_audit }
      agent: gemini-cli
    - match: { budget: low }
      agent: opencode
      model: moonshot/kimi-k2.6
```

## Chế Độ 1B: Kanban Worker Lanes (Ưu Tiên Cho Công Việc Dài Hạn)

Với công việc cần sống sót qua các lần khởi động lại, review của con người, retry, hoặc bàn giao nhiều lần, hãy đặt coding agent phía sau [luồng Kanban của Phần 23](./part23-tenacity-stack.md#2-add-worker-lanes-instead-of-giant-prompt-swarms):

```text
/kanban create "Fix flaky checkout tests and open a PR" \
  --assignee codex-worker \
  --workspace worktree
```

Các mặc định tốt:

- `codex-worker` cho các sửa lỗi nhỏ, cô lập; thoát thành công sẽ chặn lại để chờ Hermes/con người review thay vì tự động hoàn tất.
- `claude-code` cho refactor đa file; yêu cầu test và review trước khi đánh dấu hoàn thành.
- `gemini-cli` cho các thẻ audit quy mô repo, chỉ nên tạo comment/spec, không phải commit.
- `reviewer` như một lane riêng biệt để "agent đã viết code" và "công việc đã hoàn thành" luôn là hai trạng thái khác nhau.

Dùng print mode cho các câu trả lời nhanh, một lần. Dùng Kanban lane cho bất cứ thứ gì mà bạn sẽ xấu hổ nếu để mất giữa chừng.

---

## Chế Độ 2: Thread-Bound Interactive Sessions (Mẫu OpenClaw)

Điều bạn thực sự muốn trên điện thoại: một topic Telegram tên "Claude Code" nơi mọi tin nhắn đều đi vào một session Claude Code bền vững. Không cần giải thích lại ngữ cảnh. Không cần khởi tạo lại. Chỉ cần chat trực tiếp với coding agent, trong khi Hermes xử lý phần transport, memory, và voice-to-text.

Mẫu này hữu ích cho lập trình cặp đôi (pair-programming) qua chat. Với công việc không cần giám sát, hãy ưu tiên Kanban worker lane để trạng thái tác vụ và các cổng review sống sót qua khởi động lại. Quy trình tương tác:

```bash
# Trong Telegram, tạo một topic, sau đó từ CLI hoặc dashboard:
hermes bind-thread <thread-id> --runtime claude-code --cwd ~/projects/myapp
```

Từ thời điểm đó:
- Mọi tin nhắn trong topic sẽ đi đến một session Claude Code bền vững
- Việc chỉnh sửa file diễn ra trong `~/projects/myapp` trên host của Hermes
- Các subagent điều phối có thể tự sinh worker riêng nếu `max_spawn_depth` cho phép
- Các worker chạy song song phối hợp trạng thái file thay vì ghi đè mù quáng lên nhau
- `/unbind` trong topic sẽ tách ra và quay lại chat Hermes bình thường
- `/runtime gemini-cli` hoán đổi runtime mà không làm mất thread

Cách bind tương tự cũng hoạt động với Codex, Gemini CLI, OpenCode, và bất kỳ coding agent tương thích ACP nào.

**Điểm cộng thực thi từ xa:** kết hợp với [tính năng remote sandbox](./part21-remote-sandboxes.md) và coding agent chạy trên một host Modal/Daytona/SSH — điện thoại của bạn điều khiển, một máy khỏe từ xa làm việc.

---

## Cập Nhật Công Cụ Agent (25 tháng 5, 2026)

- **Claude Code Week 20+**: agent view, `/goal`, và Opus 4.7 nhanh hơn khiến nó trở thành worker lane cao cấp tốt nhất cho các PR quan trọng.
- **Codex v0.133+**: goal được bật mặc định; hãy trỏ nó vào `hermes proxy` khi bạn muốn OAuth ChatGPT/Codex mà không cần thêm API key khác.
- **Gemini CLI v0.43**: cải thiện điều hướng chỉnh sửa chính xác, export/import session, và sửa lỗi OAuth headless khiến nó an toàn hơn khi làm reader quy mô repo.
- **Zed ACP Registry**: v0.14 expose Hermes qua `uvx`/ACP để Zed và các editor nhận biết ACP khác có thể điều khiển Hermes trực tiếp.
- **Aider/Cline/Continue**: tất cả đều hưởng lợi từ `hermes proxy` vì chúng chỉ cần một base URL tương thích OpenAI.

---

## ACP: Giao Thức Làm Cho Điều Này Trở Nên Khả Thi

Agent Client Protocol (ACP) đối với coding agent giống như MCP đối với công cụ — một transport chuẩn để một agent giao việc cho agent khác. Hermes hỗ trợ ACP cả với vai trò client lẫn server:

- **Với vai trò ACP client:** Hermes gọi Claude Code / Codex / Gemini như các subagent qua endpoint ACP của chúng.
- **Với vai trò ACP server:** bạn có thể điều khiển Hermes từ một agent nhận biết ACP khác (Cursor, Zed, hoặc một instance Hermes khác).

```yaml
# ~/.hermes/config.yaml
acp:
  enabled: true
  server:
    listen: 127.0.0.1:41212          # Chấp nhận ACP đến từ các editor
  clients:
    claude-code:
      command: claude
      args: ["--acp"]
    codex:
      command: codex
      args: ["--acp"]
    gemini-cli:
      command: gemini
      args: ["--acp"]
```

Công cụ `/delegate_task` sau đó sẽ chọn một ACP client dựa trên quy tắc `delegation.routing` và stream tiến trình qua một WebSocket duy nhất.

---

## Vệ Sinh Git Khi Các Agent Chia Sẻ Workspace

Cạm bẫy số 1 khi điều phối coding agent là hai agent cùng chạm vào một file. Các biện pháp bảo vệ:

```yaml
delegation:
  git:
    isolate_branches: true            # Mỗi lần giao việc có một branch riêng
    branch_prefix: devin/             # Dùng quy ước của riêng bạn
    auto_commit: true                 # Commit trước khi bàn giao lại
    require_clean_tree: true          # Từ chối nếu working tree bị bẩn (dirty)
  locks:
    strategy: file-level              # Hoặc "workspace" nếu bạn muốn serialize hoàn toàn
```

Hermes tạo `devin/claude-code-1723487-refactor-auth`, chạy chuyên gia ở đó, commit, trả về tên branch, và để quyết định merge cho bạn. Cách làm tương tự cũng áp dụng cho giao việc song song — mỗi agent có branch riêng của mình.

---

## Chính Sách Approval

Coding agent chạy lệnh shell và ghi file. Bạn cần một chính sách approval, nếu không bạn sẽ mất cả cuối tuần để debug một lệnh `rm -rf node_modules` vô tình xảy ra ở sai thư mục.

```yaml
delegation:
  approval:
    default: prompt                   # Prompt ở mỗi lần ghi
    trusted_agents:
      - claude-code                   # Các agent này kế thừa tư thế approval của cha
    auto_approve_read: true           # Công cụ chỉ đọc không bao giờ prompt
    denylist:
      - "rm -rf"
      - "git push --force"
      - "curl * | bash"
```

Xem [Phần 19](./part19-security-playbook.md#layer-2-dangerous-command-approval) để biết toàn bộ câu chuyện. Việc kế thừa bỏ qua approval xuất hiện từ v0.10 ([Phần 16](./part16-backup-debug.md#approval-bypass-for-trusted-subagents)) — dùng nó cho các chuyên gia đáng tin cậy, không phải cho mọi agent.

---

## Công Thức: Review PR Của Tôi Từ Telegram

```
You (Telegram): /review_pr myorg/myapp#342
Hermes: *runs the `github-pr-review` skill*
  1. Pulls the PR diff via GitHub MCP
  2. Sends to Claude Code with --allowedTools "Read" --max-turns 5
  3. Claude Code returns a structured review
  4. Hermes posts a GitHub PR comment with the review
  5. Replies in Telegram with a summary + link
```

Nguồn skill: `~/.hermes/skills/github-pr-review/SKILL.md` (đi kèm sẵn, cộng với các biến thể do agent tạo ra xuất hiện sau khi bạn dùng nó vài lần).

---

## Công Thức: Bảo Trì Cron Hàng Đêm

```yaml
# ~/.hermes/cron.yaml
- name: weekly-dep-audit
  schedule: "0 3 * * 1"                # Thứ Hai 3 giờ sáng
  task: |
    /gemini-cli audit package.json for security advisories
    If any CRITICAL, open a GitHub issue in this repo with the list
  notify: telegram:#engineering
```

Hermes chạy việc giao việc mà không cần giám sát, context 1M của Gemini đọc toàn bộ lockfile, một GitHub MCP mở issue. Bạn thức dậy và có một vé triage, không phải một CVE bất ngờ.

---

## Tiếp Theo Là Gì

- [Phần 17: MCP Servers](./part17-mcp-servers.md) — lớp *công cụ* mà các coding agent này sử dụng
- [Phần 19: Security Playbook](./part19-security-playbook.md) — khóa chặt các agent thực thi lệnh shell
- [Phần 21: Remote Sandboxes](./part21-remote-sandboxes.md) — chạy coding agent trên một host Modal/Daytona/SSH từ điện thoại của bạn
- [Phần 8: Subagent Patterns](./part8-subagent-patterns.md) — các nguyên lý giao việc nền tảng
