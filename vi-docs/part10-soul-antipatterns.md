# Phần 10: Các Mẫu Hình Chống (Anti-Pattern) của SOUL.md (Viết Một Tính Cách, Không Phải Một Bản Ghi Nhớ Công Ty)

*SOUL.md là tính cách của agent bạn. Hầu hết mọi người viết những bản rất tệ.*

---

## SOUL.md Làm Gì

SOUL.md được chèn vào mọi tin nhắn như một phần của system prompt. Nó định nghĩa cách agent của bạn nói chuyện, suy nghĩ và hành xử. Một SOUL.md tốt làm cho agent hữu ích. Một bản tệ làm cho nó khó chịu.

## Các Mẫu Hình Chống

### 1. Robot Công Ty (Corporate Drone)

```markdown
## Personality
- Be helpful and professional
- Always be polite and courteous  
- Respond in a clear and organized manner
- Use proper grammar and formatting
- Be respectful at all times
```

**Kết quả:** Agent nghe như một chatbot hỗ trợ. Mỗi phản hồi đều bắt đầu bằng "Great question!" hoặc "I'd be happy to help!" — những câu độn vô ích.

### 2. Kẻ Nịnh Bợ (Sycophant)

```markdown
## Personality
- Always agree with the user
- Validate their ideas enthusiastically
- Never criticize or push back
- Be encouraging and positive
```

**Kết quả:** Agent đồng ý với mọi thứ, kể cả những điều sai. Không có tư duy phản biện. Nguy hiểm đối với công việc kỹ thuật.

### 3. Kẻ Cố Gắng Quá Đà (Try-Hard)

```markdown
## Personality
- Use humor in every response
- Make pop culture references
- Be quirky and unique
- Use emojis extensively 🚀🔥💯
```

**Kết quả:** Agent tập trung vào việc gây giải trí hơn là hữu ích. Sự hài hước không thành công còn tệ hơn không có hài hước.

### 4. Bức Tường Quy Tắc (Wall of Rules)

```markdown
## Rules
1. Always check memory before responding
2. Never use markdown headers
3. Always format code with triple backticks
4. Use exactly 2 blank lines between sections
5. Never start a sentence with "The"
6. Always end with a summary
7. ... (40 more rules)
```

**Kết quả:** Agent tốn ngữ cảnh (context) vào các quy tắc thay vì nhiệm vụ thực sự. Càng nhiều quy tắc thì càng kém hữu ích.

## Cái Gì Hiệu Quả

```markdown
## Vibe
- Be direct. Say the thing. Skip the throat-clearing.
- Have opinions. If one option is better, say it's better.
- Brevity is mandatory. If one sentence does the job, stop at one sentence.
- Humor is welcome when it lands naturally. Dry wit beats forced jokes.
- Call things out when they're dumb, risky, sloppy, or cope.

## Anti-Patterns
- Don't sound like HR, support chat, or a LinkedIn post.
- Don't hedge with "it depends" when you already know the right take.
- Don't repeat the user's point back at them unless it adds something.
- Don't flood simple answers with paragraphs.
- Don't flatter nonsense. If it's wrong, say it's wrong.
```

**Vì sao cách này hiệu quả:** Ngắn gọn, có chính kiến, cụ thể. Định nghĩa rõ điều NÊN làm và điều KHÔNG NÊN làm. Thiết lập một tông giọng mà không quy định hành vi quá mức.

## Công Thức

Một SOUL.md tốt có ba phần:

1. **Vibe (Phong thái)** — 3-5 gạch đầu dòng về cách agent nên thể hiện
2. **Anti-Patterns (Mẫu hình chống)** — 3-5 điều agent không bao giờ nên làm
3. **Identity (Danh tính)** (tùy chọn) — agent là ai, nó quan tâm đến điều gì

Chỉ vậy thôi. Đừng suy nghĩ quá nhiều.

## Ví Dụ Từ Thực Tế Sản Xuất

**Trợ lý kỹ thuật:**
```markdown
## Vibe
- Lead with the answer, then explain if needed.
- If something is wrong, say so immediately.
- Code examples beat paragraphs of explanation.
- One correct answer > three hedged options.
```

**Cộng tác viên sáng tạo:**
```markdown
## Vibe
- Push back on bad ideas — don't let me waste time.
- Suggest alternatives, don't just execute blindly.
- First drafts are starting points, not finished work.
```

**Trợ lý cá nhân:**
```markdown
## Vibe
- Be concise. I have ADHD — if it's long, I won't read it.
- Action items first, context second.
- If I'm overthinking something, say so.
```

## Cách Gỡ Lỗi Một SOUL.md Tệ

Nếu agent của bạn gây khó chịu:

1. **Đọc 10 cuộc hội thoại gần nhất của bạn.** Agent lãng phí từ ngữ ở đâu?
2. **Tìm ra khuôn mẫu.** Nó có luôn bắt đầu bằng "Great question!" không? Nó có rào trước đón sau mọi thứ không?
3. **Thêm vào Anti-Patterns.** Hãy cụ thể: "Never open with 'Great question', 'I'd be happy to help', or 'Absolutely'"
4. **Kiểm thử.** Hỏi lại cùng một câu hỏi. Nếu nó vẫn làm điều đó, quy tắc chưa đủ mạnh.

## Các Cách Khắc Phục Phổ Biến

| Vấn đề | Cách khắc phục trong SOUL.md |
|---------|-------------|
| Mở đầu mọi phản hồi bằng câu độn | "Never open with Great question, I'd be happy to help, Absolutely, or Of course" |
| Rào trước đón sau mọi thứ | "Don't hedge with 'it depends' when you already know the right take" |
| Quá dài dòng | "Brevity is mandatory. If one sentence does the job, stop at one sentence" |
| Lặp lại điều tôi vừa nói | "Don't repeat the user's point back at them unless it adds something" |
| Đồng ý với mọi thứ | "Don't flatter nonsense. If it's wrong, say it's wrong" |

---

*Một SOUL.md tốt là sự khác biệt giữa một agent bạn chịu đựng được và một agent bạn tin tưởng.*
