import os
import shutil
import sys

import pytest

# CI/headless verification must never ask Qt to attach to a window server.
os.environ["QT_QPA_PLATFORM"] = "offscreen"

from kitapkatalog.qtenv import ensure_qt_plugins_visible


@pytest.fixture(autouse=True)
def _bol_disk(monkeypatch):
    """Kapasite kontrolünü makinenin gerçek boş alanından ayır.

    Kapasite tahmini gerçek diskin boş alanını okur; disk dolmaya
    yaklaştığında CLI/webapp içe aktarma testleri makine durumuna göre
    kırılıyordu. Testlerde boş alan en az 200 GiB olarak raporlanır;
    yetersizlik senaryoları zaten free_bytes'ı elle kurarak test ediliyor.
    """

    real = shutil.disk_usage

    def bol(path):
        usage = real(path)
        return type(usage)(usage.total, usage.used, max(usage.free, 200 * 1024**3))

    monkeypatch.setattr("kitapkatalog.capacity.shutil.disk_usage", bol)


def pytest_runtest_setup(item):
    """İlk QApplication kurulmadan hemen önce Qt eklenti bayraklarını temizle.

    Bu makinede bir arka plan süreci .venv içeriğine periyodik UF_HIDDEN
    basıyor; QFactoryLoader gizli eklentiyi görmeyince QApplication SIGABRT
    ile çöküyor. Hook, modül-kapsamlı fixture'lardan da önce koştuğu için
    QApplication nerede kurulursa kurulsun eklentiler görünür durumdadır.
    PySide6 import edilmemişse maliyet sıfırdır; uygulama bir kez kurulunca
    temizlik atlanır (eklentiler zaten yüklüdür).
    """

    qtwidgets = sys.modules.get("PySide6.QtWidgets")
    if qtwidgets is not None and qtwidgets.QApplication.instance() is None:
        ensure_qt_plugins_visible()
