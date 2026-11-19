#!/bin/bash
# K143 第 1 章互動演練：改變了什麼——Fable 5、Mythos 5 與 Harness，一次跑一步
# 用法：bash ch01.sh <步驟 1-8>
# 全部用書附 fable5/ 範例離線執行，不呼叫模型、不需 API 金鑰
set -u
STEP="${1:-1}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PRACTICE="$HERE/.."
LAB="$PRACTICE/fable5"
WORK="$PRACTICE/ch01/interactive"   # 動手改的檔案放這裡，不碰 fable5/
mkdir -p "$WORK"
G=$'\e[32m'; Y=$'\e[33m'; C=$'\e[36m'; B=$'\e[1m'; N=$'\e[0m'

banner() { clear; printf '%s╔══════════════════════════════════════════════════════╗%s\n' "$C" "$N"; printf '%s  K143 第 1 章｜Fable 5 與 Harness　第 %s / 8 步%s\n' "$B" "$STEP" "$N"; printf '%s  %s%s\n' "$B" "$1" "$N"; printf '%s╚══════════════════════════════════════════════════════╝%s\n\n' "$C" "$N"; }
tip() { printf '%s💡 %s%s\n\n' "$Y" "$1" "$N"; }
show() { printf '%s▶ 要執行的指令：%s\n' "$G" "$N"; printf '%s' "$1" | sed "s/^/${G}  │ ${N}/"; printf '\n%s▶ 執行結果：%s\n' "$G" "$N"; }
done_step() { printf '\n%s👉 第 %s 步完成%s\n' "$C" "$STEP" "$N"; }
# 執行 shell 指令（在 fable5/ 目錄）
sh_run() { (cd "$LAB" && PYTHONUTF8=1 bash -c "$1"); done_step; }
# 執行 Python（先裝轉接層，讓會 import anthropic 的範例也能離線匯入）
py_run() { (cd "$LAB" && PYTHONUTF8=1 PYTHONPATH=. python - <<PY
import sys; sys.path.insert(0, ".."); import claude_cli_client; claude_cli_client.install()
$1
PY
); done_step; }

case "$STEP" in
1) banner "先看一份「舊世代」提示詞"
   tip "書附的 bad_prompt.md 是寫給舊模型的典型提示詞：大寫 IMPORTANT、YOU MUST、十幾條條列、要求逐步說明思考、還告訴模型剩多少 token。"
   P='cat -n fable_scanner/examples/bad_prompt.md'
   show "$P"; sh_run "$P" ;;
2) banner "用掃描器抓出舊鷹架"
   tip "fable_scanner 是書附的靜態掃描器，不呼叫模型。error 會觸發拒答或提早收工；warn 是新模型不需要的哄法。"
   P='python -m fable_scanner scan fable_scanner/examples/bad_prompt.md | grep -v "^ *https"'
   show "$P"; sh_run "$P" ;;
3) banner "對照：Harness 式的好提示詞"
   tip "good_prompt.md 用平鋪直敘講目標、邊界、驗證與停止條件。看內容，再掃一次，應該是 0 個問題。"
   P='cat fable_scanner/examples/good_prompt.md
echo; echo "──── 掃描結果 ────"
python -m fable_scanner scan fable_scanner/examples/good_prompt.md'
   show "$P"; sh_run "$P" ;;
4) banner "動手改：把兩個 error 拿掉"
   tip "複製一份舊提示詞到 ch01/interactive/，刪掉「逐步說明推理」和「剩餘 token」兩句，再掃。兩個 error（RX-01、FS-01）應該消失。"
   P='sed -e "/step by step/d" -e "/tokens remaining/d" fable_scanner/examples/bad_prompt.md > ../ch01/interactive/fixed_prompt.md
python -m fable_scanner scan ../ch01/interactive/fixed_prompt.md | grep -v "^ *https"'
   show "$P"; sh_run "$P" ;;
5) banner "API 請求也要遷移：送錯參數直接 400"
   tip "不只提示詞，請求本身也變了。這份舊的 Opus 請求帶了 temperature、top_p、手動 thinking 預算，在 Fable 5 上會直接被 400 擋下。"
   P='import json
from migration.migration_linter import lint
req = json.load(open("migration/sample_opus_request.json", encoding="utf-8"))
print("請求帶的欄位：", list(req))
print()
for field, sev, msg in lint(req):
    print(f"  {sev.upper():<5} {field:<22} {msg[:70]}")'
   show "$P"; py_run "$P" ;;
6) banner "先看 stop_reason，再讀內容"
   tip "Fable 5 拒答不是例外，而是 HTTP 200、stop_reason=refusal、內容是空的。模擬三種回應：直接回答、備援模型接手、全部拒答。"
   P='from types import SimpleNamespace as NS
from refusal.refusal_stack import read
def msg(stop, texts, model, iters):
    return NS(stop_reason=stop, model=model, stop_details=NS(category="cyber"),
              content=[NS(type="text", text=t) for t in texts],
              usage=NS(iterations=[NS(type=i) for i in iters]))
cases = {
    "Fable 直接回答": msg("end_turn", ["好的，這是摘要。"], "claude-fable-5", ["message"]),
    "Fable 拒答、備援接手": msg("end_turn", ["由備援模型回答。"], "claude-opus-4-8", ["message", "fallback_message"]),
    "全部拒答": msg("refusal", [], "claude-fable-5", ["message"]),
}
for name, m in cases.items():
    text, who = read(m)
    print(f"  {name:<12} stop_reason={m.stop_reason:<9} → 來源：{who}｜內容：{text}")'
   show "$P"; py_run "$P" ;;
7) banner "用 effort 控制深度與成本"
   tip "思考永遠開著，不能再送 thinking 參數；改用 effort 五個等級。分類、擷取用 low，摘要用 medium，遷移、稽核才用 xhigh。"
   P='from effort.effort_router import effort_for
for kind in ["classify", "extract", "summarize", "chat", "write-code", "migrate", "audit"]:
    lvl = effort_for({"kind": kind})
    print(f"  任務 {kind:<12} → effort = {lvl}")'
   show "$P"; py_run "$P" ;;
8) banner "總結：從精巧提示詞到 Harness"
   tip "工程重心從「把提示詞哄好」移到「圍繞模型的 Harness」：給目標、邊界、驗證方式與停止條件。五個模組各擋一種新模型特有的毛病。"
   P='print("""  五個提示詞模組（各擋一種毛病）
    邊界        → 沒授權就亂動手
    接地進度    → 沒證據就說「已完成」
    自主性      → 小事也停下來問
    白話摘要    → 自創縮寫、看不懂的報告
    上下文平靜  → 看到剩餘 token 就提早收工

  寫進程式的 API 注意事項
    不送 thinking／temperature，用 effort 控深度
    每個請求都接備援（fallbacks）
    先看 stop_reason 再讀內容
    做的人不當審的人（驗證子代理只看產出）""")'
   show "$P"; py_run "$P" ;;
*) echo "步驟要 1～8" ;;
esac
