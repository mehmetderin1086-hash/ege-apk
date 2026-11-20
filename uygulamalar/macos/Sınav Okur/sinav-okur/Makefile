# sinav-okur kalite kapısı.
#
# `make kontrol` bir değişikliği yayına almadan önce koşulacak tek komuttur:
# testler + altın set regresyonu + güvenlik kapısı teşhisi.
#
# Altın set boşken tezgâh "atlandı" sayılır (uyarı verir, kapıyı kırmızıya
# boyamaz) — veri gelene kadar geliştirme durmasın diye. Zorunlu kılmak için:
#   SINAV_OKUR_ALTIN_ZORUNLU=1 make kontrol

UV ?= uv
DB ?= sinav_okur.db
TANIYICI ?= coklu

.PHONY: kontrol test tezgah kapi perf altin temiz-saglik yardim

kontrol: test tezgah kapi
	@echo "✓ Kalite kapısı geçildi."

test:
	@echo "→ Testler"
	@$(UV) run pytest -q

tezgah:
	@echo "→ Altın set regresyonu"
	@$(UV) run sinav-okur tezgah --db $(DB) --altin-uret --kaynak hepsi \
		--zincir ikisi --supurme --taniyici $(TANIYICI); \
	kod=$$?; \
	if [ $$kod -eq 2 ]; then \
		if [ -n "$$SINAV_OKUR_ALTIN_ZORUNLU" ]; then \
			echo "✗ Altın set boş (SINAV_OKUR_ALTIN_ZORUNLU açık)"; exit 1; \
		fi; \
		echo "⚠ Altın set boş — tezgâh atlandı."; \
	elif [ $$kod -ne 0 ]; then \
		exit $$kod; \
	fi

kapi:
	@echo "→ Güvenlik kapısı teşhisi"
	@$(UV) run sinav-okur motor-sagligi

perf:
	@$(UV) run sinav-okur tezgah --db $(DB) --perf

altin:
	@$(UV) run sinav-okur tezgah --db $(DB) --altin-uret --kaynak hepsi \
		--taniyici yapay

temiz-saglik:
	@$(UV) run sinav-okur motor-sagligi --sifirla

yardim:
	@echo "kontrol       testler + tezgâh + kapı teşhisi (yayın öncesi)"
	@echo "test          yalnız pytest"
	@echo "tezgah        altın set regresyon ölçümü"
	@echo "kapi          motor sağlığı / kapı teşhisi"
	@echo "perf          sayfa-OCR motor süre kırılımı"
	@echo "altin         altın örnek üret (ölçüm yapmadan)"
	@echo "temiz-saglik  elenen motorları geri getir"
