package com.mehmetderin.secde_vakti.saglik;

import android.app.AlertDialog;
import android.content.Context;
import android.content.SharedPreferences;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.HapticFeedbackConstants;
import android.view.View;
import android.widget.FrameLayout;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONArray;
import org.json.JSONObject;

import java.lang.ref.WeakReference;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Collections;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;

/**
 * 30 Cüz Kur'ân-ı Kerîm Hatim Takipçisi ve Sesli Cüz Meali Dinleme Modülü.
 * Cüz durumlarını (Okunmadı / Okunuyor / Tamamlandı), tamamlanan hatim sayısını ve
 * günlük sayfa hedefi hesabını "secde_hatim" tercihlerinde kalıcı olarak saklar.
 */
public final class HatimTakip {

    public static final int DURUM_OKUNMADI = 0;
    public static final int DURUM_OKUNUYOR = 1;
    public static final int DURUM_TAMAMLANDI = 2;

    /** 1..30 Cüz başlangıç (sureNo, ayetNo) tablosu. */
    public static final int[][] CUZ_BASLANGIC = {
            {1, 1},   {2, 142}, {2, 253}, {3, 93},  {4, 24},
            {4, 148}, {5, 82},  {6, 111}, {7, 88},  {8, 41},
            {9, 93},  {11, 6},  {12, 53}, {15, 1},  {17, 1},
            {18, 75}, {21, 1},  {23, 1},  {25, 21}, {27, 56},
            {29, 46}, {33, 31}, {36, 28}, {39, 32}, {41, 47},
            {46, 1},  {51, 31}, {58, 1},  {67, 1},  {78, 1}
    };

    private static final String[] CUZ_ISIMLERI = {
            "Elif Lâm Mîm", "Seyekûlü", "Tilke'r-Rusülü", "Len Tenâlü", "Ve'l-Muhsanâtü",
            "Lâ Yuhibbullâhü", "Ve İzâ Semiû", "Ve Lev Ennenâ", "Kâle'l-Meleü", "Va'lemû",
            "Ya'tezirûne", "Ve Mâ Min Dâbbetin", "Ve Mâ Überriü", "Rubemâ", "Sübhânellezî",
            "Kâle Elem", "İkterabe", "Kad Efleha", "Ve Kâle'llezîne", "Emmen Haleka",
            "Ütlü Mâ Ûhiye", "Ve Men Yaknüt", "Ve Mâ Liye", "Femen Azlemü", "İleyhi Yüraddü",
            "Hâ Mîm", "Kâle Femâ Hatbüküm", "Kad Semia'llâhü", "Tebârekellezî", "Amme Yetesâelûn"
    };

    private static final String HATIM_DUASI_ARAPCA =
            "صَدَقَ اللّٰهُ الْعَظِيمُ وَبَلَّغَ رَسُولُهُ الْكَرِيمُ ۝ "
            + "اَللّٰهُمَّ ارْحَمْنِي بِالْقُرْآنِ وَاجْعَلْهُ لِي إِمَامًا وَنُورًا وَهُدًى وَرَحْمَةً، "
            + "اَللّٰهُمَّ ذَكِّرْنِي مِنْهُ مَا نُسِّيتُ وَعَلِّمْنِي مِنْهُ مَا جَهِلْتُ، وَارْزُقْنِي تِلَاوَتَهُ "
            + "آنَاءَ اللَّيْلِ وَأَطْرَافَ النَّهَارِ، وَاجْعَلْهُ لِي حُجَّةً يَا رَبَّ الْعَالَمِينَ";

    private static final String HATIM_DUASI_OKUNUS =
            "Sadakallâhü'l-azîm ve belleğa Rasûlühü'l-kerîm. Allâhümmerhamnî bi'l-Kur'âni vec'alhü lî imâmen "
            + "ve nûran ve hüden ve rahmeh. Allâhümme zekkirnî minhü mâ nüssîtü ve allimnî minhü mâ cehiltü, "
            + "verzuknî tilâvetehû ânâe'l-leyli ve etrâfe'n-nehâr, vec'alhü lî hucceten yâ Rabbe'l-âlemîn.";

    private static final String HATIM_DUASI_MEAL =
            "Yüce Allah doğru söyledi ve Kerîm Rasûlü tebliğ buyurdu. Allah'ım! Kur'ân-ı Kerîm hürmetine bana merhamet eyle; "
            + "onu bana rehber, nûr, hidâyet ve rahmet kıl. Allah'ım! Ondan unuttuğumu bana hatırlat, bilmediğimi öğret; "
            + "gece saatlerinde ve gündüz vakitlerinde onu okumayı bana nasip eyle. Ey âlemlerin Rabbi! Kur'ân'ı "
            + "lehimde şâhit ve delil eyle. Okuduğumuz hatm-i şerîfi dergâh-ı izzetinde kabûl eyle. Âmîn.";

    private static final List<WeakReference<Runnable>> ozetDinleyiciler = new ArrayList<>();
    private static JSONObject onbellekMealSes;

    private HatimTakip() {}

    private static SharedPreferences sp(Context c) {
        return c.getSharedPreferences("secde_hatim", Context.MODE_PRIVATE);
    }

    public static int tamamlananCuzSayisi(Context c) {
        SharedPreferences p = sp(c);
        int sayac = 0;
        for (int i = 1; i <= 30; i++) {
            if (p.getInt("cuz_" + i, DURUM_OKUNMADI) == DURUM_TAMAMLANDI) sayac++;
        }
        return sayac;
    }

    public static int cuzDurumu(Context c, int cuzNo) {
        if (cuzNo < 1 || cuzNo > 30) return DURUM_OKUNMADI;
        int d = sp(c).getInt("cuz_" + cuzNo, DURUM_OKUNMADI);
        return Math.max(DURUM_OKUNMADI, Math.min(DURUM_TAMAMLANDI, d));
    }

    public static void cuzDurumuSec(Context c, int cuzNo, int durum) {
        if (cuzNo < 1 || cuzNo > 30) return;
        int d = Math.max(DURUM_OKUNMADI, Math.min(DURUM_TAMAMLANDI, durum));
        sp(c).edit().putInt("cuz_" + cuzNo, d).apply();
        ozetleriBildir();
    }

    public static int tamamlananHatimSayisi(Context c) {
        return Math.max(0, sp(c).getInt("toplam_hatim", 0));
    }

    private static void ozetleriBildir() {
        for (int i = ozetDinleyiciler.size() - 1; i >= 0; i--) {
            Runnable r = ozetDinleyiciler.get(i).get();
            if (r == null) ozetDinleyiciler.remove(i);
            else r.run();
        }
    }

    /** Kur'an sekmesi için kompakt Hatim Takibi özet kartı. */
    public static View ozetKart(final DurumAktivitesi a) {
        final TemaMotoru.Durum tm = TemaMotoru.aktif(a);
        LinearLayout kart = new LinearLayout(a);
        kart.setOrientation(LinearLayout.VERTICAL);
        kart.setPadding(a.dp(16), a.dp(14), a.dp(16), a.dp(14));
        kart.setBackground(tm.kartArkaPlani(a));
        LinearLayout.LayoutParams kLp = new LinearLayout.LayoutParams(-1, -2);
        kLp.setMargins(0, 0, 0, a.dp(12));
        kart.setLayoutParams(kLp);

        LinearLayout ustSatir = new LinearLayout(a);
        ustSatir.setOrientation(LinearLayout.HORIZONTAL);
        ustSatir.setGravity(Gravity.CENTER_VERTICAL);

        final TextView baslik = metin(a, tm, "", 13, tm.vurgu, true);
        baslik.setLetterSpacing(0.05f);
        ustSatir.addView(baslik, new LinearLayout.LayoutParams(0, -2, 1f));

        TextView eylem = metin(a, tm, "Cüzleri Aç ›", 13, tm.ana, true);
        ustSatir.addView(eylem);
        kart.addView(ustSatir);

        final TextView altBilgi = metin(a, tm, "", 13, tm.soluk, false);
        kart.addView(altBilgi);
        a.bosluk(kart, 8);

        final FrameLayout cubukDis = new FrameLayout(a);
        GradientDrawable disArka = new GradientDrawable();
        disArka.setCornerRadius(a.dp(6));
        disArka.setColor(tm.acik ? 0x2014211C : 0x28FFFFFF);
        cubukDis.setBackground(disArka);

        final View cubukIc = new View(a);
        GradientDrawable icArka = new GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT,
                new int[]{tm.vurgu, tm.ana});
        icArka.setCornerRadius(a.dp(6));
        cubukIc.setBackground(icArka);
        cubukDis.addView(cubukIc, new FrameLayout.LayoutParams(0, a.dp(8)));
        kart.addView(cubukDis, new LinearLayout.LayoutParams(-1, a.dp(8)));

        final Runnable guncelle = () -> {
            int biten = tamamlananCuzSayisi(a);
            int yuzde = Math.round((biten * 100f) / 30f);
            baslik.setText("HATİM TAKİBİ  ·  " + biten + " / 30 Cüz (%" + yuzde + ")");

            int okunanCuz = -1;
            int siradakiCuz = -1;
            for (int i = 1; i <= 30; i++) {
                int d = cuzDurumu(a, i);
                if (d == DURUM_OKUNUYOR && okunanCuz < 0) okunanCuz = i;
                if (d == DURUM_OKUNMADI && siradakiCuz < 0) siradakiCuz = i;
            }
            int toplamHatim = tamamlananHatimSayisi(a);
            String ekHatim = toplamHatim > 0 ? "  ·  " + toplamHatim + " Hatim tamamlandı" : "";
            if (biten == 30) {
                altBilgi.setText("Elhamdülillâh, 30 cüz tamamlandı! Hatim duâsı için dokunun." + ekHatim);
            } else if (okunanCuz > 0) {
                altBilgi.setText("Şu an okunan: " + okunanCuz + ". Cüz (" + CUZ_ISIMLERI[okunanCuz - 1] + ")" + ekHatim);
            } else if (siradakiCuz > 0) {
                altBilgi.setText("Sıradaki: " + siradakiCuz + ". Cüz (" + CUZ_ISIMLERI[siradakiCuz - 1] + ")" + ekHatim);
            } else {
                altBilgi.setText("30 cüz okuma ve sesli meal takibi" + ekHatim);
            }

            cubukDis.post(() -> {
                int gen = cubukDis.getWidth();
                if (gen > 0) {
                    FrameLayout.LayoutParams lp = (FrameLayout.LayoutParams) cubukIc.getLayoutParams();
                    lp.width = Math.round(gen * (biten / 30f));
                    cubukIc.setLayoutParams(lp);
                }
            });
        };

        ozetDinleyiciler.add(new WeakReference<>(guncelle));
        kart.addOnAttachStateChangeListener(new View.OnAttachStateChangeListener() {
            @Override
            public void onViewAttachedToWindow(View v) {
                guncelle.run();
            }

            @Override
            public void onViewDetachedFromWindow(View v) {}
        });
        guncelle.run();

        kart.setClickable(true);
        a.basmaEfekti(kart);
        kart.setOnClickListener(v -> {
            v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            sayfaAc(a);
        });
        return kart;
    }

    /** Tam kapsamlı 30 Cüz Hatim ve Sesli Cüz Meali alt sayfasını açar. */
    public static void sayfaAc(final DurumAktivitesi a) {
        a.guvenli("HatimTakip", () -> sayfaAcIc(a));
    }

    private static void sayfaAcIc(final DurumAktivitesi a) {
        final TemaMotoru.Durum tm = TemaMotoru.aktif(a);
        final SharedPreferences p = sp(a);
        final LinearLayout sutun = a.sutun();

        // Aktif TilavetServisi oynatıcı çubuğu
        if (a.kuranArayuz != null) {
            sutun.addView(a.kuranArayuz.oynaticiCubugu());
        }

        // ----------------------------------------------------------------
        // 1 · Genel İlerleme ve Günlük Hedef Hesaplayıcı Kartı
        // ----------------------------------------------------------------
        LinearLayout genelKart = kart(a, tm);
        final TextView anaIlerleme = metin(a, tm, "", 20, tm.metin, true);
        final TextView altDurum = metin(a, tm, "", 13, tm.soluk, false);
        genelKart.addView(anaIlerleme);
        genelKart.addView(altDurum);
        a.bosluk(genelKart, 8);

        final FrameLayout barDis = new FrameLayout(a);
        GradientDrawable barDisArka = new GradientDrawable();
        barDisArka.setCornerRadius(a.dp(7));
        barDisArka.setColor(tm.acik ? 0x2014211C : 0x28FFFFFF);
        barDis.setBackground(barDisArka);

        final View barIc = new View(a);
        GradientDrawable barIcArka = new GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT,
                new int[]{tm.vurgu, tm.ana});
        barIcArka.setCornerRadius(a.dp(7));
        barIc.setBackground(barIcArka);
        barDis.addView(barIc, new FrameLayout.LayoutParams(0, a.dp(10)));
        genelKart.addView(barDis, new LinearLayout.LayoutParams(-1, a.dp(10)));
        a.bosluk(genelKart, 12);

        // Günlük sayfa hedefi seçici (5 / 10 / 20 sayfa)
        genelKart.addView(metin(a, tm, "GÜNLÜK OKUMA HEDEFİ VE TAHMİNÎ BİTİŞ", 11, tm.vurgu, true));
        final LinearLayout hedefSatir = new LinearLayout(a);
        hedefSatir.setOrientation(LinearLayout.HORIZONTAL);
        LinearLayout.LayoutParams hsLp = new LinearLayout.LayoutParams(-1, -2);
        hsLp.setMargins(0, a.dp(4), 0, a.dp(6));
        hedefSatir.setLayoutParams(hsLp);
        genelKart.addView(hedefSatir);

        final TextView tahminiBitisMetni = metin(a, tm, "", 13, tm.iyi, true);
        genelKart.addView(tahminiBitisMetni);

        final TextView yeniHatimDugme = metin(a, tm, "Yeni Hatim Başlat / Tamamla", 14, tm.birincilDugmeYaziRengi(), true);
        yeniHatimDugme.setShadowLayer(0, 0, 0, 0);
        yeniHatimDugme.setGravity(Gravity.CENTER);
        yeniHatimDugme.setMinHeight(a.dp(44));
        yeniHatimDugme.setBackground(tm.birincilDugme(a, 14));
        LinearLayout.LayoutParams yhLp = new LinearLayout.LayoutParams(-1, -2);
        yhLp.setMargins(0, a.dp(10), 0, 0);
        yeniHatimDugme.setLayoutParams(yhLp);
        yeniHatimDugme.setClickable(true);
        a.basmaEfekti(yeniHatimDugme);
        genelKart.addView(yeniHatimDugme);

        sutun.addView(genelKart);

        // ----------------------------------------------------------------
        // 2 · Sesli Cüz Meali Okuyucu Seçici
        // ----------------------------------------------------------------
        final List<String> okuyucular = cuzOkuyuculariniAl(a);
        if (!okuyucular.isEmpty()) {
            LinearLayout mealKart = kart(a, tm);
            mealKart.addView(metin(a, tm, "SESLİ CÜZ MEALİ OKUYUCUSU", 12, tm.vurgu, true));
            mealKart.addView(metin(a, tm,
                    "Aşağıdaki cüzlerde \"Sesli Meal ▶\" düğmesine dokunduğunuzda seçili okuyucu ile çalar.",
                    12, tm.soluk, false));
            a.bosluk(mealKart, 6);

            HorizontalScrollView okYatay = new HorizontalScrollView(a);
            okYatay.setHorizontalScrollBarEnabled(false);
            okYatay.setOverScrollMode(View.OVER_SCROLL_NEVER);
            final LinearLayout okCipler = new LinearLayout(a);
            okCipler.setOrientation(LinearLayout.HORIZONTAL);
            okYatay.addView(okCipler);
            mealKart.addView(okYatay);

            final Runnable[] okCiz = new Runnable[1];
            okCiz[0] = () -> {
                okCipler.removeAllViews();
                String secili = seciliCuzOkuyucu(a, okuyucular);
                for (final String ok : okuyucular) {
                    boolean aktif = ok.equals(secili);
                    TextView c = metin(a, tm, ok, 13, aktif ? tm.birincilDugmeYaziRengi() : tm.metin, true);
                    c.setShadowLayer(0, 0, 0, 0);
                    c.setPadding(a.dp(14), a.dp(8), a.dp(14), a.dp(8));
                    c.setBackground(tm.cipArkaPlani(a, aktif, 16));
                    LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-2, -2);
                    lp.setMargins(0, 0, a.dp(8), 0);
                    c.setLayoutParams(lp);
                    c.setClickable(true);
                    c.setOnClickListener(v -> {
                        v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
                        p.edit().putString("cuz_okuyucu", ok).apply();
                        okCiz[0].run();
                    });
                    okCipler.addView(c);
                }
            };
            okCiz[0].run();
            sutun.addView(mealKart);
        }

        // ----------------------------------------------------------------
        // 3 · 30 Cüz Listesi
        // ----------------------------------------------------------------
        TextView listeBaslik = metin(a, tm, "30 CÜZ LİSTESİ  ·  DURUM DEĞİŞTİRMEK İÇİN ROZETE DOKUNUN", 12, tm.vurgu, true);
        listeBaslik.setPadding(a.dp(4), a.dp(4), 0, a.dp(8));
        sutun.addView(listeBaslik);

        final Runnable[] cuzSatirlariYenile = new Runnable[30];

        final Runnable ustKartiGuncelle = new Runnable() {
            @Override
            public void run() {
                int biten = tamamlananCuzSayisi(a);
                int okunuyor = 0;
                for (int i = 1; i <= 30; i++) {
                    if (cuzDurumu(a, i) == DURUM_OKUNUYOR) okunuyor++;
                }
                int yuzde = Math.round((biten * 100f) / 30f);
                int toplamHatim = tamamlananHatimSayisi(a);

                anaIlerleme.setText(biten + " / 30 Cüz  ·  %" + yuzde);
                altDurum.setText("Tamamlanan Hatim: " + toplamHatim
                        + (okunuyor > 0 ? "  ·  Okunuyor: " + okunuyor + " cüz" : ""));

                barDis.post(() -> {
                    int gen = barDis.getWidth();
                    if (gen > 0) {
                        FrameLayout.LayoutParams lp = (FrameLayout.LayoutParams) barIc.getLayoutParams();
                        lp.width = Math.round(gen * (biten / 30f));
                        barIc.setLayoutParams(lp);
                    }
                });

                final int[] hedefler = {5, 10, 20};
                int aktifHedef = p.getInt("gunluk_sayfa_hedef", 20);
                hedefSatir.removeAllViews();
                for (int i = 0; i < hedefler.length; i++) {
                    final int hSayfa = hedefler[i];
                    boolean sec = (hSayfa == aktifHedef);
                    TextView dug = metin(a, tm, "Günde " + hSayfa + " sayfa", 12,
                            sec ? tm.birincilDugmeYaziRengi() : tm.metin, true);
                    dug.setShadowLayer(0, 0, 0, 0);
                    dug.setGravity(Gravity.CENTER);
                    dug.setPadding(a.dp(8), a.dp(8), a.dp(8), a.dp(8));
                    dug.setBackground(tm.cipArkaPlani(a, sec, 14));
                    LinearLayout.LayoutParams dlp = new LinearLayout.LayoutParams(0, -2, 1f);
                    dlp.setMargins(i == 0 ? 0 : a.dp(6), 0, 0, 0);
                    dug.setLayoutParams(dlp);
                    dug.setClickable(true);
                    final Runnable kendiniYenile = this;
                    dug.setOnClickListener(v -> {
                        v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
                        p.edit().putInt("gunluk_sayfa_hedef", hSayfa).apply();
                        kendiniYenile.run();
                    });
                    hedefSatir.addView(dug);
                }

                int kalanSayfa = Math.max(0, (30 - biten) * 20 - okunuyor * 10);
                if (kalanSayfa == 0) {
                    tahminiBitisMetni.setText("✓ Tüm cüzler tamamlandı! Hatmi kaydedip duâsını okuyabilirsiniz.");
                } else {
                    int kalanGun = Math.max(1, (int) Math.ceil(kalanSayfa / (double) aktifHedef));
                    Calendar bitisTakvim = Calendar.getInstance();
                    bitisTakvim.add(Calendar.DAY_OF_MONTH, kalanGun);
                    String tarihMetin = new SimpleDateFormat("d MMMM yyyy", new Locale("tr", "TR"))
                            .format(bitisTakvim.getTime());
                    tahminiBitisMetni.setText("Kalan ~" + kalanSayfa + " sayfa  ·  Tahminî bitiş: "
                            + tarihMetin + " (" + kalanGun + " gün)");
                }
            }
        };

        yeniHatimDugme.setOnClickListener(v -> {
            int biten = tamamlananCuzSayisi(a);
            String[] secenekler = {
                    "Mevcut Hatmi Tamamla (+1 Hatim) ve Yeni Başlat",
                    "Yalnızca Cüz İşaretlerini Sıfırla"
            };
            new AlertDialog.Builder(a)
                    .setTitle(biten == 30 ? "Hatm-i Şerîf Tamamlandı!" : "Hatim İşlemi")
                    .setItems(secenekler, (d, secim) -> {
                        SharedPreferences.Editor ed = p.edit();
                        if (secim == 0) {
                            ed.putInt("toplam_hatim", tamamlananHatimSayisi(a) + 1);
                        }
                        for (int i = 1; i <= 30; i++) {
                            ed.putInt("cuz_" + i, DURUM_OKUNMADI);
                        }
                        ed.apply();
                        ozetleriBildir();
                        ustKartiGuncelle.run();
                        for (Runnable r : cuzSatirlariYenile) if (r != null) r.run();
                        if (secim == 0) {
                            Toast.makeText(a, "Allah kabûl eylesin! Yeni hatim başlatıldı.", Toast.LENGTH_SHORT).show();
                        } else {
                            Toast.makeText(a, "Cüz işaretleri sıfırlandı.", Toast.LENGTH_SHORT).show();
                        }
                    })
                    .setNegativeButton("Vazgeç", null)
                    .show();
        });

        for (int i = 0; i < 30; i++) {
            final int cuzNo = i + 1;
            final int sureNo = CUZ_BASLANGIC[i][0];
            final int ayetNo = CUZ_BASLANGIC[i][1];
            Kuran.Sure su = Kuran.sure(a, sureNo);
            final String sureAdi = su != null ? su.ad : (sureNo + ". Sûre");
            final int mushafSayfa = cuzNo == 1 ? 1 : ((cuzNo - 1) * 20 + 2);

            LinearLayout cKart = kart(a, tm);
            cKart.setPadding(a.dp(14), a.dp(12), a.dp(14), a.dp(12));

            // Üst satır: Numara dairesi + Cüz başlığı + Durum rozeti
            LinearLayout ust = new LinearLayout(a);
            ust.setOrientation(LinearLayout.HORIZONTAL);
            ust.setGravity(Gravity.CENTER_VERTICAL);

            TextView numara = metin(a, tm, String.valueOf(cuzNo), 14, tm.birincilDugmeYaziRengi(), true);
            numara.setShadowLayer(0, 0, 0, 0);
            numara.setGravity(Gravity.CENTER);
            numara.setBackground(tm.birincilDugme(a, 18));
            ust.addView(numara, new LinearLayout.LayoutParams(a.dp(34), a.dp(34)));

            LinearLayout bilgi = new LinearLayout(a);
            bilgi.setOrientation(LinearLayout.VERTICAL);
            bilgi.setPadding(a.dp(10), 0, a.dp(6), 0);
            bilgi.addView(metin(a, tm, cuzNo + ". Cüz  ·  " + CUZ_ISIMLERI[i], 15, tm.metin, true));
            bilgi.addView(metin(a, tm, sureAdi + " Sûresi " + ayetNo + ". Âyet  ·  Sayfa " + mushafSayfa, 12, tm.soluk, false));
            ust.addView(bilgi, new LinearLayout.LayoutParams(0, -2, 1f));

            final TextView durumRozet = metin(a, tm, "", 12, tm.metin, true);
            durumRozet.setShadowLayer(0, 0, 0, 0);
            durumRozet.setGravity(Gravity.CENTER);
            durumRozet.setPadding(a.dp(12), a.dp(7), a.dp(12), a.dp(7));
            durumRozet.setClickable(true);
            a.basmaEfekti(durumRozet);
            ust.addView(durumRozet);
            cKart.addView(ust);

            // Alt eylem satırı: Kur'an'da Aç ›  |  Sesli Meal ▶
            LinearLayout eylemler = new LinearLayout(a);
            eylemler.setOrientation(LinearLayout.HORIZONTAL);
            LinearLayout.LayoutParams eLp = new LinearLayout.LayoutParams(-1, -2);
            eLp.setMargins(0, a.dp(10), 0, 0);
            eylemler.setLayoutParams(eLp);

            TextView kurandaAc = eylemDugmesi(a, tm, "Kur'an'da Aç ›", false);
            kurandaAc.setOnClickListener(v -> {
                v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
                if (a.kuranArayuz != null) {
                    a.kuranArayuz.sureAc(sureNo, ayetNo);
                }
            });
            LinearLayout.LayoutParams solLp = new LinearLayout.LayoutParams(0, -2, 1f);
            solLp.setMargins(0, 0, a.dp(5), 0);
            eylemler.addView(kurandaAc, solLp);

            TextView sesliMeal = eylemDugmesi(a, tm, "Sesli Meal ▶", true);
            sesliMeal.setOnClickListener(v -> {
                v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
                cuzMealiCal(a, cuzNo, okuyucular);
            });
            LinearLayout.LayoutParams sagLp = new LinearLayout.LayoutParams(0, -2, 1f);
            sagLp.setMargins(a.dp(5), 0, 0, 0);
            eylemler.addView(sesliMeal, sagLp);

            cKart.addView(eylemler);

            final Runnable satirGuncelle = () -> {
                int d = cuzDurumu(a, cuzNo);
                GradientDrawable rg = new GradientDrawable();
                rg.setCornerRadius(a.dp(14));
                if (d == DURUM_TAMAMLANDI) {
                    durumRozet.setText("Tamamlandı ✓");
                    durumRozet.setTextColor(tm.iyi);
                    rg.setColor(tm.acik ? 0x221B7A50 : 0x332E9E6B);
                    rg.setStroke(Math.max(1, a.dp(1)), tm.iyi);
                } else if (d == DURUM_OKUNUYOR) {
                    durumRozet.setText("Okunuyor ◐");
                    durumRozet.setTextColor(tm.uyari);
                    rg.setColor(tm.acik ? 0x22B26200 : 0x33D98B1E);
                    rg.setStroke(Math.max(1, a.dp(1)), tm.uyari);
                } else {
                    durumRozet.setText("Okunmadı ○");
                    durumRozet.setTextColor(tm.soluk);
                    rg.setColor(tm.acik ? 0x1214211C : 0x1EFFFFFF);
                    rg.setStroke(1, tm.acik ? 0x3314211C : 0x38FFFFFF);
                }
                durumRozet.setBackground(rg);
            };
            cuzSatirlariYenile[i] = satirGuncelle;

            durumRozet.setOnClickListener(v -> {
                int yeni = (cuzDurumu(a, cuzNo) + 1) % 3;
                if (yeni == DURUM_TAMAMLANDI) {
                    v.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS);
                } else {
                    v.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK);
                }
                cuzDurumuSec(a, cuzNo, yeni);
                satirGuncelle.run();
                ustKartiGuncelle.run();
            });

            satirGuncelle.run();
            sutun.addView(cKart);
        }

        ustKartiGuncelle.run();

        // ----------------------------------------------------------------
        // 4 · Hatim Duâsı Kartı
        // ----------------------------------------------------------------
        a.bosluk(sutun, 6);
        LinearLayout duaKart = kart(a, tm);
        duaKart.addView(metin(a, tm, "HATM-İ ŞERÎF DUÂSI", 13, tm.vurgu, true));
        a.bosluk(duaKart, 6);

        TextView arDua = new TextView(a);
        arDua.setText(HATIM_DUASI_ARAPCA);
        arDua.setTypeface(Varlik.kuranYazisi(a));
        arDua.setTextSize(TypedValue.COMPLEX_UNIT_SP, TemaMotoru.olcekliSp(a, 22));
        arDua.setTextColor(tm.metin);
        arDua.setLineSpacing(0, 1.45f);
        arDua.setGravity(Gravity.RIGHT);
        arDua.setPadding(a.dp(12), a.dp(10), a.dp(12), a.dp(10));
        GradientDrawable arArka = new GradientDrawable();
        arArka.setCornerRadius(a.dp(14));
        arArka.setColor(tm.acik ? 0x101E6B55 : 0x24000000);
        arArka.setStroke(1, tm.acik ? 0x221E6B55 : 0x28FFFFFF);
        arDua.setBackground(arArka);
        duaKart.addView(arDua);

        TextView okDua = metin(a, tm, "Okunuşu: " + HATIM_DUASI_OKUNUS, 13, tm.vurgu, false);
        okDua.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.ITALIC));
        okDua.setPadding(0, a.dp(8), 0, a.dp(4));
        duaKart.addView(okDua);

        duaKart.addView(metin(a, tm, "Anlamı: " + HATIM_DUASI_MEAL, 13, tm.soluk, false));
        sutun.addView(duaKart);

        ScrollView sv = new ScrollView(a);
        sv.setVerticalScrollBarEnabled(false);
        sv.setOverScrollMode(View.OVER_SCROLL_NEVER);
        sv.setClipToPadding(false);
        sv.addView(sutun);

        a.altSayfa("Hatim ve Cüz Takipçisi", sv, "kuran_bg");
    }

    // ========================================================================
    // Sesli Cüz Meali Yardımcıları (meal_ses.json -> "cuz" & "sure")
    // ========================================================================

    private static synchronized JSONObject mealSesVerisi(Context c) {
        if (onbellekMealSes == null) {
            try {
                String metin = Varlik.secdeMetin(c, "meal_ses.json");
                onbellekMealSes = metin != null ? new JSONObject(metin) : new JSONObject();
            } catch (Throwable t) {
                onbellekMealSes = new JSONObject();
            }
        }
        return onbellekMealSes;
    }

    private static List<String> cuzOkuyuculariniAl(Context c) {
        List<String> liste = new ArrayList<>();
        JSONObject kok = mealSesVerisi(c);
        JSONObject cuzler = kok.optJSONObject("cuz");
        if (cuzler != null) {
            for (int i = 1; i <= 30; i++) {
                JSONObject o = cuzler.optJSONObject(String.valueOf(i));
                if (o == null) continue;
                if (o.has("okuyucu") && o.has("url")) {
                    String ok = o.optString("okuyucu", "").trim();
                    if (!ok.isEmpty() && !liste.contains(ok)) liste.add(ok);
                } else {
                    Iterator<String> it = o.keys();
                    while (it.hasNext()) {
                        String k = it.next();
                        if (!"url".equals(k) && !liste.contains(k)) liste.add(k);
                    }
                }
            }
        }
        JSONArray genelOk = kok.optJSONArray("okuyucular");
        if (genelOk != null) {
            for (int i = 0; i < genelOk.length(); i++) {
                String ok = genelOk.optString(i, "").trim();
                if (!ok.isEmpty() && !liste.contains(ok)) liste.add(ok);
            }
        }
        return liste;
    }

    private static String seciliCuzOkuyucu(Context c, List<String> okuyucular) {
        String kayitli = sp(c).getString("cuz_okuyucu", null);
        if (kayitli != null && okuyucular.contains(kayitli)) return kayitli;
        return okuyucular.isEmpty() ? null : okuyucular.get(0);
    }

    private static void cuzMealiCal(DurumAktivitesi a, int cuzNo, List<String> okuyucular) {
        JSONObject kok = mealSesVerisi(a);
        JSONObject cuzler = kok.optJSONObject("cuz");
        String secili = seciliCuzOkuyucu(a, okuyucular);
        int sureBas = CUZ_BASLANGIC[cuzNo - 1][0];
        int ayetBas = CUZ_BASLANGIC[cuzNo - 1][1];

        // 1 · Doğrudan "cuz" nesnesi içinde eşleşen kayıt var mı?
        if (cuzler != null) {
            JSONObject cObj = cuzler.optJSONObject(String.valueOf(cuzNo));
            if (cObj != null) {
                if (secili != null && cObj.has(secili)) {
                    String adres = cObj.optString(secili, "");
                    if (adres.startsWith("http")) {
                        TilavetServisi.Parca parca = new TilavetServisi.Parca(
                                adres, cuzNo + ". Cüz Türkçe Meali", sureBas, ayetBas);
                        TilavetServisi.baslat(a, Collections.singletonList(parca), secili + " · Cüz Meali");
                        return;
                    }
                }
                String gomuluOkuyucu = cObj.optString("okuyucu", "");
                String gomuluAdres = cObj.optString("url", "");
                if (!gomuluAdres.isEmpty() && (secili == null || secili.equals(gomuluOkuyucu))) {
                    String okAdi = gomuluOkuyucu.isEmpty() ? "Sesli Cüz Meali" : gomuluOkuyucu;
                    TilavetServisi.Parca parca = new TilavetServisi.Parca(
                            gomuluAdres, cuzNo + ". Cüz Türkçe Meali", sureBas, ayetBas);
                    TilavetServisi.baslat(a, Collections.singletonList(parca), okAdi + " · Tam Cüz Meali");
                    return;
                }
            }
        }

        // 2 · Kullanıcı sûre bazlı bir okuyucu (ör. Hakan Vanlı) seçtiyse bu cüzdeki sûrelerin meallerini kuyrukla
        int sureBit = (cuzNo < 30) ? CUZ_BASLANGIC[cuzNo][0] : 114;
        if (cuzNo < 30 && CUZ_BASLANGIC[cuzNo][1] == 1) {
            sureBit = Math.max(sureBas, sureBit - 1);
        }
        List<TilavetServisi.Parca> kuyruk = new ArrayList<>();
        String kullanilanOkuyucu = secili;
        for (int sNo = sureBas; sNo <= sureBit; sNo++) {
            String[] ms = Kuran.mealSesi(a, sNo, secili);
            if (ms != null && ms.length == 2 && ms[1] != null && !ms[1].isEmpty()) {
                kullanilanOkuyucu = ms[0];
                Kuran.Sure su = Kuran.sure(a, sNo);
                String baslik = cuzNo + ". Cüz · " + (su != null ? su.ad : (sNo + ". Sûre"));
                kuyruk.add(new TilavetServisi.Parca(ms[1], baslik, sNo, sNo == sureBas ? ayetBas : 1));
            }
        }
        if (!kuyruk.isEmpty()) {
            TilavetServisi.baslat(a, kuyruk, (kullanilanOkuyucu != null ? kullanilanOkuyucu : "Sesli Meal") + " · " + cuzNo + ". Cüz");
            return;
        }

        // 3 · Son yedek: "cuz" içindeki varsayılan URL
        if (cuzler != null) {
            JSONObject cObj = cuzler.optJSONObject(String.valueOf(cuzNo));
            if (cObj != null) {
                String url = cObj.optString("url", "");
                if (!url.isEmpty()) {
                    TilavetServisi.Parca parca = new TilavetServisi.Parca(
                            url, cuzNo + ". Cüz Türkçe Meali", sureBas, ayetBas);
                    TilavetServisi.baslat(a, Collections.singletonList(parca),
                            cObj.optString("okuyucu", "Sesli Meal") + " · Cüz Meali");
                    return;
                }
            }
        }

        Toast.makeText(a, cuzNo + ". cüz için sesli meal kaydı bulunamadı.", Toast.LENGTH_SHORT).show();
    }

    // ========================================================================
    // Görünüm Yardımcıları
    // ========================================================================

    private static TextView eylemDugmesi(DurumAktivitesi a, TemaMotoru.Durum tm, String yazi, boolean birincil) {
        TextView t = metin(a, tm, yazi, 13, birincil ? tm.birincilDugmeYaziRengi() : tm.metin, true);
        t.setShadowLayer(0, 0, 0, 0);
        t.setGravity(Gravity.CENTER);
        t.setMinHeight(a.dp(40));
        t.setPadding(a.dp(10), a.dp(8), a.dp(10), a.dp(8));
        t.setBackground(birincil ? tm.birincilDugme(a, 13) : tm.ikincilDugme(a, 13));
        t.setClickable(true);
        a.basmaEfekti(t);
        return t;
    }

    private static LinearLayout kart(DurumAktivitesi a, TemaMotoru.Durum tm) {
        LinearLayout k = new LinearLayout(a);
        k.setOrientation(LinearLayout.VERTICAL);
        k.setPadding(a.dp(16), a.dp(14), a.dp(16), a.dp(14));
        k.setBackground(tm.kartArkaPlani(a));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(0, 0, 0, a.dp(10));
        k.setLayoutParams(lp);
        return k;
    }

    private static TextView metin(DurumAktivitesi a, TemaMotoru.Durum tm, String s, int sp, int renk, boolean kalin) {
        TextView t = new TextView(a);
        t.setText(s);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, TemaMotoru.olcekliSp(a, sp));
        t.setTextColor(renk);
        t.setTypeface(kalin ? Typeface.create("sans-serif-medium", Typeface.NORMAL) : Typeface.DEFAULT);
        t.setLineSpacing(0, 1.15f);
        t.setPadding(0, a.dp(1), 0, a.dp(1));
        if (!tm.acik) {
            t.setShadowLayer(a.dp(4), 0, a.dp(1), 0x55000000);
        }
        return t;
    }
}
