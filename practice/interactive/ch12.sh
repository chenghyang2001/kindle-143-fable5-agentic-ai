#!/bin/bash
# K143 第 12 章互動演練：提示快取經濟學——回本次數、存活期、排序守則與真實快取欄位，一次跑一步
# 用法：bash ch12.sh <步驟 1-8>
# 只有第 6、7 步會真的呼叫模型（第 6 步 2 次、第 7 步 4 次）：走 claude -p（Max 訂閱），不設 ANTHROPIC_API_KEY
# 所有產出寫到 ch12/interactive/，fable5/ 一個檔都不改、也不寫入
set -u
# 轉接層每次呼叫才讀這個上限；第 7 步一個行程 4 次，設 6 留一點餘裕又擋得住失控迴圈
export K143_CLI_MAX_CALLS=6
STEP="${1:-1}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PRACTICE="$HERE/.."
LAB="$PRACTICE/fable5"
WORK="$PRACTICE/ch12/interactive"   # 動手改的檔案放這裡，不碰 fable5/
mkdir -p "$WORK"
G=$'\e[32m'; Y=$'\e[33m'; C=$'\e[36m'; B=$'\e[1m'; N=$'\e[0m'

banner() { clear; printf '%s╔══════════════════════════════════════════════════════╗%s\n' "$C" "$N"; printf '%s  K143 第 12 章｜提示快取經濟學　第 %s / 8 步%s\n' "$B" "$STEP" "$N"; printf '%s  %s%s\n' "$B" "$1" "$N"; printf '%s╚══════════════════════════════════════════════════════╝%s\n\n' "$C" "$N"; }
tip() { printf '%s💡 %s%s\n\n' "$Y" "$1" "$N"; }
show() { printf '%s▶ 要執行的指令：%s\n' "$G" "$N"; printf '%s' "$1" | sed "s/^/${G}  │ ${N}/"; printf '\n%s▶ 執行結果：%s\n' "$G" "$N"; }
done_step() { printf '\n%s👉 第 %s 步完成%s\n' "$C" "$STEP" "$N"; }
# 執行 shell 指令（在 fable5/ 目錄）
sh_run() { (cd "$LAB" && PYTHONUTF8=1 bash -c "$1"); done_step; }
# 執行 Python（先裝轉接層，讓 import anthropic 改走 claude -p；不寫 __pycache__ 進 fable5/）
py_run() { (cd "$LAB" && PYTHONUTF8=1 PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=. python - <<PY
import sys; sys.path.insert(0, ".."); import claude_cli_client; claude_cli_client.install()
$1
PY
); done_step; }

# 第 2～7 步共用：常數＋損益計算＋排序檢查
# 注意：py_run 的 heredoc 沒加引號，這段程式不可出現錢字號與反引號（金額一律寫 USD）
# 程式是經 $1 展開塞進 heredoc 的，展開結果不再做反斜線處理，所以 Python 跳脫照原樣寫
CALC_PY='import json
from pathlib import Path
from fable_scanner.monitor import PRICE_PER_M
WORK = Path("../ch12/interactive").resolve()
WORK.mkdir(parents=True, exist_ok=True)

# 出處：書中第 12 章（5 分鐘寫入 1.25 倍、1 小時寫入 2 倍）
WRITE_MULT = {"5m": 1.25, "1h": 2.0}
TTL_MIN = {"5m": 5, "1h": 60}
# 假設，需查官方定價頁確認
READ_MULT = 0.1
BATCH_DISCOUNT = 0.5
# 出處：fable5/fable_scanner/monitor.py PRICE_PER_M，與 README「10/50 pricing」一致
FABLE_IN = PRICE_PER_M["claude-fable-5"][0]

def cost(n_calls, prefix_tokens, ttl, price_per_m, writes=1, batch=False):
    """回傳（不用快取, 用快取）兩種總輸入成本；writes＝這段期間寫入快取幾次。"""
    base = prefix_tokens / 1e6 * price_per_m
    plain = n_calls * base
    if ttl is None:
        cached = plain
    else:
        w = min(writes, n_calls)
        cached = w * base * WRITE_MULT[ttl] + (n_calls - w) * base * READ_MULT
    if batch:
        cached = cached * BATCH_DISCOUNT
    return plain, cached

def break_even(ttl):
    """最少要複用幾次（呼叫數－1）才比不用快取便宜。"""
    k = 0
    while True:
        plain, cached = cost(k + 1, 1000000, ttl, 1)
        if cached < plain:
            return k
        k += 1

RANK = {"1h": 2, "5m": 1, None: 0}

def check_order(blocks):
    """短存活期（或不快取）排在較長存活期之前就回報：哪塊排錯、它一變會讓後面哪些快取失效。"""
    problems = []
    for i, b in enumerate(blocks):
        longer_after = [x["name"] for x in blocks[i + 1:] if RANK[x["ttl"]] > RANK[b["ttl"]]]
        if longer_after:
            hit = [x["name"] for x in blocks[i + 1:] if x["ttl"] is not None]
            problems.append({"block": b["name"], "ttl": b["ttl"], "排在它後面的較長區塊": longer_after, "會失效": hit})
    return problems
'

# 第 6、7 步共用：穩定長前綴＋呼叫一次並印快取欄位（同樣不可有錢字號與反引號）
LIVE_PY='import os
from datetime import datetime
import anthropic
from fable_scanner.monitor import analyze

# 約 1 萬 2 千 token 的穩定前綴（超過 Haiku 最小可快取長度），內容固定不變
STABLE = "你是 K143 演練的 SOC 助理，以下是全機隊共用、很少改的規則清單。\n" + "\n".join(
    "Rule " + str(i) + ": keep the answer short, cite the log line, never run commands." for i in range(1, 801))

def ask(tag, system, user, log):
    os.environ["K143_CLI_LOG"] = str(log)
    m = anthropic.Anthropic().messages.create(
        model="claude-haiku-4-5", system=system, output_config={"effort": "low"},
        messages=[{"role": "user", "content": user}])
    u = m.usage
    text = m.content[0].text.strip()[:10] if m.content else "（拒答）"
    print(f"  {tag:<16} 寫入快取={u.cache_creation_input_tokens:>6}  讀取快取={u.cache_read_input_tokens:>6}  未快取輸入={u.input_tokens:>5}  回覆={text}")
    return u
'

case "$STEP" in
1) banner "書附裡的定價與快取線索（本章沒有獨立資料夾）"
   tip "本章在書附 repo 沒有專屬資料夾。先找計算器要用的單價（monitor 單價表、README），再看兩個伏筆：重送會從零寫快取、書附 monitor 算錢完全沒算快取欄位。"
   P='echo "──── fable5/ 底下的資料夾（沒有 cache 專章資料夾）────"
ls -d */
echo
echo "──── README：Fable 5 定價 ────"
grep -n -i "pricing" README.md
echo
echo "──── monitor.py 的單價表（每百萬 token：輸入, 輸出）────"
sed -n 13,18p fable_scanner/monitor.py
echo
echo "──── monitor.py 怎麼算錢（只看 input_tokens / output_tokens）────"
sed -n 51,57p fable_scanner/monitor.py
echo
echo "──── credit_retry.py：重送會從零寫快取，比讀快取貴 ────"
sed -n 1,8p fallback_credit/credit_retry.py
echo
echo "──── 轉接層會把 claude -p 的快取欄位帶回來 ────"
grep -n "cache_" ../claude_cli_client.py'
   show "$P"; sh_run "$P" ;;
2) banner "用計算器驗證書中的回本次數"
   tip "把「寫入 1.25／2 倍、讀取 0.1 倍」寫成 cost()，以一份前綴原價當 1，列出複用 0～3 次的總成本。書中說 5 分鐘快取複用 1 次回本、1 小時要 2 次，看 break_even 是否一致。"
   P='print("乘數：寫入 5m=" + str(WRITE_MULT["5m"]) + "、1h=" + str(WRITE_MULT["1h"]) + "（書中）；讀取=" + str(READ_MULT) + "（假設，需查官方定價頁確認）")
print("以一份前綴的原價當 1，比較總輸入成本：")
print()
for ttl in ["5m", "1h"]:
    print("  ──── " + ttl + " 快取 ────")
    print("  複用次數  呼叫數  不快取  用快取  划算嗎")
    for k in range(4):
        plain, cached = cost(k + 1, 1000000, ttl, 1)
        ok = "是" if cached < plain else "否"
        print(f"  {k:>6}  {k + 1:>6}  {plain:>6.2f}  {cached:>6.2f}  {ok}")
    print()
book = {"5m": 1, "1h": 2}
for ttl in ["5m", "1h"]:
    got = break_even(ttl)
    verdict = "和書中一致" if got == book[ttl] else "和書中不一致（書：" + str(book[ttl]) + "）"
    print(f"  break_even({ttl}) = 複用 {got} 次就回本 → {verdict}")
print()
print("推算式：用快取＝寫入乘數＋複用次數×0.1；不快取＝(複用次數+1)×1")'
   show "$P"; py_run "$CALC_PY
$P" ;;
3) banner "算一份真實帳：無快取、5m、1h、1h＋批次"
   tip "Fable 輸入 10 USD／百萬 token、8 萬 token 共用前綴、每天 200 次呼叫，假設每個存活期內都有呼叫（一天只寫 1 次）。算四種做法的每日成本與降幅，結果存到 ch12/interactive/daily-cost.txt。"
   P='N, PREFIX = 200, 80000
print(f"Fable 輸入單價 {FABLE_IN} USD／百萬 token；前綴 {PREFIX} token；每天 {N} 次；假設每個存活期內都有呼叫（一天只寫 1 次）")
print()
rows = [
    ("無快取", None, False),
    ("5 分鐘快取", "5m", False),
    ("1 小時快取", "1h", False),
    ("1 小時快取＋批次 5 折", "1h", True),
]
plain0 = cost(N, PREFIX, None, FABLE_IN)[0]
lines = []
for name, ttl, batch in rows:
    _, c = cost(N, PREFIX, ttl, FABLE_IN, writes=1, batch=batch)
    drop = (plain0 - c) / plain0 * 100
    line = f"  {name:<14} 每日 {c:>7.2f} USD   降幅 {drop:>5.1f}%"
    print(line)
    lines.append(line)
(WORK / "daily-cost.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
print()
print("已存到 " + str(WORK / "daily-cost.txt"))'
   show "$P"; py_run "$CALC_PY
$P" ;;
4) banner "找缺口：存活期要配呼叫節奏，快取不保證省錢"
   tip "第 3 步假設每個存活期內都有呼叫。改成固定間隔 3、7.2（200 次平均攤在 24 小時）、30、90 分鐘：間隔超過存活期就過期、每次重寫。看 5 分鐘快取何時比不快取還貴。"
   P='N, PREFIX = 200, 80000
plain0 = cost(N, PREFIX, None, FABLE_IN)[0]
print("假設：每次命中會刷新存活期；間隔超過存活期就過期、下次重寫（需查官方文件確認）")
print(f"無快取基準：{plain0:.2f} USD")
print()
print("  間隔(分)   5m 快取 USD   1h 快取 USD")
for gap in [3, 7.2, 30, 90]:
    cells = []
    for ttl in ["5m", "1h"]:
        writes = 1 if gap <= TTL_MIN[ttl] else N
        _, c = cost(N, PREFIX, ttl, FABLE_IN, writes=writes)
        mark = "（比不快取貴）" if c > plain0 else ""
        cells.append(f"{c:>8.2f}{mark}")
    print(f"  {gap:>7}   {cells[0]:<16}  {cells[1]}")
print()
print("結論：200 次平均攤在一天（7.2 分鐘一次）時，5 分鐘快取每次都過期重寫，比不快取還貴；要改用 1 小時。")'
   show "$P"; py_run "$CALC_PY
$P" ;;
5) banner "排序檢查器：短存活期排前面會連累誰"
   tip "快取是位元組前綴比對，前面一塊變了，後面全部失效。check_order 檢查四種排法：正確、session 倒置在最前、中間夾一塊不快取的時間戳、空清單；最後用 4 個 assert 鎖住，結果存到 ch12/interactive/order-check.txt。"
   P='cases = {
    "正確排序": [
        {"name": "system", "ttl": "1h"}, {"name": "tools", "ttl": "1h"},
        {"name": "examples", "ttl": "1h"}, {"name": "session", "ttl": "5m"},
        {"name": "question", "ttl": None}],
    "倒置：session 在最前": [
        {"name": "session", "ttl": "5m"}, {"name": "system", "ttl": "1h"},
        {"name": "tools", "ttl": "1h"}, {"name": "question", "ttl": None}],
    "中間夾時間戳": [
        {"name": "system", "ttl": "1h"}, {"name": "timestamp", "ttl": None},
        {"name": "tools", "ttl": "1h"}, {"name": "session", "ttl": "5m"}],
    "空清單": [],
}
out = []
for name, blocks in cases.items():
    order = " → ".join(b["name"] + "(" + str(b["ttl"]) + ")" for b in blocks) or "（空）"
    probs = check_order(blocks)
    out.append("【" + name + "】" + order)
    if not probs:
        out.append("  ✅ 排序正確")
    for p in probs:
        out.append("  ❌ " + p["block"] + "(" + str(p["ttl"]) + ") 排在 " + "、".join(p["排在它後面的較長區塊"]) + " 前面；它一變，" + "、".join(p["會失效"]) + " 的快取全部失效")
print("\n".join(out))
assert break_even("5m") == 1 and break_even("1h") == 2
assert check_order(cases["正確排序"]) == []
assert [p["block"] for p in check_order(cases["倒置：session 在最前"])] == ["session"]
assert check_order([]) == []
print()
print("4 個 assert 全部通過")
(WORK / "order-check.txt").write_text("\n".join(out) + "\n", encoding="utf-8")
print("已存到 " + str(WORK / "order-check.txt"))'
   show "$P"; py_run "$CALC_PY
$P" ;;
6) banner "同一份長系統提示詞連打兩次：第 2 次讀快取（呼叫模型 2 次）"
   tip "會呼叫模型 2 次（claude-haiku-4-5、effort low），約需 20～60 秒。約 1 萬 2 千 token 的穩定前綴打兩次：第 1 次寫入快取、第 2 次幾乎全部讀快取。再用書附 monitor.analyze 算同一份 log，看它完全沒算快取帳。log 寫到 ch12/interactive/calls-same.jsonl。"
   P='log = WORK / "calls-same.jsonl"
if log.exists():
    log.unlink()                          # 舊 log 會讓統計算錯
print("穩定前綴約 " + str(len(STABLE)) + " 個字元，兩次完全相同；約需 20～60 秒")
print()
try:
    u1 = ask("第 1 次", STABLE, "只回一個字：好", log)
    u2 = ask("第 2 次（相同）", STABLE, "只回一個字：好", log)
except anthropic.APIError as exc:
    print("  ❌ 呼叫模型失敗：" + str(exc))
else:
    total = u2.cache_creation_input_tokens + u2.cache_read_input_tokens + u2.input_tokens
    plain = total / 1e6 * FABLE_IN
    priced = (u2.cache_creation_input_tokens * 1.25 + u2.cache_read_input_tokens * READ_MULT + u2.input_tokens) / 1e6 * FABLE_IN
    print()
    print(f"  第 2 次若照 Fable 單價計：不快取 {plain:.4f} USD；照書中乘數（5m 寫入、0.1 讀取）{priced:.4f} USD")
    stats = analyze(log.read_text(encoding="utf-8").splitlines())
    print("  書附 monitor 對同一份 log 算出的成本：" + json.dumps(stats["cost_by_model"], ensure_ascii=False))
    print("  → monitor 只用 input_tokens×單價，快取寫入／讀取的 token 完全沒進帳")
print("呼叫次數：" + str(len(log.read_text(encoding="utf-8").splitlines()) if log.exists() else 0))'
   show "$CALC_PY
$LIVE_PY
$P"; py_run "$CALC_PY
$LIVE_PY
$P" ;;
7) banner "時間戳放在前綴最前面，快取整段穿透（呼叫模型 4 次）"
   tip "會呼叫模型 4 次（claude-haiku-4-5、effort low），約需 1～2 分鐘。A 組把每次都變的時間戳放在後面的 user 訊息；B 組把時間戳放在系統提示詞最前面。各打兩次，看 B 組第 2 次幾乎讀不到快取、又重寫一大筆。log 寫到 ch12/interactive/calls-order.jsonl。"
   P='log = WORK / "calls-order.jsonl"
if log.exists():
    log.unlink()
def stamp():
    return datetime.now().isoformat()     # 精確到微秒，每次都不同
print("A 組：系統提示詞＝穩定前綴，時間戳放在後面的 user 訊息")
print("B 組：系統提示詞＝時間戳＋穩定前綴（易變內容排最前面）")
print("共 4 次呼叫，約需 1～2 分鐘")
print()
try:
    a1 = ask("A-1 時間在後", STABLE, "現在時間：" + stamp() + "。只回一個字：好", log)
    a2 = ask("A-2 時間在後", STABLE, "現在時間：" + stamp() + "。只回一個字：好", log)
    b1 = ask("B-1 時間在前", "現在時間：" + stamp() + "\n" + STABLE, "只回一個字：好", log)
    b2 = ask("B-2 時間在前", "現在時間：" + stamp() + "\n" + STABLE, "只回一個字：好", log)
except anthropic.APIError as exc:
    print("  ❌ 呼叫模型失敗：" + str(exc))
else:
    print()
    print(f"  A-2 讀到快取 {a2.cache_read_input_tokens} token；B-2 讀到快取 {b2.cache_read_input_tokens} token、又寫入 {b2.cache_creation_input_tokens} token")
    print("  → 前面變一個字，後面整段快取失效；所以 session 內容要排在穩定前綴之後")
print("呼叫次數：" + str(len(log.read_text(encoding="utf-8").splitlines()) if log.exists() else 0))'
   show "$CALC_PY
$LIVE_PY
$P"; py_run "$CALC_PY
$LIVE_PY
$P" ;;
8) banner "總結：順序就是成本"
   tip "提示快取省不省錢，看的是兩件事：區塊的排列順序，以及存活期有沒有配上呼叫節奏。"
   P='cat <<EOF
  第 12 章總結
    提示快取是位元組前綴比對：前面變一個字，後面整段快取失效（第 7 步 B 組）
    5 分鐘快取寫入 1.25 倍、複用 1 次回本；1 小時寫入 2 倍、複用 2 次回本（第 2 步驗過）
    快取不保證省錢：呼叫間隔超過存活期就每次重寫，5 分鐘快取反而比不快取貴（第 4 步）
    排序守則：存活期長、最穩定的放最前（系統提示詞、工具、範例放 1 小時），session 內容放 5 分鐘排後面，每次都變的不快取、放最後
    快取再疊批次折扣，每天 160 USD 可以壓到 8.76 USD 左右；讀取 0.1 倍與批次 5 折是假設，要查官方定價頁
    成本儀表板要把快取寫入／讀取 token 算進去，書附 monitor 只看 input_tokens 會看不到這筆帳（第 6 步）
EOF'
   show "$P"; sh_run "$P" ;;
*) echo "用法：bash ch12.sh <步驟 1-8>"; exit 1 ;;
esac
