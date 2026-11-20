#!/usr/bin/env python3
"""Asistan Sistem Köprüsü kestirmesini üretir ve imzalar.

iOS uygulamalara Wi-Fi, Bluetooth, uçak modu, odak, görünüm, ses düzeyi gibi sistem
anahtarları için genel API vermez; bunları yalnız Kestirmeler eylemleri değiştirebilir.
Köprü tek metin girdisi alır (örn. "wifi_kapat") ve yalnız bu tablodaki sabit dallardan
birini çalıştırır: girdi hiçbir zaman komut, adres ya da betik olarak yorumlanmaz.

Eylem kimlikleri ve parametre anahtarları macOS ActionKit Actions.intentdefinition ile
dyld önbelleğindeki WorkflowKit dizgelerinden doğrulandı (29 Ekim 2026).

Kullanım:
  araclar/sistem-koprusu.py            # imzasız + imzalı dosyaları üretir
  araclar/sistem-koprusu.py --imzasiz  # yalnız imzasız (test için)
  araclar/sistem-koprusu.py --sinama   # Mac'te kodlama sınaması kestirmesi
"""
import argparse
import plistlib
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path

KOK = Path(__file__).resolve().parent.parent
AD = "Asistan Sistem Köprüsü"
IMZASIZ = KOK / "araclar" / "sistem-koprusu" / "asistan-sistem-koprusu.unsigned.shortcut"
IMZALI = KOK / "Asistan" / "Resources" / "asistan-sistem-koprusu.shortcut"


def anahtar(kimlik, acik):
    # Yeni biçim (operation/state) + eski OnValue: eski istemci de aynı değeri okur.
    return (f"is.workflow.actions.{kimlik}", {"operation": "set", "state": acik, "OnValue": acik})


ANAHTARLAR = {
    "wifi": "wifi.set",
    "bluetooth": "bluetooth.set",
    "ucak": "airplanemode.set",
    "mobilveri": "cellulardata.set",
    "dusukguc": "lowpowermode.set",
    "donmekilidi": "orientationlock.set",
    "hotspot": "personalhotspot.set",
    "gecevardiyasi": "nightshift.set",
    "truetone": "truetone.set",
    "bildirimseslendir": "announcenotifications.set",
}

ODAK = {"Identifier": "com.apple.donotdisturb.mode.default", "DisplayString": "Do Not Disturb"}


def komutlar():
    t = {}
    for ad, kimlik in ANAHTARLAR.items():
        t[f"{ad}_ac"] = [anahtar(kimlik, True)]
        t[f"{ad}_kapat"] = [anahtar(kimlik, False)]
    t["karanlik"] = [("is.workflow.actions.appearance", {"operation": "set", "style": "dark"})]
    t["aydinlik"] = [("is.workflow.actions.appearance", {"operation": "set", "style": "light"})]
    t["odak_ac"] = [("is.workflow.actions.dnd.set", {"Operation": "Turn", "Enabled": 1, "AssertionType": "Turned Off", "FocusModes": ODAK})]
    t["odak_kapat"] = [("is.workflow.actions.dnd.set", {"Operation": "Turn", "Enabled": 0, "FocusModes": ODAK})]
    t["kilitle"] = [("is.workflow.actions.lockscreen", {})]
    t["deneme"] = []   # kurulum sınaması: boş dal, yalnız x-success dönüşü
    for y in range(0, 101, 10):
        t[f"ses_{y}"] = [("is.workflow.actions.setvolume", {"WFVolume": y / 100})]
    return t


def sinama_komutlari():
    """Mac'te güvenle geri alınabilen eylemlerle iki kodlama adayı."""
    return {
        "gorunum_metin": [("is.workflow.actions.appearance", {"operation": "set", "style": "light"})],
        "gorunum_sayi": [("is.workflow.actions.appearance", {"operation": 1, "style": 2})],
        "dusukguc_metin": [anahtar("lowpowermode.set", True)],
        "dusukguc_eski": [("is.workflow.actions.lowpowermode.set", {"OnValue": True})],
    }


def girdi():
    return {"Type": "Variable", "Variable": {"WFSerializationType": "WFTextTokenAttachment", "Value": {
        "Type": "ExtensionInput",
        "Aggrandizements": [{"Type": "WFCoercionVariableAggrandizement", "CoercionItemClass": "WFStringContentItem"}]}}}


def eylemler(tablo):
    out = []
    for komut, adimlar in tablo.items():
        g = str(uuid.uuid5(uuid.NAMESPACE_URL, "asistan-sistem/" + komut))
        out.append({"WFWorkflowActionIdentifier": "is.workflow.actions.conditional", "WFWorkflowActionParameters": {
            "GroupingIdentifier": g, "WFCondition": 4, "WFConditionalActionString": komut, "WFControlFlowMode": 0, "WFInput": girdi()}})
        for kimlik, p in adimlar:
            out.append({"WFWorkflowActionIdentifier": kimlik, "WFWorkflowActionParameters": dict(p)})
        out.append({"WFWorkflowActionIdentifier": "is.workflow.actions.conditional", "WFWorkflowActionParameters": {
            "GroupingIdentifier": g, "UUID": str(uuid.uuid5(uuid.NAMESPACE_URL, "asistan-sistem-son/" + komut)), "WFControlFlowMode": 2}})
    return out


def kestirme(ad, tablo):
    return {
        "WFQuickActionSurfaces": [], "WFWorkflowClientVersion": "5110.0.8", "WFWorkflowHasOutputFallback": False,
        "WFWorkflowHasShortcutInputVariables": True,
        "WFWorkflowIcon": {"WFWorkflowIconGlyphNumber": 59511, "WFWorkflowIconStartColor": -2071128321},
        "WFWorkflowImportQuestions": [], "WFWorkflowInputContentItemClasses": ["WFStringContentItem"],
        "WFWorkflowMinimumClientVersion": 900, "WFWorkflowMinimumClientVersionString": "900", "WFWorkflowName": ad,
        "WFWorkflowOutputContentItemClasses": [], "WFWorkflowTypes": [], "WFWorkflowActions": eylemler(tablo)}


def yaz(yol, veri):
    yol.parent.mkdir(parents=True, exist_ok=True)
    with open(yol, "wb") as f:
        plistlib.dump(veri, f, fmt=plistlib.FMT_BINARY)


def imzala(kaynak, hedef):
    # İmzalayıcının yardımcı süreci yazdığı çıktıyı birkaç dakika sonra siliyor (29 Eki'de depodaki dosya iki kez
    # kayboldu). Bu yüzden geçici klasöre imzalanır, baytlar hedefe yeni bir dosya olarak kopyalanır.
    with tempfile.TemporaryDirectory() as gecici:
        cikti = Path(gecici) / "imzali.shortcut"
        subprocess.run(["shortcuts", "sign", "--mode", "anyone", "--input", str(kaynak), "--output", str(cikti)], check=True)
        veri = cikti.read_bytes() if cikti.exists() else b""
    if len(veri) < 1000:
        sys.exit(f"imzalı dosya yazılamadı: {hedef}")
    hedef.write_bytes(veri)
    hedef.chmod(0o644)


def main():
    a = argparse.ArgumentParser()
    a.add_argument("--imzasiz", action="store_true")
    a.add_argument("--sinama", type=Path, help="sınama kestirmesinin yazılacağı klasör")
    o = a.parse_args()
    if o.sinama:
        ham = o.sinama / "sinama.unsigned.shortcut"
        yaz(ham, kestirme("Asistan Kodlama Sınaması", sinama_komutlari()))
        imzala(ham, o.sinama / "Asistan Kodlama Sınaması.shortcut")
        print(o.sinama / "Asistan Kodlama Sınaması.shortcut")
        return
    yaz(IMZASIZ, kestirme(AD, komutlar()))
    print(f"{len(komutlar())} komut → {IMZASIZ.relative_to(KOK)}")
    if not o.imzasiz:
        imzala(IMZASIZ, IMZALI)
        print(f"imzalı → {IMZALI.relative_to(KOK)}")


if __name__ == "__main__":
    sys.exit(main())
