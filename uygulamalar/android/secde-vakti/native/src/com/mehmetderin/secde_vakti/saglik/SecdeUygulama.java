package com.mehmetderin.secde_vakti.saglik;

import android.app.Activity;
import android.app.Application;
import android.content.Intent;
import android.content.pm.ShortcutInfo;
import android.content.pm.ShortcutManager;
import android.graphics.drawable.Icon;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;

import java.util.ArrayList;
import java.util.List;

/**
 * Uygulama sınıfı (manifestteki android.app.Application yerine geçer).
 * - Eski 1.0.0 Flutter MainActivity ne yoldan çağrılırsa çağrılsın (eski kısayol, bildirim
 *   SELECT_NOTIFICATION, görev geçmişi veya süreç yenilemesi) 0 sn içinde DurumAktivitesi'ne
 *   yönlendirip kapatır; eski ekran hiçbir koşulda görünmez.
 * - Vakit takvimini, kısayolları, sayacı ve bekçiyi canlı tutar.
 */
public class SecdeUygulama extends Application {

    private static final String ESKI_EKRAN = "com.mehmetderin.secde_vakti.MainActivity";
    private final Handler handler = new Handler(Looper.getMainLooper());

    @Override
    public void onCreate() {
        super.onCreate();
        Hata.yakalayiciKur(this);
        Tercihler.acilisMenu(this, true);
        Gorunum.sadeGorunumuUygula(this);
        Gorunum.bolumleriGeriAc(this);
        new Thread(() -> {
            try {
                KonumVeTakvim.otomatikTazele(this);
                Kanallar.kur(this);
                kisayollar();
                Bekci.planla(this);
                VakitSayaci.guncelle(this);
                SessizMod.planla(this);
            } catch (Throwable ignored) {
            }
        }, "secde-baslangic").start();

        registerActivityLifecycleCallbacks(new ActivityLifecycleCallbacks() {
            @Override
            public void onActivityCreated(Activity a, Bundle b) {
                if (ESKI_EKRAN.equals(a.getClass().getName())) {
                    eskiEkraniYonlendirVeKapat(a);
                }
            }

            @Override
            public void onActivityStarted(Activity a) {
                if (ESKI_EKRAN.equals(a.getClass().getName())) {
                    eskiEkraniYonlendirVeKapat(a);
                }
            }

            @Override
            public void onActivityResumed(Activity a) {
                if (ESKI_EKRAN.equals(a.getClass().getName())) {
                    eskiEkraniYonlendirVeKapat(a);
                } else if (a instanceof DurumAktivitesi) {
                    gecikmeliSayac(2500);
                }
            }

            @Override
            public void onActivityPaused(Activity a) {
                if (a instanceof DurumAktivitesi) {
                    gecikmeliSayac(1200);
                }
            }

            @Override public void onActivityStopped(Activity a) {}
            @Override public void onActivitySaveInstanceState(Activity a, Bundle b) {}
            @Override public void onActivityDestroyed(Activity a) {}
        });
    }

    /**
     * Eski 1.0.0 MainActivity herhangi bir niyetle (bildirim tıklaması, eski masaüstü kısayolu,
     * sıcak görev dönüşü vb.) açılırsa tekil DurumAktivitesi'ne yönlendirir ve anında sonlandırır.
     */
    private void eskiEkraniYonlendirVeKapat(Activity a) {
        try {
            Intent kaynak = a.getIntent();
            Intent yeni = new Intent(a, DurumAktivitesi.class)
                    .setAction(Intent.ACTION_MAIN)
                    .addCategory(Intent.CATEGORY_LAUNCHER)
                    .putExtra(DurumAktivitesi.EK_ANA, true)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK
                            | Intent.FLAG_ACTIVITY_CLEAR_TOP
                            | Intent.FLAG_ACTIVITY_SINGLE_TOP);
            if (kaynak != null && kaynak.getExtras() != null) {
                yeni.putExtras(kaynak.getExtras());
                yeni.removeExtra(DurumAktivitesi.EK_DOGRUDAN);
                yeni.putExtra(DurumAktivitesi.EK_ANA, true);
            }
            a.startActivity(yeni);
            a.overridePendingTransition(0, 0);
            if (!a.isFinishing()) {
                a.finish();
                a.overridePendingTransition(0, 0);
            }
        } catch (Throwable ignored) {
        }
    }

    private void gecikmeliSayac(long ms) {
        handler.postDelayed(() -> new Thread(() -> {
            KonumVeTakvim.otomatikTazele(this);
            VakitSayaci.guncelle(this);
            Bekci.kontrol(this);
            SessizMod.planla(this);
        }, "secde-sayac").start(), ms);
    }

    private void kisayollar() {
        if (Build.VERSION.SDK_INT < 25) return;
        ShortcutManager sm = getSystemService(ShortcutManager.class);
        if (sm == null) return;
        Icon simge = Icon.createWithResource(this, Kanallar.kucukSimge(this));
        List<ShortcutInfo> liste = new ArrayList<>();
        liste.add(new ShortcutInfo.Builder(this, "durum")
                .setShortLabel("Vakitler")
                .setLongLabel("Bugünün vakitleri ve bildirim durumu")
                .setIcon(simge)
                .setIntent(new Intent(this, DurumAktivitesi.class).setAction(Intent.ACTION_VIEW))
                .setRank(0)
                .build());
        liste.add(new ShortcutInfo.Builder(this, "kuran")
                .setShortLabel("Kur'an-ı Kerim")
                .setLongLabel("114 sûre, meal ve tilavet")
                .setIcon(simge)
                .setIntent(new Intent(this, DurumAktivitesi.class).setAction(Intent.ACTION_VIEW)
                        .putExtra(DurumAktivitesi.EK_SEKME, DurumAktivitesi.S_KURAN))
                .setRank(1)
                .build());
        liste.add(new ShortcutInfo.Builder(this, "kible")
                .setShortLabel("Kıble")
                .setLongLabel("Kıble pusulası")
                .setIcon(simge)
                .setIntent(new Intent(this, DurumAktivitesi.class).setAction(Intent.ACTION_VIEW)
                        .putExtra(DurumAktivitesi.EK_SEKME, DurumAktivitesi.S_KIBLE))
                .setRank(2)
                .build());
        liste.add(new ShortcutInfo.Builder(this, "zikir")
                .setShortLabel("Zikirmatik")
                .setLongLabel("Zikirmatik ve tesbihat")
                .setIcon(simge)
                .setIntent(new Intent(this, DurumAktivitesi.class).setAction(Intent.ACTION_VIEW)
                        .putExtra(DurumAktivitesi.EK_SEKME, DurumAktivitesi.S_ZIKIR))
                .setRank(3)
                .build());
        try {
            sm.setDynamicShortcuts(liste);
        } catch (Throwable ignored) {
        }
    }
}
