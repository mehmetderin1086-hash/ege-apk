"""Test yapılandırması — veri dizinini geçici klasöre yönlendirir.

app modülleri import edilmeden ÖNCE çalışır; gerçek data/ kirlenmez.
"""
import os
import tempfile

os.environ.setdefault("SESLAB_DATA", tempfile.mkdtemp(prefix="seslab_test_"))
