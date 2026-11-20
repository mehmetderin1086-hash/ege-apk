# Yerel kalite kapısı — kardeş projelerdeki desenin aynısı. Uzak CI yok;
# `make kontrol` commit öncesi elle çalıştırılır.

PY := .venv/bin/python
RUFF := .venv/bin/ruff

.PHONY: kontrol lint bicimle test kapsam mufredat sunucu kur-app

kontrol: lint test

lint:
	$(RUFF) check .

bicimle:
	$(RUFF) check . --fix

test:
	$(PY) -m pytest

kapsam:
	$(PY) -m pytest --cov

# Müfredat JSON'unu resmî PDF'ten yeniden üretir (tek seferlik; çıktı depoda).
mufredat:
	$(PY) scripts/mufredat_cikar.py

sunucu:
	$(PY) -m ogretmen_cantasi.cli sunucu

kur-app:
	$(PY) scripts/install_macos_app.py --replace
