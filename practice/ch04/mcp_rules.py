"""第 4 章練習 2：不用模型，用四條規則替 MCP 連接器打 0～4 分。

用法：PYTHONUTF8=1 python ch04/mcp_rules.py [servers.json]
"""
import json
import sys
from pathlib import Path

PRACTICE = Path(__file__).resolve().parents[1]
DEFAULT = PRACTICE / "fable5" / "projects" / "02_mcp_audit" / "sample_mcp_servers.json"
STALE_DAYS = 90


def _broad_scope(s):
    # "admin"、"admin:org" 這類管理權限，或任何帶 * 的萬用字元
    return [x for x in s.get("scopes", []) if "admin" in x.lower() or "*" in x]


RULES = [
    ("R1 scope 含 admin 或 *", lambda s: (lambda hit: f"{', '.join(hit)}" if hit else None)(_broad_scope(s))),
    ("R2 auth 為 none", lambda s: "auth=none" if s.get("auth") == "none" else None),
    (f"R3 超過 {STALE_DAYS} 天沒用",
     lambda s: f"{s['last_used_days_ago']} 天" if (s.get("last_used_days_ago") or 0) > STALE_DAYS else None),
    ("R4 金鑰放在環境變數", lambda s: "auth=env_var_key" if s.get("auth") == "env_var_key" else None),
]


def score(server):
    hits = [(name, detail) for name, rule in RULES if (detail := rule(server)) is not None]
    return len(hits), hits


def main():
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT
    try:
        servers = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        print(f"錯誤：讀不到或解析不了 {path}：{e}", file=sys.stderr)
        sys.exit(1)
    ranked = sorted(((score(s), s) for s in servers), key=lambda t: (-t[0][0], t[1]["name"]))
    print(f"MCP 連接器規則稽核（{len(servers)} 個，來源 {path.name}）\n")
    for rank, ((pts, hits), s) in enumerate(ranked, 1):
        print(f"{rank}. {s['name']}：{pts}/4 分  scopes={s.get('scopes')} auth={s.get('auth')} "
              f"last_used={s.get('last_used_days_ago')} 天前")
        for name, detail in hits:
            print(f"     ✗ {name}（{detail}）")
        if not hits:
            print("     ✓ 四條規則都沒命中")


if __name__ == "__main__":
    main()
