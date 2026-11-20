package com.mehmetderin.secde_vakti.saglik;

import android.Manifest;
import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Looper;
import android.text.Editable;
import android.text.TextWatcher;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.HapticFeedbackConstants;
import android.view.View;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONArray;
import org.json.JSONObject;

import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.TimeZone;

/**
 * Yerel Konum, 81 İl Seçici, 35 Günlük Otomatik Vakit Takvimi Üretici ve Yerel Vakit Alarm Motoru.
 * Eski 1.0.0 Flutter ekranına (MainActivity) hiçbir zaman ihtiyaç bırakmadan konum seçimi,
 * GPS ile yakın il tespiti, flutter.schedule.json yenilemesi ve ezan/vakit bildirim planlamasını yürütür.
 */
public final class KonumVeTakvim {

    public static final String KANAL_EZAN = "secde_ezan_yerel";
    static final int BILDIRIM_VAKIT = 0x5ece0;
    private static final int ALARM_ISTEK_KODU = 0x5ece1;

    public static final class Sehir {
        public final String ad;
        public final String bolge;
        public final double enlem;
        public final double boylam;
        public final String saatDilimi;

        Sehir(String ad, String bolge, double enlem, double boylam, String saatDilimi) {
            this.ad = ad;
            this.bolge = bolge;
            this.enlem = enlem;
            this.boylam = boylam;
            this.saatDilimi = saatDilimi;
        }
    }

    /** Türkiye'nin 81 ili + başlıca İslâm beldeleri ve dünya merkezleri. */
    public static final Sehir[] SEHIRLER = {
            // Başlıca merkezler (hızlı erişim için üstte de aranabilir)
            new Sehir("İstanbul", "Türkiye · Marmara", 41.0082, 28.9784, "Europe/Istanbul"),
            new Sehir("Ankara", "Türkiye · İç Anadolu", 39.9334, 32.8597, "Europe/Istanbul"),
            new Sehir("İzmir", "Türkiye · Ege", 38.4237, 27.1428, "Europe/Istanbul"),
            new Sehir("Bursa", "Türkiye · Marmara", 40.1885, 29.0610, "Europe/Istanbul"),
            new Sehir("Antalya", "Türkiye · Akdeniz", 36.8969, 30.7133, "Europe/Istanbul"),
            new Sehir("Konya", "Türkiye · İç Anadolu", 37.8746, 32.4932, "Europe/Istanbul"),
            new Sehir("Adana", "Türkiye · 01", 37.0000, 35.3213, "Europe/Istanbul"),
            new Sehir("Adıyaman", "Türkiye · 02", 37.7648, 38.2786, "Europe/Istanbul"),
            new Sehir("Afyonkarahisar", "Türkiye · 03", 38.7507, 30.5567, "Europe/Istanbul"),
            new Sehir("Ağrı", "Türkiye · 04", 39.7191, 43.0503, "Europe/Istanbul"),
            new Sehir("Amasya", "Türkiye · 05", 40.6499, 35.8353, "Europe/Istanbul"),
            new Sehir("Artvin", "Türkiye · 08", 41.1828, 41.8183, "Europe/Istanbul"),
            new Sehir("Aydın", "Türkiye · 09", 37.8560, 27.8416, "Europe/Istanbul"),
            new Sehir("Balıkesir", "Türkiye · 10", 39.6484, 27.8826, "Europe/Istanbul"),
            new Sehir("Bilecik", "Türkiye · 11", 40.1451, 29.9799, "Europe/Istanbul"),
            new Sehir("Bingöl", "Türkiye · 12", 38.8854, 40.4980, "Europe/Istanbul"),
            new Sehir("Bitlis", "Türkiye · 13", 38.4006, 42.1095, "Europe/Istanbul"),
            new Sehir("Bolu", "Türkiye · 14", 40.7392, 31.6089, "Europe/Istanbul"),
            new Sehir("Burdur", "Türkiye · 15", 37.7203, 30.2908, "Europe/Istanbul"),
            new Sehir("Çanakkale", "Türkiye · 17", 40.1553, 26.4142, "Europe/Istanbul"),
            new Sehir("Çankırı", "Türkiye · 18", 40.6013, 33.6134, "Europe/Istanbul"),
            new Sehir("Çorum", "Türkiye · 19", 40.5506, 34.9556, "Europe/Istanbul"),
            new Sehir("Denizli", "Türkiye · 20", 37.7765, 29.0864, "Europe/Istanbul"),
            new Sehir("Diyarbakır", "Türkiye · 21", 37.9144, 40.2306, "Europe/Istanbul"),
            new Sehir("Edirne", "Türkiye · 22", 41.6771, 26.5557, "Europe/Istanbul"),
            new Sehir("Elazığ", "Türkiye · 23", 38.6810, 39.2264, "Europe/Istanbul"),
            new Sehir("Erzincan", "Türkiye · 24", 39.7500, 39.5000, "Europe/Istanbul"),
            new Sehir("Erzurum", "Türkiye · 25", 39.9043, 41.2679, "Europe/Istanbul"),
            new Sehir("Eskişehir", "Türkiye · 26", 39.7767, 30.5206, "Europe/Istanbul"),
            new Sehir("Gaziantep", "Türkiye · 27", 37.0662, 37.3833, "Europe/Istanbul"),
            new Sehir("Giresun", "Türkiye · 28", 40.9128, 38.3895, "Europe/Istanbul"),
            new Sehir("Gümüşhane", "Türkiye · 29", 40.4603, 39.4814, "Europe/Istanbul"),
            new Sehir("Hakkâri", "Türkiye · 30", 37.5833, 43.7333, "Europe/Istanbul"),
            new Sehir("Hatay", "Türkiye · 31", 36.2021, 36.1606, "Europe/Istanbul"),
            new Sehir("Isparta", "Türkiye · 32", 37.7648, 30.5566, "Europe/Istanbul"),
            new Sehir("Mersin", "Türkiye · 33", 36.8121, 34.6415, "Europe/Istanbul"),
            new Sehir("Kars", "Türkiye · 36", 40.6013, 43.0975, "Europe/Istanbul"),
            new Sehir("Kastamonu", "Türkiye · 37", 41.3887, 33.7827, "Europe/Istanbul"),
            new Sehir("Kayseri", "Türkiye · 38", 38.7312, 35.4787, "Europe/Istanbul"),
            new Sehir("Kırklareli", "Türkiye · 39", 41.7333, 27.2167, "Europe/Istanbul"),
            new Sehir("Kırşehir", "Türkiye · 40", 39.1425, 34.1709, "Europe/Istanbul"),
            new Sehir("Kocaeli", "Türkiye · 41", 40.8533, 29.8815, "Europe/Istanbul"),
            new Sehir("Kütahya", "Türkiye · 43", 39.4167, 29.9833, "Europe/Istanbul"),
            new Sehir("Malatya", "Türkiye · 44", 38.3552, 38.3095, "Europe/Istanbul"),
            new Sehir("Manisa", "Türkiye · 45", 38.6191, 27.4289, "Europe/Istanbul"),
            new Sehir("Kahramanmaraş", "Türkiye · 46", 37.5858, 36.9371, "Europe/Istanbul"),
            new Sehir("Mardin", "Türkiye · 47", 37.3212, 40.7245, "Europe/Istanbul"),
            new Sehir("Muğla", "Türkiye · 48", 37.2153, 28.3636, "Europe/Istanbul"),
            new Sehir("Muş", "Türkiye · 49", 38.7432, 41.5065, "Europe/Istanbul"),
            new Sehir("Nevşehir", "Türkiye · 50", 38.6244, 34.7144, "Europe/Istanbul"),
            new Sehir("Niğde", "Türkiye · 51", 37.9667, 34.6833, "Europe/Istanbul"),
            new Sehir("Ordu", "Türkiye · 52", 40.9839, 37.8764, "Europe/Istanbul"),
            new Sehir("Rize", "Türkiye · 53", 41.0201, 40.5234, "Europe/Istanbul"),
            new Sehir("Sakarya", "Türkiye · 54", 40.7569, 30.3783, "Europe/Istanbul"),
            new Sehir("Samsun", "Türkiye · 55", 41.2867, 36.3300, "Europe/Istanbul"),
            new Sehir("Siirt", "Türkiye · 56", 37.9333, 41.9500, "Europe/Istanbul"),
            new Sehir("Sinop", "Türkiye · 57", 42.0231, 35.1531, "Europe/Istanbul"),
            new Sehir("Sivas", "Türkiye · 58", 39.7477, 37.0179, "Europe/Istanbul"),
            new Sehir("Tekirdağ", "Türkiye · 59", 40.9833, 27.5167, "Europe/Istanbul"),
            new Sehir("Tokat", "Türkiye · 60", 40.3167, 36.5500, "Europe/Istanbul"),
            new Sehir("Trabzon", "Türkiye · 61", 41.0027, 39.7168, "Europe/Istanbul"),
            new Sehir("Tunceli", "Türkiye · 62", 39.1079, 39.5401, "Europe/Istanbul"),
            new Sehir("Şanlıurfa", "Türkiye · 63", 37.1591, 38.7969, "Europe/Istanbul"),
            new Sehir("Uşak", "Türkiye · 64", 38.6823, 29.4082, "Europe/Istanbul"),
            new Sehir("Van", "Türkiye · 65", 38.4891, 43.4089, "Europe/Istanbul"),
            new Sehir("Yozgat", "Türkiye · 66", 39.8181, 34.8147, "Europe/Istanbul"),
            new Sehir("Zonguldak", "Türkiye · 67", 41.4564, 31.7987, "Europe/Istanbul"),
            new Sehir("Aksaray", "Türkiye · 68", 38.3687, 34.0370, "Europe/Istanbul"),
            new Sehir("Bayburt", "Türkiye · 69", 40.2552, 40.2249, "Europe/Istanbul"),
            new Sehir("Karaman", "Türkiye · 70", 37.1759, 33.2287, "Europe/Istanbul"),
            new Sehir("Kırıkkale", "Türkiye · 71", 39.8468, 33.5153, "Europe/Istanbul"),
            new Sehir("Batman", "Türkiye · 72", 37.8812, 41.1351, "Europe/Istanbul"),
            new Sehir("Şırnak", "Türkiye · 73", 37.5164, 42.4611, "Europe/Istanbul"),
            new Sehir("Bartın", "Türkiye · 74", 41.6344, 32.3375, "Europe/Istanbul"),
            new Sehir("Ardahan", "Türkiye · 75", 41.1105, 42.7022, "Europe/Istanbul"),
            new Sehir("Iğdır", "Türkiye · 76", 39.9167, 44.0333, "Europe/Istanbul"),
            new Sehir("Yalova", "Türkiye · 77", 40.6500, 29.2667, "Europe/Istanbul"),
            new Sehir("Karabük", "Türkiye · 78", 41.2061, 32.6204, "Europe/Istanbul"),
            new Sehir("Kilis", "Türkiye · 79", 36.7184, 37.1212, "Europe/Istanbul"),
            new Sehir("Osmaniye", "Türkiye · 80", 37.0742, 36.2478, "Europe/Istanbul"),
            new Sehir("Düzce", "Türkiye · 81", 40.8438, 31.1565, "Europe/Istanbul"),
            // Kutsal beldeler ve uluslararası merkezler
            new Sehir("Mekke-i Mükerreme", "Haremeyn · Suudi Arabistan", 21.4225, 39.8262, "Asia/Riyadh"),
            new Sehir("Medîne-i Münevvere", "Haremeyn · Suudi Arabistan", 24.4672, 39.6111, "Asia/Riyadh"),
            new Sehir("Kudüs-i Şerîf", "Mescid-i Aksâ · Filistin", 31.7761, 35.2358, "Asia/Jerusalem"),
            new Sehir("Lefkoşa", "KKTC", 35.1856, 33.3823, "Asia/Nicosia"),
            new Sehir("Bakü", "Azerbaycan", 40.4093, 49.8671, "Asia/Baku"),
            new Sehir("Berlin", "Almanya", 52.5200, 13.4050, "Europe/Berlin"),
            new Sehir("Köln", "Almanya", 50.9375, 6.9603, "Europe/Berlin"),
            new Sehir("Viyana", "Avusturya", 48.2082, 16.3738, "Europe/Vienna"),
            new Sehir("Amsterdam", "Hollanda", 52.3676, 4.9041, "Europe/Amsterdam"),
            new Sehir("Londra", "Birleşik Krallık", 51.5072, -0.1276, "Europe/London"),
            new Sehir("Paris", "Fransa", 48.8566, 2.3522, "Europe/Paris"),
            new Sehir("New York", "ABD", 40.7128, -74.0060, "America/New_York"),
    };

    private KonumVeTakvim() {}

    /** Uygulama açılışında ve arka plan zamanlayıcısında takvimi ve bildirimleri canlı tutar. */
    public static void otomatikTazele(Context c) {
        try {
            VakitTakvimi.Takvim mevcut = VakitTakvimi.oku(c);
            long simdi = System.currentTimeMillis();
            long kalanMs = mevcut.bitis() - simdi;
            if (mevcut.bos() || kalanMs < 14L * 86_400_000L) {
                String yer = mevcut.yer != null ? mevcut.yer : "İstanbul";
                double enlem = !Double.isNaN(mevcut.enlem) ? mevcut.enlem : 41.0082;
                double boylam = !Double.isNaN(mevcut.boylam) ? mevcut.boylam : 28.9784;
                takvimiYaz(c, yer, enlem, boylam, mevcutSaatDilimi(c), !mevcut.bos());
            }
            List<Vakit> gelecek = VakitDeposu.gelecek(c);
            if (VakitDeposu.say(gelecek, "main") < 12) {
                bildirimleriYenile(c, false);
            } else {
                sonrakiYerelAlarmiKur(c, false);
            }
        } catch (Throwable ignored) {
        }
    }

    private static String mevcutSaatDilimi(Context c) {
        try {
            Object v = c.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    .getAll().get("flutter.schedule.json");
            if (v instanceof String) {
                String tz = new JSONObject((String) v).optString("timeZoneIdentifier", "");
                if (!tz.isEmpty() && !"null".equals(tz)) return tz;
            }
        } catch (Throwable ignored) {
        }
        return TimeZone.getDefault().getID();
    }

    /** Yeni bir şehir seçildiğinde takvimi ve vakit bildirimlerini baştan üretir. */
    public static void sehirSec(Context c, Sehir s) {
        if (s == null) return;
        takvimiYaz(c, s.ad, s.enlem, s.boylam, s.saatDilimi, false);
        bildirimleriYenile(c, true);
        VakitSayaci.guncelle(c);
        SessizMod.planla(c);
    }

    /** En yakın kayıtlı şehri bulur (GPS etiketi için). */
    public static Sehir enYakinSehir(double enlem, double boylam) {
        Sehir enIyi = SEHIRLER[0];
        double enKucuk = Double.MAX_VALUE;
        for (Sehir s : SEHIRLER) {
            double d = Math.hypot(s.enlem - enlem, (s.boylam - boylam) * Math.cos(Math.toRadians(enlem)));
            if (d < enKucuk) {
                enKucuk = d;
                enIyi = s;
            }
        }
        return enIyi;
    }

    /**
     * 35 günlük vakit, hicrî tarih ve kıble saati önbelleğini flutter.schedule.json biçiminde yazar.
     * mevcutKorunsun=true ise mevcut takvimdeki gelecek günlerin Diyanet saatlerini aynen korur.
     */
    public static void takvimiYaz(Context c, String yer, double enlem, double boylam, String saatDilimi, boolean mevcutKorunsun) {
        try {
            TimeZone tz = TimeZone.getTimeZone(saatDilimi == null || saatDilimi.isEmpty()
                    ? TimeZone.getDefault().getID() : saatDilimi);
            SharedPreferences fsp = c.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE);
            Map<String, JSONObject> korunanGunler = new HashMap<>();
            if (mevcutKorunsun) {
                Object eskiHam = fsp.getAll().get("flutter.schedule.json");
                if (eskiHam instanceof String) {
                    JSONArray eskiDizi = new JSONObject((String) eskiHam).optJSONArray("days");
                    if (eskiDizi != null) {
                        for (int i = 0; i < eskiDizi.length(); i++) {
                            JSONObject g = eskiDizi.optJSONObject(i);
                            if (g != null) {
                                String ds = g.optString("dayStart", "");
                                if (ds.length() >= 10) korunanGunler.put(ds.substring(0, 10), g);
                            }
                        }
                    }
                }
            }

            SimpleDateFormat iso = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.ROOT);
            iso.setTimeZone(tz);
            SimpleDateFormat ymd = new SimpleDateFormat("yyyy-MM-dd", Locale.ROOT);
            ymd.setTimeZone(tz);

            Calendar gun = Calendar.getInstance(tz);
            gun.set(Calendar.HOUR_OF_DAY, 0);
            gun.set(Calendar.MINUTE, 0);
            gun.set(Calendar.SECOND, 0);
            gun.set(Calendar.MILLISECOND, 0);

            HesapMotoru.Metot metot = HesapMotoru.aktifMetot(c);
            boolean asriSani = HesapMotoru.asriSani(c);
            JSONArray days = new JSONArray();

            for (int d = 0; d < 35; d++) {
                String anahtarGun = ymd.format(gun.getTime());
                JSONObject korunan = korunanGunler.get(anahtarGun);
                if (korunan != null) {
                    days.put(korunan);
                } else {
                    int yil = gun.get(Calendar.YEAR);
                    int ay = gun.get(Calendar.MONTH) + 1;
                    int ayGunu = gun.get(Calendar.DAY_OF_MONTH);
                    HesapMotoru.GunVakitleri gv = HesapMotoru.hesapla(yil, ay, ayGunu, enlem, boylam, tz, metot, asriSani);
                    int[] hicri = HicriTakvim.miladidenHicriye(yil, ay, ayGunu);
                    String hicriMetin = hicri[2] + " " + HicriTakvim.hicriAyAdi(hicri[1]) + " " + hicri[0];

                    JSONObject go = new JSONObject();
                    go.put("dayStart", iso.format(gun.getTime()));
                    go.put("hicriDate", hicriMetin);
                    // Öğle vaktinden ~24 dk öncesi yaklaşık güneş-kıble hizası özeti
                    go.put("qiblaTime", Metinler.saat(gv.ogle - 22 * 60_000L));

                    JSONArray times = new JSONArray();
                    long[] saatler = {gv.imsak, gv.gunes, gv.ogle, gv.ikindi, gv.aksam, gv.yatsi};
                    for (int i = 0; i < VakitTakvimi.SIRA.length; i++) {
                        times.put(new JSONObject()
                                .put("prayer", VakitTakvimi.SIRA[i])
                                .put("date", iso.format(new java.util.Date(saatler[i]))));
                    }
                    go.put("times", times);
                    days.put(go);
                }
                gun.add(Calendar.DAY_OF_MONTH, 1);
            }

            JSONObject kok = new JSONObject();
            kok.put("placeName", yer);
            kok.put("latitude", enlem);
            kok.put("longitude", boylam);
            kok.put("timeZoneIdentifier", tz.getID());
            kok.put("source", metot.kod);
            kok.put("days", days);

            fsp.edit()
                    .putBoolean("flutter.settings.onboarded", true)
                    .putString("flutter.schedule.json", kok.toString())
                    .apply();
        } catch (Throwable ignored) {
        }
    }

    /**
     * 30 günlük vakit bildirim kaydını yeniler ve yerel AlarmManager zincirini kurar.
     * Eski Flutter MainActivity'yi açmadan tüm bildirim ve bekçi sistemini besler.
     */
    public static void bildirimleriYenile(Context c, boolean zorla) {
        try {
            VakitTakvimi.Takvim t = VakitTakvimi.oku(c);
            if (t.bos()) {
                takvimiYaz(c, "İstanbul", 41.0082, 28.9784, TimeZone.getDefault().getID(), false);
                t = VakitTakvimi.oku(c);
            }
            String tzId = mevcutSaatDilimi(c);
            TimeZone tz = TimeZone.getTimeZone(tzId);
            SimpleDateFormat yerBicimi = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.ROOT);
            yerBicimi.setTimeZone(tz);

            long simdi = System.currentTimeMillis();
            JSONArray dizi = new JSONArray();
            int id = 2000;

            for (VakitTakvimi.An an : t.vakitler) {
                if ("sunrise".equals(an.namaz) || an.zaman <= simdi) continue;
                String ad = Metinler.namazAdi(an.namaz);
                if (ad == null) ad = "Namaz";
                JSONObject o = new JSONObject();
                o.put("id", id++);
                o.put("title", ad + " Vakti");
                o.put("body", (t.yer != null ? t.yer + " için " : "") + ad + " vakti girdi (" + Metinler.saat(an.zaman) + ").");
                o.put("channelId", "sekine_alarm_default");
                o.put("scheduledDateTime", yerBicimi.format(new java.util.Date(an.zaman)));
                o.put("timeZoneName", tzId);
                o.put("payload", "{\"kind\":\"main\",\"prayer\":\"" + an.namaz + "\"}");
                dizi.put(o);
                if (dizi.length() >= 160) break;
            }

            // Günün âyeti kartı için kayıt
            Calendar ayetZaman = Calendar.getInstance(tz);
            ayetZaman.add(Calendar.HOUR_OF_DAY, 4);
            String[] gununAyeti = gununAyetiSec(ayetZaman.get(Calendar.DAY_OF_YEAR));
            dizi.put(new JSONObject()
                    .put("id", 9901)
                    .put("title", "Günün Âyeti")
                    .put("body", gununAyeti[0] + " — " + gununAyeti[1])
                    .put("scheduledDateTime", yerBicimi.format(ayetZaman.getTime()))
                    .put("timeZoneName", tzId)
                    .put("payload", "{\"kind\":\"verse\"}"));

            if (zorla || VakitDeposu.say(VakitDeposu.gelecek(c), "main") < 12) {
                c.getSharedPreferences("scheduled_notifications", Context.MODE_PRIVATE)
                        .edit()
                        .putString("scheduled_notifications", dizi.toString())
                        .apply();
                c.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                        .edit()
                        .putLong("flutter.notifications.lastRescheduleMs", simdi)
                        .apply();
                Tercihler.sp(c).edit().putBoolean("yerel_alarm_etkin", true).apply();
            }
            sonrakiYerelAlarmiKur(c, zorla);
            Bekci.kontrol(c);
        } catch (Throwable ignored) {
        }
    }

    private static String[] gununAyetiSec(int gunSirasi) {
        String[][] ayetler = {
                {"Kalpler ancak Allah'ı anmakla huzur bulur.", "Ra'd, 28"},
                {"Şüphesiz zorlukla beraber bir kolaylık vardır.", "İnşirâh, 6"},
                {"Beni anın ki Ben de sizi anayım. Bana şükredin, nankörlük etmeyin.", "Bakara, 152"},
                {"Sabır ve namazla Allah'tan yardım isteyin.", "Bakara, 45"},
                {"Rabbiniz buyurdu ki: Bana duâ edin, size icâbet edeyim.", "Mü'min, 60"},
                {"Kim Allah'a tevekkül ederse O, ona yeter.", "Talâk, 3"},
                {"Namazı dosdoğru kılın; çünkü namaz insanı kötülüklerden alıkoyar.", "Ankebût, 45"},
        };
        return ayetler[Math.abs(gunSirasi) % ayetler.length];
    }

    /** Sıradaki namaz vaktine yerel AlarmManager uyarısı kurar. */
    public static void sonrakiYerelAlarmiKur(Context c, boolean zorla) {
        try {
            if (!zorla && !Tercihler.sp(c).getBoolean("yerel_alarm_etkin", false)) return;
            AlarmManager am = (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
            if (am == null) return;
            VakitTakvimi.Takvim t = VakitTakvimi.oku(c);
            long simdi = System.currentTimeMillis();
            VakitTakvimi.An hedef = null;
            for (VakitTakvimi.An a : t.vakitler) {
                if (!"sunrise".equals(a.namaz) && a.zaman > simdi + 2000L) {
                    hedef = a;
                    break;
                }
            }
            Intent niyet = new Intent(c, ZamanlayiciAlici.class)
                    .setAction(ZamanlayiciAlici.YEREL_VAKIT_ALARMI);
            if (hedef == null) {
                PendingIntent eski = PendingIntent.getBroadcast(c, ALARM_ISTEK_KODU, niyet, Kanallar.bayrak());
                am.cancel(eski);
                return;
            }
            niyet.putExtra("namaz", hedef.namaz).putExtra("zaman", hedef.zaman);
            PendingIntent pi = PendingIntent.getBroadcast(c, ALARM_ISTEK_KODU, niyet, Kanallar.bayrak());
            if (Build.VERSION.SDK_INT < 31 || am.canScheduleExactAlarms()) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, hedef.zaman, pi);
            } else {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, hedef.zaman, pi);
            }
        } catch (Throwable ignored) {
        }
    }

    /** ZamanlayiciAlici tarafından vakit girdiğinde çağrılır. */
    static void yerelVakitBildirimiGoster(Context c, Intent intent) {
        try {
            String namaz = intent.getStringExtra("namaz");
            long zaman = intent.getLongExtra("zaman", System.currentTimeMillis());
            long sonGosterilen = Tercihler.sp(c).getLong("son_yerel_vakit_ms", 0);
            if (Math.abs(zaman - sonGosterilen) < 60_000L) {
                sonrakiYerelAlarmiKur(c, true);
                return;
            }
            Tercihler.sp(c).edit().putLong("son_yerel_vakit_ms", zaman).apply();

            NotificationManager nm = Kanallar.nm(c);
            if (nm != null) {
                Kanallar.kur(c);
                String kanal = KANAL_EZAN;
                if (Build.VERSION.SDK_INT >= 26) {
                    NotificationChannel mevcutEzan = nm.getNotificationChannel("sekine_alarm_default");
                    if (mevcutEzan != null && mevcutEzan.getImportance() != NotificationManager.IMPORTANCE_NONE) {
                        kanal = mevcutEzan.getId();
                    } else {
                        NotificationChannel ch = new NotificationChannel(KANAL_EZAN, "Namaz Vakti Uyarıları", NotificationManager.IMPORTANCE_HIGH);
                        ch.setDescription("Namaz vakti girdiğinde bildirim gönderir");
                        ch.enableVibration(true);
                        nm.createNotificationChannel(ch);
                    }
                }
                String ad = Metinler.namazAdi(namaz);
                if (ad == null) ad = "Namaz";
                VakitTakvimi.Takvim t = VakitTakvimi.oku(c);
                String icerik = (t.yer != null ? t.yer + " · " : "") + ad + " vakti girdi (" + Metinler.saat(zaman) + ")";
                Notification.Builder b = Build.VERSION.SDK_INT >= 26
                        ? new Notification.Builder(c, kanal)
                        : new Notification.Builder(c);
                Kanallar.kucukSimgeAta(b, c);
                b.setColor(Gorunum.bildirimRengi())
                        .setContentTitle(ad + " Vakti")
                        .setContentText(icerik)
                        .setAutoCancel(true)
                        .setCategory(Notification.CATEGORY_ALARM)
                        .setContentIntent(Kanallar.durumEkrani(c, 0x5ece2));
                if (Build.VERSION.SDK_INT < 26) {
                    b.setPriority(Notification.PRIORITY_HIGH).setDefaults(Notification.DEFAULT_ALL);
                }
                nm.notify(BILDIRIM_VAKIT, b.build());
            }
            VakitSayaci.guncelle(c);
            sonrakiYerelAlarmiKur(c, true);
        } catch (Throwable ignored) {
        }
    }

    // ================================================================ Konum & 81 İl Seçici Alt Sayfası

    public static void sayfaAc(final DurumAktivitesi a, final Runnable yenile) {
        final TemaMotoru.Durum tm = TemaMotoru.aktif(a);
        final VakitTakvimi.Takvim mevcut = VakitTakvimi.oku(a);
        final LinearLayout kok = a.sutun();

        LinearLayout ozet = a.cam();
        a.baslik(ozet, "Aktif Konum & Vakit Takvimi");
        String sehirAd = mevcut.yer != null ? mevcut.yer : "İstanbul";
        ozet.addView(a.metin("📍 " + sehirAd, 18, DurumAktivitesi.ALTIN, true));
        if (!Double.isNaN(mevcut.enlem)) {
            ozet.addView(a.metin(String.format(Locale.ROOT,
                    "Koordinat: %.4f°, %.4f°  ·  Kıble: %.1f° (%.0f km)",
                    mevcut.enlem, mevcut.boylam,
                    Kible.yon(mevcut.enlem, mevcut.boylam),
                    Kible.uzaklikKm(mevcut.enlem, mevcut.boylam)), 13, DurumAktivitesi.SOLUK, false));
        }
        long bitis = mevcut.bitis();
        if (bitis > 0) {
            long kalanGun = Math.max(0, (bitis - System.currentTimeMillis()) / 86_400_000L);
            ozet.addView(a.metin("Takvim önbelleği: " + Metinler.tarih(bitis) + " tarihine kadar (" + kalanGun + " gün hazır)",
                    13, DurumAktivitesi.IYI, false));
        }

        LinearLayout ikili = new LinearLayout(a);
        ikili.addView(a.dugme("📍 GPS ile Bul", true, v -> gpsIleKonumBul(a, yenile)), a.yarim(true));
        ikili.addView(a.dugme("🔔 Vakitleri Yenile", false, v -> {
            otomatikTazele(a);
            bildirimleriYenile(a, true);
            VakitSayaci.guncelle(a);
            Toast.makeText(a, "35 günlük vakit takvimi ve bildirimler yenilendi", Toast.LENGTH_SHORT).show();
            if (yenile != null) yenile.run();
        }), a.yarim(false));
        ozet.addView(ikili);
        kok.addView(ozet);

        // Arama kutusu
        LinearLayout aramaKart = a.cam();
        a.baslik(aramaKart, "81 İl ve Dünya Merkezleri");
        final EditText arama = new EditText(a);
        arama.setHint("Şehir ara (ör. İstanbul, Konya, Mekke, Berlin)…");
        arama.setHintTextColor(tm.silik);
        arama.setTextColor(tm.metin);
        arama.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15 * tm.yaziOlcegi);
        arama.setSingleLine(true);
        arama.setPadding(a.dp(14), a.dp(11), a.dp(14), a.dp(11));
        GradientDrawable ag = new GradientDrawable();
        ag.setColor(tm.acik ? 0x12000000 : 0x26FFFFFF);
        ag.setStroke(1, tm.acik ? 0x28000000 : 0x38FFFFFF);
        ag.setCornerRadius(a.dp(14));
        arama.setBackground(ag);
        aramaKart.addView(arama);
        kok.addView(aramaKart);

        final LinearLayout listeKabi = new LinearLayout(a);
        listeKabi.setOrientation(LinearLayout.VERTICAL);
        kok.addView(listeKabi);

        final Runnable listeyiDoldur = () -> {
            listeKabi.removeAllViews();
            String aranan = norm(arama.getText() == null ? "" : arama.getText().toString());
            LinearLayout kart = a.cam();
            int sayac = 0;
            for (final Sehir s : SEHIRLER) {
                if (!aranan.isEmpty() && !norm(s.ad).contains(aranan) && !norm(s.bolge).contains(aranan)) {
                    continue;
                }
                sayac++;
                boolean aktif = sehirAd.toLowerCase(Metinler.TR).startsWith(s.ad.toLowerCase(Metinler.TR));
                LinearLayout satir = new LinearLayout(a);
                satir.setGravity(Gravity.CENTER_VERTICAL);
                satir.setPadding(a.dp(10), a.dp(11), a.dp(10), a.dp(11));
                satir.setClickable(true);
                satir.setContentDescription("Şehir " + s.ad);
                if (aktif) {
                    GradientDrawable sg = new GradientDrawable();
                    sg.setColor((tm.vurgu & 0x00FFFFFF) | (tm.acik ? 0x22000000 : 0x38000000));
                    sg.setStroke(1, (tm.vurgu & 0x00FFFFFF) | 0x88000000);
                    sg.setCornerRadius(a.dp(12));
                    satir.setBackground(sg);
                }
                LinearLayout sol = new LinearLayout(a);
                sol.setOrientation(LinearLayout.VERTICAL);
                sol.addView(a.metin((aktif ? "✓ " : "") + s.ad, 16, aktif ? DurumAktivitesi.ALTIN : DurumAktivitesi.BEYAZ, true));
                sol.addView(a.metin(s.bolge, 12, DurumAktivitesi.SOLUK, false));
                satir.addView(sol, new LinearLayout.LayoutParams(0, -2, 1f));
                satir.addView(a.metin(String.format(Locale.ROOT, "%.0f°", Kible.yon(s.enlem, s.boylam)), 13, DurumAktivitesi.SILIK, true));
                a.basmaEfekti(satir);
                satir.setOnClickListener(v -> {
                    v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
                    sehirSec(a, s);
                    Toast.makeText(a, s.ad + " vakitleri ve bildirimleri kuruldu", Toast.LENGTH_SHORT).show();
                    a.altSayfaKapat();
                    if (yenile != null) yenile.run();
                });
                kart.addView(satir);
            }
            if (sayac == 0) {
                kart.addView(a.metin("Eşleşen şehir bulunamadı.", 14, DurumAktivitesi.SOLUK, false));
            }
            listeKabi.addView(kart);
        };

        listeyiDoldur.run();
        arama.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
            @Override public void onTextChanged(CharSequence s, int start, int before, int count) { listeyiDoldur.run(); }
            @Override public void afterTextChanged(Editable s) {}
        });

        ScrollView sv = a.sayfa(kok);
        sv.setPadding(0, 0, 0, 0);
        a.altSayfa("Konum & Şehir", sv, "mihrap");
    }

    private static void gpsIleKonumBul(final DurumAktivitesi a, final Runnable yenile) {
        try {
            if (Build.VERSION.SDK_INT >= 23) {
                boolean ince = a.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED;
                boolean kaba = a.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED;
                if (!ince && !kaba) {
                    a.requestPermissions(new String[]{
                            Manifest.permission.ACCESS_FINE_LOCATION,
                            Manifest.permission.ACCESS_COARSE_LOCATION
                    }, 0x5ec77);
                    Toast.makeText(a, "Konum iznini verdikten sonra tekrar dokunun", Toast.LENGTH_LONG).show();
                    return;
                }
            }
            LocationManager lm = (LocationManager) a.getSystemService(Context.LOCATION_SERVICE);
            if (lm == null) {
                Toast.makeText(a, "Konum servisine erişilemedi", Toast.LENGTH_SHORT).show();
                return;
            }
            Location enIyi = null;
            for (String p : new String[]{LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER, LocationManager.PASSIVE_PROVIDER}) {
                try {
                    Location l = lm.getLastKnownLocation(p);
                    if (l != null && (enIyi == null || l.getTime() > enIyi.getTime())) enIyi = l;
                } catch (Throwable ignored) {
                }
            }
            if (enIyi != null) {
                konumuUygula(a, enIyi, yenile);
                return;
            }
            Toast.makeText(a, "GPS konumu alınıyor…", Toast.LENGTH_SHORT).show();
            String saglayici = lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
                    ? LocationManager.NETWORK_PROVIDER : LocationManager.GPS_PROVIDER;
            lm.requestSingleUpdate(saglayici, new LocationListener() {
                @Override public void onLocationChanged(Location loc) {
                    if (loc != null && !a.isFinishing() && !a.isDestroyed()) {
                        a.runOnUiThread(() -> konumuUygula(a, loc, yenile));
                    }
                }
                @Override public void onStatusChanged(String p, int s, Bundle b) {}
                @Override public void onProviderEnabled(String p) {}
                @Override public void onProviderDisabled(String p) {}
            }, Looper.getMainLooper());
        } catch (Throwable t) {
            Toast.makeText(a, "GPS konumu alınamadı, listeden şehir seçebilirsiniz", Toast.LENGTH_LONG).show();
        }
    }

    private static void konumuUygula(DurumAktivitesi a, Location loc, Runnable yenile) {
        Sehir yakin = enYakinSehir(loc.getLatitude(), loc.getLongitude());
        String etiket = yakin.ad + " (GPS)";
        takvimiYaz(a, etiket, loc.getLatitude(), loc.getLongitude(), TimeZone.getDefault().getID(), false);
        bildirimleriYenile(a, true);
        VakitSayaci.guncelle(a);
        SessizMod.planla(a);
        Toast.makeText(a, etiket + " konumu güncellendi", Toast.LENGTH_SHORT).show();
        a.altSayfaKapat();
        if (yenile != null) yenile.run();
    }

    private static String norm(String s) {
        if (s == null) return "";
        return s.toLowerCase(Metinler.TR)
                .replace('ı', 'i').replace('î', 'i').replace('â', 'a').replace('û', 'u')
                .replace('ş', 's').replace('ğ', 'g').replace('ü', 'u').replace('ö', 'o').replace('ç', 'c')
                .trim();
    }
}
