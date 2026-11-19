# fable_scanner 規則一覽（fable5/fable_scanner/rules.py）

「範例檔有沒有觸發」依據 `ch05/scan-examples.json`（掃描 `fable_scanner/examples/`：bad_prompt.md、good_prompt.md、agent_config.json；refusal_log.jsonl 副檔名不在掃描範圍）。

| 代碼 | 類別 | 嚴重度 | 適用 | 擋什麼毛病（我的話） | 範例檔觸發 |
| --- | --- | --- | --- | --- | --- |
| RX-01 | reasoning-extraction | error | prompt | 要模型「explain / show / share / walk me through 你的推理或思考過程」：叫它把內部思考寫進回答，是已知的拒答觸發點 | ✅ bad_prompt.md 第 3 行「explain your reasoning」 |
| RX-02 | reasoning-extraction | error | prompt | 「think step by step」、「think out loud」：同樣是要它把思考外露成輸出 | ❌ 沒有（bad_prompt 寫的是「explain your reasoning step by step」，step by step 前面不是 think） |
| OT-01 | overtriggering | warn | prompt | 行首的 `IMPORTANT:`／`CRITICAL:`／`WARNING:`／`ATTENTION:` 強調框；那是給舊模型加重語氣用的，Fable 5 讀平實句子就夠了，用力喊反而會過度觸發 | ✅ bad_prompt.md 第 3 行 |
| OT-02 | overtriggering | warn | prompt | 全大寫的「YOU MUST」／「YOU MUST NOT」喊叫（只比對大寫） | ✅ bad_prompt.md 第 19 行「YOU MUST NOT」 |
| OT-03 | overtriggering | warn | prompt | 「DO NOT MISS / FORGET / SKIP / OMIT」這類要求面面俱到的話，會把模型推向什麼都想做、做過頭的模式 | ❌ 沒有 |
| OM-01 | old-model | warn | prompt | 整份檔案有 12 條以上的條列項目：像是替弱模型寫的長清單，Fable 5 讀一段意圖說明效果更好 | ✅ bad_prompt.md 從第 8 行起 12 條 |
| FS-01 | fable-specific | error | prompt | 讓模型看到「還剩多少 token／上下文」：它會因此提早收尾 | ✅ bad_prompt.md 第 21 行「128000 tokens remaining」 |
| FS-02 | fable-specific | warn | config | 設定檔送 `temperature`／`top_p`／`top_k`：Fable 5 不支援，API 回 400 | ✅ agent_config.json 第 4 行 `"temperature": 0.7` |
| FS-03 | fable-specific | warn | config | 手動 `"thinking": {"type": "enabled", ...}`：Fable 5 的思考一律開著，手動設定會被拒；深度改用 effort 控制 | ✅ agent_config.json 第 5 行 |
| MG-01 | missing-guardrails | warn | config | 設定裡用了 claude-fable-5 卻沒有 `"fallbacks"`：被拒答時回 200、內容空白，迴圈卡死也沒有任何東西能救回來 | ✅ agent_config.json 第 2 行 |
| MG-02 | missing-guardrails | info | prompt | 長時間／自主代理提示詞（含 autonomous、long-running、agentic、orchestrat 等字，且超過 800 字元）卻沒有「audit each claim」或「verified against a tool result」這種進度核對句：代理可能捏造進度 | ❌ 沒有（bad_prompt 雖有 long-running autonomous，但全文不到 800 字元） |

good_prompt.md 沒有任何發現。

另外注意：`--format json` 模式不論有沒有 error，結束碼都是 0（scan.py 只有文字模式才會在有 error 時回 1）。所以 CI 若用 JSON 輸出，必須自己解析 severity，不能靠結束碼。
