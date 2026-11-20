# Commit öncesi tek komut. (Özgün Makefile iCloud tahliyesinde kayboldu;
# bu, hayatta kalan kaynağa göre yeniden yazıldı.)
PY = PYTHONPATH=src .venv/bin/python

.PHONY: kontrol lint tip test

kontrol: lint test

lint:
	.venv/bin/ruff check src tests

tip:
	.venv/bin/mypy src/bioprof/rag src/bioprof/config.py src/bioprof/db \
		src/bioprof/studio/podcast.py src/bioprof/services/studio_service.py \
		src/bioprof/voice/seslab.py src/bioprof/evaluation/nli_esik.py

test:
	$(PY) -m pytest -q
