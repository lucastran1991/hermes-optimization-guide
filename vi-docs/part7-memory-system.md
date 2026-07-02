# Phần 7: Hệ Thống Bộ Nhớ (Ba Tầng Thực Sự Hiệu Quả)

*Hermes có ba hệ thống bộ nhớ. Hầu hết mọi người chỉ biết một cái.*

---

## Ba Tầng

| Công cụ | Chức năng | Khi nào kích hoạt | Chi phí |
|------|-------------|---------------|------|
| `memory` | Lưu trữ các sự kiện bền vững xuyên suốt mọi phiên | Sở thích người dùng, môi trường, bài học rút ra | Miễn phí (local) |
| `session_search` | Tìm kiếm bản ghi hội thoại trong quá khứ | "Chúng ta đã quyết định gì về X?" hoặc "Nhớ lúc chúng ta..." | Miễn phí (local) |
| `skill_manage` | Bộ nhớ thủ tục — quy trình làm việc có thể tái sử dụng | Sau khi sửa lỗi, xây dựng thứ gì đó phức tạp, hoặc khám phá ra cách tiếp cận mới | Miễn phí (local) |

Cả ba đều **ưu tiên local-first**. Không gọi API, không tốn chi phí embedding. Chúng dùng SQLite và tìm kiếm full-text.

## Tầng 1: memory (Sự Kiện Bền Vững)

Công cụ `memory` lưu các sự kiện lâu dài, được đưa vào mọi phiên trong tương lai.

**Những gì nên lưu:**
- Sở thích người dùng ("Terp ghét các bước thủ công")
- Chi tiết môi trường ("PC 5090 tại 192.168.1.67, cổng 11434")
- Đặc thù công cụ ("PowerShell cần -Encoding utf8 cho file Unicode")
- Quy ước ổn định ("Dùng OnlyTerp cho các repo GitHub")

**Những gì KHÔNG nên lưu:**
- Tiến độ công việc (dùng session_search để nhớ lại)
- Trạng thái tạm thời (danh sách TODO, trạng thái hiện tại)
- Bất cứ thứ gì thay đổi thường xuyên

**Định dạng:** Giữ tổng các mục dưới 2000 ký tự. Ngắn gọn. Những nội dung này sẽ được chèn vào mỗi tin nhắn.

**Thao tác theo lô (v0.17):** công cụ `memory` áp dụng nhiều thao tác add/update/delete **nguyên tử trong một lần gọi**. Dọn dẹp hàng loạt chỉ mất một lượt round-trip thay vì mười — và một lô bị lỗi sẽ không để bộ nhớ bị sửa dở dang.

```python
# Tốt
memory(action="add", target="memory", content="OpenClaw migrated. LightRAG: 4528 entities, float16 vectors (4096d). Telegram bot 8624585264, group -5216536760.")

# Xấu — quá dài dòng, chỉ liên quan đến một tác vụ cụ thể
memory(action="add", target="memory", content="Today I worked on the lead gen pipeline. First I fixed the API key issue, then I updated the quality gate scoring to use a new algorithm, then I tested with 50 leads...")
```

## Tầng 2: session_search (Truy Hồi Hội Thoại)

`session_search` tìm kiếm trên toàn bộ lịch sử hội thoại xuyên suốt mọi phiên đã qua.

**Hai chế độ:**

```python
# Duyệt qua các phiên gần đây (không tốn chi phí, tức thì)
session_search()

# Tìm kiếm theo chủ đề cụ thể (tìm kiếm full-text local — miễn phí và tức thì kể từ v0.15)
session_search(query="hermes optimization guide github")
session_search(query="LightRAG setup OR embedding model")
```

**Khi nào nên dùng:**
- Người dùng nói "chúng ta đã làm việc này trước rồi" hoặc "nhớ lúc..."
- Bạn nghi ngờ có ngữ cảnh liên quan xuyên phiên
- Bạn muốn kiểm tra xem đã từng giải quyết vấn đề tương tự chưa

**Điểm mấu chốt:** session_search là bản sao lưu gần đây của bạn. memory dành cho các sự kiện vẫn còn quan trọng sau 6 tháng nữa. Nếu một sự kiện chỉ liên quan đến giai đoạn dự án hiện tại, session_search tốt hơn là làm phình to memory.

## Tầng 3: skill_manage (Bộ Nhớ Thủ Tục)

`skill_manage` lưu các quy trình làm việc có thể tái sử dụng dưới dạng skill. Đây là cách Hermes học hỏi.

**Khi nào nên tạo một skill:**
- Sau một tác vụ phức tạp (5+ lượt gọi công cụ)
- Sau khi sửa một lỗi hóc búa
- Sau khi khám phá ra một quy trình không hề đơn giản
- Khi người dùng yêu cầu bạn ghi nhớ một quy trình

```python
# Tạo một skill mới
skill_manage(
    action="create",
    name="supabase-migrate",
    content="---\ndescription: Run Supabase SQL migrations via Management API\n---\n\n# Supabase Migration\n\n1. Read the SQL file from supabase/migrations/\n2. Use Python http.client to POST to Management API...",
    category="devops"
)

# Vá một skill đã có khi phát hiện vấn đề
skill_manage(
    action="patch",
    name="supabase-migrate",
    old_string="Use requests.post",
    new_string="Use http.client (requests has timeout issues with Supabase)"
)
```

**Quy tắc quan trọng:**
- Skill phải có điều kiện kích hoạt — khi nào skill này nên được nạp?
- Skill phải có các bước được đánh số — chính xác cần làm gì?
- Skill phải nêu các cạm bẫy — điều gì có thể sai?
- Vá skill ngay khi phát hiện vấn đề — đừng chờ được yêu cầu

## Chúng Phối Hợp Với Nhau Như Thế Nào

```
Người dùng đặt câu hỏi
    ↓
memory chèn ngữ cảnh bền vững (sở thích người dùng, môi trường)
    ↓
session_search truy hồi các hội thoại liên quan trong quá khứ (nếu cần)
    ↓
skill_manage nạp kiến thức thủ tục (nếu được kích hoạt)
    ↓
Agent có đầy đủ ngữ cảnh → câu trả lời tốt hơn
```

**Thứ bậc:** memory luôn hoạt động. session_search hoạt động theo yêu cầu. skill_manage được kích hoạt khi tác vụ khớp điều kiện.

## Kiểm Toán Những Gì Agent Đã Học (v0.18)

Hệ thống bộ nhớ không còn chỉ để ghi. Hai bổ sung của v0.18 khép kín vòng lặp này:

- **`/journey`** — dòng thời gian của mọi memory và skill mà Hermes đã tích lũy; chỉnh sửa hoặc xóa bất kỳ mục nào tại chỗ. Ứng dụng desktop hiển thị nó dưới dạng **memory graph** có thể tương tác.
- **`/learn <anything>`** — chủ động chắt lọc một skill từ một thư mục, URL, hoặc một quy trình bạn vừa thực hiện, thay vì chờ vòng lặp tự cải thiện chạy ngầm.

Hãy thực hiện một đợt dọn dẹp `/journey` hàng tháng — một memory sai sẽ bị chèn vào mọi phiên trong tương lai và tích lũy dần thành vấn đề lớn. Hướng dẫn đầy đủ: [Phần 26](./part26-moa-verification.md#3-learn-and-journey--self-improvement-you-can-see).

## Các Kiểu Chống Mẫu (Anti-Patterns)

| Đừng Làm Điều Này | Hãy Làm Thế Này Thay Vào Đó |
|--------------|-----------------|
| Lưu tiến độ công việc vào memory | Dùng session_search để nhớ lại |
| Tạo một skill cho tác vụ chỉ dùng một lần | Cứ làm luôn, bỏ qua việc tạo skill |
| Đổ dữ liệu thô vào memory | Lưu các sự kiện ngắn gọn, bền vững |
| Dùng session_search để tìm mọi thứ | Kiểm tra memory trước, nó miễn phí và tức thì |
| Để skill trở nên lỗi thời | Vá chúng ngay khi phát hiện đã lỗi thời |

---

*Bộ nhớ là thứ phân biệt một chatbot vô trạng thái với một agent thực thụ. Hãy sử dụng cả ba tầng.*
