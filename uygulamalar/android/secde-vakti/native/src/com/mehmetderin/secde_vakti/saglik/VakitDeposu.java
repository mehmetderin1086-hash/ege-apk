package com.mehmetderin.secde_vakti.saglik;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.Build;

import org.json.JSONArray;
import org.json.JSONObject;

import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.TimeZone;

/**
 * Dart tarafının flutter_local_notifications ile kurduğu bildirimleri okur.
 *
 * Eklenti kurduğu her bildirimi "scheduled_notifications" adlı SharedPreferences
 * dosyasında Gson ile JSON dizi olarak saklar; çalan tek seferlik bildirim listeden düşer.
 * Bu sınıf yalnızca okur, hiçbir şey yazmaz.
 */
public final class VakitDeposu {

    private static final String DOSYA = "scheduled_notifications";
    private static final String ANAHTAR = "scheduled_notifications";

    private VakitDeposu() {}

    /** Henüz çalmamış bildirimler, zamana göre sıralı. Okuma hatasında boş liste. */
    public static List<Vakit> gelecek(Context c) {
        List<Vakit> hepsi = oku(c);
        long simdi = System.currentTimeMillis();
        List<Vakit> sonuc = new ArrayList<>();
        for (Vakit v : hepsi) if (v.zaman >= simdi - 30_000L) sonuc.add(v);
        return sonuc;
    }

    public static Vakit sonrakiVakit(Context c) {
        for (Vakit v : gelecek(c)) if (v.vakitBildirimi()) return v;
        return null;
    }

    /** Kurulu en son vakit bildiriminin zamanı; yoksa 0. */
    public static long sonVakitZamani(List<Vakit> liste) {
        long son = 0;
        for (Vakit v : liste) if (v.vakitBildirimi() && !v.tekrarli) son = Math.max(son, v.zaman);
        return son;
    }

    public static int say(List<Vakit> liste, String tur) {
        int n = 0;
        for (Vakit v : liste) if (tur.equals(v.tur)) n++;
        return n;
    }

    public static List<Vakit> oku(Context c) {
        List<Vakit> liste = new ArrayList<>();
        try {
            SharedPreferences sp = c.getSharedPreferences(DOSYA, Context.MODE_PRIVATE);
            String json = sp.getString(ANAHTAR, null);
            if (json == null || json.isEmpty()) return liste;
            JSONArray dizi = new JSONArray(json);
            long simdi = System.currentTimeMillis();
            for (int i = 0; i < dizi.length(); i++) {
                JSONObject o = dizi.optJSONObject(i);
                if (o == null) continue;
                try {
                    Vakit v = cevir(o, simdi);
                    if (v != null) liste.add(v);
                } catch (Throwable ignored) {
                }
            }
        } catch (Throwable ignored) {
        }
        Collections.sort(liste);
        return liste;
    }

    private static Vakit cevir(JSONObject o, long simdi) throws Exception {
        String tarih = o.optString("scheduledDateTime", null);
        if (tarih == null || tarih.isEmpty() || "null".equals(tarih)) return null;
        String bolge = o.optString("timeZoneName", null);
        long zaman = zamanaCevir(tarih, bolge);
        if (zaman <= 0) return null;

        String tekrar = o.optString("matchDateTimeComponents", null);
        boolean tekrarli = tekrar != null && !tekrar.isEmpty() && !"null".equals(tekrar);
        if (tekrarli && zaman < simdi) {
            long adim;
            if ("Time".equals(tekrar)) adim = 86_400_000L;
            else if ("DayOfWeekAndTime".equals(tekrar)) adim = 7 * 86_400_000L;
            else adim = 0;
            if (adim > 0) {
                long fark = simdi - zaman;
                zaman += ((fark / adim) + 1) * adim;
            }
        }

        String tur = null, namaz = null;
        String yuk = o.optString("payload", null);
        if (yuk != null && yuk.startsWith("{")) {
            try {
                JSONObject p = new JSONObject(yuk);
                tur = p.optString("kind", null);
                namaz = p.optString("prayer", null);
                if (namaz != null && namaz.isEmpty()) namaz = null;
            } catch (Throwable ignored) {
            }
        }
        return new Vakit(o.optInt("id", 0), o.optString("title", ""), o.optString("body", ""),
                tur, namaz, o.optString("channelId", null), zaman, tekrarli);
    }

    /** Eklentinin "yyyy-MM-ddTHH:mm:ss[.SSS]" yerel saat metnini, verilen saat diliminde epoch ms'e çevirir. */
    static long zamanaCevir(String metin, String bolge) {
        try {
            if (Build.VERSION.SDK_INT >= 26) {
                java.time.ZoneId z;
                try {
                    z = bolge == null || bolge.isEmpty() ? java.time.ZoneId.systemDefault() : java.time.ZoneId.of(bolge);
                } catch (Throwable t) {
                    z = java.time.ZoneId.systemDefault();
                }
                return java.time.LocalDateTime.parse(metin).atZone(z).toInstant().toEpochMilli();
            }
        } catch (Throwable ignored) {
        }
        String yalin = metin.length() >= 19 ? metin.substring(0, 19) : metin;
        SimpleDateFormat f = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.ROOT);
        f.setTimeZone(bolge == null || bolge.isEmpty() ? TimeZone.getDefault() : TimeZone.getTimeZone(bolge));
        try {
            return f.parse(yalin).getTime();
        } catch (ParseException e) {
            return 0;
        }
    }
}
