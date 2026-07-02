# Phần 26: Mixture-of-Agents, Xác Minh & Tự Cải Thiện — Tầng Phán Đoán

<p align="center">
  <img src="./assets/moa-judgment.png" alt="Mixture-of-Agents — verified, self-improving Hermes" width="880">
</p>

*Hermes v0.18.0 (v2026.7.1, "The Judgment Release") nói về việc agent suy nghĩ tốt đến đâu và làm sao nó biết công việc của mình đã thực sự hoàn thành. Ba ý tưởng lớn cùng ra mắt: **Mixture-of-Agents như một model hạng nhất**, **xác minh dựa trên bằng chứng (evidence-based verification)** cho công việc coding và `/goal`, cùng một vòng lặp **tự cải thiện (self-improvement)** có thể nhìn thấy và điều khiển được (`/learn`, `/journey`, và memory graph trên desktop). Phần này chỉ ra cách thực sự sử dụng chúng.*

---

## 1. Mixture-of-Agents — Chọn Một Hội Đồng Như Cách Bạn Chọn Model

MoA từng chỉ là một chế độ (mode) mà bạn bật/tắt. Kể từ v0.18, mọi preset MoA có tên đều là một **virtual model có thể chọn được** dưới một provider `moa` — nó xuất hiện trong bộ chọn model mờ (fuzzy model picker) trên CLI, TUI, desktop, và gateway, ngay cạnh Claude, GPT, và Grok.

```yaml
# ~/.hermes/config.yaml
moa:
  presets:
    my-council:
      references:            # the models that each answer independently
        - anthropic/claude-opus-4.7
        - openai/gpt-5.5
        - xai/grok-4.3
      aggregator: anthropic/claude-opus-4.7   # synthesizes the final answer
```

Sau đó chỉ cần:

```text
/model my-council      # persistent — route every prompt through the ensemble
/moa <prompt>          # one-shot — run one prompt through the default preset,
                       # then restore your previous model
```

Những gì bạn nhận được trong v0.18:

- **Toàn bộ output của từng reference model được hiển thị thành một khối riêng có nhãn** — bạn đọc được từng model đã nghĩ gì *trước khi* aggregator tổng hợp. Hội đồng thảo luận công khai.
- **Câu trả lời của aggregator được stream trực tiếp** thay vì xuất hiện trọn vẹn sau một khoảng im lặng dài.
- **Các reference nhìn thấy toàn bộ trạng thái tool** và được kích hoạt ở mỗi phản hồi của user/tool, nên ensemble hoạt động được ngay giữa vòng lặp agent, chứ không chỉ ở các lượt chat một lần.
- **Lưu trace tùy chọn (opt-in)** — đặt `moa.save_traces: true` để xuất trace đầy đủ của từng lượt ra JSONL phục vụ debug và eval.

### Khi nào nên dùng (và khi nào không)

| Dùng MoA cho | Bỏ qua MoA khi |
|---|---|
| Các quyết định rủi ro cao (kiến trúc, thao tác không thể đảo ngược) | Các vòng lặp agent dùng tool thông thường |
| Bài toán suy luận khó mà các model bất đồng ý kiến | Tác vụ hàng loạt, rẻ tiền, cron job |
| Xem lại plan hoặc diff của một agent khác | Bất cứ điều gì nhạy cảm với độ trễ |
| "Ý kiến thứ hai" dạng one-shot qua `/moa` | Các phiên làm việc dài (bạn trả tiền cho N model mỗi lượt) |

Chi phí tăng theo số lượng reference model — một ensemble gồm ba model frontier tốn xấp xỉ gấp 4 lần token so với một model. Giữ một council preset cho các quyết định cần phán đoán; đừng biến nó thành driver mặc định của bạn.

> **Lưu ý:** context window được xác định dựa trên **aggregator**, và các tác vụ phụ trợ cũng được định tuyến tới aggregator. Hãy chọn một aggregator có context window ít nhất bằng tổng output của các reference của bạn.

---

## 2. Xác Minh — "Hoàn Thành" Nghĩa Là Đã Chứng Minh, Không Phải Chỉ Tuyên Bố

v0.18 dạy Hermes đánh giá việc hoàn thành dựa trên **bằng chứng** thay vì cảm tính:

- **Sổ ghi xác minh coding (coding verification ledger)** — `agent.coding_context` phát hiện các kiểm tra chuẩn (canonical checks) của dự án bạn (test, lint, build) và Hermes ghi lại bằng chứng xác minh khi nó tuyên bố công việc coding đã hoàn thành.
- **Hook `pre_verify`** — gắn thêm các kiểm tra tùy chỉnh phải đạt trước khi agent được phép công bố thành công.
- **verify-on-stop mặc định TẮT** (một lần migration sẽ tinh chỉnh giá trị mặc định) và bỏ qua các chỉnh sửa chỉ liên quan đến tài liệu — hãy bật nó cho các repo mà tiêu chuẩn là "nó compile được và test pass":

```yaml
agent:
  coding_context: true
  verification:
    verify_on_stop: true
    pre_verify: "./scripts/ci-local.sh"
```

### Hợp đồng hoàn thành (completion contracts) cho `/goal`

`/goal` ([Phần 23](./part23-tenacity-stack.md#3-use-goal-for-do-not-stop-until-it-is-done)) đã có thêm **completion contracts**: nêu rõ "hoàn thành" trông như thế nào, và vòng lặp standing-goal sẽ đánh giá dựa trên bằng chứng đó thay vì lời nói của model.

```text
/goal Fix the flaky auth test. Done means: pytest tests/auth passes 5 consecutive runs, no skips.
/goal wait <pid>       # park the goal loop on a background process instead of re-poking the agent
```

Sự khác biệt giữa "tôi nghĩ tôi đã sửa nó" và "test đã pass, đây là bằng chứng." Nếu bạn chạy các phiên `/goal` không giám sát hoặc các worker Kanban, hãy áp dụng completion contract ở mọi nơi — đó là biện pháp phòng vệ tốt nhất trước tình trạng "tự tin tuyên bố hoàn thành nhưng chưa xong."

---

## 3. `/learn` và `/journey` — Tự Cải Thiện Mà Bạn Có Thể Nhìn Thấy

Hai lệnh biến hệ thống skill/memory từ một hộp đen thành thứ bạn có thể điều khiển được:

```text
/learn <anything>      # distill a reusable skill from a directory, a URL,
                       # or the workflow you just walked the agent through
/journey               # a timeline of every memory + skill Hermes has
                       # accumulated — edit or delete any of them in place
```

- `/learn` tự động tuân theo các chuẩn skill trong CONTRIBUTING.md của repo bạn. Việc dạy Hermes một workflow giờ chỉ còn là một lệnh duy nhất, không còn là một phiên viết `skill_manage` thủ công (xem [Phần 5](./part5-creating-skills.md) để biết một skill tốt trông như thế nào — điều đó vẫn còn quan trọng).
- `/journey` hoạt động trên CLI và TUI; ứng dụng desktop bổ sung thêm một **memory graph** — một dòng thời gian dạng radial có thể tương tác của các memory và skill theo thời gian ([Phần 24](./part24-desktop-app.md)).
- Nhánh tự cải thiện sau mỗi lượt (post-turn self-improvement fork) — vòng lặp quyết định có nên lưu một memory hay skill sau các lượt của bạn hay không — giờ đây được định tuyến tới một **auxiliary model**, tóm lược ngữ cảnh (digest context) thay vì phát lại toàn bộ cuộc hội thoại, và tự điều chỉnh nhịp độ của nó — nó chỉ tốn một phần nhỏ chi phí so với trước. Cứ để nó bật.

Bảo trì hàng tháng: mở `/journey`, dọn bớt các memory sai hoặc lỗi thời, và kiểm tra xem các skill được học tự động có khớp với cách bạn thực sự làm việc hay không. Kết hợp với Curator ([Phần 22](./part22-latest-power-moves.md#1-turn-on-curator-before-your-skill-library-becomes-noise)) cho phía skill.

---

## 4. Phân Tán Nền (Background Fan-Out) — Giao Việc Cho Cả Đội Ngũ Và Tiếp Tục Làm Việc

`delegate_task` đã trưởng thành qua v0.17 → v0.18:

```python
# v0.17: one background subagent — returns a handle immediately,
# result re-enters the conversation as a new turn when done
delegate_task(goal="Deep-dive the competitor's pricing page", background=True)

# v0.18: background fan-out — parallel subagents, one consolidated
# turn when ALL of them finish
delegate_task(
    tasks=[
        {"goal": "Audit src/auth for the token-refresh bug"},
        {"goal": "Audit src/billing for the same pattern"},
        {"goal": "Check upstream issues for known reports"},
    ],
    background=True,
)
```

Cuộc trò chuyện của bạn không bao giờ bị chặn; thanh trạng thái CLI/TUI theo dõi các subagent nền đang chạy. Dùng fan-out cho các nhánh nghiên cứu/audit độc lập, và giữ [Kanban](./part23-tenacity-stack.md) cho công việc cần sống sót qua các lần khởi động lại. Các mẫu delegation đầy đủ: [Phần 8](./part8-subagent-patterns.md).

---

## 5. Những Điều Nhỏ Bạn Sẽ Dùng Mỗi Ngày

- **`/prompt`** — mở `$EDITOR` để soạn một prompt nhiều dòng dạng markdown thật, được xếp hàng như tin nhắn tiếp theo của bạn. Ngừng vật lộn với ô nhập liệu một dòng.
- **`/reasoning full`** — suy luận không giới hạn (uncapped thinking) cho phiên hiện tại khi bạn muốn mức độ cân nhắc tối đa.
- **`/timestamps`** + timestamp trong `/history` — xem chính xác thời điểm các lượt đã diễn ra.
- **`/version`** và **`/billing`** — thông tin phiên bản và billing tương tác ngay trong TUI/CLI.
- **Nén tại chỗ (in-place compaction)** giờ là mặc định — việc nén viết lại phiên dưới cùng một session id thay vì chuyển sang một id mới, nên các liên kết `@session` và các tích hợp không còn bị hỏng ở các phiên dài.
- **Thiết lập Blank Slate** — chế độ onboarding tối giản agent: bắt đầu với không có gì được bật và bật từng tool một theo lựa chọn. Lựa chọn đúng đắn cho các máy bị khóa chặt hoặc nhạy cảm về tuân thủ (compliance).

---

## 6. Vận Hành Hermes Cho Một Đội Nhóm — Scale-to-Zero Và Managed Scope

Nếu bạn vận hành Hermes cho nhiều hơn một mình bạn, v0.17/v0.18 đã ra mắt tầng fleet:

- **Scale-to-zero** — gateway ngủ khi rảnh và thức dậy theo yêu cầu; các hành động vòng đời gây gián đoạn (restart, migration, auto-update) sẽ phối hợp một **external drain** để không ai bị cắt ngang giữa lượt làm việc.
- **Managed scope** — cấu hình và secret do quản trị viên ghim (pinned), người dùng không thể sửa, từ `/etc/hermes` thuộc sở hữu root. Ghim tư thế bảo mật (security posture); để người dùng sở hữu phần còn lại.
- **Multiplexed gateway** (tùy chọn) — chạy tất cả các profile trên một tiến trình gateway duy nhất.
- **Automation Blueprints** — các automation có tham số hóa được hiển thị dưới dạng một form trên dashboard, một slash command trong chat, hoặc một cuộc hội thoại — "báo cáo hàng ngày lúc 8 giờ sáng" mà không cần cú pháp cron.
- **Cron continuations** — các job theo lịch có thể tiếp tục trong một thread (có phương án dự phòng DM-mirror), nên một báo cáo cron trở thành một cuộc hội thoại thay vì một tin nhắn cụt lủn.

Kết hợp với xác thực dashboard đã được tăng cường ([Phần 12](./part12-web-dashboard.md)) và [cẩm nang bảo mật Phần 19](./part19-security-playbook.md) trước khi expose bất cứ thứ gì ra mạng.

---

## Danh Sách Kiểm Tra Nâng Cấp (v0.16 → v0.18)

```bash
hermes update --check
hermes backup            # now includes projects.db + kanban boards
hermes update
hermes --version         # expect 0.18.x
```

Sau đó:

1. Định nghĩa một MoA preset và thử `/moa` trên một quyết định thực tế.
2. Bật xác minh cho repo coding chính của bạn và diễn đạt lại các `/goal` đang đứng (standing) của bạn thành các completion contract.
3. Chạy `/journey` một lần — dọn bớt bất cứ thứ gì sai trước khi nó tích lũy thành vấn đề lớn.
4. Thử `/learn` trên workflow gần nhất mà bạn đã giải thích cho agent bằng tay.
5. Nếu bạn đã dùng provider **Gemini CLI OAuth**, hãy migrate: nó đã bị loại bỏ trong v0.18. Dùng một Gemini API key, hoặc provider **Vertex AI** mới nếu tổ chức của bạn chạy Gemini qua GCP ([Phần 9](./part9-custom-models.md)).
6. Kiểm tra lại cấu hình nền tảng: tin nhắn phong phú (rich messages) của Telegram được bật mặc định; iMessage có một đường dẫn không cần Mac thông qua Photon ([Phần 15](./part15-new-platforms.md)).

---

*Chủ đề của Hermes giữa năm 2026: ngừng tin tưởng cảm tính của một model đơn lẻ. Ensemble hóa các quyết định cần phán đoán, xác minh các tuyên bố, và audit những gì agent của bạn nghĩ rằng nó đã học được.*
