package com.mehmetderin.secde_vakti.saglik;

import android.content.Context;
import android.os.Build;

import org.json.JSONArray;
import org.json.JSONObject;

import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.TimeZone;

/**
 * Uygulamanın vakit önbelleğini okur: FlutterSharedPreferences içinde "flutter.schedule.json".
 * Biçim: {placeName, timeZoneIdentifier, days:[{dayStart, hicriDate, times:[{prayer, date}]}]}.
 * Bildirim kaydından farkı: kapatılmış vakitler ve geçmiş vakitler de burada vardır.
 */
public final class VakitTakvimi {

    public static final String[] SIRA = {"fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"};

    /** Tek bir namaz vakti. */
    public static final class An implements Comparable<An> {
        public final String namaz;
        public final long zaman;

        An(String namaz, long zaman) {
            this.namaz = namaz;
            this.zaman = zaman;
        }

        public String ad() {
            String a = Metinler.namazAdi(namaz);
            return a == null ? namaz : a;
        }

        @Override
        public int compareTo(An o) {
            return Long.compare(zaman, o.zaman);
        }
    }

    /** Okunan takvim. */
    public static final class Takvim {
        public String yer;
        public String hicri;
        /** Konum (schedule.json latitude/longitude); yoksa NaN. */
        public double enlem = Double.NaN, boylam = Double.NaN;
        public final List<An> vakitler = new ArrayList<>();
        /** Gün başı (yerel saat) -> o günün hicrî tarihi; ilk eşleşme yeter. */
        final List<long[]> gunler = new ArrayList<>();
        final List<String> hicriler = new ArrayList<>();
        final List<String> kibleSaatleri = new ArrayList<>();

        public boolean bos() {
            return vakitler.isEmpty();
        }

        /** Bugünün (yerel) vakitleri, sıralı. */
        public List<An> bugun() {
            return gun(System.currentTimeMillis());
        }

        public List<An> gun(long herhangiAn) {
            Calendar b = Calendar.getInstance();
            b.setTimeInMillis(herhangiAn);
            List<An> l = new ArrayList<>();
            for (An a : vakitler) {
                Calendar c = Calendar.getInstance();
                c.setTimeInMillis(a.zaman);
                if (c.get(Calendar.YEAR) == b.get(Calendar.YEAR) && c.get(Calendar.DAY_OF_YEAR) == b.get(Calendar.DAY_OF_YEAR)) {
                    l.add(a);
                }
            }
            return l;
        }

        /** Şu anki vakit (en son giren); yoksa null. */
        public An simdiki() {
            long simdi = System.currentTimeMillis();
            An son = null;
            for (An a : vakitler) {
                if (a.zaman <= simdi) son = a;
                else break;
            }
            return son;
        }

        public An sonraki() {
            long simdi = System.currentTimeMillis();
            for (An a : vakitler) if (a.zaman > simdi) return a;
            return null;
        }

        /** Takvimdeki son vaktin zamanı; boşsa 0. */
        public long bitis() {
            return vakitler.isEmpty() ? 0 : vakitler.get(vakitler.size() - 1).zaman;
        }

        /** Bugünün hicrî tarihi (varsa). */
        public String bugunHicri() {
            return hicri(System.currentTimeMillis());
        }

        /** Bugünün kıble saati ("12:34"): güneşin kıble yönünde olduğu an; yoksa null. */
        public String kibleSaati() {
            Calendar b = Calendar.getInstance();
            for (int i = 0; i < gunler.size(); i++) {
                Calendar c = Calendar.getInstance();
                c.setTimeInMillis(gunler.get(i)[0]);
                if (c.get(Calendar.YEAR) == b.get(Calendar.YEAR) && c.get(Calendar.DAY_OF_YEAR) == b.get(Calendar.DAY_OF_YEAR)) {
                    return kibleSaatleri.get(i);
                }
            }
            return null;
        }

        /** Verilen günün hicrî tarihi (varsa). */
        public String hicri(long herhangiAn) {
            Calendar b = Calendar.getInstance();
            b.setTimeInMillis(herhangiAn);
            for (int i = 0; i < gunler.size(); i++) {
                Calendar c = Calendar.getInstance();
                c.setTimeInMillis(gunler.get(i)[0]);
                if (c.get(Calendar.YEAR) == b.get(Calendar.YEAR) && c.get(Calendar.DAY_OF_YEAR) == b.get(Calendar.DAY_OF_YEAR)) {
                    String h = hicriler.get(i);
                    return h == null || h.isEmpty() ? null : h;
                }
            }
            return null;
        }
    }

    private VakitTakvimi() {}

    public static Takvim oku(Context c) {
        Takvim t = new Takvim();
        try {
            Object v = c.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    .getAll().get("flutter.schedule.json");
            if (!(v instanceof String)) return t;
            JSONObject o = new JSONObject((String) v);
            t.yer = bosIse(o.optString("placeName", null));
            if (o.has("latitude") && o.has("longitude")) {
                t.enlem = o.optDouble("latitude", Double.NaN);
                t.boylam = o.optDouble("longitude", Double.NaN);
            }
            String bolge = bosIse(o.optString("timeZoneIdentifier", null));
            JSONArray gunler = o.optJSONArray("days");
            if (gunler == null) return t;
            for (int i = 0; i < gunler.length(); i++) {
                JSONObject g = gunler.optJSONObject(i);
                if (g == null) continue;
                long gb = zaman(g.optString("dayStart", ""), bolge);
                if (gb > 0) {
                    t.gunler.add(new long[]{gb});
                    t.hicriler.add(bosIse(g.optString("hicriDate", null)));
                    t.kibleSaatleri.add(saatMetni(g.optString("qiblaTime", null), bolge));
                }
                JSONArray vakitler = g.optJSONArray("times");
                if (vakitler == null) continue;
                for (int j = 0; j < vakitler.length(); j++) {
                    JSONObject a = vakitler.optJSONObject(j);
                    if (a == null) continue;
                    String namaz = bosIse(a.optString("prayer", null));
                    long z = zaman(a.optString("date", ""), bolge);
                    if (namaz != null && z > 0) t.vakitler.add(new An(namaz, z));
                }
            }
        } catch (Throwable ignored) {
        }
        Collections.sort(t.vakitler);
        t.hicri = t.bugunHicri();
        return t;
    }

    /** "12:34", "12:34:00" ya da ISO tarih-saat → "12:34"; anlaşılmazsa null. */
    static String saatMetni(String s, String bolge) {
        s = bosIse(s);
        if (s == null) return null;
        if (s.matches("\\d{1,2}:\\d{2}(:\\d{2})?")) return (s.length() == 4 ? "0" : "") + s.substring(0, s.indexOf(':') + 3);
        long z = zaman(s, bolge);
        return z > 0 ? Metinler.saat(z) : null;
    }

    private static String bosIse(String s) {
        return s == null || s.isEmpty() || "null".equals(s) ? null : s;
    }

    /**
     * Dart DateTime.toIso8601String çıktısını çevirir: "…Z" ya da "+03:00" ise mutlak an,
     * değilse verilen saat diliminde (yoksa telefonun) yerel saat.
     */
    static long zaman(String s, String bolge) {
        if (s == null || s.length() < 10) return 0;
        try {
            if (Build.VERSION.SDK_INT >= 26) {
                boolean ofsetli = s.endsWith("Z") || s.matches(".*[+-]\\d{2}:?\\d{2}$");
                if (ofsetli) return java.time.OffsetDateTime.parse(s.endsWith("Z") ? s : s.replaceAll("([+-]\\d{2})(\\d{2})$", "$1:$2"))
                        .toInstant().toEpochMilli();
                if (s.length() == 10) s = s + "T00:00:00";
                java.time.ZoneId z;
                try {
                    z = bolge == null ? java.time.ZoneId.systemDefault() : java.time.ZoneId.of(bolge);
                } catch (Throwable e) {
                    z = java.time.ZoneId.systemDefault();
                }
                return java.time.LocalDateTime.parse(s).atZone(z).toInstant().toEpochMilli();
            }
        } catch (Throwable ignored) {
        }
        try {
            boolean utc = s.endsWith("Z");
            String yalin = s.length() >= 19 ? s.substring(0, 19) : s.substring(0, 10) + "T00:00:00";
            SimpleDateFormat f = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.ROOT);
            f.setTimeZone(utc ? TimeZone.getTimeZone("UTC")
                    : (bolge == null ? TimeZone.getDefault() : TimeZone.getTimeZone(bolge)));
            return f.parse(yalin).getTime();
        } catch (Throwable e) {
            return 0;
        }
    }
}
