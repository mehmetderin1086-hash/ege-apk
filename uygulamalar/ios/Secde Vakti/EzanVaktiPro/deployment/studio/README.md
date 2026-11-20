# Secde Vakti studio speech

The iOS AdhanPlayer uses the Secde gateway for Turkish narration (Azure Aydın/Elif MAI Voice 2 Flash) and Arabic word pronunciation (Hamed Neural). Quran recitations and existing human-recorded translations retain their recorded audio paths. Apple AVSpeechSynthesizer is no longer used.

- Public endpoint: `https://xn--cumhuriyetanadolulisesiktphanesi-vmdb.com.tr/secde-studio/speech`
- POST JSON: `text` (1–1200 characters), `voice` (`aydin`, `elif`, `arabic`). Response: 24 kHz / 160 kbps MP3.
- Credentials stay in the existing server environment file, never in the application or repository.
- Gateway binds loopback port 8796, runs as `webapps` under `secde-studio.service`, and is routed by Caddy. No changes to the existing Dersdaş application service.
- Bounded queue, serialized synthesis, transient-error retry, persistent per-IP 30,000-character/day and global 200,000-character/day limits. Cached responses also count against request budgets. There is no per-user identity; this bounded endpoint is intended for the current personal deployment. Broader distribution needs device attestation/authentication and capacity planning.
- Server cache: 512 MiB. iPhone cache: 150 MiB, keyed by synthesis version, voice and text; OS may evict it. First play requires internet; cached narration works offline.
- `generate_notifications.py` regenerates 14 bundled reminder CAFs and rejects durations >=29 seconds. These notifications work offline independently of the narration cache.
- `server.py` does not log narration, credentials, or raw IPs. Quota table stores hashed IP identifiers, pruned daily. Audio cache has a size bound.

Deployment files: `/srv/apps/secde-studio/server.py`, `/etc/systemd/system/secde-studio.service`. Rollback: stop/disable that service and remove only the `/secde-studio/*` Caddy block. The pre-change Caddy snapshot is `/etc/caddy/Caddyfile.before-secde-studio`; do not blindly restore it over later edits.

Voice documentation: https://learn.microsoft.com/azure/ai-services/speech-service/language-support?tabs=tts
