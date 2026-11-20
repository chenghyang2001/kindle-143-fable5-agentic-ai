#!/bin/bash
# K143 第 7 章互動演練：把生產機隊從 Opus 4.8 遷移過來——linter、CI 閘門、找缺口、影子比對，一次跑一步
# 用法：bash ch07.sh <步驟 1-8>
# 只有第 7 步會真的呼叫模型（2 次）：走 claude -p（Max 訂閱），不設 ANTHROPIC_API_KEY
# 所有產出寫到 ch07/interactive/，fable5/ 一個檔都不改、也不寫入
set -u
# 轉接層每次呼叫才讀這個上限；第 7 步新舊模型各 1 次，設 6 留一點餘裕又擋得住失控迴圈
export K143_CLI_MAX_CALLS=6
STEP="${1:-1}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PRACTICE="$HERE/.."
LAB="$PRACTICE/fable5"
WORK="$PRACTICE/ch07/interactive"   # 動手改的檔案放這裡，不碰 fable5/
mkdir -p "$WORK"
G=$'\e[32m'; Y=$'\e[33m'; C=$'\e[36m'; B=$'\e[1m'; N=$'\e[0m'

banner() { clear; printf '%s╔══════════════════════════════════════════════════════╗%s\n' "$C" "$N"; printf '%s  K143 第 7 章｜機隊遷移　第 %s / 8 步%s\n' "$B" "$STEP" "$N"; printf '%s  %s%s\n' "$B" "$1" "$N"; printf '%s╚══════════════════════════════════════════════════════╝%s\n\n' "$C" "$N"; }
tip() { printf '%s💡 %s%s\n\n' "$Y" "$1" "$N"; }
show() { printf '%s▶ 要執行的指令：%s\n' "$G" "$N"; printf '%s' "$1" | sed "s/^/${G}  │ ${N}/"; printf '\n%s▶ 執行結果：%s\n' "$G" "$N"; }
done_step() { printf '\n%s👉 第 %s 步完成%s\n' "$C" "$STEP" "$N"; }
# 執行 shell 指令（在 fable5/ 目錄）
sh_run() { (cd "$LAB" && PYTHONUTF8=1 bash -c "$1"); done_step; }
# 執行 Python（先裝轉接層，讓 import anthropic 改走 claude -p）
# 注意：py_run 的 heredoc 沒加引號，這裡的 Python 不可出現錢字號與反引號
py_run() { (cd "$LAB" && PYTHONUTF8=1 PYTHONPATH=. python - <<PY
import sys; sys.path.insert(0, ".."); import claude_cli_client; claude_cli_client.install()
$1
PY
); done_step; }

case "$STEP" in
1) banner "認識主角：migration_linter 檢查哪幾件事"
   tip "換模型不是改一個字串。linter 把遷移陷阱分三級：error（Fable 5 直接 400）、warn（白花錢或拒答時卡死）、info（日後難改）。下方 grep 只抓得到固定欄位名；取樣參數那條的欄位是變數 p，在第 22～26 行的迴圈裡，所以不會出現在清單上。"
   P='sed -n 1,60p migration/migration_linter.py
echo
echo "──── 每條檢查的欄位與嚴重度 ────"
grep -n -A1 "findings.append" migration/migration_linter.py | grep -o '\''("[a-z_.]*", "[a-z]*"'\'' | sed '\''s/[("]//g'\'''
   show "$P"; sh_run "$P" ;;
2) banner "掃書附的舊請求：6 個 finding、3 個會 400"
   tip "這份 Opus 時代的請求帶了 temperature、top_p、手動 budget_tokens，assistant 回合還夾著思考區塊。linter 只要有 error 就回傳 exit code 1，正好拿來當 CI 閘門。最後再跑書附自帶的 3 個檢查。"
   P='cat -n migration/sample_opus_request.json
echo
echo "──── linter 掃描 ────"
python migration/migration_linter.py migration/sample_opus_request.json
echo "exit code = $?"
echo
echo "──── 書附自帶檢查 ────"
python -m migration.test_migration_linter'
   show "$P"; sh_run "$P" ;;
3) banner "動手修：把舊請求修到 clean"
   tip "照 linter 的指示逐條修：拿掉取樣參數與手動 thinking、剝掉 assistant 的思考區塊、接上 fallbacks 備援、把 effort 寫明。修好的檔存到 ch07/interactive/fixed_request.json，書附原檔不動。"
   P='import copy, json
from pathlib import Path
from migration.migration_linter import lint, main, SAMPLING_PARAMS
src = json.loads(Path("migration/sample_opus_request.json").read_text(encoding="utf-8"))
req = copy.deepcopy(src)
for key in SAMPLING_PARAMS + ("thinking",):
    req.pop(key, None)                       # 取樣參數與手動 thinking 一律拿掉
for m in req["messages"]:
    if m["role"] == "assistant" and isinstance(m["content"], list):
        m["content"] = [b for b in m["content"] if b.get("type") not in ("thinking", "redacted_thinking")]
req["model"] = "claude-fable-5"
req["fallbacks"] = [{"model": "claude-opus-4-8"}]   # 實際呼叫時另帶 betas=["server-side-fallback-2026-06-01"]
req["output_config"] = {"effort": "medium"}
out = Path("../ch07/interactive/fixed_request.json")
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(req, ensure_ascii=False, indent=2), encoding="utf-8")   # 覆寫，重跑可重現
print("拿掉的欄位：", sorted(set(src) - set(req)))
print("新增的欄位：", sorted(set(req) - set(src)))
print("assistant 回合剩下的區塊：", [b["type"] for b in req["messages"][1]["content"]])
print("finding 數：修改前", len(lint(src)), "→ 修改後", len(lint(req)))
print()
print("──── 用 linter 的 main() 掃修好的檔 ────")
print("exit code =", main(str(out)))'
   show "$P"; py_run "$P" ;;
4) banner "白花錢的陷阱：思考區塊不會 400，CI 也擋不住"
   tip "從對話歷史帶過來的思考區塊，換模型後不報錯，卻會被當成無效輸入照算 token。linter 只給 warn，而 main() 只有 error 才回 1，所以只看 exit code 的 CI 會放行。另外注意：轉接層攤平訊息時會自己丟掉思考區塊，真 API 不會。"
   P='import json
from pathlib import Path
from migration.migration_linter import lint, main
thought = "先看事件時間線，再找根因，最後整理影響範圍。" * 40   # 模擬一大段舊模型的思考
req = {
    "model": "claude-fable-5",
    "fallbacks": [{"model": "claude-opus-4-8"}],
    "output_config": {"effort": "medium"},
    "messages": [
        {"role": "user", "content": "總結這份事件報告。"},
        {"role": "assistant", "content": [
            {"type": "thinking", "thinking": thought},
            {"type": "text", "text": "這是摘要：資料庫連線池耗盡。"},
        ]},
        {"role": "user", "content": "再補一句改善建議。"},
    ],
}
out = Path("../ch07/interactive/history_with_thinking.json")
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(req, ensure_ascii=False, indent=2), encoding="utf-8")   # 覆寫，重跑可重現
print("lint 結果：", [(f, s) for f, s, _ in lint(req)])
rc = main(str(out))
print("exit code =", rc, "（0 代表只看 exit code 的 CI 會放行）")
print()
body = json.dumps(req["messages"], ensure_ascii=False)
print("歷史訊息總字元：", len(body))
print("其中思考區塊字元：", len(thought), "≈", round(len(thought) * 100 / len(body)), "% 是白付的輸入")
print()
flat = claude_cli_client._flatten_messages(req["messages"])
print("轉接層攤平後還有思考內容嗎：", "有" if "事件時間線" in flat else "沒有（轉接層自己剝掉了，真 API 不會）")'
   show "$P"; py_run "$P" ;;
5) banner "寫 CI 閘門：任何 error 就讓建置失敗"
   tip "在 ch07/interactive/ 準備兩個請求資料夾，寫一支 ci_gate.py：逐檔 lint，有 error 就標 FAIL、整體 exit code 1；warn 也一併列出給人看，補上第 4 步的教訓。每次重跑會先清空資料夾。"
   P='import json, subprocess
from pathlib import Path
work = Path("../ch07/interactive").resolve()
base = {"model": "claude-fable-5", "fallbacks": [{"model": "claude-opus-4-8"}],
        "output_config": {"effort": "low"},
        "messages": [{"role": "user", "content": "hi"}]}
original = json.loads(Path("migration/sample_opus_request.json").read_text(encoding="utf-8"))
history = dict(base, messages=[{"role": "user", "content": "hi"},
                               {"role": "assistant", "content": [{"type": "thinking", "thinking": "..."},
                                                                 {"type": "text", "text": "hello"}]},
                               {"role": "user", "content": "again"}])
sets = {
    "requests": {
        "01-fixed.json": base,
        "02-original-opus.json": original,
        "03-top-k-only.json": dict(base, top_k=40),
        "04-thinking-disabled.json": dict(base, thinking={"type": "disabled"}),
        "05-thinking-history.json": history,
    },
    "requests-pass": {"01-fixed.json": base, "05-thinking-history.json": history},
}
for folder, files in sets.items():
    d = work / folder
    d.mkdir(parents=True, exist_ok=True)
    for old in d.glob("*.json"):
        old.unlink()                          # 重跑才可重現
    for name, body in files.items():
        (d / name).write_text(json.dumps(body, ensure_ascii=False, indent=2), encoding="utf-8")
gate = work / "ci_gate.py"
gate.write_text("""import json, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "fable5"))
from migration.migration_linter import lint
folder = Path(sys.argv[1])
failed = 0
for path in sorted(folder.glob("*.json")):
    findings = lint(json.loads(path.read_text(encoding="utf-8")))
    errors = [f for f, s, _ in findings if s == "error"]
    warns = [f for f, s, _ in findings if s == "warn"]
    status = "FAIL" if errors else "PASS"
    failed += bool(errors)
    print("  " + status + "  " + path.name.ljust(28) + " error=" + str(errors) + " warn=" + str(warns))
print("  結果：" + str(failed) + " 個檔有 error")
sys.exit(1 if failed else 0)
""", encoding="utf-8")
for folder in ("requests", "requests-pass"):
    print("──── 閘門掃 " + folder + "/ ────")
    rc = subprocess.run([sys.executable, str(gate), str(work / folder)]).returncode
    print("  exit code = " + str(rc))
    print()'
   show "$P"; py_run "$P" ;;
6) banner "找缺口：linter 漏掉的四種請求"
   tip "linter 不是萬能。準備四份「應該被警告」的請求：fallbacks 是空陣列、mythos-5 沒接備援、effort 打錯字、model 名稱打錯，再加一份對照組，看哪些被它放過。這些缺口遷移時要自己補檢查。"
   P='from migration.migration_linter import lint
msgs = [{"role": "user", "content": "hi"}]
fb = [{"model": "claude-opus-4-8"}]
cases = [
    ("對照組：fable-5 沒接備援", "warn fallbacks",
     {"model": "claude-fable-5", "output_config": {"effort": "high"}, "messages": msgs}),
    ("(a) fallbacks 是空陣列", "應警告：等於沒接",
     {"model": "claude-fable-5", "fallbacks": [], "output_config": {"effort": "high"}, "messages": msgs}),
    ("(b) mythos-5 沒接備援", "應警告：mythos 也會拒答",
     {"model": "claude-mythos-5", "output_config": {"effort": "high"}, "messages": msgs}),
    ("(c) effort 打錯字 hgih", "應警告：無效等級",
     {"model": "claude-fable-5", "fallbacks": fb, "output_config": {"effort": "hgih"}, "messages": msgs}),
    ("(d) model 打錯 claude-fable5", "應警告：不認得的模型",
     {"model": "claude-fable5", "output_config": {"effort": "high"}, "messages": msgs}),
]
for name, expect, req in cases:
    got = [f + ":" + s for f, s, _ in lint(req)]
    verdict = "抓到" if got else "漏掉 ⚠️"
    print("  " + name.ljust(26) + "｜預期：" + expect.ljust(18) + "｜linter：" + (str(got) if got else "（0 個 finding）") + "｜" + verdict)
print()
print("原因：fallbacks 只檢查「鍵在不在」、只對 model == claude-fable-5 檢查；effort 只檢查有沒有，不檢查值。")'
   show "$P"; py_run "$P" ;;
7) banner "影子比對：同一個提示詞，新舊模型各跑一次（呼叫模型 2 次）"
   tip "會呼叫模型 2 次（Opus 4.8、Fable 5 各一次），約 20～60 秒。比的是可檢查的性質：只回一個詞、在允許清單內、答對 network，不比字面。log 寫到 ch07/interactive/calls-shadow.jsonl，再用書附 monitor 離線算成本。轉接層限制：max_tokens、fallbacks 會被忽略，所以 fallback served 一定是 0，測不到切換後有多少比例改走備援，正式切換前要用真 API 補測。"
   P='import os
from pathlib import Path
import anthropic
from fable_scanner.monitor import analyze, print_report
work = Path("../ch07/interactive").resolve()
work.mkdir(parents=True, exist_ok=True)
log = work / "calls-shadow.jsonl"
if log.exists():
    log.unlink()                              # 舊 log 會讓統計算錯
os.environ["K143_CLI_LOG"] = str(log)
PROMPT = ("把這段錯誤訊息分類成 bug／config／network，只回一個詞。\n\n"
          "錯誤訊息：requests.exceptions.ConnectTimeout: HTTPSConnectionPool(host=api.internal, "
          "port=443): Max retries exceeded (Caused by ConnectTimeoutError: timed out after 10s)")
ALLOWED = {"bug", "config", "network"}
checks = [
    ("只有一個詞", lambda t: len(t.strip().split()) == 1),
    ("在允許清單內", lambda t: t.strip().strip(".").lower() in ALLOWED),
    ("答對 network", lambda t: t.strip().strip(".").lower() == "network"),
]
client = anthropic.Anthropic()
print("模型".ljust(18) + "性質通過｜output_tokens｜回答")
for model in ["claude-opus-4-8", "claude-fable-5"]:
    try:
        msg = client.messages.create(
            model=model, max_tokens=50, output_config={"effort": "medium"},
            fallbacks=[{"model": "claude-opus-4-8"}] if model == "claude-fable-5" else None,
            messages=[{"role": "user", "content": PROMPT}])
    except anthropic.APIError as exc:
        print("  ❌ " + model + " 呼叫失敗：" + str(exc))
        continue
    text = msg.content[0].text if msg.content else ""
    passed = sum(bool(fn(text)) for _, fn in checks)
    print(model.ljust(18) + str(passed) + "/3     ｜" + str(msg.usage.output_tokens).rjust(5) + "        ｜" + text.strip()[:40])
print()
print("呼叫次數：" + str(claude_cli_client.calls_made()))
print()
print("──── 書附 monitor 離線分析（不呼叫模型）────")
if log.exists():
    print_report(analyze(log.read_text(encoding="utf-8").splitlines()))'
   show "$P"; py_run "$P" ;;
8) banner "總結"
   tip "遷移先 lint、CI 擋 error 也要看 warn、知道 linter 的缺口、切換前影子比對比性質。最後確認 fable5/migration 底下沒有被寫入任何檔案。"
   P='cat <<EOF
  第 7 章總結
    換模型不是改一個字串：temperature／top_p／top_k、手動 budget_tokens、thinking disabled 在 Fable 5 都直接 400
    帶過來的思考區塊不報錯卻白付輸入 token；linter 只給 warn，只看 exit code 的 CI 會放行（第 4 步）
    拒答是 HTTP 200＋空內容：Fable 5 請求一定要接 fallbacks＋server-side-fallback beta，否則卡死
    effort 明確寫在 output_config，整個機隊要調整時只改一處；1M 上下文同價，切分請求的邏輯可以拿掉
    linter 有缺口：空的 fallbacks、mythos-5、effort 打錯字、model 名稱打錯都放過（第 6 步），CI 要自己補
    切換前先影子比對：比可檢查的性質（格式、清單、長度），不是字面；轉接層測不到備援比例，要用真 API 補測
EOF
echo
if ls migration | grep -qv -e "^migration_linter.py$" -e "^sample_opus_request.json$" -e "^test_migration_linter.py$" -e "^__init__.py$" -e "^__pycache__$"; then echo "⚠️ fable5/migration 底下多了檔案"; else echo "✅ fable5/migration 沒被寫入"; fi'
   show "$P"; sh_run "$P" ;;
*) echo "用法：bash ch07.sh <步驟 1-8>"; exit 1 ;;
esac
