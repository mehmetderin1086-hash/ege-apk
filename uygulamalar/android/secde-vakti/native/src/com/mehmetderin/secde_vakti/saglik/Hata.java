package com.mehmetderin.secde_vakti.saglik;

import android.content.Context;

import java.io.PrintWriter;
import java.io.StringWriter;

/**
 * Hata kaydı: çökme ve açılamayan bölümler kalıcı olarak saklanır; denetim raporunda görünür.
 * Kullanıcı yalnız telefondan çalıştığı için hata bilgisinin tek yolu budur.
 */
final class Hata {

    private static final String DOSYA = "secde_hata";

    private Hata() {}

    /** Uygulama çökerse son hatayı kaydeder, sonra sistemin varsayılan davranışına bırakır. */
    static void yakalayiciKur(Context c) {
        final Context uc = c.getApplicationContext();
        final Thread.UncaughtExceptionHandler onceki = Thread.getDefaultUncaughtExceptionHandler();
        Thread.setDefaultUncaughtExceptionHandler((t, e) -> {
            try {
                kaydet(uc, "Çökme (" + t.getName() + ")", e, true);
            } catch (Throwable ignored) {
            }
            if (onceki != null) onceki.uncaughtException(t, e);
        });
    }

    static void kaydet(Context c, String yer, Throwable e) {
        kaydet(c, yer, e, false);
    }

    private static void kaydet(Context c, String yer, Throwable e, boolean hemen) {
        StringWriter sw = new StringWriter();
        e.printStackTrace(new PrintWriter(sw));
        String iz = sw.toString();
        if (iz.length() > 3500) iz = iz.substring(0, 3500);
        android.content.SharedPreferences.Editor ed = c.getSharedPreferences(DOSYA, Context.MODE_PRIVATE).edit()
                .putString("yer", yer)
                .putString("iz", iz)
                .putLong("zaman", System.currentTimeMillis())
                .putInt("sayi", c.getSharedPreferences(DOSYA, Context.MODE_PRIVATE).getInt("sayi", 0) + 1);
        if (hemen) ed.commit();
        else ed.apply();
    }

    /** Son hata metni ya da null. */
    static String son(Context c) {
        android.content.SharedPreferences sp = c.getSharedPreferences(DOSYA, Context.MODE_PRIVATE);
        String iz = sp.getString("iz", null);
        if (iz == null) return null;
        return sp.getString("yer", "?") + " · " + Metinler.gunVeSaat(sp.getLong("zaman", 0))
                + " · toplam " + sp.getInt("sayi", 1) + " kayıt\n" + iz;
    }

    static void temizle(Context c) {
        c.getSharedPreferences(DOSYA, Context.MODE_PRIVATE).edit().clear().apply();
    }
}
