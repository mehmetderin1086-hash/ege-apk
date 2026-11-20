package com.mehmetderin.secde_vakti.saglik;

import android.content.Context;
import android.graphics.BlurMaskFilter;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RadialGradient;
import android.graphics.Shader;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.HapticFeedbackConstants;
import android.view.View;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Calendar;
import java.util.Collections;
import java.util.List;
import java.util.Locale;

/**
 * Hicrî–Milâdî çift yönlü tarih dönüştürücü, bugünün ay evresi & mânevî ay rehberi
 * ve önümüzdeki 365 gün için 12 Mübârek Gün / Kandil takvimi.
 */
public final class HicriTakvim {

    private static final String[] HICRI_AYLAR = {
            "Muharrem", "Safer", "Rebîülevvel", "Rebîülâhir",
            "Cemâziyelevvel", "Cemâziyelâhir", "Recep", "Şâban",
            "Ramazan", "Şevval", "Zilkâde", "Zilhicce"
    };

    private static final String[] MILADI_AYLAR = {
            "Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran",
            "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"
    };

    private static final String[] HAFTA_GUNLERI = {
            "Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi", "Pazar"
    };

    /** Kuveyt / İslâmî 30 yıllık çevrimde artık (355 günlük) yıllar. */
    private static final int[] ARTIK_YILLAR_30 = {2, 5, 7, 10, 13, 15, 18, 21, 24, 26, 29};
    private static final int HICRI_BASLANGIC_JDN = 1948440;

    /** 12 Mübârek Gün ve Kandil şablonu. */
    private static final class MubarekSablon {
        final int hicriAy;
        final int hicriGun; // 0 ise Recep'in ilk Cuma gecesi (Regâib)
        final boolean kandilGecesi;
        final String varsayilanAd;
        final String anlam;
        final String varsayilanAyet;
        final String varsayilanKaynak;
        final String ibadetOnerisi;

        MubarekSablon(int hicriAy, int hicriGun, boolean kandilGecesi, String varsayilanAd,
                      String anlam, String varsayilanAyet, String varsayilanKaynak, String ibadetOnerisi) {
            this.hicriAy = hicriAy;
            this.hicriGun = hicriGun;
            this.kandilGecesi = kandilGecesi;
            this.varsayilanAd = varsayilanAd;
            this.anlam = anlam;
            this.varsayilanAyet = varsayilanAyet;
            this.varsayilanKaynak = varsayilanKaynak;
            this.ibadetOnerisi = ibadetOnerisi;
        }
    }

    private static final MubarekSablon[] ON_IKI_GUN = {
            new MubarekSablon(1, 1, false, "Hicrî Yılbaşı",
                    "Hz. Peygamber'in (s.a.v.) Mekke'den Medîne'ye hicretiyle başlayan İslâm takviminin yeni yılı ve Haram Aylar'dan Muharrem'in ilk günüdür.",
                    "Şüphesiz Allah katında ayların sayısı, gökleri ve yeri yarattığı günden beri on ikidir.",
                    "Tevbe 9/36",
                    "Geçmiş yılın muhâsebesini yapmak, tevbe-istiğfâr etmek, Muharrem orucuna niyetlenmek ve hayır duâda bulunmak."),
            new MubarekSablon(1, 10, false, "Aşûre Günü",
                    "Peygamberler târihinde pek çok ilâhî kurtuluşun gerçekleştiği Muharrem ayının onuncu mübârek günüdür.",
                    "Sonunda 'Ey Nûh! Bizden bir esenlik ve bereketle in!' denildi.",
                    "Hûd 11/48",
                    "Muharrem'in 9–10 veya 10–11. günlerini birlikte oruçlu geçirmek, sıla-i rahim yapmak, ikrâm ve sadakayı çoğaltmak."),
            new MubarekSablon(3, 12, true, "Mevlid Kandili",
                    "Âlemlere rahmet olarak gönderilen Sevgili Peygamberimiz Hz. Muhammed Mustafa'nın (s.a.v.) dünyayı teşrif ettiği kutlu gecedir.",
                    "Biz seni ancak âlemlere rahmet olarak gönderdik.",
                    "Enbiyâ 21/107",
                    "Çokça Salavât-ı Şerîfe getirmek, Siyer-i Nebî okumak, sünnet-i seniyyeyi hayâtımıza tatbik etmeye niyet etmek."),
            new MubarekSablon(7, 1, false, "Üç Ayların Başlangıcı",
                    "Rahmet, mağfiret ve bereket mevsimi olan Recep, Şâban ve Ramazan-ı Şerîf ikliminin kapısının aralandığı gündür.",
                    "Ey Rabbimiz! Bize Recep ve Şâban'ı mübârek kıl ve bizi Ramazan'a ulaştır.",
                    "Ahmed b. Hanbel, Müsned, I/259",
                    "Nâfile oruçlara, Kur'ân-ı Kerîm hatmine ve günlük düzenli zikir/tesbihât programına başlamak."),
            new MubarekSablon(7, 0, true, "Regâib Kandili",
                    "Recep ayının ilk Cuma gecesi; ilâhî ihsân ve rağbetlerin bolca tecellî ettiği Üç Aylar'ın ilk kandil gecesidir.",
                    "Bana duâ edin, duânıza karşılık vereyim.",
                    "Mü'min 40/60",
                    "Perşembe gününü oruçlu geçirmek, kazâ ve nâfile namaz kılmak, anne-babaya duâ edip gönül almak."),
            new MubarekSablon(7, 27, true, "Mi'râc Kandili",
                    "Resûl-i Ekrem'in (s.a.v.) Mescid-i Harâm'dan Mescid-i Aksâ'ya ve ilâhî huzûra yükseldiği; beş vakit namazın müjdelendiği gecedir.",
                    "Kulunu bir gece Mescid-i Harâm'dan Mescid-i Aksâ'ya götüren Allah'ın şânı ne yücedir!",
                    "İsrâ 17/1",
                    "Beş vakit namaza ve kazâ namazlarına sarılmak, Bakara Sûresi'nin son iki âyetini (Âmene'r-Resûlü) okumak."),
            new MubarekSablon(8, 15, true, "Berât Kandili",
                    "Şâban ayının ortasında günahlardan arınma, af ve kulluk bilincini tazeleme gecesidir.",
                    "Biz onu mübârek bir gecede indirdik. Şüphesiz biz insanları uyarmaktayız.",
                    "Duhân 44/3",
                    "Samîmî tevbe ve istiğfârda bulunmak, kırgınlıkları giderip helâlleşmek, gündüzünü oruçla ihyâ etmek."),
            new MubarekSablon(9, 1, false, "Ramazan-ı Şerîf Başlangıcı",
                    "On bir ayın sultanı, Kur'ân-ı Kerîm'in indirildiği oruç, rahmet ve arınma ayının ilk günüdür (ilk Terâvih bir önceki akşam kılınır).",
                    "Ramazan ayı, insanlara yol gösterici olarak Kur'ân'ın indirildiği aydır.",
                    "Bakara 2/185",
                    "Oruca niyet etmek, mukâbele/Kur'ân tilâvetine başlamak, Terâvih namazına ve infâka özen göstermek."),
            new MubarekSablon(9, 27, true, "Kadir Gecesi",
                    "Kur'ân-ı Kerîm'in inmeye başladığı, meleklerin yeryüzüne selâm indirdiği bin aydan daha hayırlı müstesnâ gecedir.",
                    "Kadir gecesi bin aydan daha hayırlıdır.",
                    "Kadr 97/3",
                    "\"Allâhümme inneke afüvvün tuhibbü'l-afve fa'fü annî\" duâsını sıkça okumak, Kur'ân, tefekkür ve teheccüdle geceyi ihyâ etmek."),
            new MubarekSablon(10, 1, false, "Ramazan Bayramı",
                    "Bir aylık oruç ve sabır eğitiminin ardından mü'minlerin şükür ve kardeşlik sevincini paylaştığı 3 günlük bayramdır.",
                    "Size doğru yolu göstermesine karşılık Allah'ı yüceltmeniz ve şükretmeniz için.",
                    "Bakara 2/185",
                    "Fıtır sadakasını (fitre) bayram namazından önce ulaştırmak, bayram namazına gitmek, büyükleri ve akrabaları ziyâret etmek."),
            new MubarekSablon(12, 9, false, "Kurban Bayramı Arefesi",
                    "Hacıların Arafat'ta vakfeye durduğu, Teşrîk tekbirlerinin sabah namazıyla başladığı fazîleti çok yüksek gündür.",
                    "Bugün sizin için dininizi kemâle erdirdim, üzerinizdeki nimetimi tamamladım.",
                    "Mâide 5/3",
                    "Hacda olmayanlar için geçmiş ve gelecek birer yılın günahlarına keffâret ümidiyle Arefe orucu tutmak, 1000 İhlâs-ı Şerîf ve zikir okumak."),
            new MubarekSablon(12, 10, false, "Kurban Bayramı",
                    "Hz. İbrâhîm ve Hz. İsmâil'in teslîmiyetini yaşatan, kurban ibâdeti ve paylaşma ile idrâk edilen 4 günlük bayramdır.",
                    "Öyleyse Rabbin için namaz kıl ve kurban kes.",
                    "Kevser 108/2",
                    "Bayram namazını kılmak, 23 vakit Teşrîk tekbirlerini unutmamak, kurban etini ihtiyaç sahipleri ve komşularla paylaşmak.")
    };

    /** Hesaplanmış yaklaşan mübârek gün kaydı. */
    private static final class YaklasanGun implements Comparable<YaklasanGun> {
        final String ad;
        final boolean kandilGecesi;
        final int[] miladi; // {yil, ay, gun}
        final int[] hicri;  // {hYil, hAy, hGun}
        final int kalanGun;
        final String anlam;
        final String ayet;
        final String kaynak;
        final String ibadet;

        YaklasanGun(String ad, boolean kandilGecesi, int[] miladi, int[] hicri, int kalanGun,
                    String anlam, String ayet, String kaynak, String ibadet) {
            this.ad = ad;
            this.kandilGecesi = kandilGecesi;
            this.miladi = miladi;
            this.hicri = hicri;
            this.kalanGun = kalanGun;
            this.anlam = anlam;
            this.ayet = ayet;
            this.kaynak = kaynak;
            this.ibadet = ibadet;
        }

        @Override
        public int compareTo(YaklasanGun o) {
            return Integer.compare(this.kalanGun, o.kalanGun);
        }
    }

    private HicriTakvim() {}

    // ================================================================ GENEL API (DÖNÜŞTÜRME)

    /** Milâdî {yil, ay(1..12), gun(1..31)} tarihini Hicrî {hicriYil, hicriAy(1..12), hicriGun(1..30)} dizisine çevirir. */
    public static int[] miladidenHicriye(int yil, int ay, int gun) {
        int mAy = Math.max(1, Math.min(12, ay));
        int mGun = Math.max(1, Math.min(miladiAyUzunlugu(yil, mAy), gun));
        try {
            if (Build.VERSION.SDK_INT >= 26) {
                int[] sonuc = Api26Hicri.miladidenHicriye(yil, mAy, mGun);
                if (sonuc != null && sonuc[0] > 0) return sonuc;
            }
        } catch (Throwable ignored) {
        }
        return kuveytMiladidenHicriye(yil, mAy, mGun);
    }

    /** Hicrî {hYil, hAy(1..12), hGun(1..30)} tarihini güvenli gün kırpmasıyla Milâdî {yil, ay, gun} dizisine çevirir. */
    public static int[] hicridenMiladiye(int hYil, int hAy, int hGun) {
        int temizAy = Math.max(1, Math.min(12, hAy));
        int temizGun = Math.max(1, Math.min(30, hGun));
        try {
            if (Build.VERSION.SDK_INT >= 26) {
                int[] sonuc = Api26Hicri.hicridenMiladiye(hYil, temizAy, temizGun);
                if (sonuc != null) return sonuc;
            }
        } catch (Throwable ignored) {
        }
        return kuveytHicridenMiladiye(hYil, temizAy, temizGun);
    }

    /** 1..12 Hicrî ay numarasının Türkçe adını döndürür. */
    public static String hicriAyAdi(int ay) {
        if (ay < 1 || ay > 12) return "";
        return HICRI_AYLAR[ay - 1];
    }

    /** API 26+ java.time.chrono.HijrahDate sarmalayıcısı (API 24 doğrulayıcısı için ayrı iç sınıf). */
    private static final class Api26Hicri {
        static int[] miladidenHicriye(int yil, int ay, int gun) {
            java.time.LocalDate ld = java.time.LocalDate.of(yil, ay, gun);
            java.time.chrono.HijrahDate hd = java.time.chrono.HijrahDate.from(ld);
            return new int[]{
                    hd.get(java.time.temporal.ChronoField.YEAR),
                    hd.get(java.time.temporal.ChronoField.MONTH_OF_YEAR),
                    hd.get(java.time.temporal.ChronoField.DAY_OF_MONTH)
            };
        }

        static int[] hicridenMiladiye(int hYil, int hAy, int hGun) {
            java.time.chrono.HijrahDate ayBasi = java.time.chrono.HijrahChronology.INSTANCE.date(hYil, hAy, 1);
            int maksGun = ayBasi.lengthOfMonth();
            java.time.chrono.HijrahDate hd = java.time.chrono.HijrahChronology.INSTANCE.date(hYil, hAy, Math.min(hGun, maksGun));
            java.time.LocalDate ld = java.time.LocalDate.from(hd);
            return new int[]{ld.getYear(), ld.getMonthValue(), ld.getDayOfMonth()};
        }
    }

    // ================================================================ KUVEYT ASTRONOMİK / ÇEVRİMSEL YEDEK HESAP

    static int miladiJdn(int yil, int ay, int gun) {
        int a = (14 - ay) / 12;
        int y = yil + 4800 - a;
        int m = ay + 12 * a - 3;
        return gun + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045;
    }

    static int[] jdnMiladi(int jdn) {
        int f = jdn + 1401 + (((4 * jdn + 274277) / 146097) * 3) / 4 - 38;
        int e = 4 * f + 3;
        int g = (e % 1461) / 4;
        int h = 5 * g + 2;
        int gun = (h % 153) / 5 + 1;
        int ay = ((h / 153 + 2) % 12) + 1;
        int yil = (e / 1461) - 4716 + (14 - ay) / 12;
        return new int[]{yil, ay, gun};
    }

    private static boolean hicriArtikYil(int hYil) {
        int mod = ((hYil % 30) + 30) % 30;
        if (mod == 0) mod = 30;
        for (int a : ARTIK_YILLAR_30) {
            if (a == mod) return true;
        }
        return false;
    }

    private static int kuveytAyUzunlugu(int hYil, int hAy) {
        if (hAy == 12) return hicriArtikYil(hYil) ? 30 : 29;
        return (hAy % 2 == 1) ? 30 : 29;
    }

    static int hicriAyUzunlugu(int hYil, int hAy) {
        int m = Math.max(1, Math.min(12, hAy));
        try {
            if (Build.VERSION.SDK_INT >= 26) {
                return java.time.chrono.HijrahChronology.INSTANCE.date(hYil, m, 1).lengthOfMonth();
            }
        } catch (Throwable ignored) {
        }
        return kuveytAyUzunlugu(hYil, m);
    }

    static int[] kuveytMiladidenHicriye(int yil, int ay, int gun) {
        int jdn = miladiJdn(yil, ay, gun);
        int gunSayisi = jdn - HICRI_BASLANGIC_JDN;
        int dongu = Math.floorDiv(gunSayisi, 10631);
        int kalan = gunSayisi - dongu * 10631;
        int hYil = dongu * 30 + 1;
        while (true) {
            int yilGun = hicriArtikYil(hYil) ? 355 : 354;
            if (kalan < yilGun) break;
            kalan -= yilGun;
            hYil++;
        }
        int hAy = 1;
        while (hAy < 12) {
            int ayGun = kuveytAyUzunlugu(hYil, hAy);
            if (kalan < ayGun) break;
            kalan -= ayGun;
            hAy++;
        }
        int hGun = kalan + 1;
        return new int[]{hYil, hAy, Math.max(1, Math.min(30, hGun))};
    }

    static int[] kuveytHicridenMiladiye(int hYil, int hAy, int hGun) {
        int m = Math.max(1, Math.min(12, hAy));
        int maksGun = kuveytAyUzunlugu(hYil, m);
        int g = Math.max(1, Math.min(maksGun, hGun));

        int gecenYil = hYil - 1;
        int dongu = Math.floorDiv(gecenYil, 30);
        int yilIci = gecenYil - dongu * 30;
        int toplamGun = dongu * 10631;
        for (int y = 1; y <= yilIci; y++) {
            toplamGun += hicriArtikYil(dongu * 30 + y) ? 355 : 354;
        }
        for (int ay = 1; ay < m; ay++) {
            toplamGun += kuveytAyUzunlugu(hYil, ay);
        }
        toplamGun += (g - 1);
        return jdnMiladi(HICRI_BASLANGIC_JDN + toplamGun);
    }

    static int miladiAyUzunlugu(int yil, int ay) {
        switch (ay) {
            case 2:
                boolean artik = (yil % 4 == 0 && yil % 100 != 0) || (yil % 400 == 0);
                return artik ? 29 : 28;
            case 4:
            case 6:
            case 9:
            case 11:
                return 30;
            default:
                return 31;
        }
    }

    private static String haftaGunuAdi(int yil, int ay, int gun) {
        int jdn = miladiJdn(yil, ay, gun);
        int idx = ((jdn % 7) + 7) % 7; // JDN % 7 == 0 -> Pazartesi
        return HAFTA_GUNLERI[idx];
    }

    // ================================================================ ALT SAYFA ARAYÜZÜ

    /** Hicrî Takvim, Ay Evresi, Tarih Dönüştürücü ve 12 Mübârek Gün rehberi sayfasını açar. */
    public static void sayfaAc(final DurumAktivitesi a, VakitTakvimi.Takvim takvimGirdi) {
        if (a == null) return;
        a.guvenli("hicriTakvim", () -> {
            final TemaMotoru.Durum tema = TemaMotoru.aktif(a);
            final LinearLayout dis = a.sutun();

            Calendar simdi = Calendar.getInstance();
            final int bYil = simdi.get(Calendar.YEAR);
            final int bAy = simdi.get(Calendar.MONTH) + 1;
            final int bGun = simdi.get(Calendar.DAY_OF_MONTH);
            final int bugunJdn = miladiJdn(bYil, bAy, bGun);
            final int[] bugunHicri = miladidenHicriye(bYil, bAy, bGun);

            // 1. Bugünün Hicrî Durumu ve Ay Evresi Kartı
            dis.addView(bugunAyEvresiKarti(a, tema, bugunHicri, bYil, bAy, bGun));

            // 2. Çift Yönlü Tarih Dönüştürücü Kartı
            dis.addView(bolumBasligi(a, tema, "ÇİFT YÖNLÜ TARİH DÖNÜŞTÜRÜCÜ"));
            dis.addView(donusturucuKarti(a, tema, bYil, bAy, bGun, bugunHicri, bugunJdn));

            // 3. 12 Mübârek Gün ve Kandil Takvimi
            dis.addView(bolumBasligi(a, tema, "12 MÜBÂREK GÜN VE KANDİL TAKVİMİ (365 GÜN)"));

            LinearLayout notKart = kart(a, tema);
            GradientDrawable ng = new GradientDrawable();
            ng.setCornerRadius(a.dp(16));
            ng.setColor(tema.acik ? 0x169C6514 : 0x2EF0B35A);
            ng.setStroke(Math.max(1, a.dp(1)), (tema.vurgu & 0x00FFFFFF) | 0x66000000);
            notKart.setBackground(ng);
            notKart.addView(yazi(a, tema,
                    "✦ Kandil geceleri bir önceki günün akşam ezanıyla başlar.",
                    13, tema.vurgu, true));
            notKart.addView(yazi(a, tema,
                    "İslâmî takvimde yeni gün akşam ezanı (gurûb-i şems) ile girdiğinden mübârek geceler gündüzünden bir önceki akşam ihyâ edilir.",
                    12, tema.soluk, false));
            dis.addView(notKart);

            List<YaklasanGun> mubarekler = yaklasanOnIkiGun(a, bYil, bAy, bGun, bugunHicri[0]);
            for (YaklasanGun g : mubarekler) {
                dis.addView(mubarekGunKarti(a, tema, g));
            }

            ScrollView sv = a.sayfa(dis);
            sv.setPadding(0, 0, 0, 0);
            a.altSayfa("Hicrî Takvim ve Dini Günler", sv, "kandil");
        });
    }

    private static View bugunAyEvresiKarti(DurumAktivitesi a, TemaMotoru.Durum tema,
                                           int[] h, int mYil, int mAy, int mGun) {
        LinearLayout k = kart(a, tema);
        k.addView(yazi(a, tema, "BUGÜNÜN HİCRÎ DURUMU VE AY EVRESİ", 11, tema.vurgu, true));

        LinearLayout orta = new LinearLayout(a);
        orta.setOrientation(LinearLayout.HORIZONTAL);
        orta.setGravity(Gravity.CENTER_VERTICAL);

        AyEvresiView ayGorunum = new AyEvresiView(a, h[2]);
        int boy = a.dp(88);
        FrameLayout ayKabi = new FrameLayout(a);
        ayKabi.addView(ayGorunum, new FrameLayout.LayoutParams(boy, boy, Gravity.CENTER));
        orta.addView(ayKabi, new LinearLayout.LayoutParams(boy, boy));

        LinearLayout sag = new LinearLayout(a);
        sag.setOrientation(LinearLayout.VERTICAL);
        sag.setPadding(a.dp(14), 0, 0, 0);

        String hicriTam = h[2] + " " + hicriAyAdi(h[1]) + " " + h[0];
        sag.addView(yazi(a, tema, hicriTam, 22, tema.metin, true));
        String miladiTam = mGun + " " + MILADI_AYLAR[mAy - 1] + " " + mYil + " · " + haftaGunuAdi(mYil, mAy, mGun);
        sag.addView(yazi(a, tema, miladiTam, 13, tema.soluk, false));
        sag.addView(yazi(a, tema, "☾ " + ayEvresiAdi(h[2]), 14, tema.vurgu, true));

        orta.addView(sag, new LinearLayout.LayoutParams(0, -2, 1f));
        k.addView(orta);
        a.bosluk(k, 10);

        // Ay döngüsü ilerleme çubuğu (1..30)
        int ayUzunluk = hicriAyUzunlugu(h[0], h[1]);
        LinearLayout cubukUst = new LinearLayout(a);
        cubukUst.setOrientation(LinearLayout.HORIZONTAL);
        cubukUst.addView(yazi(a, tema, "1 " + hicriAyAdi(h[1]), 11, tema.silik, false), new LinearLayout.LayoutParams(0, -2, 1f));
        TextView ortaEtiket = yazi(a, tema, "Eyyâm-ı Bîz (13·14·15)", 11,
                (h[2] >= 13 && h[2] <= 15) ? tema.iyi : tema.silik, h[2] >= 13 && h[2] <= 15);
        cubukUst.addView(ortaEtiket);
        TextView sonEtiket = yazi(a, tema, ayUzunluk + " gün", 11, tema.silik, false);
        sonEtiket.setGravity(Gravity.RIGHT);
        cubukUst.addView(sonEtiket, new LinearLayout.LayoutParams(0, -2, 1f));
        k.addView(cubukUst);

        FrameLayout cubukDis = new FrameLayout(a);
        GradientDrawable cd = new GradientDrawable();
        cd.setCornerRadius(a.dp(5));
        cd.setColor(tema.acik ? 0x2214211C : 0x33FFFFFF);
        cubukDis.setBackground(cd);
        final View cubukIc = new View(a);
        GradientDrawable ci = new GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT,
                new int[]{tema.vurguKoyu, tema.vurgu});
        ci.setCornerRadius(a.dp(5));
        cubukIc.setBackground(ci);
        cubukDis.addView(cubukIc, new FrameLayout.LayoutParams(0, a.dp(8)));
        final float oran = Math.max(0.04f, Math.min(1f, h[2] / (float) ayUzunluk));
        cubukDis.post(() -> {
            int gen = cubukDis.getWidth();
            if (gen <= 0) return;
            FrameLayout.LayoutParams lp = (FrameLayout.LayoutParams) cubukIc.getLayoutParams();
            lp.width = Math.round(gen * oran);
            cubukIc.setLayoutParams(lp);
        });
        k.addView(cubukDis, new LinearLayout.LayoutParams(-1, a.dp(8)));
        a.bosluk(k, 8);

        // Hicrî ay mânevî notu
        k.addView(yazi(a, tema, hicriAyManeviNotu(h[1], h[2]), 13, tema.soluk, false));
        return k;
    }

    private static View donusturucuKarti(final DurumAktivitesi a,
                                         final TemaMotoru.Durum tema,
                                         final int bugunYil, final int bugunAy, final int bugunGun,
                                         final int[] bugunHicri,
                                         final int bugunJdn) {
        final LinearLayout k = kart(a, tema);

        // Mod geçiş çipleri: [ Milâdî → Hicrî | Hicrî → Milâdî ]
        final LinearLayout modSatir = new LinearLayout(a);
        modSatir.setOrientation(LinearLayout.HORIZONTAL);
        k.addView(modSatir);
        a.bosluk(k, 10);

        final boolean[] miladidenHicriyeMod = {true};
        final int[] secMiladi = {bugunYil, bugunAy, bugunGun};
        final int[] secHicri = {bugunHicri[0], bugunHicri[1], bugunHicri[2]};

        final LinearLayout sayacAlan = new LinearLayout(a);
        sayacAlan.setOrientation(LinearLayout.VERTICAL);
        k.addView(sayacAlan);
        a.bosluk(k, 10);

        // Sonuç kutusu
        final LinearLayout sonucKutu = new LinearLayout(a);
        sonucKutu.setOrientation(LinearLayout.VERTICAL);
        sonucKutu.setGravity(Gravity.CENTER_HORIZONTAL);
        sonucKutu.setPadding(a.dp(14), a.dp(12), a.dp(14), a.dp(12));
        GradientDrawable sg = new GradientDrawable();
        sg.setCornerRadius(a.dp(16));
        sg.setColor(tema.acik ? 0x121E6B55 : 0x29000000);
        sg.setStroke(Math.max(1, a.dp(1)), (tema.vurgu & 0x00FFFFFF) | 0x55000000);
        sonucKutu.setBackground(sg);

        final TextView sonucUst = yazi(a, tema, "", 11, tema.vurgu, true);
        sonucUst.setGravity(Gravity.CENTER);
        final TextView sonucAna = yazi(a, tema, "", 22, tema.metin, true);
        sonucAna.setGravity(Gravity.CENTER);
        final TextView sonucHafta = yazi(a, tema, "", 14, tema.soluk, true);
        sonucHafta.setGravity(Gravity.CENTER);
        final TextView sonucFark = yazi(a, tema, "", 13, tema.iyi, false);
        sonucFark.setGravity(Gravity.CENTER);
        sonucKutu.addView(sonucUst);
        sonucKutu.addView(sonucAna);
        sonucKutu.addView(sonucHafta);
        sonucKutu.addView(sonucFark);
        k.addView(sonucKutu);

        final Runnable[] yenile = new Runnable[1];

        TextView buguneDon = dugme(a, tema, "Bugüne Dön", false, v -> {
            secMiladi[0] = bugunYil;
            secMiladi[1] = bugunAy;
            secMiladi[2] = bugunGun;
            secHicri[0] = bugunHicri[0];
            secHicri[1] = bugunHicri[1];
            secHicri[2] = bugunHicri[2];
            yenile[0].run();
        });
        k.addView(buguneDon);

        yenile[0] = () -> {
            modSatir.removeAllViews();
            TextView m1 = cipOlustur(a, tema, "Milâdî → Hicrî", miladidenHicriyeMod[0], v -> {
                if (!miladidenHicriyeMod[0]) {
                    int[] m = hicridenMiladiye(secHicri[0], secHicri[1], secHicri[2]);
                    secMiladi[0] = m[0];
                    secMiladi[1] = m[1];
                    secMiladi[2] = m[2];
                    miladidenHicriyeMod[0] = true;
                    yenile[0].run();
                }
            });
            TextView m2 = cipOlustur(a, tema, "Hicrî → Milâdî", !miladidenHicriyeMod[0], v -> {
                if (miladidenHicriyeMod[0]) {
                    int[] h = miladidenHicriye(secMiladi[0], secMiladi[1], secMiladi[2]);
                    secHicri[0] = h[0];
                    secHicri[1] = h[1];
                    secHicri[2] = h[2];
                    miladidenHicriyeMod[0] = false;
                    yenile[0].run();
                }
            });
            m1.setGravity(Gravity.CENTER);
            m2.setGravity(Gravity.CENTER);
            LinearLayout.LayoutParams lp1 = new LinearLayout.LayoutParams(0, -2, 1f);
            lp1.setMargins(0, 0, a.dp(6), 0);
            LinearLayout.LayoutParams lp2 = new LinearLayout.LayoutParams(0, -2, 1f);
            modSatir.addView(m1, lp1);
            modSatir.addView(m2, lp2);

            sayacAlan.removeAllViews();
            int hedefJdn;
            if (miladidenHicriyeMod[0]) {
                int maksG = miladiAyUzunlugu(secMiladi[0], secMiladi[1]);
                if (secMiladi[2] > maksG) secMiladi[2] = maksG;

                sayacAlan.addView(adimSatiriOlustur(a, tema, "Gün", String.valueOf(secMiladi[2]),
                        () -> {
                            int ust = miladiAyUzunlugu(secMiladi[0], secMiladi[1]);
                            secMiladi[2] = secMiladi[2] <= 1 ? ust : secMiladi[2] - 1;
                            yenile[0].run();
                        },
                        () -> {
                            int ust = miladiAyUzunlugu(secMiladi[0], secMiladi[1]);
                            secMiladi[2] = secMiladi[2] >= ust ? 1 : secMiladi[2] + 1;
                            yenile[0].run();
                        }));
                sayacAlan.addView(adimSatiriOlustur(a, tema, "Ay", secMiladi[1] + " · " + MILADI_AYLAR[secMiladi[1] - 1],
                        () -> {
                            secMiladi[1] = secMiladi[1] <= 1 ? 12 : secMiladi[1] - 1;
                            secMiladi[2] = Math.min(secMiladi[2], miladiAyUzunlugu(secMiladi[0], secMiladi[1]));
                            yenile[0].run();
                        },
                        () -> {
                            secMiladi[1] = secMiladi[1] >= 12 ? 1 : secMiladi[1] + 1;
                            secMiladi[2] = Math.min(secMiladi[2], miladiAyUzunlugu(secMiladi[0], secMiladi[1]));
                            yenile[0].run();
                        }));
                sayacAlan.addView(adimSatiriOlustur(a, tema, "Yıl", String.valueOf(secMiladi[0]),
                        () -> {
                            secMiladi[0] = Math.max(1900, secMiladi[0] - 1);
                            secMiladi[2] = Math.min(secMiladi[2], miladiAyUzunlugu(secMiladi[0], secMiladi[1]));
                            yenile[0].run();
                        },
                        () -> {
                            secMiladi[0] = Math.min(2120, secMiladi[0] + 1);
                            secMiladi[2] = Math.min(secMiladi[2], miladiAyUzunlugu(secMiladi[0], secMiladi[1]));
                            yenile[0].run();
                        }));

                int[] cevrilen = miladidenHicriye(secMiladi[0], secMiladi[1], secMiladi[2]);
                hedefJdn = miladiJdn(secMiladi[0], secMiladi[1], secMiladi[2]);
                sonucUst.setText("HİCRÎ KARŞILIĞI");
                sonucAna.setText(cevrilen[2] + " " + hicriAyAdi(cevrilen[1]) + " " + cevrilen[0]);
                sonucHafta.setText(haftaGunuAdi(secMiladi[0], secMiladi[1], secMiladi[2]) + " · " + ayEvresiAdi(cevrilen[2]));
            } else {
                int maksH = hicriAyUzunlugu(secHicri[0], secHicri[1]);
                if (secHicri[2] > maksH) secHicri[2] = maksH;

                sayacAlan.addView(adimSatiriOlustur(a, tema, "Hicrî Gün", String.valueOf(secHicri[2]),
                        () -> {
                            int ust = hicriAyUzunlugu(secHicri[0], secHicri[1]);
                            secHicri[2] = secHicri[2] <= 1 ? ust : secHicri[2] - 1;
                            yenile[0].run();
                        },
                        () -> {
                            int ust = hicriAyUzunlugu(secHicri[0], secHicri[1]);
                            secHicri[2] = secHicri[2] >= ust ? 1 : secHicri[2] + 1;
                            yenile[0].run();
                        }));
                sayacAlan.addView(adimSatiriOlustur(a, tema, "Hicrî Ay", secHicri[1] + " · " + hicriAyAdi(secHicri[1]),
                        () -> {
                            secHicri[1] = secHicri[1] <= 1 ? 12 : secHicri[1] - 1;
                            secHicri[2] = Math.min(secHicri[2], hicriAyUzunlugu(secHicri[0], secHicri[1]));
                            yenile[0].run();
                        },
                        () -> {
                            secHicri[1] = secHicri[1] >= 12 ? 1 : secHicri[1] + 1;
                            secHicri[2] = Math.min(secHicri[2], hicriAyUzunlugu(secHicri[0], secHicri[1]));
                            yenile[0].run();
                        }));
                sayacAlan.addView(adimSatiriOlustur(a, tema, "Hicrî Yıl", String.valueOf(secHicri[0]),
                        () -> {
                            secHicri[0] = Math.max(1320, secHicri[0] - 1);
                            secHicri[2] = Math.min(secHicri[2], hicriAyUzunlugu(secHicri[0], secHicri[1]));
                            yenile[0].run();
                        },
                        () -> {
                            secHicri[0] = Math.min(1550, secHicri[0] + 1);
                            secHicri[2] = Math.min(secHicri[2], hicriAyUzunlugu(secHicri[0], secHicri[1]));
                            yenile[0].run();
                        }));

                int[] cevrilen = hicridenMiladiye(secHicri[0], secHicri[1], secHicri[2]);
                hedefJdn = miladiJdn(cevrilen[0], cevrilen[1], cevrilen[2]);
                sonucUst.setText("MİLÂDÎ KARŞILIĞI");
                sonucAna.setText(cevrilen[2] + " " + MILADI_AYLAR[cevrilen[1] - 1] + " " + cevrilen[0]);
                sonucHafta.setText(haftaGunuAdi(cevrilen[0], cevrilen[1], cevrilen[2]));
            }

            int fark = hedefJdn - bugunJdn;
            if (fark == 0) {
                sonucFark.setText("Bugün");
                sonucFark.setTextColor(tema.iyi);
            } else if (fark > 0) {
                sonucFark.setText("Bugünden " + fark + " gün sonra");
                sonucFark.setTextColor(tema.vurgu);
            } else {
                sonucFark.setText("Bugünden " + Math.abs(fark) + " gün önce");
                sonucFark.setTextColor(tema.soluk);
            }
        };

        yenile[0].run();
        return k;
    }

    private static View adimSatiriOlustur(DurumAktivitesi a, TemaMotoru.Durum tema,
                                          String etiket, String deger, Runnable azalt, Runnable artir) {
        LinearLayout satir = new LinearLayout(a);
        satir.setOrientation(LinearLayout.HORIZONTAL);
        satir.setGravity(Gravity.CENTER_VERTICAL);
        satir.setPadding(0, a.dp(4), 0, a.dp(4));

        satir.addView(yazi(a, tema, etiket, 14, tema.soluk, true), new LinearLayout.LayoutParams(a.dp(82), -2));

        TextView eksi = adimDugme(a, tema, "−", azalt);
        satir.addView(eksi);

        TextView orta = yazi(a, tema, deger, 16, tema.metin, true);
        orta.setGravity(Gravity.CENTER);
        satir.addView(orta, new LinearLayout.LayoutParams(0, -2, 1f));

        TextView arti = adimDugme(a, tema, "+", artir);
        satir.addView(arti);
        return satir;
    }

    private static TextView adimDugme(DurumAktivitesi a, TemaMotoru.Durum tema, String isaret, Runnable eylem) {
        TextView b = yazi(a, tema, isaret, 19, tema.metin, true);
        b.setShadowLayer(0, 0, 0, 0);
        b.setGravity(Gravity.CENTER);
        b.setBackground(tema.ikincilDugme(a, 12));
        b.setClickable(true);
        a.basmaEfekti(b);
        b.setOnClickListener(v -> {
            v.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK);
            eylem.run();
        });
        return new LinearLayout.LayoutParams(a.dp(42), a.dp(38)) != null ? ayarlaBoyut(b, a.dp(42), a.dp(38)) : b;
    }

    private static TextView ayarlaBoyut(TextView b, int g, int y) {
        b.setLayoutParams(new LinearLayout.LayoutParams(g, y));
        return b;
    }

    // ================================================================ 12 MÜBÂREK GÜN VE KANDİL HESABI

    private static List<YaklasanGun> yaklasanOnIkiGun(Context c, int bYil, int bAy, int bGun, int baslangicHicriYil) {
        JSONArray jsonListe = null;
        try {
            String ham = Varlik.flutterMetin(c, "assets/data/HolyDays.json");
            if (ham != null && !ham.isEmpty()) jsonListe = new JSONArray(ham);
        } catch (Throwable ignored) {
        }

        int bugunJdn = miladiJdn(bYil, bAy, bGun);
        List<YaklasanGun> sonuc = new ArrayList<>();

        for (MubarekSablon s : ON_IKI_GUN) {
            String ad = s.varsayilanAd;
            String ayet = s.varsayilanAyet;
            String kaynak = s.varsayilanKaynak;

            // HolyDays.json içinden eşleşen ay/gün varsa metinlerini birleştir
            if (jsonListe != null) {
                for (int i = 0; i < jsonListe.length(); i++) {
                    JSONObject o = jsonListe.optJSONObject(i);
                    if (o == null) continue;
                    if (o.optInt("hijriMonth", -1) == s.hicriAy && o.optInt("hijriDay", -1) == s.hicriGun) {
                        String jAd = o.optString("name", "").trim();
                        String jAyet = o.optString("verse", "").trim();
                        String jKaynak = o.optString("verseSource", "").trim();
                        if (!jAd.isEmpty() && !"Hicri Yılbaşı".equals(jAd)) ad = jAd;
                        if (!jAyet.isEmpty()) ayet = jAyet;
                        if (!jKaynak.isEmpty()) kaynak = jKaynak;
                        break;
                    }
                }
            }

            // Bu veya gelecek Hicrî yıllarda bugünden itibaren ilk gerçekleşen tarihi bul
            for (int hy = baslangicHicriYil - 1; hy <= baslangicHicriYil + 2; hy++) {
                int hedefJdn;
                int gosterilenHicriGun;
                if (s.hicriGun == 0) {
                    // Regâib Kandili: Recep ayının ilk Cuma gecesi (ilk Cuma'dan bir önceki Perşembe günü)
                    int[] recepBasi = hicridenMiladiye(hy, 7, 1);
                    int recepBasiJdn = miladiJdn(recepBasi[0], recepBasi[1], recepBasi[2]);
                    // JDN % 7 == 4 -> Cuma (0:Pzt, 1:Sal, 2:Çar, 3:Per, 4:Cum, 5:Cmt, 6:Paz)
                    int gunHafta = ((recepBasiJdn % 7) + 7) % 7;
                    int ilkCumayaFark = (4 - gunHafta + 7) % 7;
                    int ilkCumaJdn = recepBasiJdn + ilkCumayaFark;
                    hedefJdn = ilkCumaJdn - 1; // Perşembe gündüzü (akşamı Cuma gecesidir)
                    int[] regaibMiladi = jdnMiladi(hedefJdn);
                    int[] regaibHicri = miladidenHicriye(regaibMiladi[0], regaibMiladi[1], regaibMiladi[2]);
                    gosterilenHicriGun = regaibHicri[2];
                } else {
                    int[] m = hicridenMiladiye(hy, s.hicriAy, s.hicriGun);
                    int asilJdn = miladiJdn(m[0], m[1], m[2]);
                    hedefJdn = s.kandilGecesi ? (asilJdn - 1) : asilJdn;
                    gosterilenHicriGun = s.hicriGun;
                }

                int kalan = hedefJdn - bugunJdn;
                if (kalan >= 0 && kalan <= 370) {
                    int[] hedefMiladi = jdnMiladi(hedefJdn);
                    int[] hedefHicri = s.hicriGun == 0
                            ? miladidenHicriye(hedefMiladi[0], hedefMiladi[1], hedefMiladi[2])
                            : new int[]{hy, s.hicriAy, gosterilenHicriGun};
                    sonuc.add(new YaklasanGun(ad, s.kandilGecesi, hedefMiladi, hedefHicri, kalan,
                            s.anlam, ayet, kaynak, s.ibadetOnerisi));
                    break;
                }
            }
        }

        Collections.sort(sonuc);
        return sonuc;
    }

    private static View mubarekGunKarti(DurumAktivitesi a, TemaMotoru.Durum tema, YaklasanGun g) {
        LinearLayout k = kart(a, tema);

        LinearLayout ust = new LinearLayout(a);
        ust.setOrientation(LinearLayout.HORIZONTAL);
        ust.setGravity(Gravity.CENTER_VERTICAL);

        LinearLayout sol = new LinearLayout(a);
        sol.setOrientation(LinearLayout.VERTICAL);
        sol.addView(yazi(a, tema, g.ad, 17, tema.metin, true));

        String mTarih = g.miladi[2] + " " + MILADI_AYLAR[g.miladi[1] - 1] + " " + g.miladi[0]
                + " " + haftaGunuAdi(g.miladi[0], g.miladi[1], g.miladi[2]);
        String hTarih = g.hicri[2] + " " + hicriAyAdi(g.hicri[1]) + " " + g.hicri[0]
                + (g.kandilGecesi ? " gecesi" : "");
        sol.addView(yazi(a, tema, mTarih + "  ·  " + hTarih, 13, tema.vurgu, true));
        ust.addView(sol, new LinearLayout.LayoutParams(0, -2, 1f));

        String rozetMetni = g.kalanGun == 0
                ? (g.kandilGecesi ? "Bu Akşam!" : "Bugün!")
                : (g.kalanGun == 1 ? "Yarın" : g.kalanGun + " gün kaldı");
        boolean bugunMu = g.kalanGun <= 1;
        TextView rozet = yazi(a, tema, rozetMetni, 12,
                bugunMu ? tema.birincilDugmeYaziRengi() : tema.vurgu, true);
        rozet.setShadowLayer(0, 0, 0, 0);
        rozet.setPadding(a.dp(10), a.dp(6), a.dp(10), a.dp(6));
        rozet.setBackground(bugunMu ? tema.birincilDugme(a, 14) : tema.ikincilDugme(a, 14));
        ust.addView(rozet);

        k.addView(ust);
        a.bosluk(k, 6);

        k.addView(yazi(a, tema, g.anlam, 13, tema.soluk, false));

        if (g.ayet != null && !g.ayet.isEmpty()) {
            LinearLayout ayetKutu = new LinearLayout(a);
            ayetKutu.setOrientation(LinearLayout.VERTICAL);
            ayetKutu.setPadding(a.dp(10), a.dp(8), a.dp(10), a.dp(8));
            GradientDrawable ag = new GradientDrawable();
            ag.setCornerRadius(a.dp(12));
            ag.setColor(tema.acik ? 0x101E6B55 : 0x20000000);
            ayetKutu.setBackground(ag);
            LinearLayout.LayoutParams alp = new LinearLayout.LayoutParams(-1, -2);
            alp.setMargins(0, a.dp(6), 0, a.dp(6));
            ayetKutu.setLayoutParams(alp);
            ayetKutu.addView(yazi(a, tema, "“" + g.ayet + "”", 13, tema.metin, false));
            ayetKutu.addView(yazi(a, tema, "— " + g.kaynak, 11, tema.vurgu, true));
            k.addView(ayetKutu);
        }

        k.addView(yazi(a, tema, "İbâdet Önerisi: " + g.ibadet, 12, tema.iyi, false));
        return k;
    }

    // ================================================================ AY EVRESİ METİNLERİ VE GÖRÜNÜMÜ

    private static String ayEvresiAdi(int hicriGun) {
        if (hicriGun <= 3) return "Yeni Hilâl";
        if (hicriGun <= 6) return "Büyüyen Hilâl";
        if (hicriGun <= 10) return "İlk Dördün";
        if (hicriGun <= 12) return "Büyüyen Ay";
        if (hicriGun <= 15) return "Dolunay · Eyyâm-ı Bîz";
        if (hicriGun <= 19) return "Küçülen Ay";
        if (hicriGun <= 24) return "Son Dördün";
        return "Son Hilâl";
    }

    private static String hicriAyManeviNotu(int ay, int gun) {
        String eyyamNotu = (gun >= 13 && gun <= 15)
                ? "✦ Bugün Eyyâm-ı Bîz (ayın en parlak 13, 14, 15. günleri) oruç sünneti vaktidir. "
                : "";
        switch (ay) {
            case 1:
                return eyyamNotu + "Muharrem Ayı · Kur'ân'da bildirilen dört Haram Ay'dan biridir; Peygamber Efendimiz \"Allah'ın ayı\" olarak nitelendirmiş ve nâfile orucu tavsiye buyurmuştur.";
            case 2:
                return eyyamNotu + "Safer Ayı · İslâm'da uğursuzluk inancı yoktur; Safer ayı sabır, duâ, sadaka ve hayırlı amellerle bereketlendirilen bir aydır.";
            case 3:
                return eyyamNotu + "Rebîülevvel Ayı · Âlemlere rahmet Hz. Muhammed Mustafa'nın (s.a.v.) dünyayı şereflendirdiği Mevlid ve salavât ayıdır.";
            case 4:
                return eyyamNotu + "Rebîülâhir Ayı · Günlük Kur'ân virdi, Pazartesi–Perşembe sünnet oruçları ve tefekkürle değerlendirilen mübârek aydır.";
            case 5:
                return eyyamNotu + "Cemâziyelevvel Ayı · Üç Aylar iklimine yaklaşırken kalbi ve ibâdet düzenini hazırlama mevsimidir.";
            case 6:
                return eyyamNotu + "Cemâziyelâhir Ayı · Recep ayının müjdecisi; istiğfâr, kazâ namazları ve hayırla Üç Aylar'a hazırlık ayıdır.";
            case 7:
                return eyyamNotu + "Recep Ayı · Hem Haram Aylar'dan hem de Üç Aylar'ın ilkidir; Regâib ve Mi'râc gecelerini barındıran rahmet ve tohum ekme ayıdır.";
            case 8:
                return eyyamNotu + "Şâban Ayı · Üç Aylar'ın ikincisi ve Peygamber Efendimiz'in en çok nâfile oruç tuttuğu, amellerin Âlemlerin Rabbine arz olunduğu Berât ayıdır.";
            case 9:
                return "Ramazan-ı Şerîf · On bir ayın sultanı; farz oruç, Kur'ân-ı Kerîm tilâveti, Terâvih, infâk ve Kadir Gecesi ayıdır.";
            case 10:
                return eyyamNotu + "Şevval Ayı · Ramazan Bayramı sevincini taşıyan ve 6 gün Şevval orucu ile bütün yılı oruçlu geçirmiş sevâbı kazandıran aydır.";
            case 11:
                return eyyamNotu + "Zilkâde Ayı · Haram Aylar'ın üçüncüsüdür; hac hazırlığı, sükûnet ve barış ayıdır.";
            case 12:
                return eyyamNotu + "Zilhicce Ayı · Haram Aylar'dandır; ilk on gecesi Fecr Sûresi'nde övülmüş olup Hac, Arefe ve Kurban Bayramı'nı kuşatır.";
            default:
                return eyyamNotu;
        }
    }

    /** Hicrî 1..30 gününe göre gerçekçi ışıklı ay evresi çizen saf Canvas görünümü. */
    private static final class AyEvresiView extends View {
        private final int hicriGun;
        private final Paint boya = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint parilti = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Path aydinlikYol = new Path();

        AyEvresiView(Context c, int hicriGun) {
            super(c);
            setLayerType(LAYER_TYPE_SOFTWARE, null);
            this.hicriGun = Math.max(1, Math.min(30, hicriGun));
        }

        @Override
        protected void onDraw(Canvas c) {
            float w = getWidth(), h = getHeight();
            if (w <= 0 || h <= 0) return;
            float cx = w / 2f, cy = h / 2f;
            float R = Math.min(w, h) * 0.38f;

            // Dış altın hâle
            parilti.setStyle(Paint.Style.FILL);
            parilti.setColor(0x55F5CF5B);
            parilti.setMaskFilter(new BlurMaskFilter(Math.max(1f, R * 0.35f), BlurMaskFilter.Blur.NORMAL));
            c.drawCircle(cx, cy, R * 1.12f, parilti);
            parilti.setMaskFilter(null);

            // Karanlık ay yüzeyi
            boya.setStyle(Paint.Style.FILL);
            boya.setColor(0xFF141B2D);
            c.drawCircle(cx, cy, R, boya);

            // Evre açısı: 1. gün yeni hilâl, 14-15. gün tam dolunay, 29-30 son hilâl
            double faz = ((hicriGun - 0.5) / 29.53); // 0..1
            boolean buyuyen = faz <= 0.5;
            // Terminator elips yatay yarıçapı (-R .. +R)
            double aydinlikOran = 0.5 * (1.0 - Math.cos(2.0 * Math.PI * faz)); // 0..1..0
            float termX = (float) ((1.0 - 2.0 * aydinlikOran) * R);

            aydinlikYol.reset();
            int adim = 40;
            for (int i = 0; i <= adim; i++) {
                double aci = -Math.PI / 2.0 + (Math.PI * i / adim); // -90° .. +90°
                float dy = (float) Math.sin(aci) * R;
                float disX = (buyuyen ? 1f : -1f) * (float) Math.cos(aci) * R;
                if (i == 0) aydinlikYol.moveTo(cx + disX, cy + dy);
                else aydinlikYol.lineTo(cx + disX, cy + dy);
            }
            for (int i = adim; i >= 0; i--) {
                double aci = -Math.PI / 2.0 + (Math.PI * i / adim);
                float dy = (float) Math.sin(aci) * R;
                float icX = (buyuyen ? 1f : -1f) * (float) Math.cos(aci) * termX;
                aydinlikYol.lineTo(cx + icX, cy + dy);
            }
            aydinlikYol.close();

            boya.setShader(new RadialGradient(cx - R * 0.2f, cy - R * 0.2f, R * 1.3f,
                    new int[]{0xFFFFF6D6, 0xFFF3CA6B, 0xFFD29B38}, null, Shader.TileMode.CLAMP));
            c.drawPath(aydinlikYol, boya);
            boya.setShader(null);

            // İnce çerçeve halkası
            boya.setStyle(Paint.Style.STROKE);
            boya.setStrokeWidth(Math.max(1.2f, R * 0.05f));
            boya.setColor(0x66F5CF5B);
            c.drawCircle(cx, cy, R, boya);
        }
    }

    // ================================================================ GÖRÜNÜM YARDIMCILARI

    private static TextView bolumBasligi(DurumAktivitesi a, TemaMotoru.Durum tema, String s) {
        TextView t = yazi(a, tema, s, 12, tema.vurgu, true);
        t.setLetterSpacing(0.07f);
        t.setPadding(a.dp(4), a.dp(8), a.dp(4), a.dp(8));
        return t;
    }

    private static LinearLayout kart(DurumAktivitesi a, TemaMotoru.Durum tema) {
        LinearLayout k = new LinearLayout(a);
        k.setOrientation(LinearLayout.VERTICAL);
        k.setPadding(a.dp(16), a.dp(14), a.dp(16), a.dp(14));
        k.setBackground(tema.kartArkaPlani(a));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(0, 0, 0, a.dp(12));
        k.setLayoutParams(lp);
        return k;
    }

    private static TextView yazi(Context c, TemaMotoru.Durum tema, String metin, int bazSp, int renk, boolean kalin) {
        TextView t = new TextView(c);
        t.setText(metin);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, TemaMotoru.olcekliSp(c, bazSp));
        t.setTextColor(renk);
        t.setTypeface(kalin ? Typeface.create("sans-serif-medium", Typeface.NORMAL) : Typeface.DEFAULT);
        t.setLineSpacing(0, 1.15f);
        int p = TemaMotoru.dp(c, 2);
        t.setPadding(0, p, 0, p);
        if (!tema.acik) {
            t.setShadowLayer(TemaMotoru.dp(c, 4), 0, TemaMotoru.dp(c, 1), 0x55000000);
        }
        return t;
    }

    private static TextView cipOlustur(DurumAktivitesi a, TemaMotoru.Durum tema,
                                       String metin, boolean secili, View.OnClickListener tik) {
        TextView c = yazi(a, tema, metin, 13, secili ? tema.birincilDugmeYaziRengi() : tema.metin, true);
        c.setShadowLayer(0, 0, 0, 0);
        c.setPadding(a.dp(12), a.dp(9), a.dp(12), a.dp(9));
        c.setBackground(tema.cipArkaPlani(a, secili, 16));
        c.setClickable(true);
        a.basmaEfekti(c);
        c.setOnClickListener(v -> {
            v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            tik.onClick(v);
        });
        return c;
    }

    private static TextView dugme(DurumAktivitesi a, TemaMotoru.Durum tema,
                                  String metin, boolean birincil, View.OnClickListener tik) {
        TextView b = yazi(a, tema, metin, 14, birincil ? tema.birincilDugmeYaziRengi() : tema.metin, true);
        b.setShadowLayer(0, 0, 0, 0);
        b.setGravity(Gravity.CENTER);
        b.setMinHeight(a.dp(42));
        b.setPadding(a.dp(14), a.dp(8), a.dp(14), a.dp(8));
        b.setBackground(birincil ? tema.birincilDugme(a, 15) : tema.ikincilDugme(a, 15));
        b.setClickable(true);
        a.basmaEfekti(b);
        b.setOnClickListener(v -> {
            v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            tik.onClick(v);
        });
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(0, a.dp(10), 0, 0);
        b.setLayoutParams(lp);
        return b;
    }
}
