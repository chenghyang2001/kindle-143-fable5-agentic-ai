# 深度研究迴圈小段執行筆記

完整輸出在 `ch02/research-output.txt`；共 5 次 claude -p（拆題 1、搜尋 1、投票 3），結果 3 票 SUPPORTED、主張 confirmed，已附加寫入 `ch02/claims.jsonl`。

## (a) 三步各用什麼 effort、為什麼這樣分

| 步驟 | 函式 | effort | 工具／預算 | 為什麼 |
| --- | --- | --- | --- | --- |
| 拆題 | `decompose()` 第 46～53 行 | xhigh | 無工具 | 拆題是規劃：角度拆得好不好決定後面所有搜尋的覆蓋面，錯一次會讓整輪研究偏掉，值得花最多思考。只呼叫一次，貴也划算。 |
| 搜尋 | `search_angle()` 第 56～73 行 | medium | web_search、task_budget 30000 | 執行層：要上網、讀資料、整理成可證偽的主張，需要一定判斷力，但每個角度都要跑一次，用 medium 控成本。 |
| 投票 | `verify()` 第 76～91 行 | low | web_search、task_budget 20000 | 評分層：每條主張要跑 3 次，數量最多；任務很窄（只回 REFUTED／SUPPORTED 加一句證據），用 low 就夠，靠「三票」而不是「單票想很久」來換可靠度。 |

這就是 README 說的分法：planning 與 synthesis 用 xhigh、execution 用 medium、grader 用 low。

## (b) 投票者提示詞怎麼讓它們「試著推翻」

看第 80～84 行：

1. **角色就是對手**：「adversarial claim verifier」，任務寫成「Try to REFUTE this claim」，預設立場是找反證，不是確認。
2. **自己去查**：給它 web_search，要它用搜尋找證據，而不是只憑主張本身的說服力判斷。
3. **只給成品、不給敘述**：只有 `claim` 和 `source`，沒有搜尋者的理由或上下文（docstring：「artifacts only」），附和不了它沒看過的論證。
4. **三個彼此獨立的全新上下文**：每票是獨立呼叫，互相看不到彼此的答案，不會從眾。
5. **強制先下結論**：第一個字必須是 REFUTED 或 SUPPORTED，不能用模稜兩可的長篇帶過。
6. **門檻設計**：2/3 推翻就淘汰（第 91 行）。注意它是「推翻要過半才淘汰」，不是「支持要過半才留下」；空回應或拒答不算推翻票，所以偏向保留主張。

這次三票都回 SUPPORTED。投票者 1 還自己點出一個細節：「frontmatter fields are technically optional」，表示它確實有在找漏洞，只是判斷這不足以推翻主張的核心。

## (c) 轉接層和真的 API 的差別

| 差別 | 對這次結果的影響 |
| --- | --- |
| `output_config.task_budget`（30000／20000）被忽略 | 每次呼叫沒有 token 預算上限，模型可以搜得比原設計更久、更多次；原設計的「per-run token budget」停止條件在這裡不存在。 |
| 伺服器端 `web_search_20260209`（`max_uses: 5`）換成 Claude Code 的 WebSearch | 搜尋引擎、結果格式、次數上限都不同；`max_uses: 5` 不生效。我也無法從輸出確認投票者實際搜了幾次。 |
| `max_tokens=16000` 被忽略 | 回應長度不受限；投票者都在一句話後多附了「Sources:」區塊，若輸出被截斷的風險反而比較低。 |
| `stream()` 是轉接層模擬 | 不是真的串流，一次拿完整結果，結果相同。 |
| `betas`／`fallbacks` 被忽略 | 沒有伺服器端備援到 Opus 4.8；這次沒有拒答，所以沒有影響，但遇到拒答就會直接拿到 None。 |
| 模型與環境 | `claude -p` 底下是 Claude Code 代理，有自己的系統提示詞與工具；同樣的提示詞在原生 API 上的行為可能不同（例如格式遵守程度）。 |
| CLI 不回傳拒答類別 | 只能知道有沒有拒答，看不到 stop_details.category。 |

## (d) 這條主張我看來可信嗎

主張：Skill 是資料夾、裡面必須有 SKILL.md（YAML frontmatter＋Markdown 指示），個人層級在 `~/.claude/skills/`、專案層級在 `.claude/skills/`。

我覺得可信。這和我在這台機器上看到的一致：使用者的全域規則提到 `~/.claude/skills/*/scripts/` 底下的腳本，本 session 可用的 skills 也是以這種名稱載入。唯一要打折的是「必須」兩字：投票者 1 指出 frontmatter 的欄位技術上是選填的，所以「必須有 SKILL.md」成立，「必須有完整 frontmatter」就說得太滿。

來源網址：搜尋步驟給的是 `https://code.claude.com/docs/en/skills`，三位投票者也都引用同一個網址（投票者 2 另外引用 `.../skills.md` 和 `.../skills?m=1`）。我沒有另外開網址查證，所以只能說：三個獨立的搜尋都回報了這個網址並引用了內容，看起來是真實存在的頁面，但我沒有親眼確認。另外要注意，三票引用的都是主張本身附的那個來源，算不上真的獨立證據。
