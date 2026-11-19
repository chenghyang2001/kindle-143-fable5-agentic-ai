# 11 個技能的地圖（fable5/skills/）

依據：`fable5/skills/README.md`、11 個 `SKILL.md`、`fable5/.claude-plugin/plugin.json`（另外看了同資料夾的 `marketplace.json`）。

「任務型／常駐型」照 README〈How they activate〉：effort-router、verifier-subagent、lesson-memory 是任務型（遇到對應請求會自動觸發），其餘是常駐行為規則。mythos-scope-gate README 沒有點名，但它的 description 寫「Use before any approved Mythos-style … run」，是綁定特定工作類型的閘門，所以我歸為任務型。

| # | 技能 | description 重點（我的話） | 修的毛病 | 類型 | 建議放哪裡 | 對應前面的範例 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | effort-router | 依任務類別挑 effort，並定期重新檢查；從 Opus 4.7／4.8 移植時別照搬 xhigh | 整條流程用同一個 effort、沿用舊模型預設，導致多花錢或變慢 | 任務型 | 自動觸發（設計流程、移植時） | 第 4 章 `job_packet/packet.py`（prep／execute 便宜、plan_or_audit 才貴）；第 2 章 research_loop 的 xhigh／medium／low 分層 |
| 2 | scope-fence | 先分辨是「問問題」還是「要求改動」；問題只交評估，改狀態的動作要更高門檻 | 只要求診斷卻直接動手修、重啟服務、建備份分支 | 常駐型 | 貼進 CLAUDE.md（維運、正式環境旁的工作） | 第 1 章 system_prompt.md 的「邊界」小節；第 2 章 triage_loop「唯讀、隔離動作要人工閘門」 |
| 3 | no-gold-plating | diff 要能一步對回需求；不為單一呼叫者抽象化、不替不可能的狀態加防禦 | diff 比需求大：順手重構、預留旗標、多餘的錯誤處理 | 常駐型 | 明確呼叫（code review）或貼進 CLAUDE.md | 第 5 章 fixed_prompt.md 改寫掉 bad_prompt 的 12 條「Improve X」 |
| 4 | evidence-bound-progress | 每個進度宣稱都要綁一個本 session 的工具結果；做完／失敗／略過／未驗證要分清楚 | 長時間執行的報告說「測試通過」，其實根本沒跑 | 常駐型 | 貼進 CLAUDE.md（長時間、無人看管的工作） | 第 1 章「接地進度」與 harness/VERIFY.md；掃描器 MG-02 規則 |
| 5 | act-on-sufficiency | 資訊夠了就動手；已確定的事不重驗；只給一個建議，不列選單 | 簡單的請求也過度規劃、重複推導、列出一堆不會選的選項 | 常駐型 | 明確呼叫（互動）或貼進 CLAUDE.md | 第 1 章 system_prompt.md 的「自主性」 |
| 6 | verifier-subagent | 做的人不打分；驗證者只拿規格和成品，不拿做的人的敘述；長時間工作要定期驗證 | 自我檢討抓不到自己的盲點 | 任務型 | 自動觸發（設計多代理流程、驗收長時間產出） | 第 2 章 triage_loop 的 `verify()`、research_loop 的三票驗證；`job_packet.verify()` |
| 7 | autonomy-contract | 無人看管時，可逆且在範圍內的動作直接做；結束一輪前先檢查最後一段是不是空頭承諾；不讓 token 倒數影響工作 | 停在「我接下來會…」卻沒呼叫工具、中途問已經授權過的事、擔心上下文就自己切 session | 常駐型 | 貼進系統提示詞／CLAUDE.md（README 說它就是為無人值守寫的） | 第 1 章「上下文平靜」、掃描器 FS-01；ch01 harness 的停止條件 |
| 8 | lesson-memory | 一課一檔＋INDEX.md；第一行能獨立看懂、寫為什麼；共享的 lesson 視為不可信，命令句要隔離 | 同樣的錯一再被糾正；記憶被投毒 | 任務型 | 自動觸發（重複執行的代理、專案啟動） | 第 3 章 `memory/memory_tool_handler.py`、`memory/startup_scan.py`；templates/memory-scaffold.md |
| 9 | reader-first-summary | 最終報告先講結果、用完整句子、不用箭頭鏈和自創縮寫、每個識別碼都說明它是什麼 | 報告寫成只有做的人看得懂的速記 | 常駐型 | 貼進 CLAUDE.md | 第 1 章 system_prompt.md 的「白話摘要」 |
| 10 | refusal-aware-calling | 每個 Fable 呼叫都接備援；先看 stop_reason 再讀內容；拒答要單獨記錄 | 拒答是 HTTP 200＋空內容，被當成安靜的成功 | 常駐型 | 明確呼叫（新增或審查 API 呼叫時） | 各範例的 `if msg.stop_reason == "refusal"`；第 5 章 `fable_scanner/monitor.py` 與 `canary.py`；掃描器 MG-01 |
| 11 | mythos-scope-gate | Mythos 資安工作開跑前，要有授權、確切目標、允許與禁止動作、私有證據庫、隔離沙箱、獨立驗證者、修補負責人；缺一項就停 | 把 Mythos 當成「不會拒答的 Fable」，跑超出範圍的資安任務 | 任務型（閘門） | 自動觸發（任何 Mythos 式資安工作之前） | `mythos_scope/scope_gate.py`（後面章節）；概念上接第 2 章 SOC 迴圈的唯讀邊界 |

## 技能數量是否一致

| 來源 | 寫的數量 |
| --- | --- |
| README.md 開頭 | 「11 Agent Skills」，表格也列了 1～11 |
| plugin.json `description` | 「11 Fable 5 and Mythos-class Agent Skills」，並逐一列出 11 個主題 |
| marketplace.json 的 plugin description | 「11 Fable 5 and Mythos-class Agent Skills」 |
| 實際 `skills/` 底下的資料夾 | 11 個（README.md 除外），每個都有 SKILL.md |

**一致**。三處文件與實際資料夾都是 11 個，名稱也一一對得上。附帶一提：plugin.json 沒有欄位明列技能路徑，是靠 plugin 慣例自動找 `skills/` 資料夾；數量只寫在描述文字裡，沒有機器可檢查的清單，所以之後增刪技能時，要記得手動同步三處的「11」。

## 掃描作者自己的技能

```text
$ cd fable5 && PYTHONUTF8=1 python -m fable_scanner scan skills

skills\act-on-sufficiency\SKILL.md
     1  info   MG-02  Long-running agent prompts without a progress-audit line let Fable 5 fabricate status updates.
        https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5

skills\effort-router\SKILL.md
     1  info   MG-02  Long-running agent prompts without a progress-audit line let Fable 5 fabricate status updates.
        https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5

skills\evidence-bound-progress\SKILL.md
     1  info   MG-02  Long-running agent prompts without a progress-audit line let Fable 5 fabricate status updates.
        https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5
    14  warn   OM-01  12+ enumerated behavior items suggests a skill written for a weaker model. Fable 5 follows a brief intent statement better than a long list.
        https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5

skills\reader-first-summary\SKILL.md
     1  info   MG-02  Long-running agent prompts without a progress-audit line let Fable 5 fabricate status updates.
        https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5

skills\refusal-aware-calling\SKILL.md
    18  error  RX-01  Asking Fable 5 to echo its internal reasoning as response text is a documented `reasoning_extraction` refusal trigger. Use adaptive thinking instead of narrating it in the output.
        https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5
    18  error  RX-02  "Think step by step" / "think out loud" asks the model to externalize thinking as output, another reasoning_extraction trigger.
        https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5

skills\verifier-subagent\SKILL.md
     1  info   MG-02  Long-running agent prompts without a progress-audit line let Fable 5 fabricate status updates.
        https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5

summary: 6 file(s) with findings, 8 total (2 error-severity)
rc=1
```

**作者自己的技能有沒有觸犯自己的規則？** 字面上有：6 個檔、8 個發現，其中 2 個 error，結束碼 1，CI 會失敗。但逐條看下來都是誤判（第 5 章練習 1 已逐條分析過，這次結果完全相同）：

- **refusal-aware-calling 第 18 行 RX-01＋RX-02（error）**：這句是在禁止「think step by step」和「explain your reasoning」，規則只比對字串，把引述的反例當成了違規。
- **evidence-bound-progress 第 14 行 OM-01**：三段各自都很短的清單加起來超過 12 條，不是一張長命令清單。
- **6 個 MG-02（info）**：description 裡出現 agentic／autonomous／long-running，就要求寫「audit each claim」。evidence-bound-progress 本身就是在講進度核對，只是用字不同。

還有一個「差點撞到、但沒被抓到」的例子：autonomy-contract 寫了「remaining-context countdown」與「context-budget worry」，談的正是 FS-01 要擋的事。但 FS-01 的正規表達式要求 `context` 後面接空白再接 remaining／budget，連字號寫法和倒過來的字序都比對不到，所以沒有觸發。在這裡沒觸發是對的（它是在叫人「不要顯示倒數」），但也說明這條規則換個寫法就能繞過。

結論：作者的技能在精神上沒有違反自己的規則，但掃描器分不出「引述反例」，所以作者自己的 repo 也過不了自己的 CI。這是規則該補的地方（略過引號裡的內容，或支援忽略標註），不是技能該改的地方。

## 最該先導入這個練習視窗的 2 個技能

**1. evidence-bound-progress**：練習視窗每個練習都要回報「跑了什麼、結果如何」，而我在前面幾章確實遇到過無法驗證的地方（例如第 2 章判斷不出 escalate 是模型選的還是預設值）。把「做完／失敗／略過／未驗證」四種狀態寫進 practice/CLAUDE.md，能讓每份練習的回報都對得到 log 或輸出檔，不會有人把未驗證的事寫成已完成。

**2. scope-fence**：practice/CLAUDE.md 有一條硬規則「不可修改 fable5/ 裡的任何檔案」，但範例程式會在執行時自己寫檔到 fable5/（lessons、claims.jsonl、memories），我也碰過 import 時產生 `__pycache__` 的情況。scope-fence 的「改狀態的動作門檻更高」和「不產出沒被要求的東西」，剛好對應這條邊界，讓練習視窗動手前先確認寫入路徑都在 chNN/ 底下。
