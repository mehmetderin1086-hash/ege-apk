# Yerel kalite kapısı. Bu projede GitHub uzak deposu yok (bu makinede `gh`
# ve brew kurulu değil), dolayısıyla CI'nın yerini `make kontrol` tutuyor:
# commit'ten önce elle çalıştırılır ve CI eklendiğinde aynı hedef koşulur.

PY := .venv/bin/python
RUFF := .venv/bin/ruff
MYPY := .venv/bin/mypy

.PHONY: kontrol lint tip test kapsam tam-test bicimle yedekle olcum olcum-kapi olcum-fark dilim-dondur kalibre

# Commit öncesi tek komut.
kontrol: lint tip kapsam

lint:
	$(RUFF) check .

bicimle:
	$(RUFF) check . --fix

tip:
	$(MYPY)

# Varsayılan koşu `yavas` işaretli testleri dışlar (bkz. pyproject).
test:
	$(PY) -m pytest

# Kapsam eşiği pyproject'te (fail_under); düşerse bu hedef kırılır.
kapsam:
	$(PY) -m pytest --cov

# Gerçek OCR motorlarını ve tarayıcıyı da içeren tam koşu — dakikalar sürer.
tam-test:
	$(PY) -m pytest -m ""

# Yerel yedek aynası (uzak depo kurulana kadar tek kopya koruması).
yedekle:
	git push --mirror yedek

# --- ölçüm ---
# Bunlar `kontrol`e BİLİNÇLİ olarak dahil edilmedi: gerçek modeli yükleyip
# 124 soru çözüyorlar ve dakikalarca sürüyorlar. Commit öncesi kapı hızlı
# kalmalı; ölçüm ayrı bir eylemdir ve faz sonlarında elle koşulur.
#
# Kullanım:  make olcum ETIKET=kalitim-araci
#            make olcum ETIKET=gorsel DILIM=dilim-gorsel-50-v2 GORSEL=zorla
# DILIM ve GORSEL geçilebilir olmalı: görselli dilimi ölçmenin ve iki görsel
# kipini karşılaştırmanın başka yolu yoktu, her ölçüm tek kipe sabitlenmişti.
ETIKET ?=
DILIM ?= dilim-v1
GORSEL ?=
_OLCUM_BAYRAK = --dilim "$(DILIM)" $(if $(GORSEL),--gorsel-modu $(GORSEL),)

olcum:
	@test -n "$(ETIKET)" || { echo "ETIKET zorunlu: make olcum ETIKET=<ne-olculuyor>"; exit 1; }
	$(PY) -m biyo_cozucu.cli olcum --etiket "$(ETIKET)" $(_OLCUM_BAYRAK)

# Gerileme varsa çıkış kodu 1.
olcum-kapi:
	@test -n "$(ETIKET)" || { echo "ETIKET zorunlu: make olcum-kapi ETIKET=<ne-olculuyor>"; exit 1; }
	$(PY) -m biyo_cozucu.cli olcum --etiket "$(ETIKET)" $(_OLCUM_BAYRAK) --kapi

# Tür güven çarpanlarını DOĞRULAMA diliminden yeniden öğren.
# Model değiştiğinde şart: tablo kimin için öğrenildiyse yalnız onunla
# anlamlı, eski tabloyu yeni modele uygulamak güveni yanlış yerde kırpar.
kalibre:
	$(PY) -m biyo_cozucu.cli kalibre

# Koşu yapmadan iki kaydı karşılaştır.
olcum-fark:
	$(PY) -m biyo_cozucu.cli olcum-fark --onceki "$(ONCEKI)" --yeni "$(YENI)"

# Test dilimini dondur (bir kez; sonra dokunulmaz).
dilim-dondur:
	$(PY) -m biyo_cozucu.cli olcum --dilimi-dondur "$(if $(AD),$(AD),dilim-v1)"
