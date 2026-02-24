# -*- coding: utf-8 -*-
"""列出 Clash 代理节点并测延迟（ms）。由 list-proxy-delay.sh 调用。"""
import json
import sys
import urllib.request
import urllib.parse

def main():
    base = sys.argv[1]
    delay_url = sys.argv[2]
    timeout_ms = int(sys.argv[3])
    limit = int(sys.argv[4]) if len(sys.argv) > 4 else 0  # 0 = 全部

    try:
        with urllib.request.urlopen(base + "/proxies", timeout=5) as r:
            data = json.loads(r.read().decode())
    except Exception as e:
        print("获取代理列表失败:", e, file=sys.stderr)
        sys.exit(1)

    proxies = data.get("proxies") or {}
    names = []
    for k, v in proxies.items():
        if isinstance(v, dict) and "all" in v and isinstance(v["all"], list) and len(v["all"]) > 2:
            for n in v["all"]:
                if n not in ("DIRECT", "REJECT"):
                    names.append(n)
            break

    if not names:
        print("未解析到代理节点列表。", file=sys.stderr)
        sys.exit(1)

    if limit > 0:
        names = names[:limit]
    print("节点数:", len(names), "(共测)" if limit > 0 else "")
    print("--- 节点名 | 延迟(ms) ---")
    print()

    for name in names:
        enc = urllib.parse.quote(name, safe="")
        url = "%s/proxies/%s/delay?url=%s&timeout=%s" % (base, enc, urllib.parse.quote(delay_url), timeout_ms)
        try:
            with urllib.request.urlopen(url, timeout=timeout_ms // 1000 + 2) as r:
                out = json.loads(r.read().decode())
                delay = out.get("delay", "-")
        except Exception:
            delay = "-"
        print("%-50s %s ms" % (name, delay))

    print()
    print("--- 完成 ---")

if __name__ == "__main__":
    main()
