# Mythos 範圍閘門筆記

## 基準（ch06/gate-baseline.txt）

兩份範例 `sample_mythos_scope.json`、`sample_fable_scope.json` 都是 `clean: scope packet is ready`，exit code 0；`test_scope_gate` 三個測試全過。

## 三份工作包怎麼造

全部從範例複製後只改一處，讓每份只測一件事：

| 檔案 | 從哪份改 | 改了什麼 |
| --- | --- | --- |
| `bad-forbidden.json` | sample_mythos | `allowed_actions` 加上 `public_poc`、`exfiltration`，其他欄位都合格 |
| `bad-missing.json` | sample_mythos | 刪掉 `glasswing_scope_id`（授權範疇 id）、`evidence_store`（私有證據庫）、`human_patch_owner`（修補負責人），以及 `artifact_policy.private_store_required`；`authorization_id` 保留 |
| `fable-no-telemetry.json` | sample_fable | 刪掉 `refusal_logging` 與 `fallbacks` |

欄位名稱取自 `scope_gate.py`：第 70～75 行的必要欄位清單（authorization_id、glasswing_scope_id、evidence_store、human_patch_owner），第 92 行的 `artifact_policy.private_store_required`，第 62、65 行的 Fable 遙測欄位。

## 結果（ch06/gate-results.txt）

| 工作包 | (欄位, 嚴重度, 訊息) | 擋下？ |
| --- | --- | --- |
| bad-forbidden | (`allowed_actions`, error, Forbidden action(s) cannot be approved here: exfiltration, public_poc) | **擋下**，1 個 blocking，exit 1 |
| bad-missing | (`glasswing_scope_id`, error, Mythos workloads require this field before the run starts.)<br>(`evidence_store`, error, 同上)<br>(`human_patch_owner`, error, 同上)<br>(`artifact_policy.private_store_required`, error, Mythos artifacts must be stored in a private evidence store.) | **擋下**，4 個 blocking，exit 1 |
| fable-no-telemetry | (`refusal_logging`, warn, Fable workloads should log stop_reason and stop_details.category.)<br>(`fallbacks`, warn, Fable workloads should define a refusal fallback path.) | **不擋**，0 個 blocking，exit 0 |

### error 與 warn 的分界

- **error（擋下）**：Mythos 的每一條，以及兩種模型共用的基本檢查（model 不對、沒有目標 repo、未知或禁止的動作）。只要有一個 error，exit code 就是 1。
- **warn（只提醒）**：只有 Fable 的 `refusal_logging` 和 `fallbacks`。缺這兩個仍然 exit 0，CI 若只看結束碼，會直接放行。
- **info**：Mythos 工作包如果寫了 `refusal_logging: true`，會得到一則 info，提醒「Mythos 不拿 Fable 的分類器拒答訊號當邊界」（第 104～106 行）。這次沒有造這種檔。

這個分級的意思是：Fable 有分類器和拒答機制兜底，缺遙測是「看不見」，不是「沒防線」，所以只是 warn；Mythos 沒有那層分類器，工作包本身就是防線，缺一項就不准開跑。

### 讀程式時另外發現的兩件事

1. **`disallowed_actions` 這個欄位完全沒被檢查**。範例檔有列它，但 `lint_scope()` 只看 `allowed_actions`。bad-forbidden 的 `disallowed_actions` 仍然列著 `public_poc`，同時 `allowed_actions` 也有 `public_poc`，這個自相矛盾沒有被另外指出，只是剛好被「禁止動作」那條擋下。如果有人把禁止動作從 disallowed 清單拿掉、又沒加進 allowed，閘門也不會發現。
2. **bad-forbidden 只報了 1 個 error**：`artifact_policy.public_poc` 還是 `false`，所以第 89 行那條沒觸發。也就是說，「允許動作裡有 public_poc」和「成品政策禁止 public_poc」同時存在，閘門靠的是禁止動作清單那一條在擋。

## 為什麼 Fable 的分類器不能當 Mythos 的安全邊界

分類器是**模型這一側**的東西：Fable 5 部署時多了一層資安雙用途分類器，看到像攻擊的請求就拒答，拒答再由備援接手，所以 Fable 的「安全訊號」是 `stop_reason == "refusal"` 加上拒答類別。

Mythos 5 是同一個能力等級、**刻意拿掉那層分類器**的部署（SKILL.md 的說法是 without Fable's relevant dual-use classifier layer），專門給已核准的 Glasswing 防禦工作用。所以：

1. **沒有拒答不代表安全**。在 Mythos 上，分類器根本不在，模型不會因為請求很危險就停下來；「沒有被拒」只是代表那個機制不存在，不代表請求是正當的。
2. **分類器看的是請求內容，不是授權**。就算分類器在，它也只能判斷「這段話像不像攻擊」，判斷不了「這次有沒有被授權打這個 repo」、「成品會不會被公開」、「誰負責修補」。這些是組織層面的事實，只能寫在工作包裡，由模型之外的程式檢查。
3. **邊界必須在模型開跑之前、在模型之外**。scope_gate 是在呼叫模型之前執行的程式，跟提示詞怎麼寫無關；SKILL.md 也明講缺項時要停下來索取工作包，「Do not compensate with a more careful prompt」——不能用更小心的提示詞來彌補。

所以 Mythos 的安全訊號換成了**範圍的出處**：誰授權、碰了哪個目標、產出什麼成品、誰驗證、誰負責修補。scope_gate 檢查的正是這些欄位。
