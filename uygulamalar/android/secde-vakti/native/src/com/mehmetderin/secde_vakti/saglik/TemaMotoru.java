package com.mehmetderin.secde_vakti.saglik;

import android.content.Context;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.LayerDrawable;
import android.util.TypedValue;

import java.io.File;

/**
 * Secde Vakti Zengin Tema Motoru:
 *  - 16 özenle tasarlanmış İslâmî renk paleti (Zümrüt Mihrap, Dinamik Gökyüzü, Saf AMOLED,
 *    İznik Çinisi, Medîne Ravza, Kâbe Kisvesi, Osmanlı Sahaf, Sade Modern Pillars,
 *    Şafak Pembesi, Kandil Kehribarı, Ayasofya, Gece Mavisi, Selçuklu Çiviti,
 *    Kubbetü's-Sahra, Hicaz Akşamı, İnci Ferahlığı Açık Tema).
 *  - 4 kart biçimi (Yumuşak Cam, Altın Çerçeveli, Sade Mat, Kompakt).
 *  - 6 geometrik desen seçeneği + canlı sahne modu + yazı ölçeği + yüksek kontrast.
 *  - FlutterSharedPreferences ile çift yönlü tema eşitlemesi.
 */
public final class TemaMotoru {

    public static final String ANAHTAR_TEMA = "gorunum_tema_kodu";
    public static final String ANAHTAR_KART = "gorunum_kart_bicimi";
    public static final String ANAHTAR_DESEN = "gorunum_desen_turu";
    public static final String ANAHTAR_SAHNE = "gorunum_sahne_modu";
    public static final String ANAHTAR_OLCEK = "gorunum_yazi_olcegi";
    public static final String ANAHTAR_KONTRAST = "gorunum_yuksek_kontrast";
    public static final String ANAHTAR_SERIF = "gorunum_serif_baslik";
    public static final String ANAHTAR_ARAPCA_FONT = "gorunum_arapca_font";
    public static final String ANAHTAR_SAHNE_PAKET = "gorunum_sahne_paketi";
    public static final String ANAHTAR_SABIT_ARKAPLAN = "gorunum_sabit_arkaplan";
    public static final String ANAHTAR_EFEKT = "gorunum_efekt_yogunlugu";
    public static final String ANAHTAR_NETLIK = "gorunum_sahne_netlik";

    public static final String PAKET_KLASIK = "klasik";
    public static final String PAKET_HAREMEYN = "haremeyn";
    public static final String PAKET_KUDUS_AKSA = "kudus_aksa";
    public static final String PAKET_OSMANLI_GECE = "osmanli_gece";

    public static final String EFEKT_ZENGIN = "zengin";
    public static final String EFEKT_SADE = "sade";
    public static final String EFEKT_KAPALI = "kapali";

    public static final String NETLIK_CANLI = "canli";
    public static final String NETLIK_DENGELI = "dengeli";
    public static final String NETLIK_OKUMA = "okuma";

    public static final String[][] SAHNE_PAKETLERI = {
            {PAKET_KLASIK, "Günün Vaktine Göre", "Her namaz vaktinde değişen klasik atmosfer"},
            {PAKET_HAREMEYN, "Haremeyn · Mekke & Medîne", "Gece Kâbe-i Muazzama, gündüz Ravza-i Mutahhara"},
            {PAKET_KUDUS_AKSA, "Kudüs & Selçuklu Avlusu", "Seher Kubbetü's-Sahra, gündüz güneşli şadırvan"},
            {PAKET_OSMANLI_GECE, "Osmanlı Kemer & Haliç", "Gece teheccüd kemeri, ikindi Selçuklu avlusu"}
    };

    public static final String[][] OZEL_ARKAPLANLAR = {
            {"", "Otomatik (Vakit & Sekme)", "Seçili pakete göre vakitle değişir"},
            {"bg_mekke_gece", "Mekke · Kâbe (Gece)", "Mescid-i Harâm kubbesi ve nur ışıkları"},
            {"bg_medine_ravza", "Medîne · Ravza (Gündüz)", "Kubbe-i Hadrâ ve avlu gölgelikleri"},
            {"bg_kudus_aksa", "Kudüs · Mescid-i Aksâ", "Altın kubbe ve seher kızıllığı"},
            {"bg_selcuklu_avlu", "Selçuklu Taş Avlusu", "Güneş hüzmeleri ve şadırvan sükûneti"},
            {"bg_teheccud_pencere", "Teheccüd Penceresi", "Kemerde dolunay, rahle ve kandil"},
            {"mihrap", "Zümrüt Mihrap", "Klasik nakışlı yeşil mihrap"},
            {"vakit_4", "Haliç Akşamı", "Gün batımı minare silueti"},
            {"kandil", "Altın Kandil", "Mübarek gece ve Ramazan kandili"}
    };

    public static final String[][] ARAPCA_FONTLAR = {
            {"AmiriQuran-Regular.ttf", "Amîrî Mushaf"},
            {"ScheherazadeNew-Regular.ttf", "Şehrazad Nesih"},
            {"NotoNaskhArabic.ttf", "Noto Açık Nesih"},
            {"Lateef-Regular.ttf", "Latîf İnce Hat"},
    };

    public static final String KART_YUMUSAK = "yumusak";
    public static final String KART_CERCEVELI = "cerceveli";
    public static final String KART_MAT = "mat";
    public static final String KART_KOMPAKT = "kompakt";

    public static final String SAHNE_CANLI_FOTO = "canli_foto";
    public static final String SAHNE_CIZIM = "cizim_sahne";
    public static final String SAHNE_DINAMIK_GOK = "dinamik_gok";
    public static final String SAHNE_DUZ_AMOLED = "duz_amoled";

    public static final class Tema {
        public final String kod;
        public final String ad;
        public final String altBaslik;
        public final String flutterKarsiligi;
        public final boolean acikTema;
        public final int zemin;
        public final int heroBas, heroSon;
        public final int camUst, camAlt, camKenar;
        public final int vurgu, vurguKoyu;
        public final int ana;
        public final int onVurgu;
        public final int varsayilanDesen;
        public final String varsayilanSahne;

        Tema(String kod, String ad, String altBaslik, String flutterKarsiligi, boolean acikTema,
             int zemin, int heroBas, int heroSon, int camUst, int camAlt, int camKenar,
             int vurgu, int vurguKoyu, int ana, int onVurgu, int varsayilanDesen, String varsayilanSahne) {
            this.kod = kod;
            this.ad = ad;
            this.altBaslik = altBaslik;
            this.flutterKarsiligi = flutterKarsiligi;
            this.acikTema = acikTema;
            this.zemin = zemin;
            this.heroBas = heroBas;
            this.heroSon = heroSon;
            this.camUst = camUst;
            this.camAlt = camAlt;
            this.camKenar = camKenar;
            this.vurgu = vurgu;
            this.vurguKoyu = vurguKoyu;
            this.ana = ana;
            this.onVurgu = onVurgu;
            this.varsayilanDesen = varsayilanDesen;
            this.varsayilanSahne = varsayilanSahne;
        }
    }

    public static final Tema[] TEMALAR = {
            new Tema("zumrut", "Zümrüt Mihrap", "Sultanahmet yeşili ve varak altın", "zumrut", false,
                    0xFF0A1914, 0xFF255F4E, 0xFF123F35, 0x82112D24, 0x70081813, 0x42D9B76A,
                    0xFFE5C16C, 0xFFB8892D, 0xFF52C2A6, 0xFF171104,
                    GeometrikDesen.SELCUKLU_YILDIZI, SAHNE_CANLI_FOTO),

            new Tema("dinamik_gokyuzu", "Dinamik Gökyüzü", "Güneşin seyrine göre vakitle akan renkler", "deniz", false,
                    0xFF0D1428, 0xFF284D7A, 0xFF122645, 0x78152340, 0x660A1224, 0x38FFFFFF,
                    0xFFF0B862, 0xFFC07D22, 0xFF7EC8F2, 0xFF1A1205,
                    GeometrikDesen.SELCUKLU_YILDIZI, SAHNE_DINAMIK_GOK),

            new Tema("saf_amoled", "Saf AMOLED Gece", "Sıfır arka plan pil tüketimli tam siyah", "geceSiyahi", false,
                    0xFF000000, 0xFF151922, 0xFF040507, 0xE60B0D12, 0xF2040507, 0x33E5C786,
                    0xFFE7CA88, 0xFFB28A38, 0xFFBBD0E5, 0xFF120E04,
                    GeometrikDesen.KAPALI, SAHNE_DUZ_AMOLED),

            new Tema("iznik_cinisi", "İznik Çinisi", "Osmanlı kobalt mavisi, firuze ve mercan", "turkuaz", false,
                    0xFF091B29, 0xFF164C7E, 0xFF093B42, 0x840E2E46, 0x72071A2A, 0x454AD2D4,
                    0xFFF29A6B, 0xFFC95A38, 0xFF4AD2D4, 0xFF1C0C06,
                    GeometrikDesen.IZNIK_RUMI, SAHNE_CANLI_FOTO),

            new Tema("medine_ravza", "Medîne Ravza", "Huzur veren Ravza-i Mutahhara yeşili", "zumrut", false,
                    0xFF0E1B15, 0xFF366953, 0xFF1B3B2E, 0x84183226, 0x720C1C15, 0x4088CFA9,
                    0xFFEAD084, 0xFFB79238, 0xFF88CFA9, 0xFF171205,
                    GeometrikDesen.MIHRAP_KEMERI, SAHNE_CANLI_FOTO),

            new Tema("kabe_kisvesi", "Kâbe Kisvesi", "Siyah ipek atlas ve sırma altın kuşak", "colAltini", false,
                    0xFF07070A, 0xFF201E26, 0xFF0B0B0F, 0x9016151C, 0x820A0A0E, 0x58F2CA52,
                    0xFFF5CF5B, 0xFFC1921E, 0xFFD9B648, 0xFF181102,
                    GeometrikDesen.KISVE_KAFES, SAHNE_DUZ_AMOLED),

            new Tema("osmanli_sahaf", "Osmanlı Sahaf · Sıcak Kum", "El yazması parşömen ve kehribar sıcaklığı", "toprak", false,
                    0xFF1D1610, 0xFF6B4829, 0xFF3B2512, 0x86332318, 0x741E140D, 0x42E2AE5C,
                    0xFFE7B86A, 0xFFB57C28, 0xFFDAB08E, 0xFF1D1205,
                    GeometrikDesen.SELCUKLU_YILDIZI, SAHNE_CANLI_FOTO),

            new Tema("minimalist_pillars", "Sade Modern · Pillars", "Dingin mat yüzeyler ve yalın tipografi", "deniz", false,
                    0xFF111417, 0xFF252B32, 0xFF161A1F, 0xEB1B2026, 0xF013171C, 0x29FFFFFF,
                    0xFFD8AB63, 0xFFA67932, 0xFF7BA884, 0xFF161106,
                    GeometrikDesen.KAPALI, SAHNE_DUZ_AMOLED),

            new Tema("safak_seher", "Şafak Pembesi · Seher", "Fecir vakti gül kurusu ve seher esintisi", "gulBahcesi", false,
                    0xFF1F111A, 0xFF72304D, 0xFF3B162A, 0x82381A2B, 0x70200D18, 0x42E89DBD,
                    0xFFF4C892, 0xFFBF8546, 0xFFE89DBD, 0xFF1F1006,
                    GeometrikDesen.IZNIK_RUMI, SAHNE_CANLI_FOTO),

            new Tema("kandil_kehribari", "Kandil Kehribarı", "Mahya ışığı, sıcak bal ve bakır parıltısı", "colAltini", false,
                    0xFF1C140A, 0xFF78521D, 0xFF402A0C, 0x8435250F, 0x721F1507, 0x45FFC861,
                    0xFFFFCC6B, 0xFFC7881E, 0xFFE8AD42, 0xFF1E1202,
                    GeometrikDesen.MIHRAP_KEMERI, SAHNE_CANLI_FOTO),

            new Tema("ayasofya", "Ayasofya Kubbesi", "Tarihî kubbe zeytinisi ve mozaik altını", "ayasofya", false,
                    0xFF141910, 0xFF445933, 0xFF25341B, 0x8424301B, 0x72131B0E, 0x40B9CB8A,
                    0xFFE7CA88, 0xFFB38E3E, 0xFFB9CB8A, 0xFF181305,
                    GeometrikDesen.KUBBE_HALKA, SAHNE_CANLI_FOTO),

            new Tema("gece_mavisi", "Gece Mavisi · Sekînet", "Klasik teheccüd laciverti ve hilâl altını", "geceMavisi", false,
                    0xFF0E1328, 0xFF2B4D7E, 0xFF16254E, 0x78161E3C, 0x640B0F24, 0x389AA6F5,
                    0xFFF0B35A, 0xFFC07A1E, 0xFF9AA6F5, 0xFF1A1206,
                    GeometrikDesen.SELCUKLU_YILDIZI, SAHNE_CANLI_FOTO),

            new Tema("selcuklu_civit", "Selçuklu Çiviti · Karatay", "Konya çini çiviti ve firuze yıldız örgüsü", "menekse", false,
                    0xFF0E1026, 0xFF2D2E6E, 0xFF171942, 0x841A1C46, 0x720E102B, 0x426CD4E0,
                    0xFFEAC270, 0xFFB8882C, 0xFF6CD4E0, 0xFF171104,
                    GeometrikDesen.SELCUKLU_YILDIZI, SAHNE_CIZIM),

            new Tema("kubbetus_sahra", "Kudüs · Kubbetü's-Sahra", "Safir çini mavisi ve altın kubbe", "geceMavisi", false,
                    0xFF0A162B, 0xFF184680, 0xFF0C264A, 0x84112B50, 0x72091830, 0x4AF5CC5C,
                    0xFFF7D164, 0xFFC4941E, 0xFF66B3FF, 0xFF191203,
                    GeometrikDesen.KUBBE_HALKA, SAHNE_CIZIM),

            new Tema("hicaz_aksami", "Hicaz Akşamı", "Mekke gurûbu, kızıl kum ve hurma sıcaklığı", "visne", false,
                    0xFF211114, 0xFF732B34, 0xFF3E151B, 0x8438191E, 0x72200D10, 0x42F0B86E,
                    0xFFF2BE74, 0xFFBF7E2A, 0xFFE88D84, 0xFF1F1105,
                    GeometrikDesen.KISVE_KAFES, SAHNE_CANLI_FOTO),

            new Tema("inci_gunduz", "İnci Ferahlığı · Açık", "Gündüz okuması için aydınlık fildişi ve zümrüt", "inci", true,
                    0xFFF4F1EA, 0xFF1F5C4B, 0xFF123C31, 0xEBFFFFFF, 0xE0F5F2EB, 0x381F5C4B,
                    0xFF9C6514, 0xFF7A4B08, 0xFF1E6B55, 0xFFFFFFFF,
                    GeometrikDesen.SELCUKLU_YILDIZI, SAHNE_DUZ_AMOLED),
    };

    /** Aktif tema + görünüm tercihleri özeti. */
    public static final class Durum {
        public final Tema tema;
        public final boolean acik;
        public final int zemin;
        public final int heroBas, heroSon;
        public final int camUst, camAlt, camKenar;
        public final int metin, soluk, silik;
        public final int vurgu, vurguKoyu, ana, onVurgu;
        public final int iyi, kotu, uyari;
        public final int desen;
        public final String kartBicimi;
        public final String sahneModu;
        public final String sahnePaketi;
        public final String sabitArkaPlan;
        public final String efektYogunlugu;
        public final String sahneNetlik;
        public final float yaziOlcegi;
        public final boolean yuksekKontrast;
        public final boolean serifBaslik;

        Durum(Tema t, int zemin, int heroBas, int heroSon, int camUst, int camAlt, int camKenar,
              int vurgu, int vurguKoyu, int ana, int desen, String kartBicimi, String sahneModu,
              float yaziOlcegi, boolean yuksekKontrast, boolean serifBaslik) {
            this(t, zemin, heroBas, heroSon, camUst, camAlt, camKenar, vurgu, vurguKoyu, ana,
                    desen, kartBicimi, sahneModu, PAKET_KLASIK, "", EFEKT_ZENGIN, NETLIK_CANLI,
                    yaziOlcegi, yuksekKontrast, serifBaslik);
        }

        Durum(Tema t, int zemin, int heroBas, int heroSon, int camUst, int camAlt, int camKenar,
              int vurgu, int vurguKoyu, int ana, int desen, String kartBicimi, String sahneModu,
              String sahnePaketi, String sabitArkaPlan, String efektYogunlugu, String sahneNetlik,
              float yaziOlcegi, boolean yuksekKontrast, boolean serifBaslik) {
            this.tema = t;
            this.acik = t.acikTema;
            this.zemin = zemin;
            this.heroBas = heroBas;
            this.heroSon = heroSon;
            this.camUst = yuksekKontrast ? alfaArtir(camUst, 42) : camUst;
            this.camAlt = yuksekKontrast ? alfaArtir(camAlt, 46) : camAlt;
            this.camKenar = yuksekKontrast ? alfaArtir(camKenar, 65) : camKenar;
            this.vurgu = vurgu;
            this.vurguKoyu = vurguKoyu;
            this.ana = ana;
            this.onVurgu = t.onVurgu;
            this.desen = desen;
            this.kartBicimi = kartBicimi;
            this.sahneModu = sahneModu;
            this.sahnePaketi = sahnePaketi;
            this.sabitArkaPlan = sabitArkaPlan;
            this.efektYogunlugu = efektYogunlugu;
            this.sahneNetlik = sahneNetlik;
            this.yaziOlcegi = yaziOlcegi;
            this.yuksekKontrast = yuksekKontrast;
            this.serifBaslik = serifBaslik;

            if (acik) {
                this.metin = 0xFF14211C;
                this.soluk = yuksekKontrast ? 0xFF1B2B25 : 0xCC263A32;
                this.silik = yuksekKontrast ? 0xCC263A32 : 0x993B5249;
                this.iyi = 0xFF1B7A50;
                this.kotu = 0xFFC62828;
                this.uyari = 0xFFB26200;
            } else {
                this.metin = Color.WHITE;
                this.soluk = yuksekKontrast ? 0xF5FFFFFF : 0xCCFFFFFF;
                this.silik = yuksekKontrast ? 0xD9FFFFFF : 0x99FFFFFF;
                this.iyi = 0xFF7FD1A8;
                this.kotu = 0xFFFF8A80;
                this.uyari = 0xFFFFC66D;
            }
        }

        public float yaricapDp() {
            if (KART_KOMPAKT.equals(kartBicimi)) return 13f;
            if (KART_MAT.equals(kartBicimi)) return 18f;
            if (KART_CERCEVELI.equals(kartBicimi)) return 20f;
            return 22f;
        }

        public Drawable kartArkaPlani(Context c) {
            float dp = c.getResources().getDisplayMetrics().density;
            float r = yaricapDp() * dp;
            GradientDrawable g;
            if (KART_MAT.equals(kartBicimi)) {
                g = new GradientDrawable();
                int matRenk = acik ? 0xF5FFFFFF : alfaSabitle(karistir(camUst, zemin, 0.35f), 236);
                g.setColor(matRenk);
                g.setCornerRadius(r);
                g.setStroke(Math.max(1, Math.round(dp)), acik ? 0x2214211C : 0x22FFFFFF);
            } else {
                g = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[]{camUst, camAlt});
                g.setCornerRadius(r);
                if (KART_CERCEVELI.equals(kartBicimi)) {
                    g.setStroke(Math.max(2, Math.round(1.7f * dp)), (vurgu & 0x00FFFFFF) | 0x88000000);
                } else {
                    g.setStroke(Math.max(1, Math.round(dp)), camKenar);
                }
            }
            if (desen == GeometrikDesen.KAPALI) return g;
            GeometrikDesen gd = new GeometrikDesen(desen, vurgu, acik ? 18 : 16, dp);
            return new LayerDrawable(new Drawable[]{g, gd});
        }

        public GradientDrawable birincilDugme(Context c, int yaricapDp) {
            float dp = c.getResources().getDisplayMetrics().density;
            GradientDrawable g = new GradientDrawable(
                    GradientDrawable.Orientation.LEFT_RIGHT,
                    acik ? new int[]{ana, karistir(ana, 0xFF0B2E24, 0.35f)} : new int[]{vurguKoyu, vurgu});
            g.setCornerRadius(yaricapDp * dp);
            return g;
        }

        public GradientDrawable ikincilDugme(Context c, int yaricapDp) {
            float dp = c.getResources().getDisplayMetrics().density;
            GradientDrawable g = new GradientDrawable();
            g.setColor(acik ? 0x161E6B55 : 0x26FFFFFF);
            g.setStroke(Math.max(1, Math.round(dp)), acik ? 0x441E6B55 : 0x4DFFFFFF);
            g.setCornerRadius(yaricapDp * dp);
            return g;
        }

        public GradientDrawable cipArkaPlani(Context c, boolean secili, int yaricapDp) {
            if (secili) return birincilDugme(c, yaricapDp);
            return ikincilDugme(c, yaricapDp);
        }

        public int birincilDugmeYaziRengi() {
            return acik ? Color.WHITE : onVurgu;
        }
    }

    private static Typeface baslikFontu;

    private TemaMotoru() {}

    public static Tema bul(String kod) {
        if (kod != null) {
            for (Tema t : TEMALAR) if (t.kod.equals(kod)) return t;
        }
        return TEMALAR[0];
    }

    public static String temaKodu(Context c) {
        return Tercihler.sp(c).getString(ANAHTAR_TEMA, "zumrut");
    }

    public static void temaSec(Context c, String kod) {
        Tema t = bul(kod);
        Tercihler.sp(c).edit().putString(ANAHTAR_TEMA, t.kod).apply();
        flutterEsitle(c, t, null, null, null);
    }

    public static String kartBicimi(Context c) {
        return Tercihler.sp(c).getString(ANAHTAR_KART, KART_YUMUSAK);
    }

    public static void kartBicimiSec(Context c, String bicim) {
        Tercihler.sp(c).edit().putString(ANAHTAR_KART, bicim).apply();
        String fl = KART_CERCEVELI.equals(bicim) ? "outlined" : KART_KOMPAKT.equals(bicim) ? "compact" : "soft";
        flutterEsitle(c, null, null, fl, null);
    }

    /** -1: temanın kendi varsayılan deseni; 0..5: kullanıcı seçimi. */
    public static int desenTercihi(Context c) {
        return Tercihler.sp(c).getInt(ANAHTAR_DESEN, -1);
    }

    public static void desenSec(Context c, int desen) {
        Tercihler.sp(c).edit().putInt(ANAHTAR_DESEN, desen).apply();
        flutterEsitle(c, null, desen != GeometrikDesen.KAPALI, null, null);
    }

    /** Boşsa temanın varsayılan sahne modu döner. */
    public static String sahneTercihi(Context c) {
        return Tercihler.sp(c).getString(ANAHTAR_SAHNE, "");
    }

    public static void sahneModuSec(Context c, String mod) {
        Tercihler.sp(c).edit().putString(ANAHTAR_SAHNE, mod == null ? "" : mod).apply();
    }

    public static String sahnePaketi(Context c) {
        String p = Tercihler.sp(c).getString(ANAHTAR_SAHNE_PAKET, PAKET_KLASIK);
        for (String[] row : SAHNE_PAKETLERI) if (row[0].equals(p)) return p;
        return PAKET_KLASIK;
    }

    public static void sahnePaketiSec(Context c, String paket) {
        Tercihler.sp(c).edit().putString(ANAHTAR_SAHNE_PAKET, paket == null ? PAKET_KLASIK : paket).apply();
    }

    public static String sabitArkaPlan(Context c) {
        String s = Tercihler.sp(c).getString(ANAHTAR_SABIT_ARKAPLAN, "");
        return s == null ? "" : s;
    }

    public static void sabitArkaPlanSec(Context c, String anahtar) {
        Tercihler.sp(c).edit().putString(ANAHTAR_SABIT_ARKAPLAN, anahtar == null ? "" : anahtar).apply();
    }

    public static String efektYogunlugu(Context c) {
        String e = Tercihler.sp(c).getString(ANAHTAR_EFEKT, EFEKT_ZENGIN);
        if (EFEKT_SADE.equals(e) || EFEKT_KAPALI.equals(e)) return e;
        return EFEKT_ZENGIN;
    }

    public static void efektYogunluguSec(Context c, String yogunluk) {
        Tercihler.sp(c).edit().putString(ANAHTAR_EFEKT, yogunluk == null ? EFEKT_ZENGIN : yogunluk).apply();
    }

    public static String sahneNetlik(Context c) {
        String n = Tercihler.sp(c).getString(ANAHTAR_NETLIK, NETLIK_CANLI);
        if (NETLIK_DENGELI.equals(n) || NETLIK_OKUMA.equals(n)) return n;
        return NETLIK_CANLI;
    }

    public static void sahneNetlikSec(Context c, String netlik) {
        Tercihler.sp(c).edit().putString(ANAHTAR_NETLIK, netlik == null ? NETLIK_CANLI : netlik).apply();
    }

    /** Vakit veya bölüm sahne anahtarını kullanıcının seçtiği paket ya da sabit arka plana çözer. */
    public static String sahneAnahtariCoz(Context c, String bazAnahtar) {
        if (c == null) return bazAnahtar == null ? "vakit_5" : bazAnahtar;
        String sabit = sabitArkaPlan(c);
        if (!sabit.isEmpty()) return sabit;
        String paket = sahnePaketi(c);
        if ("huzur".equals(bazAnahtar)) {
            if (PAKET_HAREMEYN.equals(paket)) return "bg_mekke_gece";
            if (PAKET_KUDUS_AKSA.equals(paket)) return "bg_kudus_aksa";
            return "bg_teheccud_pencere";
        }
        if (bazAnahtar != null && bazAnahtar.startsWith("vakit_")) {
            int v = 5;
            if (bazAnahtar.length() == 7) {
                int ch = bazAnahtar.charAt(6) - '0';
                if (ch >= 0 && ch <= 5) v = ch;
            }
            if (PAKET_HAREMEYN.equals(paket)) {
                return (v == 0 || v == 4 || v == 5) ? "bg_mekke_gece" : "bg_medine_ravza";
            }
            if (PAKET_KUDUS_AKSA.equals(paket)) {
                if (v == 0 || v == 1 || v == 4) return "bg_kudus_aksa";
                return v == 5 ? "bg_teheccud_pencere" : "bg_selcuklu_avlu";
            }
            if (PAKET_OSMANLI_GECE.equals(paket)) {
                if (v == 0 || v == 5) return "bg_teheccud_pencere";
                return v == 4 ? "vakit_4" : "bg_selcuklu_avlu";
            }
        }
        return bazAnahtar == null ? "vakit_5" : bazAnahtar;
    }

    public static float yaziOlcegi(Context c) {
        float o = Tercihler.sp(c).getFloat(ANAHTAR_OLCEK, 1.0f);
        return Math.max(0.85f, Math.min(1.40f, o));
    }

    public static void yaziOlcegiSec(Context c, float olcek) {
        Tercihler.sp(c).edit().putFloat(ANAHTAR_OLCEK, Math.max(0.85f, Math.min(1.40f, olcek))).apply();
    }

    public static boolean yuksekKontrast(Context c) {
        return Tercihler.sp(c).getBoolean(ANAHTAR_KONTRAST, false);
    }

    public static void yuksekKontrastSec(Context c, boolean acik) {
        Tercihler.sp(c).edit().putBoolean(ANAHTAR_KONTRAST, acik).apply();
        flutterEsitle(c, null, null, null, acik);
    }

    public static boolean serifBaslik(Context c) {
        return Tercihler.sp(c).getBoolean(ANAHTAR_SERIF, true);
    }

    public static void serifBaslikSec(Context c, boolean acik) {
        Tercihler.sp(c).edit().putBoolean(ANAHTAR_SERIF, acik).apply();
    }

    public static String arapcaYaziTipiDosyasi(Context c) {
        String s = Tercihler.sp(c).getString(ANAHTAR_ARAPCA_FONT, ARAPCA_FONTLAR[0][0]);
        for (String[] f : ARAPCA_FONTLAR) if (f[0].equals(s)) return s;
        return ARAPCA_FONTLAR[0][0];
    }

    public static void arapcaYaziTipiSec(Context c, String dosyaAdi) {
        Tercihler.sp(c).edit().putString(ANAHTAR_ARAPCA_FONT, dosyaAdi).apply();
    }

    public static Typeface baslikTipi(Context c) {
        if (!serifBaslik(c)) return Typeface.create("sans-serif-medium", Typeface.NORMAL);
        if (baslikFontu == null) {
            try {
                baslikFontu = Typeface.createFromAsset(c.getAssets(), "flutter_assets/assets/fonts/Lora.ttf");
            } catch (Throwable t) {
                try {
                    String d = System.getProperty("secde.flutter.dizin");
                    if (d != null) baslikFontu = Typeface.createFromFile(new File(d, "assets/fonts/Lora.ttf"));
                } catch (Throwable ignored) {
                }
            }
            if (baslikFontu == null) baslikFontu = Typeface.create(Typeface.SERIF, Typeface.BOLD);
        }
        return baslikFontu;
    }

    /** Aktif tema ve vakit durumunu birleştirerek anlık görünüm paletini üretir. */
    public static Durum aktif(Context c) {
        Tema t = bul(temaKodu(c));
        int desenSecim = desenTercihi(c);
        int desen = desenSecim >= 0 ? desenSecim : t.varsayilanDesen;
        String sahneSecim = sahneTercihi(c);
        String sahne = (sahneSecim == null || sahneSecim.isEmpty()) ? t.varsayilanSahne : sahneSecim;
        String kart = kartBicimi(c);
        String paket = sahnePaketi(c);
        String sabit = sabitArkaPlan(c);
        String efekt = efektYogunlugu(c);
        String netlik = sahneNetlik(c);
        float olcek = yaziOlcegi(c);
        boolean kontrast = yuksekKontrast(c);
        boolean serif = serifBaslik(c);

        if ("dinamik_gokyuzu".equals(t.kod)) {
            int[] dg = dinamikVakitRenkleri(c);
            return new Durum(t, dg[0], dg[1], dg[2], dg[3], dg[4], 0x38FFFFFF,
                    dg[5], dg[6], dg[7], desen, kart, sahne, paket, sabit, efekt, netlik, olcek, kontrast, serif);
        }
        return new Durum(t, t.zemin, t.heroBas, t.heroSon, t.camUst, t.camAlt, t.camKenar,
                t.vurgu, t.vurguKoyu, t.ana, desen, kart, sahne, paket, sabit, efekt, netlik, olcek, kontrast, serif);
    }

    /**
     * Dinamik Gökyüzü: mevcut vakit ile sıradaki vakit arasında (son 25 dakikada yumuşak geçişle)
     * zemin, heroBas, heroSon, camUst, camAlt, vurgu, vurguKoyu, ana dizisini döndürür.
     */
    public static int[] dinamikVakitRenkleri(Context c) {
        final int[][] PALET = {
                // zemin, heroBas, heroSon, camUst, camAlt, vurgu, vurguKoyu, ana
                {0xFF0E1233, 0xFF3E2C68, 0xFF1A1E4A, 0x80241D48, 0x6E11132E, 0xFFF3C68F, 0xFFBE8140, 0xFFE89DBD}, // 0 İmsak
                {0xFF182C48, 0xFF3B6EA8, 0xFF21446E, 0x80214066, 0x6E122640, 0xFFFFDF8E, 0xFFC8982E, 0xFF8ED0F8}, // 1 Güneş
                {0xFF102A45, 0xFF2870B8, 0xFF15477A, 0x80183E68, 0x6E0C2440, 0xFFF5CC6A, 0xFFC28E24, 0xFF6CD4F5}, // 2 Öğle
                {0xFF221A14, 0xFF7D5828, 0xFF3F2B14, 0x803B2A16, 0x6E21160B, 0xFFFFCA68, 0xFFC88620, 0xFFF2B857}, // 3 İkindi
                {0xFF1D132E, 0xFF7A3358, 0xFF311B4E, 0x80361B3E, 0x6E1C0E28, 0xFFFFB27A, 0xFFC96B32, 0xFFFF9E6D}, // 4 Akşam
                {0xFF070A1E, 0xFF1E2D5E, 0xFF0C1433, 0x80131C3B, 0x6E090E22, 0xFFF0B35A, 0xFFC07A1E, 0xFF9AA6F5}, // 5 Yatsı
        };
        int v = 5;
        float k = 0f;
        try {
            VakitTakvimi.Takvim takvim = VakitTakvimi.oku(c);
            VakitTakvimi.An simdiki = takvim.simdiki();
            VakitTakvimi.An sonraki = takvim.sonraki();
            if (simdiki != null) v = Sahne.vakitNo(simdiki.namaz);
            if (sonraki != null) {
                long kalan = sonraki.zaman - System.currentTimeMillis();
                long pencere = 25 * 60_000L;
                if (kalan > 0 && kalan < pencere) {
                    float x = 1f - (kalan / (float) pencere);
                    k = x * x * (3f - 2f * x);
                }
            }
        } catch (Throwable ignored) {
        }
        int v2 = (v + 1) % 6;
        int[] cikti = new int[8];
        for (int i = 0; i < 8; i++) {
            cikti[i] = k <= 0.001f ? PALET[v][i] : karistir(PALET[v][i], PALET[v2][i], k);
        }
        return cikti;
    }

    public static int karistir(int c1, int c2, float oran) {
        float t = Math.max(0f, Math.min(1f, oran));
        int a = Math.round(Color.alpha(c1) + (Color.alpha(c2) - Color.alpha(c1)) * t);
        int r = Math.round(Color.red(c1) + (Color.red(c2) - Color.red(c1)) * t);
        int g = Math.round(Color.green(c1) + (Color.green(c2) - Color.green(c1)) * t);
        int b = Math.round(Color.blue(c1) + (Color.blue(c2) - Color.blue(c1)) * t);
        return Color.argb(a, r, g, b);
    }

    private static int alfaArtir(int renk, int ek) {
        int a = Math.min(255, Color.alpha(renk) + ek);
        return (renk & 0x00FFFFFF) | (a << 24);
    }

    private static int alfaSabitle(int renk, int a) {
        return (renk & 0x00FFFFFF) | (Math.max(0, Math.min(255, a)) << 24);
    }

    private static void flutterEsitle(Context c, Tema t, Boolean desen, String kartStil, Boolean kontrast) {
        try {
            SharedPreferences.Editor ed = c.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit();
            if (t != null && t.flutterKarsiligi != null) ed.putString("flutter.settings.colorTheme", t.flutterKarsiligi);
            if (desen != null) ed.putBoolean("flutter.appearance.pattern", desen);
            if (kartStil != null) ed.putString("flutter.appearance.cardStyle", kartStil);
            if (kontrast != null) ed.putBoolean("flutter.appearance.highContrast", kontrast);
            ed.apply();
        } catch (Throwable ignored) {
        }
    }

    public static int olcekliSp(Context c, int bazSp) {
        return Math.max(10, Math.round(bazSp * yaziOlcegi(c)));
    }

    public static int dp(Context c, float v) {
        return Math.round(TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, c.getResources().getDisplayMetrics()));
    }
}
