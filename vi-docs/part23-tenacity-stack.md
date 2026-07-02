# Phần 23: Nền tảng + Bộ công cụ Tenacity — Kanban, Mục tiêu, Bàn giao, Proxy, Cron không dùng Agent

*Hermes v0.14.0 (2026.5.16, "The Foundation Release") không thay thế bộ công cụ Tenacity của v0.13 — nó giúp việc cài đặt dễ hơn, chi phí vận hành rẻ hơn, và khả dụng từ nhiều bề mặt hơn. Hướng đi hiện tại là: cài đặt gọn nhẹ, đưa công việc dài hạn vào Kanban, khóa các phiên làm việc vào `/goal`, bàn giao trực tiếp khi cần đổi model/profile, và giữ các tác vụ tất định (deterministic) ngoài đường đi của LLM.*

---

## 1. Xem Kanban là Lớp Thực thi Bền vững (Durable Execution Layer)

`delegate_task` vẫn hữu ích cho các suy luận fork/join ngắn. Nhưng nó không phải là nguyên thủy (primitive) phù hợp cho công việc cần sống sót qua các lần khởi động lại, chờ con người, thử lại sau khi thất bại, hoặc đi qua nhiều vai trò.

Hãy dùng **Hermes Kanban** cho việc đó:

```bash
hermes kanban init
hermes dashboard   # mở trang Kanban
```

Sau đó tạo công việc từ chat, CLI, hoặc dashboard:

```text
/kanban create "Audit the billing dashboard for stale Hermes v0.12 claims" \
  --assignee researcher \
  --workspace worktree
```

Tại sao điều này quan trọng:

| Mẫu hình cũ | Mẫu hình v0.14 |
|-------------|---------------|
| Subagent cha bị chặn (block) cho đến khi con trả về | Dòng trên board tồn tại lâu dài; cha có thể tiếp tục công việc khác |
| Con thất bại biến mất vào log | Task bị chặn kèm bình luận, ngân sách thử lại, và lịch sử |
| Một worker vô danh | Các assignee có tên, có định danh bền vững |
| Việc nén ngữ cảnh (context compression) có thể xóa dấu vết | SQLite board giữ lại toàn bộ dấu vết kiểm toán |
| Phản hồi từ con người khá vụng về | Bình luận/mở khóa từ con người là hạng nhất (first-class) |

Worker dùng bộ công cụ `kanban_*` (`kanban_show`, `kanban_list`, `kanban_complete`, `kanban_block`, `kanban_heartbeat`, `kanban_comment`, `kanban_create`, `kanban_link`, `kanban_unblock`). Con người dùng `hermes kanban ...`, `/kanban ...`, hoặc dashboard. Cả hai đều thao tác trên cùng một `~/.hermes/kanban.db`.

Các hình dạng board tốt:

- **Lập trình viên đơn lẻ:** phân loại → triển khai → xem xét → PR.
- **Bàn nghiên cứu:** scout thu thập liên kết, analyst tổng hợp, writer soạn thảo.
- **Nhật ký vận hành:** các kiểm tra định kỳ nối thêm bình luận vào cùng một task dịch vụ qua nhiều tuần.
- **Công việc đội nhóm (fleet):** một board cho mỗi khách hàng/tài khoản/tenant; các chuyên gia nhận lane của mình.
- **Nhà máy code:** các lane worker Codex/Claude/OpenCode viết patch; Hermes xem xét trước khi hoàn tất.

---

## 2. Thêm Lane Worker Thay vì Bầy Prompt Khổng lồ

Lane worker là mẫu hình điều phối SOTA cho các thiết lập Hermes nặng về coding. Một lane là một assignee cộng với một hợp đồng spawn (spawn contract):

- Lane profile Hermes: dispatcher spawn `hermes -p <profile>` với các công cụ Kanban giới hạn theo phạm vi claim.
- Lane CLI bên ngoài: Codex, Claude Code, OpenCode, hoặc các worker tùy chỉnh lấy các thẻ đã được gán và báo cáo lại qua API/công cụ Kanban.
- Lane xem xét (review): người hoặc agent reviewer cổng "done" trước khi công việc phụ thuộc được mở khóa.

Định tuyến thực tế:

| Assignee | Dùng cho | Trạng thái hoàn tất |
|----------|---------|--------------------|
| `specifier` | Chuyển thẻ mơ hồ thành tiêu chí chấp nhận | Hoàn tất khi spec đã rõ ràng |
| `researcher` | Thu thập tài liệu, issue, ghi chú phát hành | Bình luận nguồn, rồi bàn giao |
| `codex-worker` | Chỉnh sửa code nhỏ, cô lập | Chặn để chờ Hermes/con người xem xét |
| `claude-code` | Tái cấu trúc lớn, nhiều file | Chặn để chờ xem xét + kiểm thử |
| `reviewer` | Xác minh diff, test, rủi ro | Hoàn tất hoặc mở khóa kèm sửa lỗi |

Giữ Hermes Kanban là nguồn chân lý (source of truth). Đừng để một CLI chuyên biệt âm thầm đánh dấu code là xong chỉ vì nó thoát (exit) thành công.

---

## 3. Dùng `/goal` cho "Không Dừng Cho Đến Khi Xong"

`/goal` cung cấp cho một phiên làm việc một mục tiêu bền vững. Sau mỗi lượt, Hermes kiểm tra xem mục tiêu đã được thỏa mãn chưa; nếu chưa, nó tiếp tục trong ngân sách lượt (turn budget) đã cấu hình.

```text
/goal Refresh this guide to Hermes v0.14, remove stale v0.13-as-current claims, run validation, and open a PR.
```

Dùng nó cho:

- Các đợt rà soát ghi chú phát hành mà agent có thể dừng lại sau file đầu tiên.
- Các cuộc săn lỗi cần vòng lặp tái hiện → kiểm tra → vá → kiểm thử.
- Làm mới tài liệu với nhiều liên kết chéo.
- Các phiên "làm cho cái này sẵn sàng sản xuất" dài, nơi "xong" nghĩa là đã được xác minh, không chỉ đơn thuần là đã thử.

Đừng dùng `/goal` cho các khát vọng mơ hồ như "cải thiện dự án." Hãy cho nó một điều kiện thoát có thể quan sát được: kiểm tra đạt, PR đã mở, bảng benchmark đã cập nhật, thẻ board đã hoàn tất, v.v.

> **Nâng cấp v0.18 — hợp đồng hoàn tất.** `/goal` giờ biên dịch mục tiêu của bạn thành một **hợp đồng hoàn tất (completion contract)** rõ ràng, và mục tiêu chỉ đóng lại khi các điều kiện của hợp đồng được *chứng minh* — không phải khi model tuyên bố là đã xong. Các goal chạy nền cũng chạy dưới cùng các hợp đồng này, và `/goal wait <pid>` sẽ chặn cho đến khi một goal chạy nền cụ thể hoàn tất (hữu ích để xâu chuỗi). Kết hợp với xác minh coding, "xong" giờ có nghĩa là đã được chứng minh. Chi tiết trong [Phần 26](./part26-moa-verification.md#2-verification--done-means-proven-not-claimed).

---

## 4. Checkpoints v2 Thay đổi Mô hình Rủi ro của Bạn

Hermes đã có tính năng an toàn kiểu rollback. Checkpoints v2 của v0.13 vẫn là chuẩn cơ bản cho sản xuất:

- Việc dọn dẹp (pruning) thực sự ngăn các thư mục checkpoint phình to mãi mãi.
- Các rào chắn dung lượng đĩa (disk guardrails) ngăn các snapshot chạy trốn làm đầy một VPS.
- Các shadow repo được dọn dẹp thay vì bị bỏ rơi (orphaned).
- Việc kiểm tra cú pháp (linting) khi patch/ghi file bắt lỗi Python, JSON, YAML, và TOML bị hỏng ngay sau khi ghi file.

Thói quen được khuyến nghị:

```text
Before a risky multi-file edit, confirm checkpointing is enabled.
After the edit, run tests.
If the direction is wrong, /rollback before trying a different strategy.
```

Điều này đặc biệt quan trọng khi các worker Kanban dùng git worktree: checkpoint bảo vệ không gian làm việc của worker, còn git bảo vệ diff có thể xem xét.

---

## 5. Dùng Cron `no_agent` cho Watchdog

Không phải mọi công việc theo lịch (scheduled job) đều cần một LLM. Cron từ v0.13+ có thể chạy ở **chế độ không dùng agent (no-agent mode)**: thực thi một script theo lịch, gửi stdout nếu có gì đó cần nói, và không tốn token nào.

Dùng chế độ no-agent cho:

- Cảnh báo dung lượng đĩa.
- Kiểm tra uptime.
- Kiểm tra sự hiện diện của backup.
- Bộ dò hỏi "CI có thất bại không?".
- Cảnh báo ngưỡng chi phí/ngân sách.

Mẫu hình:

```yaml
cron:
  - name: disk-watchdog
    schedule: "*/15 * * * *"
    mode: no_agent
    command: "df -h / | awk 'NR==2 && $5+0 > 85 {print \"Disk usage high: \"$5}'"
    notify: telegram_private
```

Giữ cron dùng LLM cho các công việc cần phán đoán, tổng hợp, hoặc dùng công cụ. Dùng no-agent cho các kiểm tra tất định.

---

## 6. Định tuyến Media đến Model Thực Sự Hiểu Nó

v0.13+ bổ sung đường đi công cụ `video_analyze` cho Gemini và các nhà cung cấp đa phương thức tương thích. Đừng xem video như "chỉ là một tệp đính kèm khác" trên một model văn bản.

Dùng nó cho:

- Bản ghi cuộc họp: mục hành động, phản đối, quyết định, dấu thời gian.
- Báo cáo lỗi UI: "xem video tái hiện và xác định khung hình lỗi đầu tiên."
- Xem xét bảo mật: kiểm tra bản ghi màn hình mà không đổ dữ liệu riêng tư thô vào bộ nhớ.
- Phân loại hỗ trợ khách hàng: phân loại clip của khách trước khi chuyển lên con người.

Mẫu hình:

```yaml
auxiliary_models:
  vision:
    provider: google
    model: gemini-3.1-pro
  video:
    provider: google
    model: gemini-3.1-pro
```

Đối với phản hồi giọng nói, xAI Custom Voices giờ có thể đứng cạnh TTS của Edge/OpenAI/Gemini/MiniMax:

```yaml
tts:
  provider: xai
  voice: ${XAI_CUSTOM_VOICE_ID}
  require_private_channel: true
```

Giữ các giọng nói được nhân bản (cloned voices) chỉ dùng trong kênh riêng tư trừ khi bạn có sự đồng ý rõ ràng và chính sách công bố rõ ràng.

---

## 7. Cập nhật Mô hình Tư duy về Nền tảng và Provider

v0.14 đẩy các bề mặt plugin/provider xa hơn:

- **Nền tảng:** Google Chat giờ có thêm Teams đầu-cuối, LINE, và SimpleX Chat, đưa gateway lên hơn 22 nền tảng.
- **Provider:** các provider model có thể được phát hành dưới dạng plugin, SuperGrok OAuth giờ là hạng nhất (first-class), và `hermes proxy` có thể phơi bày các provider dùng OAuth qua một endpoint cục bộ tương thích OpenAI.

Quy tắc vận hành:

1. Giữ các plugin đóng gói sẵn/của người dùng ở chế độ tự chọn tham gia (opt-in).
2. Giữ các plugin cục bộ theo dự án ở trạng thái vô hiệu hóa trừ khi repo đáng tin cậy.
3. Ưu tiên các plugin provider gốc (native) hơn các shim tương thích OpenAI chung khi chúng phơi bày caching, reasoning, media, hoặc auth đặc thù của provider.
4. Chạy lại `hermes plugins list` và `hermes model` sau mỗi bản phát hành lớn; các menu trực tiếp thay đổi nhanh hơn tài liệu tĩnh.

---

## 8. Danh sách Kiểm tra Nâng cấp từ v0.13 lên v0.14

```bash
hermes update --check
hermes backup
hermes --version
pip install -U hermes-agent
hermes plugins list
hermes model
hermes proxy --help
```

Sau đó xác minh các đường đi đặc thù của v0.14:

- Xác nhận `pip install hermes-agent` hoặc bản cài từ mã nguồn của bạn phân giải mà không kéo theo các adapter nặng không dùng đến.
- Đăng nhập vào OAuth SuperGrok/Claude/OpenAI chỉ khi bạn dùng các gói thuê bao đó, sau đó kiểm thử `hermes proxy` trên loopback.
- Chạy một truy vấn `x_search` từ một phiên dùng một lần (disposable) nếu bạn dựa vào tín hiệu X/Twitter.
- Nếu bạn dùng Teams, xác minh xác thực Graph, việc nhận webhook, và việc gửi đi đầu-cuối.
- Nếu bạn phơi bày LINE hoặc SimpleX, giữ chúng trong một profile cách ly (quarantine) cho đến khi định danh và định tuyến phê duyệt được chứng minh.
- Dùng `/handoff` trong một phiên dùng một lần để chuyển từ một model rẻ sang một profile suy luận sâu mà không mất ngữ cảnh.
- Kiểm tra lại các đường đi bền vững của v0.13: Kanban, `/goal`, Checkpoints v2, cron no-agent, và các mặc định về ẩn danh (redaction).

---

## 9. Bộ Công cụ Mạnh mẽ Hiện tại

Đối với một triển khai Hermes nghiêm túc vào tháng 5/2026:

1. **Cài đặt từ PyPI/mã nguồn với phụ thuộc lười (lazy deps)** để máy chỉ mang theo các adapter thực sự dùng đến.
2. **Dashboard** cho cấu hình, plugin, Kanban, phân tích, profile, và Chat.
3. **Kanban** cho công việc đa agent bền vững.
4. **`/goal` + `/handoff`** cho mục tiêu bền vững và leo thang model/profile trực tiếp.
5. **`hermes proxy`** cho Codex/Aider/Cline/Continue dùng các gói thuê bao dựa trên OAuth.
6. **Grok 4.3 / Gemini 3.1** cho nghiên cứu triệu-token và các lane media.
7. **MCP** cho công cụ, với ranh giới tin cậy và sampling nghiêm ngặt.
8. **Lane agent coding** cho công việc code, không phải một prompt Hermes khổng lồ.
9. **Sandbox/worktree từ xa** để cô lập.
10. **Langfuse/Helicone/Phoenix + cron no-agent** cho trace, ngân sách, và watchdog tất định.

Nếu bạn chỉ áp dụng một mẫu hình bền vững, hãy áp dụng Kanban. Nếu bạn chỉ áp dụng một mẫu hình v0.14, hãy áp dụng `hermes proxy` cho các công cụ coding dựa trên OAuth và giữ nó chỉ ở loopback.
