package com.mehmetderin.secde_vakti.saglik;

import android.content.Context;

import java.util.ArrayList;
import java.util.Calendar;
import java.util.List;
import java.util.TimeZone;

/**
 * Çoklu Namaz Vakti Hesaplama Motoru (Çevrimdışı Astronomik + Diyanet Öncelikli Hibrit):
 *  - Diyanet İşleri Başkanlığı (temkinli), Dünya İslâm Birliği (MWL), ISNA, Ümmü'l-Kurâ (Mekke),
 *    Mısır Genel Fetvâ Kurumu, Karaçi ve Avrupa İGMG metotlarını destekler.
 *  - Hanefî Asr-ı Sânî (gölge = 2 misli) ve Cumhur/Diyanet Asr-ı Evvel (gölge = 1 misli) seçimi sunar.
 *  - Diyanet 31 günlük önbelleği dışındaki tarihler (ör. 30 günlük Ramazan İmsakiyesi, ileri aylar)
 *    veya çevrimdışı durumlar için kesintisiz vakit üretir.
 */
public final class HesapMotoru {

    public static final String ANAHTAR_METOT = "hesap_metot_kodu";
    public static final String ANAHTAR_ASRI_SANI = "hesap_asri_sani";

    public static final class Metot {
        public final String kod;
        public final String ad;
        public final String aciklama;
        public final double fecirAci;
        public final double yatsiAci;
        public final int yatsiDakika; // >0 ise açı yerine akşamdan sabit dakika sonra
        public final int[] temkinDk;  // fajr, sunrise, dhuhr, asr, maghrib, isha

        Metot(String kod, String ad, String aciklama, double fecirAci, double yatsiAci, int yatsiDakika, int[] temkinDk) {
            this.kod = kod;
            this.ad = ad;
            this.aciklama = aciklama;
            this.fecirAci = fecirAci;
            this.yatsiAci = yatsiAci;
            this.yatsiDakika = yatsiDakika;
            this.temkinDk = temkinDk;
        }
    }

    public static final Metot[] METOTLAR = {
            new Metot("diyanet", "Diyanet İşleri Başkanlığı", "Türkiye resmî takvimi ve temkin ölçüleri (18° / 17°)",
                    18.0, 17.0, 0, new int[]{0, -7, 5, 4, 7, 0}),
            new Metot("mwl", "Dünya İslâm Birliği (MWL)", "Avrupa, Uzak Doğu ve uluslararası standart (18° / 17°)",
                    18.0, 17.0, 0, new int[]{0, -1, 1, 0, 1, 0}),
            new Metot("isna", "Kuzey Amerika (ISNA)", "ABD ve Kanada İslâm Cemiyeti (15° / 15°)",
                    15.0, 15.0, 0, new int[]{0, -1, 1, 0, 1, 0}),
            new Metot("makkah", "Ümmü'l-Kurâ · Mekke", "Suudi Arabistan ve Körfez bölgesi (18.5° / +90 dk)",
                    18.5, 0.0, 90, new int[]{0, -1, 1, 0, 1, 0}),
            new Metot("egypt", "Mısır Genel Fetvâ Kurumu", "Orta Doğu ve Afrika standardı (19.5° / 17.5°)",
                    19.5, 17.5, 0, new int[]{0, -1, 1, 0, 1, 0}),
            new Metot("karachi", "Karaçi İslâmî İlimler", "Güney ve Orta Asya standardı (18° / 18°)",
                    18.0, 18.0, 0, new int[]{0, -1, 1, 0, 1, 0}),
            new Metot("igmg", "Avrupa · İGMG Takvimi", "Avrupa yüksek enlem uyumlu (16.5° / 15°)",
                    16.5, 15.0, 0, new int[]{0, -2, 2, 1, 3, 0}),
    };

    public static final class GunVakitleri {
        public final long imsak, gunes, ogle, ikindi, aksam, yatsi;
        public final boolean yaklasik;

        GunVakitleri(long imsak, long gunes, long ogle, long ikindi, long aksam, long yatsi, boolean yaklasik) {
            this.imsak = imsak;
            this.gunes = gunes;
            this.ogle = ogle;
            this.ikindi = ikindi;
            this.aksam = aksam;
            this.yatsi = yatsi;
            this.yaklasik = yaklasik;
        }

        public List<VakitTakvimi.An> liste() {
            List<VakitTakvimi.An> l = new ArrayList<>(6);
            l.add(new VakitTakvimi.An("fajr", imsak));
            l.add(new VakitTakvimi.An("sunrise", gunes));
            l.add(new VakitTakvimi.An("dhuhr", ogle));
            l.add(new VakitTakvimi.An("asr", ikindi));
            l.add(new VakitTakvimi.An("maghrib", aksam));
            l.add(new VakitTakvimi.An("isha", yatsi));
            return l;
        }
    }

    private HesapMotoru() {}

    public static Metot bul(String kod) {
        if (kod != null) {
            for (Metot m : METOTLAR) if (m.kod.equals(kod)) return m;
        }
        return METOTLAR[0];
    }

    public static Metot aktifMetot(Context c) {
        return bul(Tercihler.sp(c).getString(ANAHTAR_METOT, "diyanet"));
    }

    public static void metotSec(Context c, String kod) {
        Tercihler.sp(c).edit().putString(ANAHTAR_METOT, bul(kod).kod).apply();
    }

    public static boolean asriSani(Context c) {
        return Tercihler.sp(c).getBoolean(ANAHTAR_ASRI_SANI, false);
    }

    public static void asriSaniSec(Context c, boolean sani) {
        Tercihler.sp(c).edit().putBoolean(ANAHTAR_ASRI_SANI, sani).apply();
    }

    /**
     * Verilen gün için vakitleri döndürür:
     *  - Metot "diyanet" ve Asr-ı Sânî kapalıysa, takvim önbelleğinde gün varsa birebir Diyanet verisini verir.
     *  - Aksi hâlde veya ileri bir tarihte (ör. 30 günlük Ramazan İmsakiyesi) astronomik hesap üretir.
     */
    public static GunVakitleri gun(Context c, VakitTakvimi.Takvim takvim, long gunMs) {
        Metot m = aktifMetot(c);
        boolean sani = asriSani(c);
        if (takvim != null && "diyanet".equals(m.kod) && !sani) {
            List<VakitTakvimi.An> mevcut = takvim.gun(gunMs);
            if (mevcut.size() >= 6) {
                long f = 0, s = 0, d = 0, a = 0, mg = 0, is = 0;
                for (VakitTakvimi.An x : mevcut) {
                    switch (x.namaz) {
                        case "fajr": f = x.zaman; break;
                        case "sunrise": s = x.zaman; break;
                        case "dhuhr": d = x.zaman; break;
                        case "asr": a = x.zaman; break;
                        case "maghrib": mg = x.zaman; break;
                        case "isha": is = x.zaman; break;
                    }
                }
                if (f > 0 && mg > 0) return new GunVakitleri(f, s, d, a, mg, is, false);
            }
        }
        double enlem = (takvim != null && !Double.isNaN(takvim.enlem)) ? takvim.enlem : 41.0082;
        double boylam = (takvim != null && !Double.isNaN(takvim.boylam)) ? takvim.boylam : 28.9784;
        Calendar cal = Calendar.getInstance();
        cal.setTimeInMillis(gunMs);
        return hesapla(cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1, cal.get(Calendar.DAY_OF_MONTH),
                enlem, boylam, cal.getTimeZone(), m, sani);
    }

    /** NOAA / Jean Meeus güneş konumu formülleriyle astronomik vakit hesabı. */
    public static GunVakitleri hesapla(int yil, int ay, int gun, double enlem, double boylam,
                                       TimeZone tz, Metot m, boolean asriSani) {
        if (tz == null) tz = TimeZone.getDefault();
        if (m == null) m = METOTLAR[0];

        Calendar geceYarisi = Calendar.getInstance(tz);
        geceYarisi.set(yil, ay - 1, gun, 0, 0, 0);
        geceYarisi.set(Calendar.MILLISECOND, 0);
        long bazMs = geceYarisi.getTimeInMillis();
        double saatDilimi = tz.getOffset(bazMs) / 3_600_000.0;

        double jd = julianGunu(yil, ay, gun) - boylam / (15.0 * 24.0);
        double[] gunesBilgi = gunesDeklinasyonVeZamanDenklemi(jd + 0.5);
        double dek = gunesBilgi[0];
        double eot = gunesBilgi[1];

        double zevalSaat = 12.0 + saatDilimi - (boylam / 15.0) - eot;
        double ufukSaat = saatAcisi(enlem, dek, -0.8333);
        double fecirSaat = saatAcisi(enlem, dek, -m.fecirAci);
        double ikindiSaat = ikindiSaatAcisi(enlem, dek, asriSani ? 2.0 : 1.0);

        double imsakS = zevalSaat - fecirSaat;
        double gunesS = zevalSaat - ufukSaat;
        double ogleS = zevalSaat;
        double ikindiS = zevalSaat + ikindiSaat;
        double aksamS = zevalSaat + ufukSaat;
        double yatsiS;
        if (m.yatsiDakika > 0) {
            yatsiS = aksamS + m.yatsiDakika / 60.0;
        } else {
            yatsiS = zevalSaat + saatAcisi(enlem, dek, -m.yatsiAci);
        }

        long imsak = saatMs(bazMs, imsakS, m.temkinDk[0]);
        long gunes = saatMs(bazMs, gunesS, m.temkinDk[1]);
        long ogle = saatMs(bazMs, ogleS, m.temkinDk[2]);
        long ikindi = saatMs(bazMs, ikindiS, m.temkinDk[3]);
        long aksam = saatMs(bazMs, aksamS, m.temkinDk[4]);
        long yatsi = saatMs(bazMs, yatsiS, m.temkinDk[5]);
        return new GunVakitleri(imsak, gunes, ogle, ikindi, aksam, yatsi, true);
    }

    private static long saatMs(long bazMs, double saat, int temkinDk) {
        long dk = Math.round(saat * 60.0) + temkinDk;
        return bazMs + dk * 60_000L;
    }

    private static double julianGunu(int y, int m, int d) {
        if (m <= 2) {
            y -= 1;
            m += 12;
        }
        int a = y / 100;
        int b = 2 - a + (a / 4);
        return Math.floor(365.25 * (y + 4716)) + Math.floor(30.6001 * (m + 1)) + d + b - 1524.5;
    }

    /** {deklinasyonDerece, zamanDenklemiSaat} */
    private static double[] gunesDeklinasyonVeZamanDenklemi(double jd) {
        double d = jd - 2451545.0;
        double g = rad(norm360(357.529 + 0.98560028 * d));
        double q = norm360(280.459 + 0.98564736 * d);
        double l = rad(norm360(q + 1.915 * Math.sin(g) + 0.020 * Math.sin(2 * g)));
        double e = rad(23.439 - 0.00000036 * d);
        double ra = deg(Math.atan2(Math.cos(e) * Math.sin(l), Math.cos(l))) / 15.0;
        if (ra < 0) ra += 24.0;
        double dek = deg(Math.asin(Math.sin(e) * Math.sin(l)));
        double eot = q / 15.0 - ra;
        if (eot > 12.0) eot -= 24.0;
        if (eot < -12.0) eot += 24.0;
        return new double[]{dek, eot};
    }

    private static double saatAcisi(double enlem, double dek, double yukseklikDerece) {
        double latR = rad(enlem);
        double dekR = rad(dek);
        double cosH = (Math.sin(rad(yukseklikDerece)) - Math.sin(latR) * Math.sin(dekR))
                / (Math.cos(latR) * Math.cos(dekR));
        // Yüksek enlemlerde taşmayı sınırı koruyarak önle
        cosH = Math.max(-0.98, Math.min(0.98, cosH));
        return deg(Math.acos(cosH)) / 15.0;
    }

    private static double ikindiSaatAcisi(double enlem, double dek, double golgeKatsayisi) {
        double fark = Math.abs(enlem - dek);
        double yukseklik = deg(Math.atan(1.0 / (golgeKatsayisi + Math.tan(rad(fark)))));
        return saatAcisi(enlem, dek, yukseklik);
    }

    private static double norm360(double x) {
        x = x % 360.0;
        return x < 0 ? x + 360.0 : x;
    }

    private static double rad(double d) { return Math.toRadians(d); }
    private static double deg(double r) { return Math.toDegrees(r); }
}
