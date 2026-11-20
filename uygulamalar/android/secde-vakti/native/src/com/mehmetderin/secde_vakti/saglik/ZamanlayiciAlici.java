package com.mehmetderin.secde_vakti.saglik;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/**
 * Sayaç yenileme, yerel vakit alarmları ve bekçi alarmlarını, ayrıca telefon açılışı /
 * uygulama güncellemesi olaylarını karşılar.
 */
public final class ZamanlayiciAlici extends BroadcastReceiver {

    static final String SAYAC_YENILE = "com.mehmetderin.secde_vakti.SAYAC_YENILE";
    static final String BEKCI = "com.mehmetderin.secde_vakti.BEKCI";
    static final String SESSIZ_BASLA = "com.mehmetderin.secde_vakti.SESSIZ_BASLA";
    static final String SESSIZ_BITIR = "com.mehmetderin.secde_vakti.SESSIZ_BITIR";
    static final String YEREL_VAKIT_ALARMI = "com.mehmetderin.secde_vakti.YEREL_VAKIT_ALARMI";

    @Override
    public void onReceive(Context c, Intent intent) {
        String eylem = intent == null ? null : intent.getAction();
        if (eylem == null) return;
        final PendingResult sonuc = goAsync();
        final Context uc = c.getApplicationContext();
        final String e = eylem;
        final Intent niyetKopyasi = new Intent(intent);
        new Thread(() -> {
            try {
                if (SESSIZ_BASLA.equals(e)) {
                    SessizMod.basla(uc);
                } else if (SESSIZ_BITIR.equals(e)) {
                    SessizMod.geriAl(uc, false);
                } else if (YEREL_VAKIT_ALARMI.equals(e)) {
                    KonumVeTakvim.yerelVakitBildirimiGoster(uc, niyetKopyasi);
                } else if (SAYAC_YENILE.equals(e)) {
                    KonumVeTakvim.otomatikTazele(uc);
                    VakitSayaci.guncelle(uc);
                } else if (BEKCI.equals(e)) {
                    KonumVeTakvim.otomatikTazele(uc);
                    Bekci.kontrol(uc);
                    Bekci.planla(uc);
                    VakitSayaci.guncelle(uc);
                } else {
                    // BOOT_COMPLETED, MY_PACKAGE_REPLACED, QUICKBOOT_POWERON
                    try { Thread.sleep(3500); } catch (InterruptedException ignored) { }
                    KonumVeTakvim.otomatikTazele(uc);
                    VakitSayaci.guncelle(uc);
                    Bekci.planla(uc);
                    Bekci.kontrol(uc);
                    long bitis = Tercihler.sp(uc).getLong("sessiz_bitis_ms", 0);
                    if (bitis > 0 && bitis <= System.currentTimeMillis()) SessizMod.geriAl(uc, false);
                    SessizMod.planla(uc);
                }
            } catch (Throwable ignored) {
            } finally {
                sonuc.finish();
            }
        }, "secde-zamanlayici").start();
    }
}
