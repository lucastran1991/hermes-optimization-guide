# Phần 3: LightRAG — Graph RAG Thực Sự Hiệu Quả

*Từ "tìm văn bản tương tự" đến "suy luận về các mối quan hệ." Nâng cấp trí tuệ đơn lẻ lớn nhất bạn có thể thực hiện.*

---

> **Xem thêm:** LightRAG là lớp *tri thức*. Kết hợp với [Phần 17: MCP Servers](./part17-mcp-servers.md) (memory-MCP + mem0 cho bộ nhớ đa thiết bị), [Phần 18: Coding Agents](./part18-coding-agents.md) (để ngữ cảnh 1M của Gemini nạp toàn bộ dữ liệu LightRAG để tổng hợp), và [Phần 20: Observability](./part20-observability.md) (theo dõi các lệnh gọi embedding).

## Vấn Đề Với Bộ Nhớ Cơ Bản

Hermes đi kèm với tìm kiếm bộ nhớ dựa trên vector. Nó tìm các tài liệu tương đồng về mặt văn bản với truy vấn của bạn. Điều đó hiệu quả cho các tra cứu đơn giản, nhưng có một giới hạn cơ bản: **nó tìm những gì tương tự, không phải những gì có liên kết.**

Hỏi "những quyết định phần cứng nào đã được đưa ra và tại sao?" thì tìm kiếm vector sẽ trả về các tệp đều nhắc đến GPU. Nó không thể duyệt từ một quyết định → người đưa ra quyết định đó → dự án bị ảnh hưởng → bài học rút ra sau đó.

**Graph RAG khắc phục điều này.** Nó xây dựng một đồ thị tri thức (thực thể + mối quan hệ) song song với cơ sở dữ liệu vector của bạn, sau đó tìm kiếm cả hai đồng thời.

### Naive RAG so với Graph RAG

| | Naive RAG (Mặc định) | Graph RAG (LightRAG) |
|---|---|---|
| **Lập chỉ mục** | Các đoạn văn bản dưới dạng vector | Thực thể, mối quan hệ, VÀ các đoạn văn bản |
| **Truy xuất** | Văn bản tương tự (độ tương đồng cosine) | Tri thức có liên kết (duyệt đồ thị + độ tương đồng) |
| **Trả lời** | "Đây là những gì tài liệu nói về X" | "Đây là cách X liên quan đến Y, ai đã quyết định Z, và tại sao" |
| **Khả năng mở rộng** | Suy giảm khi có 500+ tài liệu (quá nhiều kết quả khớp một phần) | Cải thiện khi có nhiều tài liệu hơn (đồ thị phong phú hơn) |
| **Chi phí** | Rẻ (chỉ embedding) | Đắt hơn ban đầu (LLM trích xuất thực thể) nhưng rẻ hơn khi truy vấn |

---

## LightRAG: Graph RAG Tốt Nhất Cho Sử Dụng Cá Nhân

[LightRAG](https://github.com/HKUDS/LightRAG) là một framework graph RAG mã nguồn mở từ HKU (bài báo EMNLP 2025). Nó cạnh tranh với GraphRAG của Microsoft với chi phí chỉ bằng một phần nhỏ.

**Tại sao chọn LightRAG thay vì các giải pháp khác:**

| Công cụ | Đồ thị | Vector | Web UI | Tự lưu trữ | API | Chi phí |
|------|-------|--------|--------|-------------|-----|------|
| **LightRAG** | Có | Có | Có | Có | REST API | Miễn phí |
| Microsoft GraphRAG | Có | Có | Không | Có | Không | Đắt hơn 10-50 lần |
| Graphiti + Neo4j | Có | Không (riêng biệt) | Không (trình duyệt Neo4j) | Có | Tự xây dựng | Miễn phí nhưng thủ công |
| Tìm kiếm vector thuần | Không | Có | Không | Có | Có | Miễn phí |

LightRAG thực hiện vector DB + đồ thị tri thức **song song** trong quá trình ingestion. Một hệ thống, cả hai khả năng.

---

## Cài Đặt

### Điều Kiện Tiên Quyết

- Python 3.11+
- Một API key LLM cho việc trích xuất thực thể trong quá trình ingestion — **Kimi K2.6** (chất lượng), **Cerebras GPT OSS 120B** (tốc độ), hoặc bất kỳ nhà cung cấp tương thích OpenAI nào
- Một API key embedding — **Fireworks + Qwen3-Embedding-8B** cho embedding 4096 chiều chất lượng cao, hoặc **Ollama + nomic-embed-text** cục bộ để miễn phí

### Cài Đặt LightRAG

```bash
# Tạo một thư mục riêng
mkdir -p ~/.hermes/lightrag
cd ~/.hermes/lightrag

# Clone LightRAG
git clone https://github.com/HKUDS/LightRAG.git
cd LightRAG

# Cài đặt các dependency
pip install -e ".[api]"
```

### Thiết Lập Môi Trường

Tạo `~/.hermes/lightrag/.env`:

**Tùy chọn A — Kimi K2.6 + Fireworks (mặc định chất lượng):**

```bash
# LLM cho trích xuất thực thể (trong quá trình ingestion)
LLM_BINDING=openai
LLM_MODEL=kimi-k2.6
LLM_BINDING_HOST=https://api.moonshot.ai/v1
LLM_BINDING_API_KEY=<your-moonshot-api-key>

# Mô hình embedding (cho lưu trữ vector)
EMBEDDING_BINDING=fireworks
EMBEDDING_MODEL=accounts/fireworks/models/qwen3-embedding-8b
EMBEDDING_API_KEY=<your-fireworks-api-key>
```

**Tùy chọn B — Cerebras GPT OSS 120B + Fireworks (mặc định tốc độ):**

```bash
# LLM cho trích xuất thực thể (trong quá trình ingestion)
LLM_BINDING=openai
LLM_MODEL=gpt-oss-120b
LLM_BINDING_HOST=https://api.cerebras.ai/v1
LLM_BINDING_API_KEY=<your-cerebras-api-key>

# Mô hình embedding (cho lưu trữ vector)
EMBEDDING_BINDING=fireworks
EMBEDDING_MODEL=accounts/fireworks/models/qwen3-embedding-8b
EMBEDDING_API_KEY=<your-fireworks-api-key>
```

**Tùy chọn C — Ollama cục bộ (miễn phí, chất lượng thay đổi):**

```bash
# LLM cho trích xuất thực thể
LLM_BINDING=ollama
LLM_MODEL=qwen3:32b
LLM_BINDING_HOST=http://localhost:11434

# Mô hình embedding
EMBEDDING_BINDING=ollama
EMBEDDING_BINDING_HOST=http://localhost:11434
EMBEDDING_MODEL=nomic-embed-text
```

> **Mẹo bảo mật:** Đặt quyền hạn chế cho tệp này: `chmod 600 ~/.hermes/lightrag/.env`

> **Nơi lấy API key:** Kimi/Moonshot dùng [platform.kimi.ai](https://platform.kimi.ai) và base URL quốc tế `https://api.moonshot.ai/v1`; Cerebras dùng [cloud.cerebras.ai](https://cloud.cerebras.ai); Fireworks dùng [fireworks.ai](https://fireworks.ai).

### Mô Hình Trích Xuất Thực Thể — Nên Dùng Gì

Đây là LLM đọc tài liệu của bạn và trích xuất thực thể cùng mối quan hệ trong quá trình ingestion. Chất lượng ở đây quyết định trực tiếp mức độ tốt của đồ thị tri thức của bạn.

| Mô hình | Tốc độ | Chất lượng | Chi phí | Khuyến nghị |
|-------|-------|---------|------|----------------|
| **Kimi K2.6** | Nhanh | Xuất sắc | Rẻ | Mặc định tốt nhất về chất lượng/chi phí cho trích xuất thực thể qua API tương thích OpenAI của Moonshot |
| **Cerebras GPT OSS 120B** | Cực nhanh | Rất tốt | Rất rẻ | Mặc định sản xuất nhanh nhất hiện tại của Cerebras; dùng khi tốc độ ingestion hàng loạt là ưu tiên |
| Gemini 3.1 Flash | Nhanh | Tốt | Rẻ | Phương án dự phòng vững chắc với ngữ cảnh cực lớn |
| Claude Sonnet 5 | Trung bình | Xuất sắc | Trung bình/cao | Quá mức cần thiết cho ingestion nhưng hữu ích cho các tài liệu rất lộn xộn |
| **Ollama cục bộ** | Tùy vào GPU | Khó đoán | Miễn phí | Khả thi cho ingestion riêng tư/cục bộ; hãy kiểm tra chất lượng đồ thị trước khi tin tưởng nó |

> **Chất lượng embedding rất quan trọng.** Nếu bạn có GPU với 8GB+ VRAM, chạy `nomic-embed-text` cục bộ qua Ollama miễn phí. Nếu bạn muốn chất lượng tốt nhất, dùng Qwen3-Embedding-8B của Fireworks (4096 chiều) — sự khác biệt về độ chính xác tìm kiếm là rất rõ rệt.

---

## Chạy Server

### Khởi Động REST API

```bash
cd ~/.hermes/lightrag/LightRAG

# Khởi động API server (mặc định bind vào localhost)
lightrag-server --host 127.0.0.1 --port 9623
```

Server khởi động tại `http://localhost:9623` với:
- **REST API** cho việc ingestion và truy vấn
- **Web UI** tại `http://localhost:9623/webui` để duyệt đồ thị tri thức
- **Health check** tại `http://localhost:9623/health`

> **Cảnh báo bảo mật:** REST API của LightRAG **không có xác thực tích hợp**. Luôn bind vào `127.0.0.1` (chỉ localhost) — không bao giờ dùng `0.0.0.0`. Nếu bạn cần truy cập từ xa, hãy đặt nó sau một reverse proxy (nginx, Caddy) có xác thực, hoặc dùng SSH tunneling / Tailscale / WireGuard. Bất kỳ ai có thể truy cập cổng này đều có thể truy vấn, ingest, hoặc xóa toàn bộ đồ thị tri thức của bạn.

### Chạy Như Một Dịch Vụ Nền

```bash
# Dùng nohup
nohup lightrag-server --port 9623 > ~/.hermes/lightrag/server.log 2>&1 &

# Hoặc dùng hermes để quản lý nó
hermes background "cd ~/.hermes/lightrag/LightRAG && lightrag-server --port 9623"
```

---

## Ingest Tri Thức Của Bạn

### Cách Hoạt Động Của Ingestion

```
Document (markdown, text, PDF, etc.)
    ↓
Chunking (text split into segments)
    ↓
┌─────────────────┐    ┌──────────────────┐
│ Embedding Model │    │ LLM Entity       │
│ (vector storage)│    │ Extraction       │
└────────┬────────┘    └────────┬─────────┘
         ↓                      ↓
   Vector Database       Knowledge Graph
   (similarity search)   (entity relationships)
```

Với mỗi tài liệu, LightRAG sẽ:
1. Chia nhỏ văn bản và embed nó (vector RAG tiêu chuẩn)
2. Dùng một LLM để trích xuất **thực thể** (người, công cụ, dự án, khái niệm) và **mối quan hệ** (ai quyết định điều gì, cái gì phụ thuộc vào cái gì)
3. Lưu trữ cả hai song song — vector cho độ tương đồng, đồ thị cho cấu trúc

### Ingest Tài Liệu Qua API

```bash
# Ingest một tệp đơn lẻ
curl -X POST http://localhost:9623/documents/upload \
  -F "file=@/path/to/your/document.md"

# Ingest trực tiếp một chuỗi văn bản
curl -X POST http://localhost:9623/documents/text \
  -H "Content-Type: application/json" \
  -d '{"text": "Your knowledge content here...", "description": "Source description"}'

# Ingest tất cả các tệp trong một thư mục
for file in ~/.hermes/memories/*.md; do
  curl -X POST http://localhost:9623/documents/upload -F "file=@$file"
  echo "Ingested: $file"
done
```

### Nên Ingest Những Gì

Cung cấp cho LightRAG mọi thứ mà agent của bạn cần "biết":

- **Tệp bộ nhớ** — `~/.hermes/memories/*.md`
- **Tài liệu dự án** — Các tệp README, tài liệu thiết kế, nhật ký quyết định
- **Tóm tắt trò chuyện** — Các bản tóm tắt hội thoại đã xuất
- **Ghi chú** — Bất kỳ tri thức markdown/văn bản nào bạn muốn có thể tìm kiếm được
- **Comment mã nguồn** — Được trích xuất từ các codebase quan trọng

> **Bắt đầu với các tệp bộ nhớ và tài liệu dự án của bạn.** Những thứ này mang lại giá trị lớn nhất cho đồ thị — các quyết định, con người, dự án, và mối quan hệ giữa chúng.

---

## Truy Vấn Đồ Thị

### Các Chế Độ Truy Vấn

LightRAG có bốn chế độ truy vấn:

| Chế độ | Tốt nhất cho | Cách hoạt động |
|------|----------|-------------|
| `naive` | Tra cứu từ khóa đơn giản | Chỉ tìm kiếm vector (giống RAG cơ bản) |
| `local` | Sự kiện thực thể cụ thể | Duyệt đồ thị tập trung vào thực thể |
| `global` | Mối quan hệ liên tài liệu | Duyệt tập trung vào mối quan hệ |
| `hybrid` | Câu hỏi tổng quát (mặc định) | Kết hợp cả local + global |

### Truy Vấn Qua API

```bash
# Truy vấn hybrid (khuyến nghị mặc định)
curl -X POST http://localhost:9623/query \
  -H "Content-Type: application/json" \
  -d '{
    "query": "What infrastructure decisions were made and why?",
    "mode": "hybrid",
    "only_need_context": false
  }'

# Chế độ local — sự kiện thực thể cụ thể
curl -X POST http://localhost:9623/query \
  -H "Content-Type: application/json" \
  -d '{
    "query": "Tell me about the 5090 PC setup",
    "mode": "local"
  }'

# Chế độ global — khám phá mối quan hệ
curl -X POST http://localhost:9623/query \
  -H "Content-Type: application/json" \
  -d '{
    "query": "How do the different projects relate to each other?",
    "mode": "global"
  }'
```

### Chỉ Lấy Ngữ Cảnh (cho LLM riêng của bạn)

```bash
curl -X POST http://localhost:9623/query \
  -H "Content-Type: application/json" \
  -d '{
    "query": "What models are running on what hardware?",
    "mode": "hybrid",
    "only_need_context": true
  }'
```

Lệnh này trả về các đoạn ngữ cảnh thô mà không tạo câu trả lời — hữu ích khi đưa vào pipeline riêng của bạn hoặc LLM của Hermes.

---

## Tích Hợp Với Hermes

### Tạo Một Skill LightRAG

Tạo `~/.hermes/skills/research/lightrag/SKILL.md`:

```markdown
---
name: lightrag
description: Query the LightRAG knowledge graph for past decisions, infrastructure, projects, and lessons learned. Use before saying "I don't remember."
---

# LightRAG Knowledge Graph

Query the LightRAG knowledge graph for past decisions, infrastructure, projects, and lessons learned.

## When To Use
- User asks about past work, decisions, or "what happened with X"
- Need context on projects, hardware, or configurations
- Remembering lessons learned or past issues
- Any question where you'd say "I don't remember" — use this FIRST

## Usage
```bash
curl -s -X POST http://localhost:9623/query \
  -H "Content-Type: application/json" \
  -d '{"query": "YOUR QUERY", "mode": "hybrid", "only_need_context": true}'
```

## Search Modes
- `hybrid` (default): Combined vector + graph search
- `local`: Entity-focused (specific facts)
- `global`: Relationship-focused (how things connect)
- `naive`: Vector-only (simple lookups)

## Important
- ALWAYS search this before saying "I don't remember"
- Results supersede general knowledge about the setup
- Reference entity names when citing results
```

### Truy Vấn Từ Một Script

Tạo `~/.hermes/skills/research/lightrag/scripts/lightrag_search.py`:

```python
#!/usr/bin/env python3
"""LightRAG search script for Hermes skill integration."""
import json
import sys
import urllib.request

def search(query: str, mode: str = "hybrid") -> str:
    url = "http://localhost:9623/query"
    payload = json.dumps({
        "query": query,
        "mode": mode,
        "only_need_context": True
    }).encode()
    
    req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            result = json.loads(resp.read())
            return result.get("response", result.get("data", str(result)))
    except Exception as e:
        return f"LightRAG query failed: {e}"

if __name__ == "__main__":
    query = " ".join(sys.argv[1:]) if len(sys.argv) > 1 else ""
    if not query:
        print("Usage: lightrag_search.py <query>")
        sys.exit(1)
    print(search(query))
```

---

## Tối Ưu Hóa Chất Lượng Tìm Kiếm

### 1. Điều Chỉnh Trích Xuất Thực Thể

Chất lượng đồ thị của bạn phụ thuộc vào trích xuất thực thể. Trong cấu hình của LightRAG:

```yaml
# Nhiều thực thể hơn = đồ thị phong phú hơn, ingestion chậm hơn
entity_extract_max_gleaning: 5    # Mặc định: 3. Cao hơn = kỹ lưỡng hơn

# Kích thước chunk ảnh hưởng đến mật độ thực thể
chunk_token_size: 1200             # Mặc định: 1200. Nhỏ hơn = nhiều thực thể hơn mỗi tài liệu
chunk_overlap_token_size: 100      # Mặc định: 100
```

### 2. Dùng Embedding Chất Lượng Cao

Chất lượng embedding ảnh hưởng trực tiếp đến độ chính xác tìm kiếm vector:

| Mô hình | Số chiều | Chất lượng | Chi phí |
|-------|-----------|---------|------|
| nomic-embed-text (Ollama) | 768 | Tốt | Miễn phí (cục bộ) |
| Qwen3-Embedding-8B (Fireworks) | 4096 | Xuất sắc | ~$0.001/1K token |
| text-embedding-3-large (OpenAI) | 3072 | Rất tốt | ~$0.00013/1K token |

> **Nếu chất lượng tìm kiếm quan trọng, hãy dùng embedding 4096 chiều.** Sự khác biệt giữa 768 và 4096 chiều giống như sự khác biệt giữa 720p và 4K — bạn sẽ nhận thấy những chi tiết mà đáng lẽ bạn sẽ bỏ lỡ.

### 3. Đánh Chỉ Mục Lại Sau Các Thay Đổi Hàng Loạt

Sau khi ingest một lô lớn tài liệu mới:

```bash
# Kiểm tra số lượng thực thể
curl http://localhost:9623/graph/label/list | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'{len(d)} entities')"
```

### 4. Dùng Đúng Chế Độ Truy Vấn

Đừng luôn mặc định dùng `hybrid`. Hãy dùng:
- `local` khi hỏi về một điều cụ thể ("Cho tôi biết về cấu hình GPU")
- `global` khi hỏi về các mối liên kết ("Các dự án liên quan với nhau như thế nào?")
- `hybrid` cho các câu hỏi tổng quát ("Những quyết định nào đã được đưa ra tuần trước?")

### 5. Giám Sát Và Cắt Tỉa

Web UI tại `http://localhost:9623/webui` cho phép bạn:
- Duyệt đồ thị tri thức trực quan
- Xem các mối quan hệ thực thể
- Xác định các thực thể mồ côi hoặc dư thừa

---

## Web UI

Khi server đang chạy, mở `http://localhost:9623/webui` trong trình duyệt của bạn. Bạn có thể:

- **Tìm kiếm** đồ thị với bất kỳ chế độ truy vấn nào
- **Trực quan hóa** các mối quan hệ thực thể dưới dạng đồ thị mạng lưới
- **Duyệt** tất cả các thực thể và mối liên kết của chúng
- **Kiểm tra** các đoạn thô và tài liệu nguồn của chúng

---

## Xử Lý Sự Cố

### "Connection refused" khi truy vấn

Server chưa chạy. Khởi động nó:
```bash
cd ~/.hermes/lightrag/LightRAG && lightrag-server --port 9623
```

### Ingestion chậm

Trích xuất thực thể bị giới hạn bởi LLM. Để tăng tốc:
- Dùng một mô hình nhanh hơn cho ingestion (Cerebras GPT OSS 120B cho tốc độ, Kimi K2.6 cho chất lượng, Gemini 3.1 Flash làm phương án dự phòng rẻ)
- Xử lý tài liệu theo các lô song song
- Dùng một mô hình cục bộ nếu bạn có năng lực GPU

### Kết quả trống hoặc không liên quan

- Kiểm tra xem tài liệu đã thực sự được ingest chưa (Web UI → entities)
- Thử các chế độ truy vấn khác nhau (`local` so với `global` so với `hybrid`)
- Diễn đạt lại truy vấn của bạn — cụ thể hơn về các thực thể
- Kiểm tra xem mô hình embedding có đang thực sự chạy không (`curl http://localhost:11434/api/tags` cho Ollama)

### Thực thể trùng lặp sau khi ingest lại

LightRAG tự động gộp các thực thể tương tự, nhưng các bản trùng lặp chính xác vẫn có thể xảy ra. Dùng Web UI để dọn dẹp thủ công, hoặc đánh chỉ mục lại từ đầu:
```bash
# Phương án cực đoan: xóa sạch và ingest lại
rm -rf ~/.hermes/lightrag/LightRAG/rag_storage/*
# Sau đó ingest lại tài liệu của bạn
```

---

## Tiếp Theo Là Gì

- **Cần truy cập di động?** → [Phần 4: Thiết Lập Telegram](./part4-telegram-setup.md)
- **Muốn agent tự cải thiện?** → [Phần 5: Tạo Skill Ngay Lập Tức](./part5-creating-skills.md)
