#!/bin/bash
# K143 第 9 章互動演練：備援切換時別付兩次錢——fallback credit、本體一致與黏性路由，一次跑一步
# 用法：bash ch09.sh <步驟 1-8>
# 只有第 7 步會真的呼叫模型（1 次）：走 claude -p（Max 訂閱），不設 ANTHROPIC_API_KEY
# 所有產出寫到 ch09/interactive/，fable5/ 一個檔都不改、也不寫入
set -u
# 轉接層每次呼叫才讀這個上限；第 7 步只呼叫 1 次，設 6 留餘裕又擋得住失控迴圈
export K143_CLI_MAX_CALLS=6
STEP="${1:-1}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PRACTICE="$HERE/.."
LAB="$PRACTICE/fable5"
WORK="$PRACTICE/ch09/interactive"   # 動手改的檔案放這裡，不碰 fable5/
mkdir -p "$WORK"
G=$'\e[32m'; Y=$'\e[33m'; C=$'\e[36m'; B=$'\e[1m'; N=$'\e[0m'

banner() { clear; printf '%s╔══════════════════════════════════════════════════════╗%s\n' "$C" "$N"; printf '%s  K143 第 9 章｜備援重試與 credit　第 %s / 8 步%s\n' "$B" "$STEP" "$N"; printf '%s  %s%s\n' "$B" "$1" "$N"; printf '%s╚══════════════════════════════════════════════════════╝%s\n\n' "$C" "$N"; }
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

# 第 2～5、7 步共用：會記錄請求本體的假 client 與一份固定的請求參數
# credit_retry.py 沒有 import anthropic，可直接匯入；它本身也不寫檔
# 注意：py_run 的 heredoc 沒加引號，這段程式不可出現錢字號與反引號（金額一律寫「美元」）
FAKE_PY='import copy
from types import SimpleNamespace as NS
from fallback_credit.credit_retry import (manual_fallback_with_credit, served_by_sticky,
                                          refused, CREDIT_BETA, FALLBACK_BETA)

FABLE = "claude-fable-5"
OPUS = "claude-opus-4-8"

def ok(model):
    return NS(stop_reason="end_turn", model=model, stop_details=None,
              content=[NS(type="text", text="好的，這是答案。")])

def refusal(token=None, prefill=False):
    return NS(stop_reason="refusal", model=FABLE, content=[],
              stop_details=NS(category="cyber", fallback_credit_token=token,
                              fallback_has_prefill_claim=prefill))

class FakeClient:
    """照劇本回應，並把每次請求本體深拷貝存起來（不深拷貝的話，事後被改的 list 會連帶改到紀錄）"""
    def __init__(self, script):
        self.script = list(script)
        self.sent = []
        self.beta = NS(messages=NS(create=self._create))
    def _create(self, **kw):
        self.sent.append(copy.deepcopy(kw))
        return self.script.pop(0)

PARAMS = {
    "model": FABLE,
    "max_tokens": 1024,
    "system": [{"type": "text", "text": "你是資安助理，只做防禦性分析。" * 3,
                "cache_control": {"type": "ephemeral"}}],
    "messages": [{"role": "user", "content": [
        {"type": "text", "text": "請檢查這段 parser 有沒有越界讀取"},
        {"type": "text", "text": ""},
    ]}],
}

def diff_keys(a, b):
    return sorted(k for k in set(a) | set(b) if a.get(k) != b.get(k))
'

case "$STEP" in
1) banner "認識主角：credit_retry.py 的兩個函式"
   tip "自己寫重試迴圈時，在備援模型上重送會從頭寫一次提示快取。平台拒答時給一次性 token，重試原樣帶回去才不會付兩次。先看程式怎麼「只換 model、加 credit」。"
   P='sed -n 1,53p fallback_credit/credit_retry.py
echo
echo "──── 關鍵行（行號）────"
grep -n "betas=\|fallback_credit\|dict(params\|getattr\|iterations\|return" fallback_credit/credit_retry.py
echo
echo "這支有幾行 import：$(grep -c "^import\|^from" fallback_credit/credit_retry.py)（0 表示不用先裝轉接層也能匯入）"'
   show "$P"; sh_run "$P" ;;
2) banner "假 client 跑三個情境：本體逐欄一致"
   tip "轉接層沒有 credit 機制，只能用會記錄請求的假 client 測重試邏輯。三個情境：一次成功、拒答有 token、拒答沒 token。重點是有 token 那個要逐欄比對，除了 model 與 fallback_credit 其他欄位一個都不能變。"
   P='# (a) 第一次就成功
c = FakeClient([ok(FABLE)])
m = manual_fallback_with_credit(c, PARAMS, OPUS)
assert len(c.sent) == 1 and m.stop_reason == "end_turn"
print("(a) 一次成功：呼叫 " + str(len(c.sent)) + " 次，回答模型 " + m.model + " ✅")

# (b) 拒答且有 token
c = FakeClient([refusal("tok-001", True), ok(OPUS)])
m = manual_fallback_with_credit(c, PARAMS, OPUS)
first, retry = c.sent
print("(b) 第一次請求欄位：" + ", ".join(first))
print("    重試請求欄位：  " + ", ".join(retry))
d = diff_keys(first, retry)
print("    不一樣的欄位：  " + str(d))
assert d == ["fallback_credit", "model"], d
for k in first:
    if k != "model":
        assert first[k] == retry[k], k          # 逐欄比，不是只比 model
assert retry["fallback_credit"] == {"token": "tok-001", "has_prefill_claim": True}
print("    model：" + first["model"] + " → " + retry["model"])
print("    fallback_credit：" + str(retry["fallback_credit"]) + " ✅")

# (c) 拒答但沒有 token
c = FakeClient([refusal(None), ok(OPUS)])
m = manual_fallback_with_credit(c, PARAMS, OPUS)
assert len(c.sent) == 2 and "fallback_credit" not in c.sent[1]
print("(c) 沒 token：仍然重試（共 " + str(len(c.sent)) + " 次），重試沒帶 credit → 快取會從頭寫 ✅")'
   show "$FAKE_PY
$P"; py_run "$FAKE_PY
$P" ;;
3) banner "body_matches：「好心清洗」讓折抵失效"
   tip "「完全一致」是字面意思。重試前順手刪掉空字串的 content 區塊、或改大 max_tokens，平台就判定本體不一致，credit 失效、照樣付快取寫入。三種重試寫法並排比較。"
   P='IGNORED = {"model", "fallback_credit"}

def body_matches(first, retry):
    """忽略 model 與 fallback_credit 後，兩個請求本體是否完全相同"""
    keep = lambda r: {k: v for k, v in r.items() if k not in IGNORED}
    return keep(first) == keep(retry)

def tidy_retry(client, params, fallback_model):
    """錯誤示範：重試前「好心」刪掉空白 content 區塊"""
    first = client.beta.messages.create(betas=[CREDIT_BETA], **params)
    if not refused(first):
        return first
    d = first.stop_details
    clean = copy.deepcopy(params)
    for msg in clean["messages"]:
        msg["content"] = [b for b in msg["content"] if b.get("text") != ""]
    return client.beta.messages.create(
        betas=[CREDIT_BETA],
        fallback_credit={"token": d.fallback_credit_token, "has_prefill_claim": d.fallback_has_prefill_claim},
        **dict(clean, model=fallback_model))

def bigger_budget_retry(client, params, fallback_model):
    """錯誤示範：重試時順便把 max_tokens 調大"""
    first = client.beta.messages.create(betas=[CREDIT_BETA], **params)
    d = first.stop_details
    return client.beta.messages.create(
        betas=[CREDIT_BETA],
        fallback_credit={"token": d.fallback_credit_token, "has_prefill_claim": False},
        **dict(params, model=fallback_model, max_tokens=4096))

print("重試寫法｜body_matches｜差在哪些欄位（忽略 model、fallback_credit）")
for name, fn in [("書附 manual_fallback_with_credit", manual_fallback_with_credit),
                 ("好心清洗空白區塊", tidy_retry),
                 ("順便調大 max_tokens", bigger_budget_retry)]:
    c = FakeClient([refusal("tok-002"), ok(OPUS)])
    fn(c, PARAMS, OPUS)
    first, retry = c.sent
    ok_match = body_matches(first, retry)
    extra = [k for k in diff_keys(first, retry) if k not in IGNORED]
    print(name + "｜" + str(ok_match) + "｜" + str(extra))

c = FakeClient([refusal("tok-002"), ok(OPUS)])
tidy_retry(c, PARAMS, OPUS)
print()
print("清洗前 content 區塊數：" + str(len(c.sent[0]["messages"][0]["content"]))
      + "，清洗後：" + str(len(c.sent[1]["messages"][0]["content"])))'
   show "$FAKE_PY
$P"; py_run "$FAKE_PY
$P" ;;
4) banner "找缺口：自帶 betas 就當掉、重試又被拒沒人管"
   tip "書附範例只示範形狀。實務上每個 Fable 請求都帶 FALLBACK_BETA，params 裡已經有 betas 時，betas=[...] 加 **params 會在送出前就 TypeError；重試結果也不再檢查。最後在記憶體裡寫一個合併 betas 的修正版，不改 fable5/。"
   P='# 缺口 1：params 自帶 betas
P2 = dict(PARAMS, betas=[FALLBACK_BETA])
c = FakeClient([ok(FABLE)])
try:
    manual_fallback_with_credit(c, P2, OPUS)
    print("缺口 1：沒當掉（不符預期）")
except TypeError as exc:
    print("缺口 1：TypeError：" + str(exc))
print("        FakeClient 收到幾次請求：" + str(len(c.sent)) + "（還沒送出就掛了）")
print()

# 缺口 2：重試也被拒
c = FakeClient([refusal("tok-003"), refusal(None)])
m = manual_fallback_with_credit(c, PARAMS, OPUS)
print("缺口 2：重試也被拒 → 函式回傳 stop_reason=" + m.stop_reason + "，content=" + str(m.content))
print("        呼叫端若直接讀 content[0] 會當掉，要自己再看 refused(m) = " + str(refused(m)))
print()

# 修正版（只在記憶體裡定義，不改 fable5/）：合併 betas，其他照書附
def manual_fallback_merged(client, params, fallback_model):
    params = dict(params)
    betas = list(params.pop("betas", []))
    if CREDIT_BETA not in betas:
        betas.append(CREDIT_BETA)
    first = client.beta.messages.create(betas=betas, **params)
    if not refused(first):
        return first
    d = first.stop_details
    token = getattr(d, "fallback_credit_token", None)
    retry = dict(params, model=fallback_model)
    extra = {} if token is None else {"fallback_credit": {
        "token": token, "has_prefill_claim": getattr(d, "fallback_has_prefill_claim", False)}}
    return client.beta.messages.create(betas=betas, **extra, **retry)

c = FakeClient([refusal("tok-004"), ok(OPUS)])
m = manual_fallback_merged(c, P2, OPUS)
first, retry = c.sent
print("修正版：betas = " + str(first["betas"]))
print("        不一樣的欄位：" + str(diff_keys(first, retry)) + "｜回答模型 " + m.model)
assert diff_keys(first, retry) == ["fallback_credit", "model"]'
   show "$FAKE_PY
$P"; py_run "$FAKE_PY
$P" ;;
5) banner "served_by_sticky：備援率別算錯"
   tip "黏性路由時這一輪直接由備援模型服務，iterations 裡只有 fallback_message、沒有原模型的嘗試。只數「有沒有 fallback_message」會把黏性輪次也算成備援，備援率就失真。"
   P='def turn(*kinds):
    return NS(usage=NS(iterations=[NS(type=k) for k in kinds]) if kinds else NS(iterations=None))

shapes = {
    "直接回答": turn("message"),
    "真正備援": turn("message", "fallback_message"),
    "黏性路由": turn("fallback_message"),
    "iterations 是 None": turn(),
}
expect = {"直接回答": False, "真正備援": False, "黏性路由": True, "iterations 是 None": False}
print("形狀｜iterations｜served_by_sticky")
for name, m in shapes.items():
    got = served_by_sticky(m)
    assert got == expect[name], name
    kinds = [i.type for i in (m.usage.iterations or [])]
    print("  " + name + "｜" + str(kinds) + "｜" + str(got))
print()

# 一天 10 輪：6 直接、1 真正備援、3 黏性
day = ["直接回答"] * 6 + ["真正備援"] + ["黏性路由"] * 3
naive = sum(any(i.type == "fallback_message" for i in shapes[s].usage.iterations) for s in day)
sticky = sum(served_by_sticky(shapes[s]) for s in day)
real = naive - sticky
print("天真算法（有 fallback_message 就算備援）：" + str(naive) + "/10 = " + str(naive * 10) + "%")
print("分開統計：真正備援 " + str(real) + "/10 = " + str(real * 10) + "%，黏性路由 " + str(sticky) + "/10 = " + str(sticky * 10) + "%")'
   show "$FAKE_PY
$P"; py_run "$FAKE_PY
$P" ;;
6) banner "成本試算：5 萬 token 系統提示詞的一次拒答重試"
   tip "用自擬數字算「付兩次」到底多貴。Fable 單價取 README；書附沒有 Opus 4.8 單價，這裡假設輸入每百萬 5 美元；快取寫入 1.25 倍、讀取 0.1 倍也是假設。結果寫到 ch09/interactive/cost.txt，每次重跑會覆蓋。"
   P='from pathlib import Path
line = [l.strip() for l in open("README.md", encoding="utf-8") if "pricing" in l and "adaptive" in l]
print("README 原文：" + (line[0] if line else "（找不到含 pricing 的那行）"))
print()
S = 50_000                 # 假設：系統提示詞 token 數
FABLE_IN = 10              # README：Fable 5 輸入每百萬 token 10 美元
OPUS_IN = 5                # 假設：書附沒寫 Opus 4.8 單價
WRITE, READ = 1.25, 0.10   # 假設：快取寫入 1.25 倍、讀取 0.1 倍
REFUSALS_PER_DAY = 200     # 假設：一天 200 次被拒後重試

fable_write = S / 1e6 * FABLE_IN * WRITE
opus_write = S / 1e6 * OPUS_IN * WRITE
opus_read = S / 1e6 * OPUS_IN * READ
no_token = fable_write + opus_write
with_token = fable_write + opus_read
rows = [
    "【全部是假設，只看量級】S=50000 token，Fable 輸入 10、Opus 輸入 5（美元／百萬 token），寫 1.25 倍、讀 0.1 倍",
    "第一次在 Fable 寫快取：50000/1e6 x 10 x 1.25 = " + format(fable_write, ".4f") + " 美元（兩種做法都要付）",
    "沒帶 token：重試在 Opus 從頭寫快取 50000/1e6 x 5 x 1.25 = " + format(opus_write, ".4f") + " → 合計 " + format(no_token, ".4f"),
    "有帶 token：重試按讀快取計 50000/1e6 x 5 x 0.1 = " + format(opus_read, ".4f") + " → 合計 " + format(with_token, ".4f"),
    "每次拒答差額：" + format(no_token - with_token, ".4f") + " 美元；一天 200 次差 " + format((no_token - with_token) * REFUSALS_PER_DAY, ".2f") + " 美元",
    "第 3 步的好心清洗會讓 credit 失效 → 回到「沒帶 token」那一列",
]
out = Path("../ch09/interactive/cost.txt").resolve()
out.write_text("\n".join(rows) + "\n", encoding="utf-8")
print("\n".join(rows))
print()
print("已寫入 " + str(out))'
   show "$P"; py_run "$P" ;;
7) banner "混合 client：劇本拒答＋轉接層重試"
   tip "會呼叫模型 1 次。第一次請求由劇本假裝拒答、不呼叫模型；重試交給 claude -p，用 K143_CLI_MODEL=haiku 加快，約 20～90 秒。看 credit 欄位確實送出，但轉接層把 betas、fallback_credit 都忽略。結果寫到 ch09/interactive/live.txt。"
   P='import os
from pathlib import Path
import anthropic
import claude_cli_client
os.environ["K143_CLI_MODEL"] = "haiku"          # 轉接層每次呼叫才讀，設在這裡就生效
real = anthropic.Anthropic()                     # 已 install()，拿到的是轉接層
sent = []

def create(**kw):
    sent.append(copy.deepcopy(kw))
    if len(sent) == 1:                           # 第一次：劇本拒答，不呼叫模型
        return refusal("tok-live-001", False)
    return real.beta.messages.create(**kw)       # 第二次：真的走 claude -p

client = NS(beta=NS(messages=NS(create=create)))
params = dict(PARAMS, messages=[{"role": "user", "content": [
    {"type": "text", "text": "用一句繁體中文說明什麼是提示快取"}, {"type": "text", "text": ""}]}])
out = Path("../ch09/interactive/live.txt").resolve()
if out.exists():
    out.unlink()                                 # 清掉上次的結果，重跑才可重現
lines = []
try:
    m = manual_fallback_with_credit(client, params, OPUS)
    lines += [
        "送出次數：" + str(len(sent)) + "（第 1 次劇本、第 2 次真的呼叫）",
        "重試請求帶了 fallback_credit：" + str(sent[1].get("fallback_credit")),
        "重試請求的 model：" + sent[1]["model"] + "；實際執行模型（K143_CLI_MODEL 強制）：" + m.model,
        "不一樣的欄位：" + str(diff_keys(sent[0], sent[1])),
        "stop_reason=" + m.stop_reason + "｜stop_details=" + str(m.stop_details),
        "回答：" + m.content[0].text.strip()[:120],
        "usage：輸入 " + str(m.usage.input_tokens) + "、快取寫入 " + str(m.usage.cache_creation_input_tokens)
            + "、快取讀取 " + str(m.usage.cache_read_input_tokens) + "、輸出 " + str(m.usage.output_tokens),
    ]
except anthropic.APIError as exc:
    lines.append("❌ 呼叫模型失敗：" + str(exc))
lines.append("claude -p 呼叫次數：" + str(claude_cli_client.calls_made()))
lines.append("注意：轉接層用 **ignored 吞掉 betas 與 fallback_credit，CLI 沒有 credit 折抵，上面的 usage 不能拿來驗證省錢")
out.write_text("\n".join(lines) + "\n", encoding="utf-8")
print("\n".join(lines))
print()
print("已寫入 " + str(out))'
   show "$FAKE_PY
$P"; py_run "$FAKE_PY
$P" ;;
8) banner "總結"
   tip "自己寫重試才需要 credit，而且本體要字面一致；黏性路由要分開數；能用中介層就別自己寫。"
   P='cat <<EOF
  第 9 章總結
    自己寫重試（裸 HTTP、其他語言、自訂迴圈）時，在備援模型上重送會從頭寫快取——比讀快取貴，等於付兩次
    拒答會附一次性 fallback_credit_token：重試原樣帶回去，這次重試就按「一開始就在備援模型上」計價
    「完全一致」是字面意思：只換 model、加 fallback_credit，連刪掉空白 content 區塊、調大 max_tokens 都會讓折抵失效
    書附只示範形狀：params 自帶 betas 會 TypeError、重試又被拒時照樣回傳，呼叫端要自己看 stop_reason
    黏性路由只有 fallback_message、沒有原模型嘗試，要用 served_by_sticky 和真正的備援分開統計，否則備援率失真
    能用 SDK 中介層或伺服器端備援就不要自己寫；轉接層沒有 credit 機制，只能用假 client 驗形狀
EOF'
   show "$P"; sh_run "$P" ;;
*) echo "用法：bash ch09.sh <步驟 1-8>"; exit 1 ;;
esac
