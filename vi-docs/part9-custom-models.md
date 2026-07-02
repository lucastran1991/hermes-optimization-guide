# Phần 9: Custom Model Providers (Dùng Bất Kỳ Model Nào Bạn Muốn)

*Hermes hỗ trợ bất kỳ API tương thích OpenAI nào, cùng với các adapter gốc (native) hạng nhất cho Nous Portal, Anthropic, OpenAI/Codex, OpenRouter, AWS Bedrock, Azure AI Foundry, Google Gemini, Google Vertex AI, LM Studio, xAI, Xiaomi MiMo, Kimi/Moonshot, z.ai/GLM, MiniMax, Arcee, GMI Cloud, Tencent TokenHub, Hugging Face, Cerebras, Groq, Fireworks, Vercel AI Gateway, Ollama, các model ảo MoA, và các plugin provider. Đây là cheat sheet ngày 1 tháng 7 năm 2026.*

> **Có gì mới kể từ bản cập nhật hướng dẫn v0.14** — v0.17 đưa **Composer** của Cursor (`grok-composer-2.5-fast`, ngữ cảnh 200K) vào trình chọn OAuth của xAI; v0.18 bổ sung provider **Google Vertex AI** hạng nhất (token OAuth2 được tự động cấp phát và tự làm mới từ một service account — không cần key tĩnh, không hết hạn giữa phiên) và biến mỗi **Mixture-of-Agents preset thành một model có thể chọn được** dưới provider `moa` ([Phần 26](./part26-moa-verification.md)). **Thay đổi phá vỡ tương thích (Breaking):** các provider OAuth Gemini-CLI (`google-gemini-cli`, `google-antigravity`) đã bị **loại bỏ trong v0.18** — hãy chuyển sang dùng `GEMINI_API_KEY` hoặc Vertex AI.

---

## Adapter Gốc (Native) so với OpenAI-Compatible Thông Dụng

Kể từ v0.14.0 (tháng 5 năm 2026), Hermes đi kèm **các adapter gốc (native)** cho một tập hợp lớn các provider, cộng với bề mặt plugin provider cho các backend nằm ngoài cây mã nguồn (out-of-tree). Các adapter gốc biết về các tính năng đặc thù của provider mà một wrapper OpenAI-compatible thông dụng không thể biết:

| Provider | Adapter gốc? | Tính năng đáng chú ý |
|----------|-----------------|-----------------|
| **Nous Portal** | Có | Xác thực qua `hermes model` (không cần API key thô). Mở khóa [Tool Gateway](./part13-tool-gateway.md). |
| **Anthropic** | Có | Prompt caching gốc, extended thinking, tầng ưu tiên `/fast` |
| **OpenAI** | Có | Responses API gốc, các mức reasoning effort, tầng ưu tiên `/fast` |
| **OpenAI Codex OAuth** | Có | Đăng nhập ChatGPT/Codex thông qua `hermes model`, không cần API key |
| **AWS Bedrock** | Có | Converse API, thông tin xác thực IAM, các inference profile liên vùng (cross-region), Bedrock Guardrails |
| **Azure AI Foundry** | Có | Tự động phát hiện các deployment kiểu OpenAI so với kiểu Anthropic và độ dài ngữ cảnh |
| **LM Studio** | Có | Khám phá `/models` cục bộ, xác thực tùy chọn, reasoning transport, kiểm tra `hermes doctor` |
| **xAI / SuperGrok** | Có | OAuth SuperGrok, Grok 4.3 ngữ cảnh 1M, `x_search`, và các tích hợp hình ảnh/STT/TTS của xAI bao gồm cả Custom Voices |
| **Xiaomi MiMo** | Có | Các chế độ reasoning gốc (`low`/`medium`/`high`) được phơi bày dưới dạng cấu hình |
| **Kimi / Moonshot** | Có | Ngữ cảnh 200K+, rất tốt cho việc trích xuất thực thể (entity extraction) của LightRAG (xem [Phần 3](./README.md#part-3-lightrag--graph-rag-that-actually-works)) |
| **z.ai / GLM** | Có | Các model open-weight dùng tool mạnh; phương án dự phòng rẻ tốt cho việc lập kế hoạch/khám phá |
| **Google Gemini (trực tiếp)** | Có | Ngữ cảnh 1M; prompt caching gốc trên Pro; định tuyến model hỗ trợ hình ảnh/video |
| **Google Vertex AI** | Có | Gemini qua service account / ADC GCP của bạn; token OAuth2 tồn tại ngắn hạn được tự động cấp phát và làm mới |
| **MoA (ảo)** | Có | Mỗi Mixture-of-Agents preset là một model có thể chọn — xem [Phần 26](./part26-moa-verification.md) |
| **MiniMax** | Có | API key hoặc OAuth; streaming gốc và TTS |
| **GMI Cloud** | Có | Các model open được host phía sau một provider gốc |
| **Tencent TokenHub** | Có | Định tuyến model Tencent thông qua các alias của TokenHub |
| **Arcee** | Có | Chuyên gia function-calling AFM-4.5, giá rẻ |
| **Cerebras** | Có | Inference tốc độ 2000+ tok/s |
| **Groq** | Có | Llama / Qwen được host, tốc độ nhanh |
| **Fireworks** | Có | Qwen3-Embedding-8B (được khuyến nghị cho LightRAG) |
| **Vercel AI Gateway** | Có | Khám phá model động, metadata giá, attribution |
| **Hugging Face** | Có | Bất kỳ endpoint TGI / TEI nào (tự host hoặc Inference Endpoints) |
| **OpenRouter** | Có | Chuyển tiếp (pass-through) tới hơn 200 model; tôn trọng các đặc thù của adapter gốc khi downstream là một adapter gốc |
| **Ollama** (cục bộ) | Thông dụng | Tương thích OpenAI, không cần xác thực |
| **Provider plugin** | Plugin | Thêm một `ProviderProfile` mà không cần vá lõi Hermes |
| **Bất kỳ thứ gì khác** | Thông dụng | Bất kỳ `base_url` tương thích OpenAI nào |

### OAuth SuperGrok + Grok 4.3

v0.14 biến xAI thành một provider Hermes hạng nhất thay vì chỉ là một key tương thích OpenAI khác. Dùng OAuth SuperGrok khi bạn đã trả tiền cho nó; dùng `XAI_API_KEY` cho tự động hóa tài khoản dịch vụ. Grok 4.3 hiện là lựa chọn cho tìm kiếm trực tiếp/sự kiện thời sự mặc định vì nó kết hợp ngữ cảnh 1M, khả năng truy xuất gốc trên X, và các tích hợp giọng nói/hình ảnh.

```bash
hermes model     # choose xAI / SuperGrok OAuth
```

```yaml
models:
  research_live:
    provider: xai
    model: grok-4.3
    context_tokens: 1048576
tools:
  x_search:
    enabled: true
    auth: oauth
```

Đừng đưa nó vào các cron loop giá rẻ; hãy định tuyến nó một cách rõ ràng cho các sự kiện trực tiếp, các thread trên X, và tổng hợp hàng triệu token.

Hãy chọn adapter gốc khi có sẵn — bạn sẽ nhận được các tính năng đặc thù của provider miễn phí. Chỉ dùng đường OpenAI-compatible thông dụng cho các endpoint chưa có adapter gốc.

### Cheat Sheet Provider (25 tháng 5, 2026)

"Model tốt nhất" chính xác thay đổi theo từng tuần, vì vậy hãy xem đây là một định hướng định tuyến (routing posture) chứ không phải một bảng xếp hạng. Dùng `hermes model` để lấy dữ liệu picker trực tiếp, sau đó chỉ ghim cố định (pin) những gì bạn cần có thể tái lập.

| Nhu cầu | Bắt đầu từ đây | Vì sao |
|------|------------|-----|
| Coding / refactor mặc định | Anthropic Sonnet 5, Claude Code, hoặc Codex OAuth | Độ tin cậy tốt nhất cho công việc nhiều patch; Codex OAuth tránh việc thay đổi API key liên tục |
| Reasoning sâu / mức độ rủi ro cao | GPT-5.5 reasoning hoặc Anthropic Opus 4.7 | Dùng một cách tường minh; đừng biến nó thành mặc định cho các tác vụ cron/hàng loạt |
| Đọc repo hoặc tài liệu ngữ cảnh dài | Gemini 3.1 Pro/Flash, Grok 4.3, hoặc tương đương trên OpenRouter | Cửa sổ ngữ cảnh khổng lồ, đủ rẻ cho map/reduce, video, và tóm tắt |
| Model dùng hàng ngày giá rẻ | Gemini Flash (API key) + Kimi K2.6 + z.ai/GLM | Tỷ lệ chất lượng/chi phí tốt, đặc biệt với định tuyến phụ trợ (auxiliary routing) |
| Ủy ban cho các quyết định khó | Một preset `moa` gồm 2–3 model hàng đầu | Sự cân nhắc đa model có thể thấy được; chi phí ~N×, dùng một cách tiết chế ([Phần 26](./part26-moa-verification.md)) |
| Doanh nghiệp / VPC / tuân thủ | AWS Bedrock hoặc Azure AI Foundry | Xác thực IAM/Azure, guardrail, triển khai riêng tư, kiểm soát audit |
| Cục bộ/riêng tư/offline | LM Studio hoặc Ollama | Không có traffic ra ngoài cloud (egress); rất tốt cho trích xuất, embedding, và bản nháp |
| Lượt tương tác cực nhanh | Cerebras hoặc Groq | Số token/giây rất cao; hữu ích cho phân loại và chat dạng ngắn |
| Sự kiện thời sự / tìm kiếm X | xAI Grok 4.3, `x_search`, hoặc tìm kiếm web dựa trên công cụ | Grok có tìm kiếm X trực tiếp gốc; Tool Gateway có thể bao phủ web rộng hơn |

> Giá và cửa sổ ngữ cảnh thay đổi quá nhanh để hardcode. Hermes hiện lấy danh sách picker của OpenRouter và Nous Portal từ một manifest từ xa, trong khi các API provider cung cấp metadata giá/ngữ cảnh khi có sẵn.

---

### Nous Portal — OAuth, Không Phải API Key

Nous Portal dùng luồng OAuth qua `hermes model` thay vì một API key thô. Sau khi xác thực, thông tin đăng nhập lưu tại `~/.hermes/auth.json` (không bao giờ trong `.env`). Xác thực lại khi nó hết hạn:

```bash
hermes model
# Pick "Nous Portal" → complete the browser OAuth flow
```

Nếu bạn đang dùng gói subscription trả phí, quá trình thiết lập cũng đề nghị bật [Tool Gateway](./part13-tool-gateway.md) — tìm kiếm web, tạo hình ảnh, TTS, và tự động hóa trình duyệt thông qua subscription của bạn, không cần key bổ sung.

### Google: API Key hoặc Vertex AI (Gemini OAuth Đã Biến Mất)

> **Ghi chú di trú (v0.18):** các provider OAuth Gemini-CLI (`google-gemini-cli`, `google-antigravity`) đã bị **loại bỏ**. Nếu cấu hình của bạn vẫn trỏ tới chúng, việc chọn model sẽ thất bại sau khi nâng cấp. Hãy chọn một trong hai đường được hỗ trợ dưới đây.

**Đường 1 — API key (đơn giản nhất).** Đặt `GEMINI_API_KEY` (hoặc `GOOGLE_API_KEY`) và dùng provider Google Gemini gốc. Các key ở gói miễn phí (free-tier) vẫn hoạt động.

**Đường 2 — Vertex AI (dành cho các đơn vị dùng GCP).** Mới trong v0.18: một provider Vertex hạng nhất qua endpoint tương thích OpenAI của Vertex. Vertex không có API key tĩnh — mỗi request cần một token OAuth2 tồn tại ngắn hạn (~1 giờ) được cấp phát từ file JSON service account hoặc Application Default Credentials. Hermes tự cấp phát và tự làm mới các token này cho bạn, để các phiên không còn bị chết giữa chừng khi token hết hạn:

```yaml
providers:
  vertex:
    project_id: ${GOOGLE_CLOUD_PROJECT}
    location: us-central1
    credentials_json: ${GOOGLE_APPLICATION_CREDENTIALS}   # or rely on ADC
```

Dùng Vertex khi tổ chức của bạn đã định tuyến Gemini qua Google Cloud (IAM, quota, audit); dùng API key thông thường ở mọi trường hợp khác.

### Composer của Cursor Qua xAI OAuth

v0.17 đưa `grok-composer-2.5-fast` — model coding nhanh đứng sau Cursor — vào trình chọn model OAuth của xAI với đầy đủ ngữ cảnh 200K. Nếu bạn có subscription xAI Grok, bạn có thể trỏ Hermes tới Composer trực tiếp qua OAuth, không cần API key riêng: gói Grok của bạn, agent loop của Hermes, tốc độ coding của Composer. Đây là một lựa chọn mạnh cho làn (lane) coding nhanh trong bảng định tuyến của bạn.

### AWS Bedrock và Azure AI Foundry — Định Tuyến Doanh Nghiệp Không Cần Proxy Glue

Bedrock dùng Converse API gốc và chuỗi xác thực boto3 thông thường:

```bash
pip install 'hermes-agent[bedrock]'
hermes model
# Choose "AWS Bedrock" → region → model/profile
```

Dùng cái này khi bạn muốn IAM role, Bedrock Guardrails, và các inference profile liên vùng (cross-region) thay vì API key trực tiếp của vendor.

Azure AI Foundry xử lý cả hai kiểu endpoint:

```bash
hermes model
# Choose "Azure Foundry" → paste endpoint + key
```

Hermes thăm dò (probe) endpoint, phát hiện kiểu `/chat/completions` giống OpenAI so với kiểu `/messages` giống Anthropic, khám phá các deployment khi có thể, và lưu `api_mode` phù hợp trong `config.yaml`.

### Remote Model Catalog: Dừng Việc Hardcode Người Chiến Thắng Của Tuần Này

Các trình chọn model của OpenRouter và Nous Portal giờ đây lấy dữ liệu từ:

```text
https://hermes-agent.nousresearch.com/docs/api/model-catalog.json
```

Cache nằm tại `~/.hermes/cache/model_catalog.json`. Nếu manifest bị lỗi, Hermes sẽ dùng lại cache trên đĩa hoặc bản snapshot đi kèm, để việc chọn model vẫn hoạt động ngay cả khi offline.

### Gemini TTS

Gemini hiện là một trong các backend giọng nói thực tiễn cùng với Edge, ElevenLabs, OpenAI, MiniMax, Mistral, NeuTTS, và xAI:

```yaml
tts:
  gemini:
    model: gemini-2.5-flash-preview-tts
    voice: Kore
```

`GEMINI_API_KEY` hoặc `GOOGLE_API_KEY` là đủ. Kết quả trả về dưới dạng PCM, được đóng gói trong WAV một cách tự nhiên (không cần dependency thêm), có thể chuyển đổi tùy chọn sang mp3/ogg qua `ffmpeg`. Hoạt động sẵn cho các tin nhắn thoại (voice bubble) Telegram.

---

## Cấu Trúc config.yaml

Các model được cấu hình trong `~/.hermes/config.yaml`:

> **Lưu ý bảo mật:** Không bao giờ đặt API key thật trực tiếp trong `config.yaml`. Hãy dùng tham chiếu biến môi trường để key ở lại trong `~/.hermes/.env` (nên được `chmod 600` và không bao giờ commit lên git). Bạn cũng có thể dùng `hermes auth` để đặt chúng một cách an toàn.
```yaml
# Default model
model: claude-sonnet-5
provider: anthropic

# Provider configurations
# API keys are loaded from ~/.hermes/.env automatically.
# Set them with: hermes auth
# Or add to ~/.hermes/.env:
#   ANTHROPIC_API_KEY=sk-ant-...
#   OPENAI_API_KEY=sk-...
#   CEREBRAS_API_KEY=csk-...
#   FIREWORKS_API_KEY=fw_...
providers:
  anthropic:
    api_key: ${ANTHROPIC_API_KEY}

  openai:
    api_key: ${OPENAI_API_KEY}

  bedrock:
    region: us-east-2                  # Auth via AWS_PROFILE, env vars, or instance role

  azure-foundry:
    api_key: ${AZURE_FOUNDRY_API_KEY}
    base_url: ${AZURE_FOUNDRY_ENDPOINT}
    api_mode: chat_completions         # Or anthropic_messages; wizard auto-detects

  lmstudio:
    base_url: http://127.0.0.1:1234/v1
    api_key: ${LM_API_KEY}             # Optional if your LM Studio server requires auth

  xai:
    api_key: ${XAI_API_KEY}
    oauth_enabled: true               # SuperGrok OAuth when available
    live_search: true                 # Grok's live X/Twitter search

  xiaomi:
    api_key: ${XIAOMI_API_KEY}
    reasoning_mode: high              # low / medium / high

  moonshot:                           # Kimi
    api_key: ${MOONSHOT_API_KEY}

  zai:                                # z.ai / GLM
    api_key: ${ZAI_API_KEY}

  minimax:
    api_key: ${MINIMAX_API_KEY}

  gmi:
    api_key: ${GMI_API_KEY}

  tencent-tokenhub:
    api_key: ${TOKENHUB_API_KEY}

  arcee:
    api_key: ${ARCEE_API_KEY}

  cerebras:
    api_key: ${CEREBRAS_API_KEY}
    base_url: https://api.cerebras.ai/v1

  fireworks:
    api_key: ${FIREWORKS_API_KEY}
    base_url: https://api.fireworks.ai/inference/v1

  local:
    base_url: http://localhost:11434/v1
    api_key: ollama  # Ollama doesn't require a real key
```

## Thêm Một Custom Provider

Bất kỳ provider nào triển khai API chat completions của OpenAI đều hoạt động:

```yaml
# Add your API key to ~/.hermes/.env:
#   MY_CUSTOM_API_KEY=your-key-here
providers:
  my-custom:
    api_key: ${MY_CUSTOM_API_KEY}
    base_url: https://api.your-provider.com/v1
```

Thêm key thật vào file `.env` của bạn:

```bash
echo "MY_CUSTOM_API_KEY=<your-key-here>" >> ~/.hermes/.env
chmod 600 ~/.hermes/.env
```

Sau đó dùng nó:

```bash
hermes --provider my-custom --model their-model-name
```

## Model Alias (Chuyển Đổi Nhanh)

Thêm các alias để chuyển đổi model mà không cần gõ tên đầy đủ:

```yaml
model_aliases:
  fast:
    model: cerebras/qwen-3-32b
    provider: cerebras
  smart:
    model: claude-opus-4.7
    provider: anthropic
  local:
    model: nemotron:latest
    provider: local
```

Dùng trong chat:

```
/model fast      # Switch to Cerebras Qwen 3 32B
/model smart     # Switch to Claude Opus
/model local     # Switch to local Ollama model
```

## So Sánh Provider (Những Gì Chúng Tôi Thực Sự Dùng)

| Provider | Tốc độ | Chi phí | Tốt Nhất Cho |
|----------|-------|------|----------|
| Cerebras | 3000+ tok/s | Rẻ | Inference nhanh, tác vụ hàng loạt, coding |
| Anthropic | ~100 tok/s | Cao cấp | Reasoning phức tạp, ngữ cảnh dài |
| OpenRouter | Tùy | Tùy | Đa dạng model, provider dự phòng |
| Fireworks | Nhanh | Rẻ | Embedding, các model chuyên biệt |
| Ollama (cục bộ) | Tùy | Miễn phí | Riêng tư, offline, thử nghiệm |

**Thiết lập của chúng tôi:** Cerebras cho tốc độ, Anthropic cho chất lượng, Ollama cho các model cục bộ và embedding.

## Cheat Sheet Định Tuyến Theo Loại Tác Vụ

Dùng những cái này như các mặc định có định hướng riêng (opinionated), sau đó tinh chỉnh với [sách hướng dẫn định tuyến chi phí của Phần 20](./part20-observability.md#cost-routing-playbook-the-one-that-actually-saves-money):

| Tác vụ | Lựa chọn đầu tiên | Dự phòng (rẻ hơn) | Dự phòng (nhanh nhất) |
|------|--------------|--------------------|--------------------|
| Trò chuyện hàng ngày | Anthropic Sonnet 5 | Gemini Flash hoặc z.ai/GLM | Cerebras Qwen 3 |
| Ủy quyền coding | Claude Code / Codex OAuth | OpenCode + Kimi K2.6 | xAI Composer 2.5 (OAuth) |
| Các quyết định phán đoán mức độ cao | Preset ủy ban `moa` ([Phần 26](./part26-moa-verification.md)) | GPT-5.5 reasoning | — |
| Đọc ngữ cảnh dài (>200K) | Gemini 3.1 Pro | Gemini Flash | — |
| Phân loại / phân luồng ưu tiên | Gemini Flash | Cerebras Qwen3 32B | Arcee AFM-4.5 |
| Reasoning (toán học, lập kế hoạch) | GPT-5.5 reasoning | Anthropic Opus 4.7 | z.ai/GLM |
| Sự kiện thời sự / tìm kiếm trực tiếp | xAI Grok 4.3 + `x_search` | Gemini với grounding | Tìm kiếm web Tool Gateway |
| Embedding (LightRAG) | Qwen3-Embedding-8B (Fireworks) | nomic-embed-text (Ollama) | OpenAI `text-embedding-3-small` |
| TTS (giọng nói Telegram) | xAI Custom Voices hoặc Tool Gateway TTS | Gemini Flash TTS | Edge TTS (miễn phí) |
| Vision / video | Gemini 3.1 Pro/Flash | GPT-5.5 multimodal | Claude Sonnet 5 |

---

## Các Vấn Đề Cần Lưu Ý Của Cerebras

Cerebras nhanh nhưng có những điểm cần lưu ý:

1. **Không có system prompt caching.** Mỗi request đều gửi lại toàn bộ system prompt. Hãy giữ nó ngắn gọn.
2. **Giới hạn tốc độ tính theo phút, không phải theo request.** Cần batch cẩn thận.
3. **Một số model không hỗ trợ tool calling.** Kiểm tra trước khi dùng làm model agent chính.
4. **Streaming nhanh nhưng ra từng cụm lớn.** Các phản hồi lớn đến theo từng đợt lớn, không mượt mà liên tục.

Cấu hình:

```yaml
# Set CEREBRAS_API_KEY in ~/.hermes/.env
providers:
  cerebras:
    api_key: ${CEREBRAS_API_KEY}
    base_url: https://api.cerebras.ai/v1
    # Models: qwen-3-32b, llama-4-scout-17b-16e-instruct
```

## Model Cục Bộ (Ollama)

Chạy model cục bộ để inference miễn phí:

```yaml
providers:
  local:
    base_url: http://localhost:11434/v1
    api_key: ollama
```

**Các model cục bộ/mở tốt nhất cho Hermes:**
- **Qwen3-Coder-Next** — làn (lane) coding cục bộ mạnh nhất nếu bạn có 24GB+ VRAM
- **DeepSeek V4-Flash / V4-Pro** — reasoning/coding open-weight mạnh nếu bạn có thể host MoE thoải mái
- **Qwen3.6-27B / 32B** — cân bằng reasoning/coding thực tế cho máy trạm đơn
- **Nemotron 30B** — phương án dự phòng tốt cho mọi trường hợp, vừa với 24GB VRAM

**Cho embedding (miễn phí):**

```yaml
embedding:
  provider: local
  model: nomic-embed-text
  base_url: http://localhost:11434
```

## Chuyển Đổi Lúc Runtime

```
/model cerebras/qwen-3-32b      # Full model path
/model fast                       # Alias
/model                            # Show current model
```

## Model Phụ Trợ (Model Riêng Cho Từng Tác Vụ)

Hermes hỗ trợ các model chuyên dụng cho tám loại tác vụ. Mỗi cái có thể có provider, model, base_url, api_key, và timeout riêng.

| Loại Tác Vụ | Chức Năng | Mặc Định |
|-----------|-------------|---------|
| `vision` | Phân tích hình ảnh/video, hiểu screenshot | auto |
| `web_extract` | Tóm tắt các trang web đã cào (scrape) | auto |
| `compression` | Nén ngữ cảnh (tóm tắt các tin nhắn cũ) | auto |
| `session_search` | Tìm kiếm trong các bản ghi hội thoại quá khứ | auto |
| `approval` | Quyết định có tự động phê duyệt các tool call hay không | auto |
| `skills_hub` | Khám phá và khớp skill | auto |
| `mcp` | Định tuyến tool MCP | auto |
| `flush_memories` | Hợp nhất và dọn dẹp bộ nhớ | auto |

Khi được đặt thành `"auto"` (mặc định), Hermes đi qua một chuỗi phân giải provider: OpenRouter → Nous Portal → Custom endpoint → v.v.

**Cấu hình trong `~/.hermes/config.yaml`:**

```yaml
auxiliary_models:
  # Use a fast cheap model for compression — it's just summarizing
  compression:
    provider: cerebras
    model: qwen-3-32b
    timeout: 30

  # Use a multimodal model for image/video analysis
  vision:
    provider: openrouter
    model: google/gemini-3.1-flash
    timeout: 60

  # Use local model for session search (free, frequent calls)
  session_search:
    provider: local
    model: nemotron:latest
    base_url: http://localhost:11434/v1
    api_key: ollama

  # Everything else stays on auto
  web_extract: auto
  approval: auto
  skills_hub: auto
  mcp: auto
  flush_memories: auto
```

**Tại sao nên bận tâm:**
- **Compression** chạy trên mọi phiên dài. Dùng một model rẻ/nhanh tiết kiệm tiền mà không ảnh hưởng đến chất lượng (tóm tắt không cần Opus).
- **Vision/video** cần một model đa phương thức (multimodal). Nếu model chính của bạn không xử lý được media, hãy đặt cái này thành một model có thể.
- **Session search** được gọi thường xuyên. Một model cục bộ giúp việc này miễn phí.
- **Approval** kiểm soát việc tự động thực thi. Một model nhanh ở đây nghĩa là ít độ trễ hơn trên mỗi lần gọi tool.

## Chuỗi Dự Phòng (Fallback)

Cấu hình dự phòng tự động nếu model chính thất bại:

```yaml
model_fallback:
  - provider: cerebras
    model: qwen-3-32b
  - provider: openrouter
    model: anthropic/claude-sonnet-5
  - provider: local
    model: nemotron:latest
```

Hermes thử lần lượt từng cái theo thứ tự. Nếu Cerebras bị down, nó sẽ chuyển sang OpenRouter, rồi tới cục bộ.

---

*Đừng tự khóa mình vào một provider duy nhất. Model tốt nhất là model đủ nhanh và đủ rẻ cho tác vụ hiện tại.*
