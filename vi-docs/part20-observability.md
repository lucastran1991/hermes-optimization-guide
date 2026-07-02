# Phần 20: Khả năng quan sát & Kiểm soát chi phí — Langfuse, Helicone, Kanban, /usage, Playbook định tuyến

*Bạn không thể tối ưu hóa cái mà bạn không thể nhìn thấy. Hermes theo dõi token, độ trễ, và lỗi một cách gốc, nhưng một khi bạn chạy trên CLI + Telegram + Discord + Google Chat + LINE + SimpleX + Teams + cron + các làn worker Kanban, bạn sẽ cần một stack tracing thực thụ. Phần này thiết lập Langfuse, Helicone, hoặc OpenTelemetry → Phoenix chỉ với một khối cấu hình, sau đó cung cấp cho bạn playbook định tuyến chi phí đã giúp giảm chi phí triển khai thử nghiệm của chúng tôi từ $34 xuống còn $3 cho mỗi lần triển khai tính năng.*

---

## Stack Ba Cấp Độ

```
┌────────────────────────────────────────────────────────┐
│  Level 3 — Hosted tracing (Langfuse / Helicone / Phoenix)│
│  Replayable traces, prompt versioning, evals            │
└────────────────────────────────────────────────────────┘
                            ↑
┌────────────────────────────────────────────────────────┐
│  Level 2 — Hermes internals (/usage, /status, dashboard)│
│  Token counts, rate-limit headers, per-session cost     │
└────────────────────────────────────────────────────────┘
                            ↑
┌────────────────────────────────────────────────────────┐
│  Level 1 — Logs (~/.hermes/logs/*, `hermes logs tail`)  │
│  Raw events, tool invocations, errors                   │
└────────────────────────────────────────────────────────┘
```

Bạn luôn có sẵn Cấp độ 1 và 2. Cấp độ 3 là yếu tố nhân sức mạnh một khi bạn chi hơn $50/tháng cho các lệnh gọi LLM.

---

## Cấp độ 1 + 2 — Những gì đi kèm với Hermes

### `/usage`

```
/usage                              # Current session
/usage 7d                           # Rolling 7-day window
/usage --by-provider                # Breakdown
/usage --by-skill                   # Which skills burn tokens
/usage --by-gateway                 # CLI vs Telegram vs Discord
```

Kể từ v0.9.0, tính năng này giờ đây còn bao gồm cả **rate-limit headers** thu thập được từ mỗi provider — bạn có thể xem "mình đang gần chạm mức trần 5M/phút đến đâu" mà không cần đào sâu vào logs.

### Phân tích trên Dashboard

[Web Dashboard](./part12-web-dashboard.md) có một tab Analytics với:

- Chi phí theo ngày / tuần / tháng
- Token đầu vào so với đầu ra (có nhận biết streaming)
- Mức sử dụng theo từng skill (skill nào thực sự xứng đáng với chi phí token của nó)
- Phân bố lượt gọi tool (bạn có thực sự đang dùng hết tất cả các MCP đó không?)
- Tỷ lệ lỗi theo từng provider (dùng để tinh chỉnh failover)

### `hermes logs`

```bash
hermes logs tail -f                 # Live tail, all gateways
hermes logs search "TokenLimit"     # Grep
hermes logs export --since 7d       # JSONL for offline analysis
```

Kết hợp với `jq` hoặc nạp vào DuckDB để phân tích chi phí theo yêu cầu tùy biến:

```bash
hermes logs export --since 30d --format jsonl \
  | duckdb -c "SELECT gateway, SUM(tokens_out) FROM read_json_auto('/dev/stdin') GROUP BY 1 ORDER BY 2 DESC"
```

---

## Cấp độ 3 — Langfuse (Mặc định được khuyến nghị)

Langfuse là lựa chọn kiểu "mọi thứ ở một nơi": tracing, quản lý prompt, evals, có thể tự host. Nếu bạn chưa chắc nên bắt đầu từ đâu, hãy bắt đầu ở đây. Kể từ v0.12, Langfuse được đóng gói sẵn dưới dạng một plugin Hermes, vì vậy hãy ưu tiên bật plugin đó thay vì tự viết hook thủ công.

### Thiết lập (Hosted Cloud)

```bash
pip install langfuse
hermes plugins enable observability/langfuse
```

Sau đó đặt các key vào `~/.hermes/.env` (plugin đọc biến môi trường, không phải một
khối YAML — không có key `observability:` nào trong `config.yaml`):

```bash
# ~/.hermes/.env  (chmod 600)
HERMES_LANGFUSE_PUBLIC_KEY=pk-lf-...
HERMES_LANGFUSE_SECRET_KEY=sk-lf-...
HERMES_LANGFUSE_BASE_URL=https://cloud.langfuse.com   # or your self-hosted URL

# Optional knobs
HERMES_LANGFUSE_ENV=production            # tags traces with an environment
HERMES_LANGFUSE_RELEASE=v0.14.0           # tags traces with a release
HERMES_LANGFUSE_SAMPLE_RATE=0.5           # 0.0–1.0; lower for very high volume
HERMES_LANGFUSE_MAX_CHARS=12000           # per-field cap before truncation
HERMES_LANGFUSE_DEBUG=true                # verbose plugin logging
```

Lấy các key tại https://cloud.langfuse.com → Settings → API Keys. Gói miễn phí
đáp ứng đủ cho hầu hết người dùng cá nhân. Nếu không có SDK hoặc thông tin xác thực,
plugin sẽ fail-open (các hook sẽ âm thầm không làm gì cả). Xác minh bằng `hermes plugins list` — dòng
tương ứng với `observability/langfuse` sẽ hiển thị `enabled`.

### Langfuse Tự Host

Vì lý do riêng tư hoặc tuân thủ quy định, chỉ cần một lệnh trên VPS với Docker:

```bash
curl -fsSL https://langfuse.com/docker-compose.yml -o langfuse.yml
docker compose -f langfuse.yml up -d
```

Trỏ `host:` vào domain của bạn. Hermes gửi OTLP qua HTTPS, nên Caddy kèm Let's Encrypt sẽ hoạt động ngay.

### Những gì bạn sẽ thấy

Mỗi lượt (turn) của Hermes trở thành một trace. Mỗi trace có các span cho:

- `agent.turn` (gốc)
  - `llm.call` (kèm prompt, completion, token, chi phí, độ trễ)
  - `tool.call` (mỗi tool kèm tham số, kết quả, thời lượng)
    - `llm.call` lồng nhau cho các MCP server có bật sampling
  - `memory.search` (các truy vấn và kết quả trúng)
  - `skill.load` (những skill nào đã được nạp vào)
  - `kanban.task` / `kanban.worker` khi một làn (lane) trên board bền vững nhận hoặc hoàn thành công việc

Có thể phát lại (replay) bất kỳ lượt nào, kiểm tra prompt chính xác, so sánh với các lần chạy trước, đánh giá (eval) các completion so với dataset. Đây là cách bạn tìm ra lượt đã tiêu tốn $4 chỉ để "nên đặt tên biến này thế nào".

---

## Cấp độ 3 — Helicone (Ưu tiên Gateway, Không cần code)

Helicone là lựa chọn kiểu "đổi base URL rồi triển khai luôn". Bạn không cần thêm một SDK tracing — bạn định tuyến traffic LLM của mình qua một proxy để nó quan sát traffic đó.

```yaml
providers:
  anthropic:
    api_key: ${ANTHROPIC_API_KEY}
    base_url: https://anthropic.helicone.ai
    headers:
      Helicone-Auth: Bearer ${HELICONE_API_KEY}
      Helicone-Property-Session: ${HERMES_SESSION_ID}
      Helicone-Property-Skill: ${HERMES_ACTIVE_SKILL}

  openai:
    api_key: ${OPENAI_API_KEY}
    base_url: https://oai.helicone.ai/v1
    headers:
      Helicone-Auth: Bearer ${HELICONE_API_KEY}
      Helicone-Cache-Enabled: "true"   # Automatic prompt caching
```

Hermes chuyển session ID và tên skill dưới dạng các custom property của Helicone, nên bạn có thể lọc trace theo skill/session trong giao diện Helicone. Các cache hit (prompt giống hệt nhau) là miễn phí — riêng điều này đã giảm đáng kể hóa đơn cho các skill lặp lại nhiều.

Chọn Helicone thay vì Langfuse khi:

- Bạn muốn tích hợp mà không cần chạm vào code
- Bạn muốn có prompt caching ở cấp provider miễn phí
- Bạn chủ yếu quan tâm đến dashboard chi phí + độ trễ, không phải quản lý prompt

---

## Cấp độ 3 — OpenTelemetry → Phoenix (Ưu tiên chuẩn hóa)

Nếu bạn đã đang chạy OpenTelemetry (Grafana, Datadog, Honeycomb), hãy trỏ một OTLP
collector vào các biến môi trường `OTEL_*` chuẩn của Hermes. Hermes không
có khối cấu hình `observability: otel:` — việc kết nối được thực hiện thông qua các biến môi trường
chuẩn của OpenTelemetry SDK trong `~/.hermes/.env`:

```bash
# ~/.hermes/.env
OTEL_EXPORTER_OTLP_ENDPOINT=https://otel.yourdomain.com:4318
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
OTEL_EXPORTER_OTLP_HEADERS=authorization=Bearer ${OTEL_TOKEN}
OTEL_SERVICE_NAME=hermes-prod
OTEL_RESOURCE_ATTRIBUTES=deployment.environment=production
```

Nếu bạn muốn các span dạng LLM `gen_ai.*` (theo quy ước OpenInference), hãy bật
plugin của Langfuse và trỏ bộ xuất OTLP của nó vào collector của bạn thông qua tuyến tự host của
Langfuse; hoặc chạy [Arize Phoenix](https://phoenix.arize.com) làm
collector của bạn và để nó nạp trực tiếp luồng OTLP thô.

---

## Playbook Định Tuyến Chi Phí (Cái Thực Sự Tiết Kiệm Tiền)

> **Lưu ý (2026-04):** Hermes trước đây từng đi kèm một khối cấu hình `smart_model_routing:`
> giúp định tuyến các lượt ngắn sang một model rẻ hơn. Tính năng này đã bị gỡ bỏ ở upstream trong
> commit `424e9f36b` ("refactor: remove smart_model_routing feature", #12732)
> sau khi heuristic này bị chứng minh là quá thô trong thực tế. Hermes hiện tại **không có
> bộ phân loại ý định/độ phức tạp tích hợp sẵn** — không có khối `model_routing:`
> với các key `intent:`, `complexity:`, hoặc `match:`. Lời khuyên dưới đây sử dụng các
> yếu tố nền tảng thực sự tồn tại: `model:` / `provider:` chính, khối `auxiliary:` theo từng tác vụ,
> `provider_routing:` dành cho OpenRouter, và `hermes fallback` cho việc chuyển đổi dự phòng. Nếu bạn thấy một ví dụ cấu hình ở đâu đó
> trông giống như một DSL định tuyến, hãy coi đó là một đề xuất tính năng, không phải một tính năng có thật.

### Quy tắc 1: Chọn Model Chính Thông Minh, Sau Đó Đẩy Các Tác Vụ Phụ Sang Model Rẻ Hơn

Phần lớn chi phí phình to của Hermes không đến từ agent chính — mà đến từ các lệnh gọi
phụ trợ (vision OCR, trích xuất web, nén ngữ cảnh, tóm tắt,
phân loại hình ảnh) âm thầm chạy trên bất kỳ model chính nào bạn đang dùng.
Đặt model chính một lần, sau đó trỏ mỗi tác vụ `auxiliary:` sang một model nhanh/rẻ
đủ tốt cho công việc cụ thể đó:

```yaml
# ~/.hermes/config.yaml
# Primary — the model that drives your tool-calling loop.
model: claude-sonnet-5
provider: anthropic

# Per-task auxiliary models. Empty model = provider default.
# These are independent of the primary; setting one here does NOT change
# how your interactive turns are routed.
auxiliary:
  vision:
    provider: openrouter
    model: google/gemini-3-flash
  web_extract:
    provider: openrouter
    model: google/gemini-3-flash
  compression:
    provider: openrouter
    model: google/gemini-3-flash
  summarization:
    provider: openrouter
    model: google/gemini-3-flash

# Failover chain — tried in order when the primary fails with rate-limit /
# overload / connection errors. Manage interactively with `hermes fallback`.
# (Edit via the command, not by hand — it lives in a separate state file.)
```

Trên thực nghiệm với thiết lập của người bảo trì này:

| Điều gì chiếm phần lớn hóa đơn trước đây | Điều gì đã khắc phục nó | Mức tiết kiệm ước tính |
|---|---|---|
| Nén (compression) trên mỗi lượt dài chạy qua Claude Sonnet | `auxiliary.compression` → `google/gemini-3-flash` | ~80% trên các phiên nặng về nén |
| Tool trích xuất web gọi Sonnet cho mỗi trang được fetch | `auxiliary.web_extract` → `google/gemini-3-flash` | ~90% trên các ngày nặng về research |
| Vision OCR trên ảnh chụp màn hình chạy qua model chính | `auxiliary.vision` → `google/gemini-3-flash` | ~85% trên các workflow dashboard/ảnh chụp màn hình |

Đối với chính model chính, đòn bẩy mà Hermes cung cấp cho bạn là lựa chọn
`model:` + `provider:`. Nếu bạn muốn OpenRouter ưu tiên các provider rẻ hơn
cho cùng một model đó, hãy dùng `provider_routing:` (DSL định tuyến duy nhất mà Hermes
thực sự đọc):

```yaml
provider_routing:
  sort: price              # or "throughput" / "latency"
  # only: [anthropic, google]
  # ignore: [deepinfra]
  # order: [anthropic, google, together]
  # require_parameters: true
  # data_collection: deny
```

### Quy tắc 2: Tận Dụng Cơ Chế Caching Bạn Thực Sự Có

Có hai lớp cache tồn tại trong Hermes hiện tại; không lớp nào cần một allow-list theo từng tool.

**Prompt caching của Anthropic** (Claude qua API gốc của Anthropic hoặc OpenRouter)
— được cấu hình toàn cục chỉ với một key:

```yaml
prompt_caching:
  cache_ttl: "5m"          # or "1h" — those are the only two Anthropic tiers
```

Hermes tự động đánh dấu các tiền tố (prefix) ổn định (system prompt, skills, SOUL.md, bộ nhớ
bền vững) là có thể cache. Các lượt đọc từ cache rẻ hơn ~90%, nên với một system
prompt 5K token được tái sử dụng 100 lần/ngày, bạn tiết kiệm được thực sự $2–5/ngày trên các model cỡ Sonnet.
Các công tắc bật/tắt theo từng thành phần như `cache_system_prompt:` / `cache_skills:` /
`min_cache_tokens:` **không** phải là các key cấu hình thật — đừng copy chúng vào.

**Response caching của OpenRouter** (một cơ chế riêng biệt — khớp các request giống hệt nhau
với cùng một response, tính phí bằng không):

```yaml
openrouter:
  response_cache: true
  response_cache_ttl: 300  # seconds; 1–86400
```

### Quy tắc 2B: Theo Dõi Cold Browser Start Trong Logs, Không Phải Trong Spans

Sự phân biệt giữa browser/CDP và computer-use mà bản trước đây mô tả
(`telemetry: spans: browser_cdp: true`) không phải là một khối cấu hình thật. Để bắt được
các lần khởi động browser nguội (cold start) hôm nay, hãy grep logs:

```bash
hermes logs tail -f --level WARNING | grep -iE 'cdp|browser_use|chrome'
```

…hoặc thiết lập một cảnh báo Langfuse trên các span tool `browser_use` / `computer_use` mà
plugin đã sẵn phát ra kèm thời lượng của chúng. Điều thực sự cần theo dõi là các span
`browser_use.launch` kéo dài nhiều giây lặp đi lặp lại, thường có nghĩa là Chrome đã
chết, profile đã thay đổi, hoặc một lần reset sandbox đã xóa mất kết nối
đã được lưu trữ (persisted).

### Quy tắc 3: Dùng Fast Mode Một Cách Có Chọn Lọc

[Fast Mode](./part14-fast-mode-watchers.md) (`/fast`) tốn nhiều tiền hơn trên mỗi token nhưng
giảm độ trễ hàng đợi. Đây là một **công tắc runtime**, không phải một khối YAML — không có
key `fast_mode:` trong `config.yaml`. Hãy dùng slash command:

```
/fast on        # opt the current session into Priority Processing / Fast Mode
/fast off       # back to normal
/fast status    # show the current state
```

Dùng nó cho:

- Các phiên CLI / Telegram / Discord tương tác nơi có người đang theo dõi trực tiếp
- Các luồng thoại (voice) thời gian thực

Đừng dùng nó cho:

- Các tác vụ cron / được lên lịch
- Các job phân tích ban đêm
- Các thao tác hàng loạt (bulk) kéo dài

Đối với các gateway không tương tác (cron, webhook), chỉ cần không chạy `/fast on` từ
những điểm vào đó, và bạn sẽ giữ nguyên mức giá bình thường.

### Quy tắc 4: Ngữ Cảnh Mới Là Chi Phí Thực Sự — Dùng `/compress`

Lượt thứ 100 của hầu hết các phiên tốn gấp 10 lần lượt thứ 10. Hermes đi kèm cơ chế nén
ngữ cảnh tự động dựa theo phần trăm ngữ cảnh đã dùng, không phải theo số token tuyệt đối. Các key
thực sự là:

```yaml
compression:
  enabled: true            # default true; set false to manage context manually
  threshold: 0.50          # trigger when session uses this % of the model's context
  target_ratio: 0.20       # fraction of the threshold kept as recent tail
  protect_last_n: 20       # always preserve the last N messages (≈10 turns) intact
```

Để nén theo yêu cầu có hướng dẫn, hãy dùng slash command:
[`/compress <topic>`](./part14-fast-mode-watchers.md#compress-topic--guided-compression).
Các key như `compression.auto.at_tokens` / `preserve.tool_results_matching` /
`topics_from` từ các bản trước không có thật — đừng copy chúng vào.

Nếu việc nén trên mỗi lượt dài là thứ đang đốt hóa đơn của bạn, hãy định tuyến chính lệnh gọi
nén ra khỏi model chính thông qua `auxiliary.compression`
(xem Quy tắc 1).

### Quy tắc 5: Cảnh Báo Khi Chi Phí Bất Thường

Hermes không có sẵn khối `alerts:` tích hợp — các key cấu hình `cost_spike` / `token_anomaly`
không tồn tại trong loader. Có hai lựa chọn thực sự:

1. **Thiết lập cảnh báo ở lớp tracing của bạn.** Langfuse, Helicone, và Phoenix
   đều hỗ trợ cảnh báo chi phí / tốc độ token theo từng dự án, gửi tới webhook,
   email, hoặc Slack. Đây là nơi phù hợp để đặt chúng — backend tracing của bạn
   thấy được mọi lệnh gọi, kể cả các lệnh gọi bất đồng bộ mà CLI không thấy.

2. **Tự xây dựng từ logs.** Nếu bạn muốn giữ mọi thứ ở local, hãy tail
   `~/.hermes/logs/agent.log` (hoặc `hermes logs tail -f`) vào một script nhỏ
   để tính cửa sổ trượt trên chi phí / token mỗi lượt và gọi ra `hermes send
   telegram …` khi vượt ngưỡng. Gateway Telegram từ
   [Phần 4](./part4-telegram-setup.md) là điểm đến phổ biến nhất.

Dù theo cách nào, hai mẫu hình đáng để bắt là các vòng lặp mất kiểm soát (một skill bị kẹt
trong một cơn lốc thử lại - retry tornado, thường thấy dưới dạng một đợt tăng đột biến số lượng
`tool.call` trên mỗi lượt) và các nỗ lực prompt-injection cố tình đốt token của bạn bằng cách
làm phình to độ dài đầu vào.

---

## Ngăn Chặn Hồi Quy Dựa Trên Eval

Hermes không đi kèm một subcommand `hermes evals` tích hợp sẵn — đó là một
workflow của Langfuse, không phải của Hermes. Sau khi Langfuse đã được kết nối, hãy thực hiện vòng lặp
eval ở phía Langfuse:

1. Trong giao diện Langfuse, xây dựng một **dataset** từ các trace thực tế mà bạn muốn
   bảo vệ (ví dụ: các lượt hỗ trợ Telegram thành công trong tuần trước).
2. Định nghĩa một **evaluator** nhỏ (LLM-as-judge hoặc theo chương trình) cho thuộc tính
   bạn quan tâm — "trả lời đúng câu hỏi của người dùng", "không
   bịa ra một mức giá", "gọi đúng tool".
3. Chạy lại dataset đó trên các model thay thế khác từ Playground của Langfuse hoặc
   qua Python SDK của Langfuse và so sánh điểm số trước khi đưa một model rẻ hơn
   vào production.

Đây là cách bạn tự tin đổi một model $10/Mtok sang một model $0.30/Mtok —
dựa trên thực nghiệm, không phải cảm tính. Xem
[Langfuse Datasets & Experiments](https://langfuse.com/docs/datasets/overview)
để biết API hiện tại.

---

## Tiếp Theo Là Gì

- [Phần 19: Playbook Bảo Mật](./part19-security-playbook.md) — thiết lập cảnh báo chi phí như một tín hiệu phát hiện injection
- [Phần 17: MCP Server](./part17-mcp-servers.md) — chi phí sampling của MCP cũng xuất hiện trong trace
- [Phần 14: Fast Mode](./part14-fast-mode-watchers.md) — công tắc fast-mode được nhắc đến ở trên
- [Phần 6: Nén Ngữ Cảnh](./part6-context-compression.md) — hệ thống nén đứng sau Quy tắc 4
