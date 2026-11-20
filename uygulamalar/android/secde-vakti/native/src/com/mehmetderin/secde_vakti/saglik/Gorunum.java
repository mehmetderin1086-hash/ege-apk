package com.mehmetderin.secde_vakti.saglik;

import android.content.Context;
import android.content.SharedPreferences;
import android.content.res.Configuration;
import android.graphics.Color;

/**
 * "Mihrap" teması: Flutter tarafındaki varsayılan temanın (libapp.so'da yamalanan) Android
 * katmanındaki karşılığı ve ilk açılışta uygulanan sade görünüm ayarları.
 */
public final class Gorunum {

    private static final String UYGULANDI = "gorunum_mihrap_v1";

    public final boolean gece;
    public final int zemin, kart, metin, ikincil, ana, vurgu, iyi, kotu, uyari, cizgi, ustBas, ustSon;

    private Gorunum(boolean gece) {
        this.gece = gece;
        if (gece) {
            zemin = Color.parseColor("#12142A");
            kart = Color.parseColor("#1C2033");
            metin = Color.parseColor("#EEF0F8");
            ikincil = Color.parseColor("#A3A8C3");
            ana = Color.parseColor("#9AA6F5");
            vurgu = Color.parseColor("#F0B35A");
            iyi = Color.parseColor("#7FD1A8");
            kotu = Color.parseColor("#FF8A80");
            uyari = Color.parseColor("#FFC66D");
            cizgi = Color.parseColor("#2A2F48");
        } else {
            zemin = Color.parseColor("#F7F7FA");
            kart = Color.WHITE;
            metin = Color.parseColor("#161A2E");
            ikincil = Color.parseColor("#5E6378");
            ana = Color.parseColor("#3D4A9C");
            vurgu = Color.parseColor("#C07A1E");
            iyi = Color.parseColor("#2E7D5B");
            kotu = Color.parseColor("#C62828");
            uyari = Color.parseColor("#A15C00");
            cizgi = Color.parseColor("#E4E6EF");
        }
        ustBas = Color.parseColor("#1E2559");
        ustSon = Color.parseColor("#3D4A9C");
    }

    public static Gorunum al(Context c) {
        boolean gece = (c.getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK)
                == Configuration.UI_MODE_NIGHT_YES;
        return new Gorunum(gece);
    }

    /** Bildirim vurgu rengi (her iki temada okunur). */
    public static int bildirimRengi() {
        return Color.parseColor("#3D4A9C");
    }

    /**
     * 1.2.0–1.5.0 uygulamanın kendi ana ekranında Öğrenme (Kur'an, Elif-Ba), Manevi ve Keşfet bölümlerini
     * gizliyordu; bu yüzden uygulamanın Kur'an ve diğer ekranlarına girilemiyordu. Bir kez geri açar.
     */
    static void bolumleriGeriAc(Context c) {
        try {
            SharedPreferences t = Tercihler.sp(c);
            if (t.getBoolean("bolumler_acik_v2", false)) return;
            c.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit()
                    .putBoolean("flutter.home.showLearning.v2", true)
                    .putBoolean("flutter.home.showSpiritual.v2", true)
                    .putBoolean("flutter.home.showDiscovery.v2", true)
                    .commit();
            t.edit().putBoolean("bolumler_acik_v2", true).commit();
        } catch (Throwable ignored) {
        }
    }

    /**
     * Bir kez: Flutter ayarlarını sade görünüme çeker. Flutter motoru başlamadan
     * (Application.onCreate) ve eşzamanlı yazılır. Kullanıcı sonra uygulama içinden değiştirebilir.
     * - Tema: Mihrap (varsayılan "zumrut" yuvası, yeni renkler)
     * - Arka plan deseni kapalı
     * (Bölümler artık gizlenmez; bkz. bolumleriGeriAc.)
     */
    static void sadeGorunumuUygula(Context c) {
        try {
            SharedPreferences t = Tercihler.sp(c);
            if (t.getBoolean(UYGULANDI, false)) return;
            SharedPreferences f = c.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE);
            f.edit()
                    .putString("flutter.settings.colorTheme", "zumrut")
                    .putBoolean("flutter.appearance.pattern", false)
                    .commit();
            t.edit().putBoolean(UYGULANDI, true).commit();
        } catch (Throwable ignored) {
        }
    }
}
