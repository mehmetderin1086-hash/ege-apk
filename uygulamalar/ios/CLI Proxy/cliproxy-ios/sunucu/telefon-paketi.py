"""CLI Proxy sunucusundaki bütün hesap/anahtar/yönlendirmeyi iPhone uygulaması için tek pakete döker.

Kullanım (sunucuda, root):
  /srv/apps/cliproxy/.venv/bin/python telefon-paketi.py --ozet          # sırsız özet
  /srv/apps/cliproxy/.venv/bin/python telefon-paketi.py > paket.json    # tam paket (SIR İÇERİR)

Paket sürüm 1 biçimi ProxyKit/BundleImport.swift ile eşleşir.
"""
from __future__ import annotations

import asyncio
import json
import os
import re
import sqlite3
import sys
from datetime import UTC, datetime
from pathlib import Path

ENV_FILES = [
    "/srv/apps/dersdas-questions/proxy.env",
    "/srv/apps/cliproxy/image-fallback.env",
    "/srv/apps/math-ai/service.env",
    "/srv/apps/cliproxy/telefon-esitleme.env",
]
CONFIG = "/srv/apps/cliproxy/config.yaml"
CADDYFILE = "/etc/caddy/Caddyfile"
GOOGLE = "https://generativelanguage.googleapis.com"


def load_env() -> None:
    os.environ.setdefault("HOME", "/srv/apps")
    os.environ["HOME"] = "/srv/apps"
    for f in ENV_FILES:
        p = Path(f)
        if not p.exists():
            continue
        for line in p.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            os.environ[k.strip()] = v.strip().strip('"').strip("'")


def caddy_remote() -> tuple[str, str]:
    text = Path(CADDYFILE).read_text()
    host = re.search(r"^(\S+\.com\.tr)\s*,", text, re.M)
    tok = re.search(r'@app header X-Personal-Token "([^"]+)"', text)
    if not host or not tok:
        raise SystemExit("Caddyfile'da alan adı ya da X-Personal-Token bulunamadı")
    return f"https://{host.group(1)}/dersdas/claude/v1", tok.group(1)


async def main() -> None:
    load_env()
    sys.path.insert(0, "/srv/apps/cliproxy/src")
    from cliproxy.config import load_config
    from cliproxy.credentials.apikey import build_apikey_credentials
    from cliproxy.credentials.file_store import FileCredentialStore
    from cliproxy.credentials.crypto import Cipher

    cfg = load_config(CONFIG)
    store = FileCredentialStore(cfg.auth_path, Cipher(cfg.resolve_cipher_key()))
    creds = await store.load_all()

    db_path = os.path.expanduser(cfg.database_url.split("///", 1)[1])
    meta: dict[str, dict] = {}
    keys: list[dict] = []
    with sqlite3.connect(f"file:{db_path}?mode=ro", uri=True) as db:
        for row in db.execute("select id, provider, label, enabled from account_meta"):
            meta[row[0]] = {"provider": row[1], "label": row[2], "enabled": bool(row[3])}
        for row in db.execute("select name, key_hash, enabled from virtual_keys"):
            keys.append({"name": row[0], "sha256": row[1], "enabled": bool(row[2])})

    enabled_providers = cfg.enabled_providers()
    oauth = []
    for c in creds:
        if c.kind != "oauth":
            continue
        m = meta.get(c.qualified_id) or meta.get(c.id) or {}
        enabled = m.get("enabled", True) and c.provider in enabled_providers
        md = {k: v for k, v in (c.metadata or {}).items() if isinstance(v, (str, int, float, bool))}
        if c.provider == "codex" and c.access_token:
            import base64
            try:
                part = c.access_token.split(".")[1]
                part += "=" * (-len(part) % 4)
                claims = json.loads(base64.urlsafe_b64decode(part))
                plan = (claims.get("https://api.openai.com/auth") or {}).get("chatgpt_plan_type")
                if plan:
                    md["plan"] = plan
            except Exception:
                pass
        oauth.append({
            "provider": c.provider,
            "id": c.id.split(":", 1)[1] if c.id.startswith(c.provider + ":") else c.id,
            "label": m.get("label") or md.get("email") or md.get("label"),
            "enabled": bool(enabled),
            "access_token": c.access_token,
            "refresh_token": c.refresh_token,
            "expires_at": c.expires_at.isoformat() if c.expires_at else None,
            "scopes": c.scopes,
            "metadata": md,
        })

    # Antigravity (17 Eki 2026): sunucudaki agy CLI'nin Google hesabı. Google yenileme belirtecini döndürmediği için
    # telefon kendisi yeniler; agy'nin dosyasına dokunulmaz (salt okunur).
    agy = Path("/srv/apps/.gemini/antigravity-cli/antigravity-oauth-token")
    if agy.exists():
        import base64
        a = json.loads(agy.read_text())
        t = a.get("token") or {}
        claims = {}
        try:
            part = a["id_token"].split(".")[1]; part += "=" * (-len(part) % 4)
            claims = json.loads(base64.urlsafe_b64decode(part))
        except Exception:
            pass
        exp = t.get("expiry")
        if exp:   # Go biçimi: nanosaniye + yerel dilim → mikro saniye
            exp = re.sub(r"(\.\d{6})\d+", r"\1", exp)
        email = claims.get("email") or "antigravity"
        oauth.append({
            "provider": "antigravity", "id": email, "label": email, "enabled": True,
            "access_token": t.get("access_token"), "refresh_token": t.get("refresh_token"), "expires_at": exp,
            "scopes": [], "metadata": {"email": email, "project": "aicode-consumers", "plan": a.get("auth_method") or ""},
        })

    # API anahtarlı sağlayıcılar
    apis = []
    routing = dict(cfg.model_routing)
    filters: dict[str, list[str]] = {}
    for rule in cfg.payload:
        for mdl in getattr(rule, "models", []) or []:
            filters.setdefault(mdl, []).extend(getattr(rule, "filter", []) or [])
    for entry in cfg.openai_compatibility:
        key = os.environ.get(entry.api_key_env)
        if not key or entry.base_url.startswith("http://127.0.0.1"):
            continue   # yerel servisler (qwen, gemini-pro köprüsü) telefona taşınamaz
        apis.append({
            "name": entry.name, "kind": "openai", "base_url": entry.base_url, "api_key": key,
            "models": list(entry.models),
            "filter": {m: f for m, f in filters.items() if m in entry.models},
        })
    gemini_key = None
    for c in build_apikey_credentials(cfg):
        if c.provider in ("gemini-script", "gemini-tts", "gemini") and c.api_key:
            gemini_key = gemini_key or c.api_key
            aliases = {}
            if c.provider == "gemini-script":
                from cliproxy.providers.apikey.gemini_script import GeminiScriptExecutor
                aliases = dict(GeminiScriptExecutor.models)   # dersdas-* → gerçek Gemini modeli
            listed = [m for m, p in routing.items() if p == c.provider]
            if c.provider == "gemini-script":
                apis.append({"name": "gemini-script", "kind": "openai", "base_url": GOOGLE + "/v1beta/openai",
                             "api_key": c.api_key, "models": [], "aliases": {**{m: m for m in listed}, **aliases}})
            elif c.provider == "gemini-tts":
                apis.append({"name": "gemini-tts", "kind": "gemini-native", "base_url": GOOGLE,
                             "api_key": c.api_key, "models": listed})

    # Claude API anahtarı (isteğe bağlı): sunucu ortamında ANTHROPIC_API_KEY varsa telefona "claude-api" olarak gider.
    # Yoksa Mac'teki telefona-kur.sh anahtarı Secrets.xcconfig'ten ekler.
    if os.environ.get("ANTHROPIC_API_KEY"):
        apis.append({"name": "claude-api", "kind": "anthropic", "base_url": os.environ.get("ANTHROPIC_BASE_URL") or "https://api.anthropic.com",
                     "api_key": os.environ["ANTHROPIC_API_KEY"], "models": []})

    remote_url, personal = caddy_remote()
    bundle = {
        "surum": 1,
        "olusturma": datetime.now(UTC).isoformat(),
        "kaynak": "82.29.179.131",
        "oauth": oauth,
        "api_anahtarlari": apis,
        "istemci_anahtarlari": keys,
        # exact kurallar önce, desenler sonra (sunucudaki çözüm sırası)
        "yonlendirme": [[k, v] for k, v in routing.items() if "*" not in k] + [[k, v] for k, v in routing.items() if "*" in k],
        "yedekler": dict(cfg.model_fallbacks),
        "varsayilan_model": cfg.default_model,
        "uzak": {"base_url": remote_url, "personal_token": personal,
                 "sync_token": os.environ.get("CLIPROXY_TELEFON_ESITLEME_TOKEN")},
    }
    if "--ozet" in sys.argv:
        print(json.dumps({
            "oauth": [{k: o[k] for k in ("provider", "id", "label", "enabled", "expires_at")} | {"plan": o["metadata"].get("plan")} for o in oauth],
            "api": [{"name": a["name"], "kind": a["kind"], "models": a["models"], "aliases": sorted((a.get("aliases") or {}).keys())} for a in apis],
            "istemci": [{"name": k["name"], "enabled": k["enabled"]} for k in keys],
            "kural": len(bundle["yonlendirme"]),
            "uzak": remote_url, "esitleme_token_var": bool(bundle["uzak"]["sync_token"]),
        }, ensure_ascii=False, indent=1))
    else:
        json.dump(bundle, sys.stdout, ensure_ascii=False)


asyncio.run(main())
