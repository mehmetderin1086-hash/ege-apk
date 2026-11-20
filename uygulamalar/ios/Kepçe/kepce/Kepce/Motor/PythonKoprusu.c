#include "PythonKoprusu.h"
#include <Python/Python.h>
#include <stdlib.h>
#include <string.h>

static char *kopya(const char *s) { return s ? strdup(s) : strdup("(bilinmeyen hata)"); }

static char *hata_metni(void) {
    PyObject *tur, *deger, *iz;
    PyErr_Fetch(&tur, &deger, &iz);
    PyErr_NormalizeException(&tur, &deger, &iz);
    char *sonuc = NULL;
    PyObject *metin = deger ? PyObject_Str(deger) : NULL;
    PyObject *ad = tur ? PyObject_GetAttrString(tur, "__name__") : NULL;
    if (metin && ad) {
        PyObject *birlesik = PyUnicode_FromFormat("%U: %U", ad, metin);
        if (birlesik) { sonuc = kopya(PyUnicode_AsUTF8(birlesik)); Py_DECREF(birlesik); }
    }
    if (!sonuc) sonuc = kopya("Python hatası");
    Py_XDECREF(metin); Py_XDECREF(ad);
    Py_XDECREF(tur); Py_XDECREF(deger); Py_XDECREF(iz);
    PyErr_Clear();
    return sonuc;
}

static char *durum_hatasi(PyStatus durum, PyConfig *ayar) {
    PyConfig_Clear(ayar);
    return kopya(durum.err_msg ? durum.err_msg : "Python başlatılamadı");
}

char *kp_baslat(const char *home, const char *paths, const char *pycache) {
    if (Py_IsInitialized()) return NULL;
    PyPreConfig on;
    PyPreConfig_InitIsolatedConfig(&on);
    on.utf8_mode = 1;
    PyStatus durum = Py_PreInitialize(&on);
    if (PyStatus_Exception(durum)) return kopya(durum.err_msg);

    PyConfig ayar;
    PyConfig_InitIsolatedConfig(&ayar);
    ayar.buffered_stdio = 0;
    ayar.write_bytecode = 1;
    ayar.install_signal_handlers = 0;
    ayar.use_system_logger = 0;

    durum = PyConfig_SetBytesString(&ayar, &ayar.home, home);
    if (PyStatus_Exception(durum)) return durum_hatasi(durum, &ayar);
    durum = PyConfig_SetBytesString(&ayar, &ayar.pycache_prefix, pycache);
    if (PyStatus_Exception(durum)) return durum_hatasi(durum, &ayar);
    durum = PyConfig_Read(&ayar);
    if (PyStatus_Exception(durum)) return durum_hatasi(durum, &ayar);

    durum = Py_InitializeFromConfig(&ayar);
    PyConfig_Clear(&ayar);
    if (PyStatus_Exception(durum)) return kopya(durum.err_msg);

    // Ek yollar standart kitaplıktan önce aranır (güncellenen yt-dlp paketteki eskisini gölgeler).
    PyObject *yol = PySys_GetObject("path");   // ödünç başvuru
    char *liste = strdup(paths ? paths : "");
    Py_ssize_t sira = 0;
    for (char *parca = strtok(liste, ":"); parca && yol; parca = strtok(NULL, ":")) {
        PyObject *oge = PyUnicode_DecodeFSDefault(parca);
        if (oge) { PyList_Insert(yol, sira++, oge); Py_DECREF(oge); }
    }
    free(liste);
    PyEval_SaveThread();   // GIL'i bırak: her çağrı kendi alır
    return NULL;
}

char *kp_cagir(const char *module, const char *function, const char *const *args, int argc, char **hata) {
    *hata = NULL;
    if (!Py_IsInitialized()) { *hata = kopya("Python başlatılmadı"); return NULL; }
    PyGILState_STATE gil = PyGILState_Ensure();
    char *sonuc = NULL;
    PyObject *modul = PyImport_ImportModule(module);
    PyObject *islev = modul ? PyObject_GetAttrString(modul, function) : NULL;
    PyObject *dizi = islev ? PyTuple_New(argc) : NULL;
    if (dizi) {
        for (int i = 0; i < argc; i++) {
            PyObject *oge = PyUnicode_FromString(args[i] ? args[i] : "");
            if (!oge) { Py_CLEAR(dizi); break; }
            PyTuple_SET_ITEM(dizi, i, oge);
        }
    }
    PyObject *donen = dizi ? PyObject_CallObject(islev, dizi) : NULL;
    if (donen) {
        PyObject *metin = PyUnicode_Check(donen) ? (Py_INCREF(donen), donen) : PyObject_Str(donen);
        const char *utf8 = metin ? PyUnicode_AsUTF8(metin) : NULL;
        if (utf8) sonuc = strdup(utf8); else *hata = hata_metni();
        Py_XDECREF(metin);
    } else {
        *hata = hata_metni();
    }
    Py_XDECREF(donen); Py_XDECREF(dizi); Py_XDECREF(islev); Py_XDECREF(modul);
    PyGILState_Release(gil);
    return sonuc;
}
