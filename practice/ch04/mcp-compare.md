# MCP 連接器稽核：規則（ch04/mcp_rules.py）vs 模型（mcp_audit.py）

- 規則：純 Python，四條規則，0 次模型呼叫，輸出 `ch04/mcp-rules.txt`。
- 模型：prep（Sonnet）→ plan_or_audit（Fable，high）→ execute（Sonnet），3 次 claude -p，輸出 `ch04/run-02.txt`。

## 逐一對照

| 連接器 | 規則分數（命中） | 規則排名 | prep 的「naive score」 | Fable 外洩風險排名 | Fable 整併計畫的建議 |
| --- | --- | --- | --- | --- | --- |
| old-jira-connector | **3/4**（admin、auth=none、300 天） | 1 | Critical (9) | 🔴 1 | 第 1 項：今天撤銷；刪除前先拉存取 log 留證據；剩下的追蹤需求併入 Notion |
| aws | **2/4**（`s3:*`／`iam:*`／`ec2:*`、env_var_key） | 2 | High (8) | 🔴 2 | 第 2 項：本週立刻輪替金鑰並改用 STS 短期憑證，刪掉 `iam:*`，s3／ec2 縮到具名 ARN、只留讀取 |
| stripe-sandbox | **2/4**（200 天、env_var_key） | 3 | High (7) | 🟡 5 | 第 3 項：停用並撤銷金鑰；是 sandbox，爆炸半徑小 |
| github | **1/4**（admin:org） | 4（同分） | Medium (5) | 🟠 3 | 第 4 項：刪 admin:org、workflow；加 MCP 層的 repo 白名單，禁止寫 `.github/workflows/**` |
| notion | **1/4**（120 天） | 4（同分） | Medium (6) | 🟡 6 | 第 6 項：降成唯讀，限制分享頁面；150 天再沒用就停用 |
| slack | **1/4**（admin） | 4（同分） | Medium (5) | 🟠 4 | 第 5 項：刪 admin；`post_message` 加頻道白名單，封鎖私訊工具 |

前兩名完全一致。差最多的是 **stripe-sandbox**：規則給 2 分、排第 3；Fable 在外洩風險上把它降到第 5，因為「sandbox 只有測試資料」。**github／slack**：規則只給 1 分；Fable 把它們升到第 3、4，因為活躍又寬權限的 token 最危險。

## 模型抓到、四條規則抓不到的判斷

1. **活躍反而更危險**：規則把「久沒用」當扣分項，Fable 指出這套評分的盲點：「Staleness reduces likelihood of legitimate need, not attacker value」。github、slack 每天在用、token 是熱的，被注入的代理拿來外洩，流量還會混在正常活動裡。
2. **需要逐工具政策，不只是縮 scope**：github 的 `repo` 沒辦法限定到特定 repo、slack 的 `chat:write` 沒辦法限定頻道、notion 沒辦法限定頁面。即使縮完 scope，還是要在 MCP 工具層加白名單（repo 白名單、頻道白名單、禁止私訊、禁止寫 workflow 檔）。
3. **權限升級路徑**：github 的 `workflow`（規則沒抓，因為它不含 admin 也沒有 `*`）可以改 CI 定義來偷 repo secrets；aws 的 `iam:*` 讓攻擊者自己發新憑證，在連接器被撤掉之後還能留在系統裡。所以 Fable 說 aws 實際的爆炸半徑比 old-jira 還大，雖然分數比較低。
4. **功能重疊**：old-jira 與 notion 都是專案追蹤，可以合併；github 的 `workflow` 如果只是為了看 CI 狀態，Slack 通知就夠了。
5. **情境減權**：stripe-sandbox 雖然 2 分，但 sandbox 爆炸半徑小，所以降低優先度。規則看不到「sandbox」這個字的意思。
6. **slack 的 `admin` 是多餘的**：`chat:write`＋`channels:read` 已經涵蓋觀察到的用途，所以 admin 可以直接拿掉。規則只知道「有 admin」，不知道「其他 scope 已經夠用」。
7. **流程建議**：禁止 `none` 認證與長期靜態金鑰、權限擴大要當成新申請重審、超過 90 天就自動標記。

另外要注意：模型有幾句是推測，例如「almost certainly unexercised」、「assume compromised after 45 idle days」。資料裡沒有實際的工具呼叫紀錄，這些話只能當假設，不能當證據。

## 規則就足夠、不需要高階模型的部分

- **事實萃取與打分**：admin／萬用字元、auth=none、超過 90 天、env_var_key 都是確定的欄位比對。prep 那一段花一次 Sonnet 呼叫，只做出一張表和一個自訂公式的「naive score」（scope 1～3＋auth 1～3＋stale 1～3）。這件事 Python 做得一樣好，而且結果可以重現、不會每次跑都不一樣。
- **「立刻撤銷」的硬規則**：「auth=none 就撤銷」、「admin 加上長期沒用就撤銷」、「禁止靜態金鑰」都可以寫成規則，不用每次讓 Fable 重新推一遍。Fable 自己也說這兩條政策「would have caught 3 of 6 entries」。
- **審查週期**：超過 90 天標記、150 天停用，是純門檻判斷。
- **排版成政策文件**：execute 段多半是把 Fable 的計畫改寫成表格，判斷內容很少。

## 結論

**應該改**：把 prep 換成 `mcp_rules.py`，可以省一次模型呼叫，交給 Fable 的分數也是確定、可重現的；Fable 只負責規則做不到的判斷，例如活躍反而更危險、需要逐工具政策、權限升級路徑、功能重疊。
