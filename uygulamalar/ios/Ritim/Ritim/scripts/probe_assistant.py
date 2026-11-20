#!/usr/bin/env python3
"""Exercise configured CLIProxy chat models without logging credentials or provider bodies."""
import argparse
import concurrent.futures
import json
import re
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def conversational(model):
    return (model.startswith(("gpt-", "claude-", "gemini-", "antigravity-claude-"))
            and not any(part in model.lower() for part in ("image", "tts", "live", "embedding", "audio")))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=Path("server/.runtime/ai-proxy.json"))
    parser.add_argument("--output", type=Path, default=Path("artifacts/expanded-ai-live.json"))
    parser.add_argument("--models", nargs="*")
    args = parser.parse_args()
    config = json.loads(args.config.read_text())
    base = config["base_url"].rstrip("/")
    if not base.startswith("https://"):
        raise SystemExit("HTTPS connection required")
    headers = {
        config.get("auth_header", "Authorization"):
            ((config.get("auth_scheme", "Bearer") + " ") if config.get("auth_scheme", "Bearer") else "") + config["api_key"],
        "X-CLIProxy-Allow-Fallback": "false",
        "Content-Type": "application/json",
    }

    def request(path, body=None, timeout=120):
        req = urllib.request.Request(base + "/" + path, headers=headers,
                                     data=None if body is None else json.dumps(body).encode())
        with urllib.request.build_opener(NoRedirect).open(req, timeout=timeout) as response:
            return json.load(response)

    rows = request("models", timeout=25)["data"]
    available = list(dict.fromkeys(row["id"] for row in rows if conversational(row["id"])))
    models = args.models or available
    missing = set(models) - set(available)
    if missing:
        raise SystemExit("Requested model is absent from the conversational catalog")
    source = Path("Ritim/Core/DirectAIClient.swift").read_text()
    system = re.search(r'private static let systemPrompt = """\n(.*?)\n    """', source, re.S).group(1)
    tracks = [{"id": str(uuid.uuid4()).upper(), "title": title, "artist": "Ritim Demo"}
              for title in ("Sessiz Sabah", "Gece Yolu", "Yeni Gün")]
    allowed = {track["id"] for track in tracks}

    def probe(model):
        start = time.monotonic()
        result = {"requested_model": model, "ok": False}
        try:
            response = request("chat/completions", {
                "model": model, "max_tokens": 6000,
                "messages": [{"role": "system", "content": system},
                             {"role": "user", "content": json.dumps({"library_metadata": tracks,
                              "request": "Kitaplığımdaki ilk iki parçadan kısa bir liste öner. Cevabın bir cümle olsun, arama önerme."}, ensure_ascii=False)}],
            })
            returned = response.get("model")
            result["returned_model"] = returned if isinstance(returned, str) and re.fullmatch(r"[A-Za-z0-9_.:/+-]{1,150}", returned) else None
            if returned != model:
                result["error"] = "model_mismatch"
                return result
            content = response["choices"][0]["message"]["content"].strip()
            if content.startswith("```json\n") and content.endswith("```"):
                content = content[8:-3]
            elif content.startswith("```\n") and content.endswith("```"):
                content = content[4:-3]
            value = json.loads(content)
            proposal = value.get("playlist") or {}
            ids = proposal.get("track_ids", [])
            result["json_valid"] = bool(isinstance(value.get("reply"), str) and value["reply"].strip()
                                         and isinstance(value.get("search_queries"), list))
            result["playlist_valid"] = isinstance(ids, list) and len(ids) == 2 and len(set(ids)) == 2 and set(ids) <= allowed
            result["ok"] = result["json_valid"] and result["playlist_valid"]
            if not result["ok"]:
                result["error"] = "invalid_music_response"
        except urllib.error.HTTPError as error:
            result["http_status"] = error.code
            result["error"] = "http_error"
        except Exception as error:
            result["error"] = type(error).__name__
        finally:
            result["seconds"] = round(time.monotonic() - start, 2)
        return result

    results = []
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        jobs = {pool.submit(probe, model): model for model in models}
        for future in concurrent.futures.as_completed(jobs):
            result = future.result()
            results.append(result)
            report = {"tested_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                      "catalog_count": len(available), "requested_count": len(models), "results": results}
            args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2))
            print(json.dumps(result, ensure_ascii=False), flush=True)
    print(json.dumps({"passed": sum(row["ok"] for row in results), "tested": len(results)}), flush=True)


if __name__ == "__main__":
    main()
