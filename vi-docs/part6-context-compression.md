# Phần 6: Nén Ngữ Cảnh (Đừng Để Mất Ngữ Cảnh Một Cách Âm Thầm)

*Các phiên làm việc dài sẽ xuống cấp. Nén ngữ cảnh (context compression) khắc phục điều này — nhưng chỉ khi nó hoạt động đúng.*

---

## Vấn Đề

Hermes chèn ngữ cảnh vào mỗi tin nhắn: bộ nhớ, kỹ năng (skills), kết quả công cụ, lịch sử hội thoại. Trong các phiên làm việc dài, dung lượng này sẽ tăng dần cho đến khi chạm giới hạn cửa sổ ngữ cảnh và agent bị đóng băng hoặc bắt đầu quên.

Nén ngữ cảnh tự động tóm tắt các tin nhắn cũ hơn để giữ ngữ cảnh gọn nhẹ. Nhưng có một lỗi trong triển khai mặc định có thể âm thầm làm mất ngữ cảnh.

## Lỗi

Trong `context_compressor.py`, khi việc tóm tắt thất bại (API timeout, lỗi model, rate limit), bộ nén **âm thầm loại bỏ các tin nhắn mà nó đang cố tóm tắt** thay vì giữ lại chúng. Bạn mất ngữ cảnh mà không có bất kỳ cảnh báo nào.

**Triệu chứng:**
- Agent đột nhiên "quên" điều gì đó mà nó đã biết cách đây 20 tin nhắn
- Các phiên làm việc dài xuống cấp nhanh hơn dự kiến
- Không có thông báo lỗi — nó chỉ âm thầm mất dữ liệu

## Cách Khắc Phục

Tìm file `context_compressor.py` của bạn:

```bash
find ~/.hermes -name "context_compressor.py" -type f
```

Tìm hàm nén (compression function). Lỗi nằm ở phần xử lý lỗi (error handling) xung quanh lời gọi tóm tắt. Nó sẽ trông giống như thế này:

```python
# BROKEN — silently drops context on failure
try:
    summary = await summarize_messages(messages_to_compress)
    compressed_context = summary
except Exception:
    compressed_context = ""  # THIS IS THE BUG — empty string = data lost
```

Hãy khắc phục bằng cách **hủy bỏ việc nén khi thất bại** thay vì làm vậy:

```python
# FIXED — preserves original context if compression fails
try:
    summary = await summarize_messages(messages_to_compress)
    compressed_context = summary
except Exception as e:
    logger.warning(f"Context compression failed: {e}, preserving original context")
    compressed_context = messages_to_compress  # Don't compress, don't lose data
```

**Nguyên tắc:** Nếu việc nén không thể thành công, hãy giữ nguyên ngữ cảnh chưa được nén. Một phản hồi chậm hơn vẫn tốt hơn một phản hồi sai.

## Khi Nào Việc Nén Được Kích Hoạt

- Mặc định: khi ngữ cảnh đạt khoảng ~80% cửa sổ của model
- Có thể cấu hình trong `~/.hermes/.env`:

```bash
# Percentage of context window to trigger compression (default: 80)
CONTEXT_COMPRESSION_THRESHOLD=80

# Minimum messages before compression activates (default: 20)
CONTEXT_COMPRESSION_MIN_MESSAGES=20
```

## Thực Hành Tốt Nhất

- **Hãy để nó nén.** Đừng đặt ngưỡng thành 99% — việc nén cần khoảng trống để hoạt động.
- **Theo dõi các phiên làm việc dài.** Nếu agent bắt đầu quên mọi thứ giữa cuộc hội thoại, hãy kiểm tra xem việc nén có âm thầm thất bại hay không.
- **Bắt đầu phiên mới cho công việc quan trọng.** Nếu bạn đang làm việc gì đó quan trọng, hãy bắt đầu một phiên mới thay vì chạy trên ngữ cảnh đã bị nén sau 100 tin nhắn.
- **Dùng `session_search` để truy hồi.** Nếu bạn bị mất ngữ cảnh do nén, `session_search` có thể tìm lại nó trong các bản ghi phiên (transcripts) trước đó.

---

*Lỗi này ảnh hưởng đến tất cả các phiên bản Hermes trước bản vá. Hãy vá lỗi này ngay lập tức nếu bạn chạy các phiên làm việc dài.*
