# 修正紀錄：bad_prompt.md → ch05/fixed_prompt.md

每一版都另存成 `ch05/fixed_prompt.vN.md`，並在 `fable5/` 下執行 `PYTHONUTF8=1 python -m fable_scanner scan ../ch05/fixed_prompt.vN.md` 掃描（`ch05/_scanver.sh` 是我寫來做「存版本＋掃描」的小工具）。

## v0

原封不動複製 bad_prompt.md。

```text

..\ch05\fixed_prompt.v0.md
     3  warn   OT-01  IMPORTANT/CRITICAL/WARNING framing compensated for weaker instruction following on older models. Fable 5 gives the same weight to a plain sentence.
        https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5
     3  error  RX-01  Asking Fable 5 to echo its internal reasoning as response text is a documented `reasoning_extraction` refusal trigger. Use adaptive thinking instead of narrating it in the output.
        https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5
     8  warn   OM-01  12+ enumerated behavior items suggests a skill written for a weaker model. Fable 5 follows a brief intent statement better than a long list.
        https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5
    19  warn   OT-02  "YOU MUST" / "YOU MUST NOT" shouting. State the constraint plainly.
        https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5
    21  error  FS-01  Surfacing a remaining-token countdown makes Fable 5 wrap up early. Never show the model its own context budget.
        https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5

summary: 1 file(s) with findings, 5 total (2 error-severity)
rc=1
```

## v1

把第 3 行的 IMPORTANT 加 explain your reasoning 改成「最終報告每個結論附上支撐它的證據」；「YOU MUST NOT skip anything」改成「Finish the task you start before moving on」；刪掉 128000 tokens 那一行。清單先不動，看 OM-01 會不會單獨留下。

```text

..\ch05\fixed_prompt.v1.md
     8  warn   OM-01  12+ enumerated behavior items suggests a skill written for a weaker model. Fable 5 follows a brief intent statement better than a long list.
        https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5

summary: 1 file(s) with findings, 1 total (0 error-severity)
rc=0
```

## v2

把 12 條「Improve X」清單換成一段意圖說明：只修 build、改動最小、跑 build 確認；重構、功能、文件、CI／部署都不碰，看到值得做的寫進報告。另外加一句 Audit each claim against a tool result。任務「fix the failing build」保留。

```text

summary: 0 file(s) with findings, 0 total (0 error-severity)
rc=0
```

v0 是 5 個發現（2 個 error），v1 剩 1 個 warn（OM-01），v2 是 0 個發現。

觀察：v1 刪掉 FS-01 那行之後，OM-01 回報的行號仍然是 8，因為倒數那行在清單後面。另外，OM-01 只是數條列項目有沒有 ≥ 12 條，所以只刪一條、剩 11 條也會「通過」，但這樣只是騙過規則，提示詞沒有變好。v2 的做法是把清單的意圖講清楚，而不是只湊數字。

### 最終版 ch05/fixed_prompt.md

```markdown
# Coding agent -- fixed example

You are a coding agent working on a small team's repository. The team needs the
failing build fixed so they can ship from main again, with the smallest change
that does it.

Diagnose why the build fails, apply a minimal fix, and run the build to confirm
it passes. Leave refactors, new features, docs, and CI or deployment changes
alone; if you spot one worth doing, mention it in the report instead.

Audit each claim against a tool result from this session before you report it.
In your final report, state each conclusion with the evidence (command output or
file contents) that supports it.

Task: fix the failing build.
```

## 掃描身邊的真實檔案

### ../CLAUDE.md（practice/CLAUDE.md，練習視窗規則）

```text

..\CLAUDE.md
     1  info   MG-02  Long-running agent prompts without a progress-audit line let Fable 5 fabricate status updates.
        https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5

summary: 1 file(s) with findings, 1 total (0 error-severity)
rc=0
```

### skills/（fable5/skills/，11 個 SKILL.md＋README.md）

```text

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

## 有沒有誤判

| 檔案 | 規則 | 判斷 | 理由 |
| --- | --- | --- | --- |
| CLAUDE.md | MG-02（info） | **誤判** | 觸發字是第 10、39 行的「agentic」（書名與練習名稱「代理式 AI 工程」）。這份是練習視窗的操作規則，不是長時間自主代理的提示詞；而且它已經要求「回報時要照實說明」轉接層的限制。只是英文寫法沒有命中 `audit each claim` 這個字串。 |
| evidence-bound-progress | MG-02（info） | **誤判** | 這整份 skill 講的就是進度核對（「bind it to a tool result from this session」），只是用字不是「audit each claim」或「verified against a tool result」，所以規則認不出來。 |
| evidence-bound-progress | OM-01（warn） | **誤判** | 規則數的是全檔所有條列項目。這份是 4 條狀態分類、5 條報告格式、加上一段反模式清單，三段各自都很短，不是一張 12 條的長命令清單。 |
| refusal-aware-calling | RX-01＋RX-02（error） | **誤判** | 第 18 行是在**禁止**這種寫法：「Never ask the model to reproduce its reasoning... instead of "think step by step" or "explain your reasoning" framing」。規則只比對字串，看不出這是在引述反例。這是唯二的 error，結果讓整個 skills 資料夾掃描回傳 rc=1。 |
| act-on-sufficiency、effort-router、reader-first-summary、verifier-subagent | MG-02（info） | **大致是誤判** | 都是因為 description 或內文出現 agentic／autonomous／long-running。這些 skill 是載入主提示詞的片段，各自不是完整的代理提示詞，進度核對應該寫在主提示詞或專門的 skill（像 evidence-bound-progress）裡，不需要每份都寫一次。 |

結論：真實檔案裡 8 個發現全部可以歸為誤判，沒有一個是真的需要修的毛病。這些規則是純正規表達式，會抓到「引述反例」和「提到關鍵字但情境不同」的句子。MG-02 嚴重度設成 info 是合理的。RX-01／RX-02 是 error，會讓 CI 失敗；比較好的做法是讓規則略過反引號或引號裡的引述，或支援在檔案裡標註忽略。
