package com.mehmetderin.secde_vakti.saglik;

import android.content.Context;
import android.content.SharedPreferences;

/** Android katmanının kendi ayarları (Flutter ayarlarından ayrı dosyada). */
public final class Tercihler {

    static final String DOSYA = "secde_bildirim_kontrol";

    static final String SAYAC_ACIK = "sayac_acik";
    static final String BEKCI_ACIK = "bekci_acik";
    static final String SON_BEKCI_UYARI = "son_bekci_uyari_ms";
    static final String SON_BEKCI_KONTROL = "son_bekci_kontrol_ms";

    private Tercihler() {}

    static SharedPreferences sp(Context c) {
        return c.getSharedPreferences(DOSYA, Context.MODE_PRIVATE);
    }

    public static boolean sayacAcik(Context c) {
        return sp(c).getBoolean(SAYAC_ACIK, false);
    }

    public static void sayacAcik(Context c, boolean acik) {
        sp(c).edit().putBoolean(SAYAC_ACIK, acik).apply();
    }

    /** Eski 1.0.0 ekranının açılmasını önlemek için ana ekran her zaman etkindir. */
    public static boolean acilisMenu(Context c) {
        return true;
    }

    public static void acilisMenu(Context c, boolean acik) {
        sp(c).edit().putBoolean("acilis_menu", true).apply();
    }

    public static boolean bekciAcik(Context c) {
        return sp(c).getBoolean(BEKCI_ACIK, true);
    }

    public static void bekciAcik(Context c, boolean acik) {
        sp(c).edit().putBoolean(BEKCI_ACIK, acik).apply();
    }

    /** Vakit bildirimlerinin en son kurulduğu an (flutter.notifications.lastRescheduleMs); yoksa 0. */
    public static long sonKurulum(Context c) {
        try {
            Object v = c.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    .getAll().get("flutter.notifications.lastRescheduleMs");
            if (v instanceof Number) return ((Number) v).longValue();
            if (v instanceof String) return Long.parseLong((String) v);
        } catch (Throwable ignored) {
        }
        return 0;
    }
}
