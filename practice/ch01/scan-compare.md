# 掃描前後對照

## 舊版：`fable_scanner/examples/bad_prompt.md`

```text
$ cd fable5 && PYTHONUTF8=1 python -m fable_scanner scan fable_scanner/examples/bad_prompt.md

fable_scanner\examples\bad_prompt.md
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
（exit code 1）
```

## 新版：`ch01/system_prompt.md`

```text
$ cd fable5 && PYTHONUTF8=1 python -m fable_scanner scan ../ch01/system_prompt.md

summary: 0 file(s) with findings, 0 total (0 error-severity)
（exit code 0）
```

## 每個規則代碼在新版怎麼消失

| 規則 | 嚴重度 | 舊版觸發的句子（行號） | 新版的處理 |
| --- | --- | --- | --- |
| OT-01 | warn | 第 3 行 `IMPORTANT:` 開頭的強調框 | 拿掉所有 IMPORTANT／CRITICAL 開頭，約束改成一般敘述句寫在「邊界」小節 |
| RX-01 | error | 第 3 行「explain your reasoning step by step」 | 不再要求把推理過程寫進回答；改在「白話摘要」只要求最終報告講清楚結論與不確定處 |
| OM-01 | warn | 第 8 行起 12 條「Improve X」清單 | 刪掉清單，開頭用一段話說明意圖（讓 build 恢復、改動最小），範圍收斂到單一任務 |
| OT-02 | warn | 第 19 行「YOU MUST NOT skip anything」 | 不用大寫喊叫；「把工作做完整」改成「上下文平靜」小節裡的平實句子 |
| FS-01 | error | 第 21 行「128000 tokens remaining」 | 移除剩餘 token 數字，反過來在「上下文平靜」要求不提剩餘空間、不為篇幅刪工作 |

另外，新版刻意放進「Audit each claim against a tool result」這句英文，因為掃描器的 MG-02（info）會檢查：提示詞若含 autonomous／long-running 等字且超過 800 字元，卻沒有「audit each claim」這類句子就會提醒；新版沒有那些字所以本來不會觸發，但保留這句讓「接地進度」小節的意圖明確。
