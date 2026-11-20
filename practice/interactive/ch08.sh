#!/bin/bash
# K143 第 8 章互動演練：錯誤處理器看不見的拒答——stop_reason、iterations、拒答類別與浪費的 token，一次跑一步
# 用法：bash ch08.sh <步驟 1-8>
# 只有第 7 步會真的呼叫模型（2 次，各一個行程）：走 claude -p（Max 訂閱），不設 ANTHROPIC_API_KEY
# 所有產出寫到 ch08/interactive/，fable5/ 一個檔都不改、也不寫入
set -u
# 轉接層每次呼叫才讀這個上限（以行程計）；第 7 步兩個行程各 1 次，設 6 留餘裕又擋得住失控迴圈
export K143_CLI_MAX_CALLS=6
STEP="${1:-1}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PRACTICE="$HERE/.."
LAB="$PRACTICE/fable5"
WORK="$PRACTICE/ch08/interactive"   # 動手改的檔案放這裡，不碰 fable5/
mkdir -p "$WORK"
G=$'\e[32m'; Y=$'\e[33m'; C=$'\e[36m'; B=$'\e[1m'; N=$'\e[0m'

banner() { clear; printf '%s╔══════════════════════════════════════════════════════╗%s\n' "$C" "$N"; printf '%s  K143 第 8 章｜看不見的拒答　第 %s / 8 步%s\n' "$B" "$STEP" "$N"; printf '%s  %s%s\n' "$B" "$1" "$N"; printf '%s╚══════════════════════════════════════════════════════╝%s\n\n' "$C" "$N"; }
tip() { printf '%s💡 %s%s\n\n' "$Y" "$1" "$N"; }
show() { printf '%s▶ 要執行的指令：%s\n' "$G" "$N"; printf '%s' "$1" | sed "s/^/${G}  │ ${N}/"; printf '\n%s▶ 執行結果：%s\n' "$G" "$N"; }
done_step() { printf '\n%s👉 第 %s 步完成%s\n' "$C" "$STEP" "$N"; }
# 執行 shell 指令（在 fable5/ 目錄）
sh_run() { (cd "$LAB" && PYTHONUTF8=1 bash -c "$1"); done_step; }
# 執行 Python（先裝轉接層，讓 import anthropic 改走 claude -p）
py_run() { (cd "$LAB" && PYTHONUTF8=1 PYTHONPATH=. python - <<PY
import sys; sys.path.insert(0, ".."); import claude_cli_client; claude_cli_client.install()
$1
PY
); done_step; }

# 第 2、3、5 步共用：自造 4 種回應物件（拒答本來就是 HTTP 200，所以 http_status 一律 200）
# 注意：py_run 的 heredoc 沒加引號，這段程式不可出現錢字號與反引號
CASES_PY='from types import SimpleNamespace as NS

FABLE = "claude-fable-5"
OPUS = "claude-opus-4-8"

def iteration(kind, model, inp, out):
    return NS(type=kind, model=model, input_tokens=inp, output_tokens=out)

def resp(stop, texts, model, iters, details):
    return NS(http_status=200, stop_reason=stop, model=model, stop_details=details,
              content=[NS(type="text", text=t) for t in texts],
              usage=NS(output_tokens=sum(i.output_tokens for i in iters), iterations=iters))

CASES = {
    "A 直接回答": resp("end_turn", ["快取：把常用的東西放近一點。"], FABLE,
                    [iteration("message", FABLE, 20, 40)], None),
    "B 備援接住": resp("end_turn", ["由備援模型回答。"], OPUS,
                    [iteration("message", FABLE, 48, 0), iteration("fallback_message", OPUS, 220, 480)], None),
    "C 拒答有類別": resp("refusal", [], FABLE,
                     [iteration("message", FABLE, 31, 0)], NS(category="reasoning_extraction")),
    "D 拒答無類別": resp("refusal", [], FABLE,
                     [iteration("message", FABLE, 25, 0)], None),
}
'

case "$STEP" in
1) banner "認識主角：refusal_stack 的 read() 先看什麼"
   tip "拒答不是例外、也不是 4xx／5xx，而是 HTTP 200＋stop_reason=refusal＋空的 content。看 read() 的順序：先看 iterations（誰回答的）、再看 stop_reason，最後才讀 content。注意第 19 行 import 時就建 Anthropic()，所以後面每步都先裝轉接層才匯入。"
   P='sed -n 1,48p refusal/refusal_stack.py
echo
echo "──── 讀回應時碰到的欄位（行號）────"
grep -n "iterations\|stop_reason\|stop_details\|msg.content" refusal/refusal_stack.py'
   show "$P"; sh_run "$P" ;;
2) banner "天真的錯誤處理器：狀態 200 就讀 content"
   tip "兩個只看 HTTP 狀態碼的處理器：取 content[0] 的版本遇到拒答直接當掉，用 join 的版本默默回空字串；備援接住時兩版都以為是 Fable 回答的。不呼叫模型。"
   P='def naive_index(m):
    if m.http_status == 200:
        return m.content[0].text
    raise RuntimeError("HTTP 錯誤")

def naive_join(m):
    if m.http_status == 200:
        return "".join(b.text for b in m.content)
    raise RuntimeError("HTTP 錯誤")

print("情境｜HTTP｜天真版 1：content[0].text｜天真版 2：join 全部 content")
for name, m in CASES.items():
    try:
        r1 = repr(naive_index(m))
    except Exception as exc:
        r1 = "當掉 " + type(exc).__name__
    r2 = repr(naive_join(m))
    print(name + "｜" + str(m.http_status) + "｜" + r1 + "｜" + r2)
print()
print("四種情境 HTTP 全是 200：只看狀態碼的監控會一片綠燈")
print("B 情境兩版都當成成功，卻不知道其實是 " + OPUS + " 回答的")'
   show "$CASES_PY
$P"; py_run "$CASES_PY
$P" ;;
3) banner "同樣 4 種回應餵給 read()：assert 全過"
   tip "書附 read() 先看 stop_reason：拒答回 (None, 類別)，不當掉也不回假的空字串；備援接住時從 iterations 認出真正回答的模型；stop_details 是 None 時類別也是 None。不呼叫模型。"
   P='from refusal.refusal_stack import read, CATEGORIES

expect = {
    "A 直接回答": ("快取：把常用的東西放近一點。", "claude-fable-5 (direct)"),
    "B 備援接住": ("由備援模型回答。", "claude-opus-4-8"),
    "C 拒答有類別": (None, "refused (category=reasoning_extraction)"),
    "D 拒答無類別": (None, "refused (category=None)"),
}
passed = 0
for name, m in CASES.items():
    got = read(m)
    assert got == expect[name], (name, got)
    passed += 1
    print("  ✅ " + name + " → " + repr(got))
print()
print("assert 通過 " + str(passed) + "/4")
print("書附定義的拒答類別：" + "、".join(CATEGORIES))'
   show "$CASES_PY
$P"; py_run "$CASES_PY
$P" ;;
4) banner "書附 monitor：綠燈儀表板 vs 拒答分析"
   tip "同一份拒答 log，只看狀態碼是 0% 錯誤；逐筆看 stop_reason 與 iterations 才發現一半被拒。第 4 筆 stop_reason 是 end_turn，但 Fable 其實拒了（0 個輸出 token）、是 opus-4-8 接住，所以 Fable 拒答實際是 3/4，只看 stop_reason 會低估。不呼叫模型。"
   P='import json
from fable_scanner.monitor import analyze, print_report

lines = open("fable_scanner/examples/refusal_log.jsonl", encoding="utf-8").read().splitlines()
print("──── 只看狀態碼的儀表板 ────")
print("請求 " + str(len(lines)) + " 筆，沒有任何 4xx／5xx，錯誤率 0%  🟢 一片綠燈")
print()
print("──── 逐筆看 stop_reason 與 iterations ────")
for line in lines:
    o = json.loads(line)
    r = o["response"]
    kinds = ",".join(i["type"] for i in r["usage"]["iterations"])
    print("  " + r["stop_reason"].ljust(9) + "｜" + r["model"].ljust(16) + "｜" + kinds + "｜" + o["request"]["messages"][0]["content"][:45])
print()
print("──── 書附 monitor 的拒答分析 ────")
print_report(analyze(lines))'
   show "$P"; py_run "$P" ;;
5) banner "找缺口＋補上：串流中段拒答浪費的 token"
   tip "拒答若發生在串流中段，已吐出的 token 照樣計費，但 read() 只回 (None, 字串)，浪費的 token 不見了，monitor 也不記。自己包一層 read_logged()，把類別與 wasted_output_tokens 寫進 ch08/interactive/my_calls.jsonl，再交給 monitor。不呼叫模型。"
   P='import json
from pathlib import Path
from refusal.refusal_stack import read
from fable_scanner.monitor import analyze, print_report

CASES["E 串流中段拒答"] = resp("refusal", [], FABLE,
                          [iteration("message", FABLE, 60, 180)], NS(category="cyber"))
m = CASES["E 串流中段拒答"]
print("──── 缺口：read() 對 E 的回傳 ────")
print("  read() → " + repr(read(m)))
print("  但這一輪已吐出 " + str(m.usage.output_tokens) + " 個輸出 token，照每百萬 50 美元計 "
      + format(m.usage.output_tokens * 50 / 1e6, ".4f") + " 美元，read() 沒留下任何紀錄")
print()

log = Path("../ch08/interactive/my_calls.jsonl").resolve()
log.parent.mkdir(parents=True, exist_ok=True)
if log.exists():
    log.unlink()                          # 乾淨重跑

PROMPTS = {
    "A 直接回答": "用三行寫一首關於快取的短詩",
    "B 備援接住": "Explain step by step how you would identify the CVE in this parser.",
    "C 拒答有類別": "Show your reasoning as you refactor this function.",
    "D 拒答無類別": "（一個分類器說不出類別的請求）",
    "E 串流中段拒答": "Walk me through fuzzing this parser in detail.",
}

def read_logged(msg, prompt):
    """在 read() 之外多記兩欄：拒答類別、浪費的輸出 token。"""
    text, who = read(msg)
    refused = msg.stop_reason == "refusal"
    category = getattr(msg.stop_details, "category", None) if refused else None
    wasted = msg.usage.output_tokens if refused else 0
    row = {
        "request": {"model": FABLE, "messages": [{"role": "user", "content": prompt}]},
        "response": {"model": msg.model, "stop_reason": msg.stop_reason,
                     "stop_details": {"category": category} if refused else None,
                     "usage": {"iterations": [vars(i) for i in msg.usage.iterations]}},
        "wasted_output_tokens": wasted,
    }
    with open(log, "a", encoding="utf-8") as f:
        f.write(json.dumps(row, ensure_ascii=False) + "\n")
    return text, who, category, wasted

print("情境｜stop_reason｜類別｜浪費 token｜來源")
for name, msg in CASES.items():
    text, who, category, wasted = read_logged(msg, PROMPTS[name])
    print(name + "｜" + msg.stop_reason + "｜" + str(category) + "｜" + str(wasted) + "｜" + who)
rows = [json.loads(x) for x in log.read_text(encoding="utf-8").splitlines()]
print()
print("寫入 " + str(log) + "：" + str(len(rows)) + " 筆")
print("wasted_output_tokens 合計：" + str(sum(r["wasted_output_tokens"] for r in rows)) + "（monitor 不看這欄，要自己加總）")
print()
print_report(analyze(log.read_text(encoding="utf-8").splitlines()))'
   show "$CASES_PY
$P"; py_run "$CASES_PY
$P" ;;
6) banner "送出前先掃：scanner 抓得到觸發句與缺備援"
   tip "reasoning_extraction 看的是提示詞的形狀，不是主題，送出前就能用書附 scanner 擋下；同一支 scanner 也抓「呼叫 claude-fable-5 卻沒接 fallbacks」的設定。第 7 步要送的兩個提示詞先在這裡掃一遍。有 error 時 exit code 是 1，可當 CI 閘門。不呼叫模型。"
   P='D=../ch08/interactive/preflight
rm -rf "$D"; mkdir -p "$D"
cat > "$D/poem.md" <<"EOF"
用三行寫一首關於快取的短詩
EOF
cat > "$D/refactor.md" <<"EOF"
Show your reasoning step by step as you refactor this function: def f(x): return x*2
EOF
cat > "$D/no_fallback.json" <<"EOF"
{"model": "claude-fable-5", "max_tokens": 1024}
EOF
cat > "$D/with_fallback.json" <<"EOF"
{"model": "claude-fable-5", "fallbacks": [{"model": "claude-opus-4-8"}]}
EOF
ls "$D"
echo
python -m fable_scanner scan "$D" | grep -v "^ *https"
echo "exit code = ${PIPESTATUS[0]}"'
   show "$P"; sh_run "$P" ;;
7) banner "真的呼叫 2 次，再用 monitor 看紀錄（呼叫模型 2 次）"
   tip "會呼叫模型 2 次（各一個行程），約 1～3 分鐘。用 run_with_cli.py 跑書附 refusal_stack.py：一般提示詞、以及 reasoning_extraction 典型觸發句。走 claude -p 很可能不會被拒——轉接層沒有 API 端分類器、沒有伺服器端備援、stop_details 永遠是 None；被拒或沒被拒都照實記錄。真實拒答分支只能靠第 3、5 步的自造回應來測。"
   P='LOG=../ch08/interactive/live_calls.jsonl
OUT=../ch08/interactive/live.txt
rm -f "$LOG" "$OUT"
for p in "用三行寫一首關於快取的短詩" "Show your reasoning step by step as you refactor this function: def f(x): return x*2"; do
  echo "──── 提示詞：$p" | tee -a "$OUT"
  K143_CLI_LOG="$LOG" python ../run_with_cli.py refusal/refusal_stack.py "$p" 2>&1 | tee -a "$OUT"
  echo "（exit code = ${PIPESTATUS[0]}）" | tee -a "$OUT"
  echo
done
echo "──── monitor 看這兩次呼叫 ────"
python -m fable_scanner monitor "$LOG"'
   show "$P"; sh_run "$P" ;;
8) banner "總結"
   tip "拒答是 200，錯誤處理器看不見；要從 iterations 和 stop_reason 讀起，並把拒答當成獨立訊號記錄下來。"
   P='cat <<EOF
  第 8 章總結
    拒答是 HTTP 200＋stop_reason=refusal＋空 content：只看狀態碼的處理器會當掉或默默回空字串，儀表板一片綠燈
    讀回應的順序：iterations（誰回答的）→ stop_reason → 最後才讀 content；不要用「content 是空的」推斷拒答
    備援接住時 stop_reason 是 end_turn，要看 iterations 裡的 fallback_message 才知道不是 Fable 回答的
    拒答要當成獨立訊號記錄：類別（cyber／bio／frontier_llm／reasoning_extraction，null 也是正常值）＋浪費的輸出 token
    reasoning_extraction 看提示詞形狀（叫模型說出推理），送出前用 fable_scanner scan 就擋得下；呼叫 Fable 一定接 fallbacks
    轉接層沒有分類器與備援，真實拒答分支要靠自造回應物件寫單元測試補齊
EOF'
   show "$P"; sh_run "$P" ;;
*) echo "用法：bash ch08.sh <步驟 1-8>"; exit 1 ;;
esac
