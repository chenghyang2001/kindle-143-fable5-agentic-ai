"""K143 轉接層：用 Claude Code 無頭模式（claude -p）冒充 anthropic SDK。

為什麼要有這支：本機不設 ANTHROPIC_API_KEY（成本鐵律：直接打 API 會扣 API Credits），
但 fable5 範例都寫成 `from anthropic import Anthropic` 再呼叫
`client.beta.messages.create(...)`。這支把那個呼叫改成 `claude -p --output-format json`
子程序，走 Max 訂閱額度，範例原始碼一行都不用改。

兩種用法：
1. 原封不動跑範例腳本：
       python run_with_cli.py fable5/projects/03_cost_dashboard/cost_dashboard.py
       python run_with_cli.py -m fable_scanner canary run
2. 自己寫的 chNN/*.py 裡：
       import claude_cli_client; claude_cli_client.install()
       import job_packet.packet as pk   # 之後的 import anthropic 都拿到本轉接層

可調環境變數（都不是金鑰）：
  K143_CLI_MODEL      強制所有呼叫改用某模型（例 haiku），預設照範例傳入的 model
  K143_CLI_TIMEOUT    單次呼叫逾時秒數，預設 180
  K143_CLI_MAX_CALLS  單一行程最多呼叫幾次，預設 10（避免迴圈範例把演練拖很久）
  K143_CLI_LOG        設成檔案路徑時，每次呼叫附加一行 fable_scanner monitor 讀得懂的 JSONL

和真 API 的差異（安全忽略或降級，見 _build_command）：
  - max_tokens、temperature、top_p、top_k、thinking、betas、fallbacks、
    output_config.task_budget、fallback_credit：CLI 沒有對應旋鈕，忽略。
  - output_config.effort：轉成 CLI 的 --effort（low/medium/high/xhigh/max）。
  - tools：只有伺服器端 web_search 會降級成 Claude Code 內建 WebSearch 工具；
    其他自訂工具（client tools）一律忽略，模型只會回文字，不會回 tool_use。
  - 多輪 messages：攤平成一份逐字稿送進 stdin；thinking 區塊不送。
  - 沒有 server-side fallback：不會出現 fallback_message iteration。
  - stop_details 永遠是 None（CLI 不回傳拒答類別）。
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import types
from datetime import datetime, timezone
from pathlib import Path

PRACTICE_DIR = Path(__file__).resolve().parent
FABLE5_DIR = PRACTICE_DIR / "fable5"
DEFAULT_SYSTEM = "You are a helpful assistant. Answer the user's message directly."
EFFORT_LEVELS = {"low", "medium", "high", "xhigh", "max"}
# 拿掉這些前綴的環境變數：金鑰（成本鐵律）與巢狀 Claude Code session 的狀態變數
STRIP_ENV_PREFIXES = ("ANTHROPIC_", "CLAUDECODE", "CLAUDE_")

_call_count = 0


# ---- 模仿 anthropic 的例外類別，讓 `except anthropic.APIError` 之類的寫法不壞 ----
class APIError(Exception):
    """轉接層呼叫失敗（CLI 回錯、逾時、JSON 解析失敗）。"""


class APIStatusError(APIError):
    pass


class APITimeoutError(APIError):
    pass


class RateLimitError(APIStatusError):
    pass


def _ns(**kw):
    return types.SimpleNamespace(**kw)


def _env_int(name, default):
    raw = os.environ.get(name)
    if raw is None or raw == "":
        return default
    try:
        return int(raw)
    except ValueError:
        print(f"[claude_cli_client] {name}={raw!r} 不是整數，改用預設 {default}", file=sys.stderr)
        return default


def _clean_env():
    """子程序環境：移除金鑰與巢狀 session 變數，其他保留（PATH、USERPROFILE 等登入要用）。"""
    return {k: v for k, v in os.environ.items() if not k.startswith(STRIP_ENV_PREFIXES)}


def _block_text(block):
    """把一個 content block 轉成文字；thinking 類不送（CLI 無法重放思考區塊）。"""
    if isinstance(block, str):
        return block
    btype = block.get("type") if isinstance(block, dict) else getattr(block, "type", None)
    get = block.get if isinstance(block, dict) else (lambda k, d=None: getattr(block, k, d))
    if btype == "text":
        return get("text", "")
    if btype in ("thinking", "redacted_thinking"):
        return ""
    if btype == "tool_result":
        inner = get("content", "")
        if isinstance(inner, list):
            inner = "\n".join(_block_text(b) for b in inner)
        return f"[tool_result]\n{inner}"
    if btype == "tool_use":
        return f"[tool_use {get('name', '')}] {json.dumps(get('input', {}), ensure_ascii=False)}"
    return json.dumps(block, ensure_ascii=False, default=str)


def _content_text(content):
    if isinstance(content, str):
        return content
    return "\n".join(t for t in (_block_text(b) for b in content or []) if t)


def _flatten_messages(messages):
    """單一 user 訊息直接送；多輪則攤平成逐字稿，最後一則當成要回答的訊息。"""
    if not messages:
        raise ValueError("messages 不可為空")
    if len(messages) == 1:
        return _content_text(messages[0].get("content", ""))
    lines = ["以下是先前的對話紀錄，請以 assistant 身分回覆最後一則 user 訊息。", ""]
    for m in messages:
        role = m.get("role", "user")
        lines.append(f"<{role}>\n{_content_text(m.get('content', ''))}\n</{role}>")
    return "\n".join(lines)


def _system_text(system):
    if system is None:
        return DEFAULT_SYSTEM
    if isinstance(system, str):
        return system or DEFAULT_SYSTEM
    return _content_text(system) or DEFAULT_SYSTEM


def _wants_web_search(tools):
    for t in tools or []:
        ttype = str(t.get("type", "")) if isinstance(t, dict) else ""
        if ttype.startswith("web_search") or (isinstance(t, dict) and t.get("name") == "web_search"):
            return True
    return False


def _build_command(exe, model, system_file, effort, web_search):
    cmd = [
        exe, "-p", "--output-format", "json",
        "--model", model,
        "--system-prompt-file", system_file,
        "--no-session-persistence",
        "--strict-mcp-config",          # 不載入 MCP 伺服器：快、也不會誤用連接器
        "--disable-slash-commands",     # 不載入 skills
        "--setting-sources", "",        # 不讀 user/project settings 與 hooks
    ]
    if web_search:
        # 伺服器端 web_search 降級成 Claude Code 內建 WebSearch（真的會上網）
        cmd += ["--tools", "WebSearch", "--allowedTools", "WebSearch"]
    else:
        cmd += ["--tools", ""]
    if effort in EFFORT_LEVELS:
        cmd += ["--effort", effort]
    return cmd


def _run_cli(prompt, model, system, effort, web_search):
    global _call_count
    max_calls = _env_int("K143_CLI_MAX_CALLS", 10)
    if _call_count >= max_calls:
        raise APIError(f"已達本行程呼叫上限 K143_CLI_MAX_CALLS={max_calls}，停止以免演練拖太久")
    exe = shutil.which("claude")
    if exe is None:
        raise APIError("找不到 claude 指令（Claude Code CLI），請確認已安裝並在 PATH 中")
    timeout = _env_int("K143_CLI_TIMEOUT", 180)
    work_dir = Path(tempfile.gettempdir()) / "k143-cli-cwd"   # 空目錄：避免讀到任何 CLAUDE.md
    work_dir.mkdir(exist_ok=True)
    fd, system_file = tempfile.mkstemp(prefix="k143-sys-", suffix=".txt")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(system)
        cmd = _build_command(exe, model, system_file, effort, web_search)
        _call_count += 1
        started = time.monotonic()
        try:
            proc = subprocess.run(
                cmd, input=prompt, capture_output=True, text=True, encoding="utf-8",
                errors="replace", env=_clean_env(), cwd=str(work_dir), timeout=timeout, check=False,
            )
        except subprocess.TimeoutExpired as exc:
            raise APITimeoutError(f"claude -p 超過 {timeout} 秒沒有回應") from exc
        except OSError as exc:
            raise APIError(f"無法啟動 claude -p：{exc}") from exc
    finally:
        try:
            os.remove(system_file)
        except OSError:
            pass
    elapsed_ms = (time.monotonic() - started) * 1000
    try:
        data = json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        detail = (proc.stderr or proc.stdout or "").strip()[:500]
        raise APIStatusError(f"claude -p 回傳不是 JSON（exit {proc.returncode}）：{detail}") from exc
    if data.get("is_error") or proc.returncode != 0:
        status = data.get("api_error_status")
        msg = f"claude -p 失敗（exit {proc.returncode}, status={status}）：{str(data.get('result'))[:500]}"
        raise (RateLimitError if status == 429 else APIStatusError)(msg)
    data["_elapsed_ms"] = elapsed_ms
    return data


def _to_message(data, model):
    usage_raw = data.get("usage") or {}
    stop_reason = data.get("stop_reason") or "end_turn"
    iterations = []
    for it in usage_raw.get("iterations") or [{"type": "message"}]:
        it = dict(it)
        it.setdefault("model", model)
        it.setdefault("input_tokens", usage_raw.get("input_tokens", 0))
        it.setdefault("output_tokens", usage_raw.get("output_tokens", 0))
        iterations.append(_ns(**{k: v for k, v in it.items() if isinstance(k, str)}))
    usage = _ns(
        input_tokens=usage_raw.get("input_tokens", 0),
        output_tokens=usage_raw.get("output_tokens", 0),
        cache_creation_input_tokens=usage_raw.get("cache_creation_input_tokens", 0),
        cache_read_input_tokens=usage_raw.get("cache_read_input_tokens", 0),
        iterations=iterations,
    )
    refused = stop_reason == "refusal"
    content = [] if refused else [_ns(type="text", text=data.get("result") or "")]
    return _ns(
        id=data.get("uuid") or data.get("session_id"), type="message", role="assistant",
        model=model, content=content, stop_reason=stop_reason, stop_sequence=None,
        stop_details=_ns(category=None) if refused else None, usage=usage,
        _elapsed_ms=data.get("_elapsed_ms"),
    )


def _append_log(path, request_model, prompt, msg):
    """寫成 fable_scanner monitor 吃得下的 {timestamp, request, response} 格式。"""
    line = {
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "request": {"model": request_model, "messages": [{"role": "user", "content": prompt[:2000]}]},
        "response": {
            "model": msg.model, "stop_reason": msg.stop_reason, "stop_details": None,
            "usage": {"iterations": [vars(it) for it in msg.usage.iterations]},
        },
    }
    try:
        with open(path, "a", encoding="utf-8") as f:
            f.write(json.dumps(line, ensure_ascii=False, default=str) + "\n")
    except OSError as exc:
        print(f"[claude_cli_client] 寫 log 失敗 {path}：{exc}", file=sys.stderr)


class _Messages:
    def create(self, *, model, messages, system=None, output_config=None, tools=None,
               max_tokens=None, **ignored):
        """模仿 messages.create；ignored 收下 betas/fallbacks/temperature/thinking 等不支援參數。"""
        effort = (output_config or {}).get("effort")
        real_model = os.environ.get("K143_CLI_MODEL") or model
        prompt = _flatten_messages(messages)
        data = _run_cli(prompt, real_model, _system_text(system), effort, _wants_web_search(tools))
        msg = _to_message(data, real_model)
        log_path = os.environ.get("K143_CLI_LOG")
        if log_path:
            _append_log(log_path, model, prompt, msg)
        return msg

    def stream(self, **kwargs):
        """deep_research 用 `with client.beta.messages.stream(...) as s: s.get_final_message()`。
        CLI 不串流，這裡一次拿完整結果再包成同樣介面。"""
        return _Stream(self, kwargs)


class _Stream:
    def __init__(self, messages, kwargs):
        self._messages, self._kwargs, self._final = messages, kwargs, None

    def __enter__(self):
        self._final = self._messages.create(**self._kwargs)
        return self

    def __exit__(self, *exc):
        return False

    def get_final_message(self):
        return self._final

    @property
    def text_stream(self):
        return iter([b.text for b in self._final.content if b.type == "text"])


class Anthropic:
    """模仿 anthropic.Anthropic；忽略 api_key 等參數（本來就不該有金鑰）。"""

    def __init__(self, *args, **kwargs):
        self.messages = _Messages()
        self.beta = _ns(messages=self.messages)


def calls_made():
    """回傳本行程已呼叫 claude -p 的次數（練習用來回報呼叫數）。"""
    return _call_count


def install():
    """把本模組註冊成 `anthropic`，並把 practice/ 與 practice/fable5/ 放進 sys.path。"""
    if os.environ.get("ANTHROPIC_API_KEY"):
        print("[claude_cli_client] 偵測到 ANTHROPIC_API_KEY：子程序會移除它，不會使用金鑰", file=sys.stderr)
    module = sys.modules[__name__]
    sys.modules["anthropic"] = module
    for p in (str(FABLE5_DIR), str(PRACTICE_DIR)):
        if p not in sys.path:
            sys.path.insert(0, p)
    return module


if __name__ == "__main__":
    # 冒煙測試：flatten 純函式＋（加 --live 時）真的打一次 claude -p
    assert _flatten_messages([{"role": "user", "content": "hi"}]) == "hi"
    multi = _flatten_messages([
        {"role": "user", "content": "1+1?"},
        {"role": "assistant", "content": [{"type": "thinking", "thinking": "x"}, {"type": "text", "text": "2"}]},
        {"role": "user", "content": "再加 1？"},
    ])
    assert "<assistant>\n2\n</assistant>" in multi and "thinking" not in multi
    assert _wants_web_search([{"type": "web_search_20260209", "name": "web_search"}])
    assert not _wants_web_search([{"name": "lookup_order"}])
    assert "ANTHROPIC_API_KEY" not in _clean_env() and "CLAUDECODE" not in _clean_env()
    print("ok: 純函式檢查通過")
    if "--live" in sys.argv:
        m = Anthropic().beta.messages.create(
            model="claude-haiku-4-5", max_tokens=50, output_config={"effort": "low"},
            betas=["x"], fallbacks=[{"model": "y"}], temperature=0.2,
            messages=[{"role": "user", "content": "Reply with exactly: alpha bravo"}])
        print("live:", m.stop_reason, repr(m.content[0].text), m.usage.output_tokens, "tok")
