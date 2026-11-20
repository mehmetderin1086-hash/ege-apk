"""Deterministik kalıtım çözücüsü.

Model soruyu çözmez, yapılandırılmış tanıma çevirir (`cikarim`); hesabı saf
Python yapar (`punnett`); sonuç yalnız verilen şıklardan birine çözülürse
kullanılır (`eslestirme`). Zincirin herhangi bir halkası kopduğunda çözücü
sessizce çekilir ve mevcut model yolu çalışır.
"""

from .tanim import Birey, Caprazlama, Istek, Lokus

__all__ = ["Birey", "Caprazlama", "Istek", "Lokus"]
