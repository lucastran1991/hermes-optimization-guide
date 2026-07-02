# Part 25: NVIDIA & Phần Cứng Cục Bộ — Chạy Hermes Trên GPU Của Riêng Bạn

<p align="center">
  <img src="./assets/nvidia-local.png" alt="Chạy Hermes cục bộ trên phần cứng NVIDIA RTX và DGX Spark" width="880">
</p>

*Hermes không phụ thuộc vào provider hay mô hình cụ thể, và điều đó có tác dụng theo cả hai chiều: bạn có thể mang một mô hình cloud hạng frontier **hoặc** chạy toàn bộ mọi thứ trên phần cứng bạn sở hữu. Nous Research và NVIDIA đã hợp tác để biến Hermes thành một **agent cục bộ luôn hoạt động (always-on)** tuyệt vời trên **NVIDIA RTX PC, RTX PRO workstation, và DGX Spark** — dữ liệu của bạn không bao giờ rời khỏi máy, không có hóa đơn theo token, và không có giới hạn tốc độ (rate limit). Phần này nói về harness trên phần cứng cục bộ; các weight cụ thể là tùy bạn chọn.*

> Đọc thêm: bài viết của NVIDIA, [*Hermes Agent on RTX and DGX Spark*](https://blogs.nvidia.com/blog/rtx-ai-garage-hermes-agent-dgx-spark/).

---

## 1. Tại Sao Nên Chạy Cục Bộ

- **Quyền riêng tư (Privacy)** — prompt, file, và bộ nhớ (memory) ở lại trên phần cứng của bạn. Tốt cho dữ liệu chịu quản lý (regulated) và cho bất cứ thứ gì bạn đơn giản là không muốn gửi cho một vendor.
- **Chi phí** — không có billing theo token. Một agent luôn hoạt động, theo dõi hộp thư, chạy cron, và soạn thảo công việc, sẽ rẻ hơn nhiều trên silicon bạn sở hữu.
- **Không giới hạn tốc độ (rate limit)** — cứ tận dụng hết mức GPU của bạn cho phép.
- **Luôn hoạt động (Always-on)** — một máy cục bộ là nơi trú ngụ tự nhiên cho một gateway 24/7, các watcher, và các job theo lịch (scheduled jobs) (xem [Phần 14](./part14-fast-mode-watchers.md) và [Phần 23](./part23-tenacity-stack.md)).

Đánh đổi ở đây là năng lực trên mỗi watt: một mô hình cục bộ sẽ không sánh được với các mô hình frontier lớn nhất trên những tác vụ khó nhất. Cách khắc phục là **routing**, không phải là niềm tin mù quáng — giữ một mô hình cloud trong fallback chain cho 5% khó nhất và để cục bộ xử lý phần còn lại (xem [Phần 9](./part9-custom-models.md)).

---

## 2. Các Hạng Phần Cứng

| Hạng | Phù hợp cho | Ghi chú |
|------|----------|-------|
| **NVIDIA RTX PC** (GeForce RTX) | Một agent cá nhân đủ mạnh, embedding, bản nháp, các luồng coding | Điểm khởi đầu phổ biến nhất; Tensor Cores tăng tốc suy luận (inference) |
| **RTX PRO workstation** | Suy luận cục bộ nặng hơn, nhanh hơn | NVIDIA báo cáo tốc độ sinh token nhanh hơn tới ~3× trên GPU RTX PRO đối với các mô hình mở hiện tại thông qua `llama.cpp` |
| **DGX Spark** | Một agent cục bộ luôn hoạt động, chạy các mô hình MoE lớn suốt cả ngày | **128GB bộ nhớ hợp nhất (unified memory)**, ~**1 petaflop** hiệu năng AI; chạy liên tục thoải mái các mô hình MoE cỡ 120B |

Cả ba đều là mục tiêu hạng nhất — hãy chọn cái phù hợp với khối lượng công việc và ngân sách của bạn.

---

## 3. Stack Cục Bộ Không Phụ Thuộc Vào Mô Hình

Hermes không đi kèm engine suy luận (inference engine) riêng; nó trỏ tới bất cứ thứ gì bạn đang chạy cục bộ:

- **Ollama** — dễ bắt đầu nhất; chạy `ollama pull` một mô hình rồi chọn nó trong `hermes model`.
- **LM Studio** — một provider hạng nhất của Hermes với GUI thân thiện để quản lý các mô hình cục bộ.
- **llama.cpp** — kiểm soát tối đa và là con đường mà NVIDIA nhấn mạnh cho thông lượng (throughput) trên RTX PRO.

```bash
# Example: run a local model with Ollama, then point Hermes at it
ollama pull <your-model>
hermes model            # pick the local model in the fuzzy picker
```

Bất kỳ cái nào trong số này đều expose một endpoint tương thích OpenAI (OpenAI-compatible), vì vậy Hermes coi chúng như bất kỳ provider nào khác — kể cả trong fallback chain. Một pattern phổ biến, tiết kiệm chi phí: **mô hình cục bộ làm chính (primary)**, mô hình cục bộ nhỏ cho embedding, **mô hình cloud frontier làm fallback** cho các trường hợp khó.

---

## 4. Playbook Cho DGX Spark

DGX Spark là mục tiêu cục bộ chủ lực: 128GB bộ nhớ hợp nhất nghĩa là một mô hình MoE cỡ 120B cùng context của nó có thể nằm gọn trong bộ nhớ và luôn thường trú (resident), nhờ đó agent phản hồi nhanh suốt cả ngày thay vì phải paging mô hình ra vào liên tục.

Một thiết lập mạnh:

1. Chạy **gateway** trên DGX Spark để watcher, cron, và messaging luôn hoạt động (always-on).
2. Giữ một **mô hình cục bộ lớn thường trú** cho phần lớn công việc, cùng một mô hình cloud trong fallback chain cho các tác vụ khó nhất.
3. Điều khiển nó từ laptop của bạn bằng **[remote backend của desktop app](./part24-desktop-app.md#7-connect-to-a-remote-hermes)** — GUI mỏng chạy cục bộ, agent nặng chạy trên Spark.
4. Đặt công việc bền vững (durable) lên **[Kanban](./part23-tenacity-stack.md)** để các job chạy lâu dài có thể sống sót qua các lần restart.

---

## 5. OpenShell — Cô Lập Ở Cấp Kernel

**OpenShell** là một security runtime từ NVIDIA và Microsoft, mang lại cho agent khả năng **cô lập ở cấp kernel (kernel-level isolation)** khỏi phần còn lại của hệ điều hành, kết nối Hermes với các security primitive gốc của Windows. Ý tưởng: cho phép một agent đủ năng lực chạy tool trên máy của bạn mà không phải trao toàn bộ chìa khóa.

Hãy coi OpenShell như một sự bổ sung — chứ không phải thay thế — cho [approval layer và security playbook](./part19-security-playbook.md) riêng của Hermes. Phòng thủ theo chiều sâu (defense in depth): cô lập ở cấp hệ điều hành bên dưới, cơ chế denylist/allowlist/quarantine và phòng chống prompt-injection của Hermes bên trên.

---

## 6. NemoClaw và "Build It Yourself"

Series agentic-AI **"Build It Yourself"** của NVIDIA hướng dẫn xây dựng agent cục bộ với **NemoClaw** và **OpenShell**. **NemoClaw** là stack mã nguồn mở của NVIDIA giúp tối ưu **OpenClaw** — framework agent tiền nhiệm mà nhiều người dùng Hermes đã migrate từ đó (xem [Phần 2: Di Chuyển OpenClaw](./part2-openclaw-migration.md)) — để chạy tốt trên các thiết bị NVIDIA, giờ đây bao gồm cả **WSL2** để người dùng Windows có được đường đi tối ưu mà không cần rời khỏi Windows.

Nếu bạn đang chuyển từ OpenClaw và muốn một hướng tiếp cận local-first, thì NemoClaw + Hermes là sự kết hợp tự nhiên.

---

## 7. Điểm Kết Nối NVIDIA Skills Hub

v0.16 đã thêm **NVIDIA như một nguồn Skills đáng tin cậy tích hợp sẵn (built-in trusted Skills source)**, cùng với OpenAI, Anthropic, và Hugging Face. Điều đó có nghĩa là các skill được tuyển chọn, đã ký (curated, signed) cho hệ sinh thái NVIDIA — **CUDA-X**, **AIQ**, và **cuOpt** — chỉ cách một lần cài đặt để có mặt trong hệ thống [Skills](./part5-creating-skills.md), với cùng mô hình tin cậy (trust model) như các nguồn tích hợp sẵn khác.

---

## 8. Một Lưu Ý Về Các Mô Hình (Cố Tình Giữ Ngắn Gọn)

Vì Hermes không phụ thuộc vào mô hình cụ thể, "mô hình cục bộ tốt nhất" thay đổi liên tục — đừng hard-code người chiến thắng của tuần này. Như một điểm dữ liệu *hiện tại*, NVIDIA nhấn mạnh **Qwen 3.6** (27B/35B) chạy trên RTX / DGX Spark và báo cáo rằng nó ngang bằng hoặc vượt trội các mô hình thế hệ trước cỡ 120B–400B trong khi chạy vừa trên phần cứng nhỏ hơn nhiều. Hãy dùng nó như điểm khởi đầu, chứ không phải chân lý bất biến: mở `hermes model`, fuzzy-search, và chọn cái nào tốt *ngay bây giờ*. Harness mới là phần bền vững.

---

## Những Điều Cần Bỏ Qua

- **Đừng ám ảnh với bảng xếp hạng (leaderboard).** Chọn một mô hình cục bộ đủ mạnh, gắn một cloud fallback, rồi tiếp tục.
- **Đừng chạy cục bộ mà không có fallback** nếu bạn phụ thuộc vào agent — hãy giữ một mô hình cloud trong chain cho 5% trường hợp khó.
- **Đừng bỏ qua việc cô lập (isolation).** Một agent cục bộ với shell và file tool rất mạnh; hãy kết hợp OpenShell (hoặc container/sandbox từ [Phần 21](./part21-remote-sandboxes.md)) với approval layer của Hermes.
- **Đừng cho rằng to hơn luôn tốt hơn.** Một mô hình MoE cỡ trung thường trú, phản hồi tức thì thường vượt trội một mô hình khổng lồ phải paging liên tục.
