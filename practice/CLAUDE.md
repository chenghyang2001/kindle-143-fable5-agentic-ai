# 練習視窗（K143 Fable 5／Mythos 5 代理式 AI 工程演練）

你是演練中的「練習視窗」，工作目錄是本資料夾 practice/。教練會一個練習一個練習送提示詞過來，你直接做完。

- 一律繁體中文（台灣用語）；程式碼註解也用繁體中文。
- 不要問問題、不要出選擇題，一律採用你的推薦。
- 產出存到 `chNN/`（提示詞若寫 `practice/chNN/`，就存到 `chNN/`）。
- 不要執行 git 指令。
- 書附範例在 `fable5/`（作者 Ken Huang 公開 repo，MIT）。**不可修改 `fable5/` 裡的任何檔案**；要改就複製到 `chNN/` 再改。
- 範例執行時會寫檔到 fable5/ 內（`agentic_soc/lessons/`、`deep_research/claims.jsonl`、`memory/memories/`）；遇到這種範例，自己寫 `chNN/*.py` 匯入模組後把路徑常數改指到 `chNN/` 底下再跑。

## 🔴 金鑰與成本

- 不設定、不讀取、不要求任何 API 金鑰（ANTHROPIC_API_KEY 等），也不直接呼叫 Anthropic API。
- 範例裡要呼叫模型的地方，一律透過轉接層 `claude_cli_client.py`：它把 `anthropic` SDK 的呼叫換成 Claude Code 無頭模式 `claude -p`（走 Max 訂閱），並自動從子程序環境移除金鑰與巢狀 session 變數。
- 每個練習的 `claude -p` 呼叫控制在 5 次以內；轉接層預設單一行程上限 10 次（`K143_CLI_MAX_CALLS`），超過會直接擋下。

## 怎麼跑範例

Python 一律加 `PYTHONUTF8=1`。會呼叫模型的指令要等 20～90 秒，Bash 工具的 timeout 請設 600000。

**A. 不改原始碼，直接跑範例腳本或模組（最常用）**

```bash
PYTHONUTF8=1 python run_with_cli.py fable5/projects/03_cost_dashboard/cost_dashboard.py
PYTHONUTF8=1 python run_with_cli.py -m fable_scanner canary run
K143_CLI_LOG=ch04/calls.jsonl PYTHONUTF8=1 python run_with_cli.py fable5/projects/02_mcp_audit/mcp_audit.py
```

**B. 自己寫的 chNN/*.py 要匯入範例模組時**，開頭固定這樣寫：

```python
import sys
from pathlib import Path
PRACTICE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PRACTICE))
import claude_cli_client
claude_cli_client.install()          # 之後 import 的範例都會改走 claude -p；fable5/ 也已加進 sys.path
import agentic_soc.triage_loop as tl
tl.LESSONS = PRACTICE / "ch02" / "lessons"   # 把執行期寫檔改到 chNN/
```

**C. 自己直接呼叫模型**：`claude_cli_client.Anthropic().messages.create(model=..., system=..., messages=[...])`，回傳物件有 `.content[0].text`、`.stop_reason`、`.usage.output_tokens`。`claude_cli_client.calls_made()` 可回報呼叫次數。

轉接層可調的環境變數：`K143_CLI_MODEL`（強制換模型，例 `haiku` 變快）、`K143_CLI_TIMEOUT`（預設 180 秒）、`K143_CLI_MAX_CALLS`、`K143_CLI_LOG`（寫成 `python -m fable_scanner monitor` 讀得懂的 JSONL）。

轉接層的限制（回報時要照實說明）：`max_tokens`、`temperature`、`thinking`、`betas`、`fallbacks`、`fallback_credit` 會被忽略；`output_config.effort` 會轉成 `claude -p --effort`；伺服器端 `web_search` 會降級成 Claude Code 的 WebSearch；自訂工具不支援（不會回 tool_use）；沒有伺服器端備援，所以不會看到 `fallback_message`；CLI 不回傳拒答類別。

**不需要模型、可直接跑的離線功能**（從 `fable5/` 目錄執行，或 `cd fable5 &&` 再跑）：

```bash
cd fable5 && PYTHONUTF8=1 python -m fable_scanner scan <檔案或資料夾> [--format json]
cd fable5 && PYTHONUTF8=1 python -m fable_scanner monitor <log.jsonl>
cd fable5 && PYTHONUTF8=1 python migration/migration_linter.py <request.json>
cd fable5 && PYTHONUTF8=1 python mythos_scope/scope_gate.py <scope.json>
cd fable5 && PYTHONUTF8=1 python -m fable_scanner.test_scanner   # 另有 migration、mythos_scope 的 test
cd fable5 && PYTHONUTF8=1 python memory/memory_tool_handler.py
```

## 本專案例外

本專案是 Kindle 書籍教學 demo（快速模式），豁免全域「程式碼三 agent 鐵律」：直接寫檔，不派 code-writer／code-qa／code-reviewer；不需詢問複雜度或快速模式。
不可修改全域 `~/.claude/settings.json`，設定一律寫在本專案的 `.claude/settings.local.json`。
