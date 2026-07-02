# Hermes Optimization Guide (Bản tóm tắt tiếng Việt)

> [Bản đầy đủ tiếng Anh](./README.md) · Trang này chỉ là tóm tắt lối vào, nội dung các chương vẫn bằng tiếng Anh.

Hướng dẫn thực chiến + các sản phẩm cài đặt được (Skills, mẫu cấu hình, script hạ tầng) cho [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) (hiện cập nhật đến v0.18.0 "Judgment", gồm Mixture-of-Agents, xác minh `/goal`, desktop app, và phần cứng NVIDIA local).

## Bắt đầu trong một lệnh

```bash
# Chạy trên VPS Debian 12 / Ubuntu 24.04 mới
curl -sSL https://raw.githubusercontent.com/OnlyTerp/hermes-optimization-guide/main/scripts/vps-bootstrap.sh | sudo bash
```

Hoặc đọc [docs/quickstart.md](./docs/quickstart.md) (bot Telegram trong 5 phút).

## Tổng quan nội dung

- **27 phần nội dung** (các mục trong README + `part6` đến `part26`) — desktop app, chạy local trên NVIDIA / DGX Spark, Mixture-of-Agents như một "model" chọn được, xác minh `/goal` dựa trên bằng chứng, tự cải thiện qua `/learn` + `/journey`, fan-out subagent nền, `hermes proxy`, Kanban, Checkpoints v2, Curator, TUI, plugin, LightRAG, Telegram, MCP, bảo mật, observability, remote sandbox
- **13 Skill cài đặt được** (`skills/`) — audit, backup, quét dependency, báo cáo chi phí, phân loại Telegram, review PR, phân loại hộp thư, báo cáo tuần Hermes, lọc rác, chuẩn bị họp, v.v.
- **5 mẫu cấu hình sản xuất** (`templates/config/`) — minimum / telegram-bot / production / cost-optimized / security-hardened
- **Hạ tầng** (`templates/compose/`, `templates/caddy/`, `templates/systemd/`, `scripts/`) — Langfuse tự host, reverse proxy Caddy, hardening systemd, script khởi tạo VPS
- **Sơ đồ kiến trúc Mermaid** (`diagrams/`)
- **Benchmark tái lập được** (`benchmarks/`) — 12 model × 5 tác vụ, kèm phương pháp luận
- **Danh mục hệ sinh thái** ([`ECOSYSTEM.md`](./ECOSYSTEM.md)) — MCP server, coding agent, plugin dashboard
- **Wizard cấu hình tương tác** ([`docs/wizard/`](./docs/wizard/)) — tạo `config.yaml` ngay trên trình duyệt

## Thứ tự đọc gợi ý

1. Muốn chạy bot Telegram nhanh nhất → [docs/quickstart.md](./docs/quickstart.md)
2. Muốn hiểu kiến trúc → [diagrams/architecture.md](./diagrams/architecture.md)
3. Muốn tiết kiệm chi phí → mục "Cost-routing playbook" trong [part20-observability.md](./part20-observability.md)
4. Muốn triển khai sản xuất → chọn kiến trúc gần nhất trong [docs/reference-architectures/](./docs/reference-architectures/)
5. Triển khai công khai cho người dùng → bắt buộc đọc [part19-security-playbook.md](./part19-security-playbook.md)
6. Muốn giao diện đồ họa thay vì terminal → [part24-desktop-app.md](./part24-desktop-app.md) (Hermes Desktop)
7. Muốn chạy local trên GPU của mình → [part25-nvidia-local.md](./part25-nvidia-local.md) (RTX / DGX Spark)
8. Muốn hội đồng nhiều model + bằng chứng hoàn thành việc → [part26-moa-verification.md](./part26-moa-verification.md) (Mixture-of-Agents & Verification)

## Giấy phép & đóng góp

MIT. Chào đón Issue / PR, xem chi tiết tại [CONTRIBUTING.md](./CONTRIBUTING.md).
