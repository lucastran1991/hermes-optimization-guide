# Phần 5: Kỹ Năng Tức Thời (Để Hermes Tự Xây Dựng Playbook Của Riêng Nó)

*Yêu cầu Hermes tạo một skill mới, và nó sẽ lưu quy trình đó vĩnh viễn — không cần chỉnh sửa file thủ công.*

---

## Skills Là Gì

Skills là kiến thức về quy trình — các hướng dẫn từng bước dạy Hermes cách xử lý các tác vụ cụ thể. Không giống memory (mang tính sự kiện), skills là các **hướng dẫn cách làm** mà agent tự động tuân theo.

> **Xem thêm:** Skills kết hợp tự nhiên với [MCP Servers (Phần 17)](./part17-mcp-servers.md) — skills mã hóa quy trình làm việc *của bạn*, MCP servers bổ sung *các công cụ bên ngoài*. Kết hợp chúng lại: một skill gọi GitHub MCP để mở issue, một Postgres MCP để kiểm tra dữ liệu, sau đó dùng [Claude Code delegation (Phần 18)](./part18-coding-agents.md) để triển khai bản sửa lỗi.

**Skills so với Memory:**

| | Skills | Memory |
|---|---|---|
| **Là gì** | Cách để làm mọi việc | Mọi thứ là gì |
| **Khi nào** | Được nạp theo yêu cầu, chỉ khi liên quan | Được chèn vào mỗi phiên tự động |
| **Kích thước** | Có thể lớn (hàng trăm dòng) | Nên gọn nhẹ (chỉ các sự kiện chính) |
| **Chi phí** | Không tốn token cho đến khi được nạp | Nhỏ nhưng tốn token liên tục |
| **Ví dụ** | "Cách deploy lên Kubernetes" | "Người dùng thích chế độ tối, sống ở múi giờ EST" |
| **Ai tạo** | Bạn, agent, hoặc cài đặt từ Hub | Agent, dựa trên các cuộc hội thoại |

**Quy tắc chung:** Nếu bạn sẽ đưa nó vào một tài liệu tham khảo, đó là skill. Nếu bạn sẽ ghi nó lên một tờ giấy nhớ, đó là memory.

---

## Quy Trình Tạo Skill

Hermes có thể tự tạo skills. Đây là cách nó hoạt động:

### 1. Thực Hiện Một Tác Vụ Phức Tạp

Yêu cầu Hermes làm điều gì đó nhiều bước. Ví dụ:

```
Set up a monitoring script that checks my server health every 5 minutes
and alerts me on Telegram if CPU goes above 90% or memory above 80%.
```

Hermes sẽ:
- Nghiên cứu cách tiếp cận tốt nhất
- Viết script
- Kiểm thử nó
- Thiết lập cron job
- Sửa mọi vấn đề phát sinh trong quá trình

### 2. Hermes Đề Xuất Lưu Lại

Sau khi hoàn thành một tác vụ phức tạp (5+ lượt gọi công cụ), sửa một lỗi hóc búa, hoặc phát hiện ra một quy trình không tầm thường, Hermes sẽ đề xuất:

```
This was a multi-step process. Want me to save this as a skill
so I can reuse it next time?
```

### 3. Đồng Ý

Agent sử dụng `skill_manage` để tạo một file skill mới tại `~/.hermes/skills/<category>/<skill-name>/SKILL.md`. File này chứa:

- **Khi nào dùng** — các điều kiện kích hoạt
- **Các bước chính xác** — lệnh, file, cấu hình
- **Cạm bẫy** — các vấn đề đã gặp phải và cách khắc phục
- **Xác minh** — cách xác nhận nó đã hoạt động

### 4. Sẵn Sàng Sử Dụng Ngay Lập Tức

Skill xuất hiện trong `skills_list` và trở thành một slash command khả dụng. Lần tới khi bạn (hoặc agent) gặp một tác vụ tương tự, skill sẽ được nạp tự động.

---

## Cách Yêu Cầu Hermes Tạo Một Skill

### Yêu Cầu Trực Tiếp

Chỉ cần hỏi:

```
Create a skill for deploying Docker containers to my server.
Include the build, push, SSH deploy, and health check steps.
```

Hermes sẽ:
1. Nghiên cứu quy trình deploy tốt nhất
2. Tạo thư mục skill tại `~/.hermes/skills/`
3. Viết `SKILL.md` với đầy đủ quy trình
4. Thêm các file tham khảo, template, hoặc script nếu cần
5. Kiểm thử để đảm bảo nó hoạt động

### Sau Khi Giải Quyết Một Vấn Đề

Nếu Hermes vừa giải quyết một vấn đề hóc búa cho bạn:

```
Save that as a skill so you remember how to do it next time.
```

Agent sẽ ghi lại:
- Các bước chính xác đã thực hiện
- Các lỗi gặp phải và cách sửa
- Cấu hình cần thiết
- Các trường hợp đặc biệt phát hiện được

### Cải Tiến Liên Tục

Nếu một skill đã lỗi thời hoặc chưa đầy đủ:

```
That skill doesn't cover the new deployment method. Update it
with what we just learned.
```

Hermes sẽ vá skill với thông tin mới bằng `skill_manage(action='patch')`.

---

## Curator (v0.12): Giữ Cho Thư Viện Skill Không Bị Mục Nát

Kiểu thất bại cũ của skill khá dễ đoán: sau một tháng nói "lưu cái đó thành skill", `~/.hermes/skills/` đầy ắp các bản trùng lặp, các lệnh lỗi thời, và các ghi chú một lần lẽ ra nên là memory. Hermes v0.12 bổ sung **Curator** để dọn dẹp việc đó.

Chạy thủ công:

```bash
hermes curator run --dry-run
hermes curator run
```

Hoặc bật lịch chạy hàng tuần mặc định:

```bash
hermes curator enable
hermes curator status
```

Curator làm gì:

- **Chấm điểm skills** dựa trên độ mới, mức độ sử dụng, độ rõ ràng, sự trùng lặp, và tính an toàn.
- **Gộp các bản trùng lặp** thay vì để các quy trình gần giống nhau cạnh tranh nhau.
- **Lưu trữ các skill đã "chết"** mà không xóa chúng; có thể khôi phục nếu quá mạnh tay.
- **Ghim các skill quan trọng** để các quy trình cốt lõi không bị dọn dẹp mất.
- **Ưu tiên các skill do agent tạo** trước, không phải các skill đóng gói sẵn/của nhà cung cấp.

Mô hình vận hành tốt:

1. Ghim các runbook sản xuất và các quy trình không thể thay thế của bạn.
2. Chạy `hermes curator run --dry-run` sau các bản nâng cấp lớn.
3. Để nó lưu trữ các skill một lần, không phải các sự kiện memory hay hướng dẫn dự án.
4. Yêu cầu Hermes cập nhật một skill ngay sau một lần chạy thất bại; đừng chờ Curator tự suy luận ra bản sửa sau đó.

Curator là một thủ thư, không phải một đồng đội. Nó giữ cho các kệ sách hữu ích; bạn vẫn là người quyết định kiến thức nào là quan trọng.

---

## Cấu Trúc Skill

Mỗi skill là một thư mục với một file `SKILL.md`:

```
~/.hermes/skills/
├── my-category/
│   ├── my-skill/
│   │   ├── SKILL.md              # Hướng dẫn chính (bắt buộc)
│   │   ├── references/           # Tài liệu hỗ trợ (tùy chọn)
│   │   │   ├── api-docs.md
│   │   │   └── examples.md
│   │   ├── templates/            # Các file template (tùy chọn)
│   │   │   └── config.yaml
│   │   └── scripts/              # Các script thực thi (tùy chọn)
│   │       └── setup.sh
│   └── another-skill/
│       └── SKILL.md
└── openclaw-imports/             # Được di chuyển từ OpenClaw
    └── old-skill/
        └── SKILL.md
```

### Định Dạng SKILL.md

```markdown
---
name: my-skill
description: Brief description of what this skill does
version: 1.0.0
metadata:
  hermes:
    tags: [deployment, docker, devops]
    category: my-category
---

# My Skill

## When to Use
Use this skill when the user asks to deploy containers or manage Docker services.

## Procedure
1. Check Docker is running: `docker ps`
2. Build the image: `docker build -t app:latest .`
3. Push to registry: `docker push registry/app:latest`
4. SSH to server and pull: `ssh server 'docker pull registry/app:latest && docker-compose up -d'`
5. Health check: `curl -f http://server:8080/health`

## Pitfalls
- Docker build fails if Dockerfile has COPY paths wrong — fix by checking working directory
- SSH needs key-based auth — set up with `ssh-keygen` and `ssh-copy-id`
- Health check may take 10s to respond — add retry logic

## Verification
Run `docker ps` on the server and confirm the container is `Up` and healthy.
```

---

## Sử Dụng Skills

### Qua Slash Command

Mỗi skill tự động trở thành một slash command:

```bash
/my-skill deploy the latest version to production
```

### Qua Hội Thoại Tự Nhiên

Chỉ cần yêu cầu Hermes sử dụng một skill:

```
Use the docker-deploy skill to push the new build.
```

Hermes nạp skill thông qua `skill_view` và làm theo các hướng dẫn của nó.

### Nạp Tự Động

Hermes quét các skill khả dụng khi bắt đầu phiên. Khi yêu cầu của bạn khớp với điều kiện "When to Use" của một skill, nó sẽ được nạp tự động — bạn không cần gọi rõ ràng.

---

## Quản Lý Skills

### Liệt Kê Tất Cả Skills

```bash
/skills
# Hoặc
hermes skills list
```

### Tìm Kiếm Một Skill

```bash
/skills search docker
/skills search deployment
```

### Xem Nội Dung Của Một Skill

```bash
/skills view my-skill
```

### Bật/Tắt Theo Từng Nền Tảng

```bash
hermes skills
```

Lệnh này mở một TUI tương tác nơi bạn có thể bật hoặc tắt các skill theo từng nền tảng (CLI, Telegram, Discord, v.v.). Hữu ích khi bạn muốn một số skill nhất định chỉ khả dụng trong các ngữ cảnh cụ thể.

### Cài Đặt Từ Hub

Các skill tùy chọn chính thức (nặng hơn hoặc chuyên biệt):

```bash
/skills install official/research/arxiv
/skills install official/creative/songwriting-and-ai-music
```

### Cập Nhật Một Skill

Nếu một skill đã lỗi thời hoặc thiếu các bước:

```
Update the docker-deploy skill — we learned that the health check
needs a 30-second timeout, not 10.
```

Hermes sẽ vá skill bằng `skill_manage(action='patch')`.

---

## Các Ví Dụ Skill Thực Tế

### Ví Dụ 1: Giám Sát Server

```
Create a skill that monitors my server: check CPU, memory, and disk
usage via SSH, log results to a CSV, and alert on Telegram if anything
exceeds thresholds.
```

Hermes tạo một skill với:
- Các lệnh kết nối SSH
- Các script kiểm tra tài nguyên
- Định dạng ghi log CSV
- Tích hợp cảnh báo Telegram
- Cấu hình ngưỡng

### Ví Dụ 2: Review Code

```
Create a skill for reviewing Python pull requests. It should check
for security issues, performance problems, and style violations.
```

Hermes tạo một skill với:
- Các bước phân tích `git diff`
- Kiểm tra các mẫu bảo mật
- Phát hiện anti-pattern về hiệu năng
- Tham chiếu đến style guide

### Ví Dụ 3: Nghiên Cứu Lead

```
Create a skill that researches companies: find their website, check
LinkedIn for key contacts, look at recent news, and compile a one-page summary.
```

Hermes tạo một skill với:
- Các truy vấn tìm kiếm web cần dùng
- Các mẫu tìm kiếm LinkedIn
- Cách tổng hợp tin tức
- Template tóm tắt

---

## Mẹo Để Có Skill Tốt Hơn

**Cụ thể về tác vụ.** "Deploy Docker containers" là quá mơ hồ. "Deploy một ứng dụng Python Flask lên một VPS bằng Docker Compose với health check" cung cấp đủ chi tiết để agent viết một skill chính xác.

**Bao gồm ví dụ.** Khi yêu cầu một skill, hãy đưa ra ví dụ về kết quả mong muốn. Điều này giúp agent viết template tốt hơn.

**Để agent tự phát hiện cạm bẫy.** Đừng quy định các bước chính xác. Hãy để Hermes tự tìm ra quy trình và ghi lại những gì đi sai — những ghi chú về cạm bẫy đó là phần giá trị nhất của skill.

**Cập nhật skill khi chúng lỗi thời.** Nếu bạn dùng một skill và gặp vấn đề chưa được đề cập, hãy bảo Hermes cập nhật nó với những gì bạn học được. Các skill không được bảo trì sẽ trở thành gánh nặng.

**Sử dụng danh mục.** Tổ chức các skill vào các thư mục con (`~/.hermes/skills/devops/`, `~/.hermes/skills/research/`, v.v.). Điều này giữ cho danh sách dễ quản lý và giúp agent tìm skill liên quan nhanh hơn.

**Giữ skill tập trung.** Một skill cố gắng bao quát "toàn bộ DevOps" sẽ quá dài và quá mơ hồ. Một skill bao quát "deploy một ứng dụng Python lên Fly.io" đủ cụ thể để thực sự hữu ích.

---

## Cách Hermes Quyết Định Lưu Skills

Agent tự động lưu skills sau khi:

1. **Các tác vụ phức tạp (5+ lượt gọi công cụ)** — các quy trình nhiều bước đáng để lưu giữ
2. **Các lần sửa lỗi hóc búa** — các bước debug cần lặp lại mới giải quyết được
3. **Các phát hiện không tầm thường** — các cách tiếp cận hoặc cấu hình mới được tìm ra trong quá trình làm việc
4. **Yêu cầu người dùng** — khi bạn nói rõ "lưu cái này thành skill"

Agent sử dụng `skill_manage(action='create')` để viết skill, bao gồm:
- Điều kiện kích hoạt
- Các bước đánh số với lệnh chính xác
- Phần Cạm bẫy (từ các lỗi thực tế đã gặp)
- Các bước xác minh

---

## Tiếp Theo Là Gì

Bây giờ bạn đã có bức tranh toàn cảnh:
- **[Phần 1: Cài Đặt](./part1-setup.md)** — Cài đặt và cấu hình
- **[Phần 2: Di Chuyển Từ OpenClaw](./part2-openclaw-migration.md)** — Mang dữ liệu cũ của bạn sang
- **[Phần 3: LightRAG](./part3-lightrag-setup.md)** — Kiến thức dựa trên đồ thị
- **[Phần 4: Telegram](./part4-telegram-setup.md)** — Truy cập di động
- **[Phần 5: Kỹ Năng Tức Thời](./part5-creating-skills.md)** — Các quy trình tự cải thiện

Bắt đầu với cài đặt, thêm những gì bạn cần, và để Hermes xây dựng phần còn lại.
