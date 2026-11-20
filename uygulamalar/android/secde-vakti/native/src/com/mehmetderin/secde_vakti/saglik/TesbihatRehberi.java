package com.mehmetderin.secde_vakti.saglik;

import android.content.res.AssetFileDescriptor;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.media.AudioAttributes;
import android.media.MediaPlayer;
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

import java.io.File;
import java.util.List;
import java.util.Locale;

/**
 * 5 vakit namaz tesbihatı etkileşimli rehberi.
 * Seçilen vakte (Sabah, Öğle, İkindi, Akşam, Yatsı) özel 8 adımlı farz sonrası tesbihat akışı,
 * çevrimdışı Âyetü'l-Kürsî sesli tilâveti, dokunsal 33'lük sayaç hapları ve Haşr 22–24 (Hüvallâhüllezî) içerir.
 */
public final class TesbihatRehberi {

    public static final String[] VAKITLER = {"Sabah", "Öğle", "İkindi", "Akşam", "Yatsı"};

    private static final String AYETEL_KURSI_ARAPCA =
            "اَللّٰهُ لَا إِلٰهَ إِلَّا هُوَ الْحَيُّ الْقَيُّومُ ۚ لَا تَأْخُذُهُ سِنَةٌ وَلَا نَوْمٌ ۚ "
            + "لَهُ مَا فِي السَّمَاوَاتِ وَمَا فِي الْأَرْضِ ۗ مَنْ ذَا الَّذِي يَشْفَعُ عِنْدَهُ إِلَّا بِإِذْنِهِ ۚ "
            + "يَعْلَمُ مَا بَيْنَ أَيْدِيهِمْ وَمَا خَلْفَهُمْ ۖ وَلَا يُحِيطُونَ بِشَيْءٍ مِنْ عِلْمِهِ إِلَّا بِمَا شَاءَ ۚ "
            + "وَسِعَ كُرْسِيُّهُ السَّمَاوَاتِ وَالْأَرْضَ ۖ وَلَا يَئُودُهُ حِفْظُهُمَا ۚ وَهُوَ الْعَلِيُّ الْعَظِيمُ";

    private static final String AYETEL_KURSI_OKUNUS =
            "Allâhü lâ ilâhe illâ hüve'l-hayyü'l-kayyûm. Lâ te'huzühû sinetün ve lâ nevm. "
            + "Lehû mâ fi's-semâvâti ve mâ fi'l-ard. Men ze'llezî yeşfeu indehû illâ bi-iznih. "
            + "Ya'lemü mâ beyne eydîhim ve mâ halfehüm ve lâ yuhîtûne bi-şey'in min ilmihî illâ bimâ şâe. "
            + "Vesia kürsiyyühü's-semâvâti ve'l-ard. Ve lâ yeûdühû hıfzuhümâ ve hüve'l-aliyyü'l-azîm.";

    private static final String AYETEL_KURSI_MEAL =
            "Allah'tan başka hiçbir ilâh yoktur. O daima diridir (Hayy), bütün varlığın idaresini yürütendir (Kayyûm). "
            + "O'nu ne uyuklama tutar ne de uyku. Göklerde ve yerde ne varsa hepsi O'nundur. İzni olmadan huzurunda "
            + "şefaat edecek olan kimdir? O, kullarının önlerinde ve arkalarında ne varsa hepsini bilir. Onlar ise "
            + "O'nun dilediği kadarından başka ilminden hiçbir şey kavrayamazlar. O'nun kürsüsü gökleri ve yeri "
            + "kuşatmıştır; onları koruyup gözetmek O'na ağır gelmez. O yücedir, büyüktür.";

    private static final String HUVALLAHULLEZI_ARAPCA =
            "هُوَ اللّٰهُ الَّذِي لَا إِلٰهَ إِلَّا هُوَ ۖ عَالِمُ الْغَيْبِ وَالشَّهَادَةِ ۖ هُوَ الرَّحْمٰنُ الرَّحِيمُ ۝ "
            + "هُوَ اللّٰهُ الَّذِي لَا إِلٰهَ إِلَّا هُوَ الْمَلِكُ الْقُدُّوسُ السَّلَامُ الْمُؤْمِنُ الْمُهَيْمِنُ "
            + "الْعَزِيزُ الْجَبَّارُ الْمُتَكَبِّرُ ۚ سُبْحَانَ اللّٰهِ عَمَّا يُشْرِكُونَ ۝ "
            + "هُوَ اللّٰهُ الْخَالِقُ الْبَارِئُ الْمُصَوِّرُ ۖ لَهُ الْأَسْمَاءُ الْحُسْنٰى ۚ "
            + "يُسَبِّحُ لَهُ مَا فِي السَّمَاوَاتِ وَالْأَرْضِ ۖ وَهُوَ الْعَزِيزُ الْحَكِيمُ";

    private static final String HUVALLAHULLEZI_OKUNUS =
            "Hüvallâhüllezî lâ ilâhe illâ hû. Âlimü'l-ğaybi ve'ş-şehâdeti hüve'r-Rahmânü'r-Rahîm. "
            + "Hüvallâhüllezî lâ ilâhe illâ hüve'l-Melikü'l-Kuddûsü's-Selâmü'l-Mü'minü'l-Müheyminü'l-Azîzü'l-Cebbârü'l-Mütekebbir. "
            + "Sübhânallâhi ammâ yüşrikûn. Hüvallâhü'l-Hâliku'l-Bâriü'l-Musavviru lehü'l-esmâü'l-hüsnâ. "
            + "Yüsebbihu lehû mâ fi's-semâvâti ve'l-ard, ve hüve'l-Azîzü'l-Hakîm.";

    private static final String HUVALLAHULLEZI_MEAL =
            "O, kendisinden başka hiçbir ilâh olmayan Allah'tır. Gaybı da görünen âlemi de bilendir. O, Rahmân'dır, Rahîm'dir. "
            + "O, kendisinden başka hiçbir ilâh bulunmayan Allah'tır; O Melik'tir, Kuddûs'tür, Selâm'dır, Mü'min'dir, "
            + "Müheymin'dir, Azîz'dir, Cebbâr'dır, Mütekebbir'dir. Allah, müşriklerin ortak koştuklarından çok yücedir. "
            + "O, yaratan, yoktan var eden, şekil veren Allah'tır. En güzel isimler O'nundur. Göklerde ve yerde olanlar "
            + "O'nun şânını yüceltmektedir. O, mutlak güç sahibidir, hüküm ve hikmet sahibidir. (Haşr, 22–24)";

    private TesbihatRehberi() {}

    public static void sayfaAc(DurumAktivitesi a) {
        String v = null;
        try {
            VakitTakvimi.An s = VakitTakvimi.oku(a).simdiki();
            if (s != null) v = s.namaz;
        } catch (Throwable ignored) {
        }
        sayfaAc(a, v);
    }

    public static void sayfaAc(final DurumAktivitesi a, String baslangicVakit) {
        a.guvenli("TesbihatRehberi", () -> sayfaAcIc(a, baslangicVakit));
    }

    private static void sayfaAcIc(final DurumAktivitesi a, String baslangicVakit) {
        final TemaMotoru.Durum tm = TemaMotoru.aktif(a);
        final Zikir zikirDepo = new Zikir(a);
        final int[] seciliVakit = {vakitIndeksi(a, baslangicVakit)};
        final MediaPlayer[] oynatici = {null};
        final boolean[] caliyor = {false};
        final Runnable[] sesDugmesiGuncelle = {null};

        final Runnable sesDurdur = () -> {
            caliyor[0] = false;
            if (oynatici[0] != null) {
                try {
                    if (oynatici[0].isPlaying()) oynatici[0].stop();
                } catch (Throwable ignored) {
                }
                try {
                    oynatici[0].release();
                } catch (Throwable ignored) {
                }
                oynatici[0] = null;
            }
            if (sesDugmesiGuncelle[0] != null) sesDugmesiGuncelle[0].run();
        };

        final LinearLayout kokSutun = a.sutun();
        kokSutun.addView(metin(a, tm,
                "Farz namazların ardından sünnet-i seniyye üzere yapılan 8 adımlı tesbihat akışı. "
                        + "Sayaç haplarına dokunarak adımları tek tek tamamlayabilirsiniz.",
                13, tm.soluk, false));
        a.bosluk(kokSutun, 10);

        // Üst vakit seçici çipler
        HorizontalScrollView yatayCip = new HorizontalScrollView(a);
        yatayCip.setHorizontalScrollBarEnabled(false);
        yatayCip.setOverScrollMode(View.OVER_SCROLL_NEVER);
        final LinearLayout cipSatiri = new LinearLayout(a);
        cipSatiri.setOrientation(LinearLayout.HORIZONTAL);
        yatayCip.addView(cipSatiri);
        kokSutun.addView(yatayCip, new LinearLayout.LayoutParams(-1, -2));
        a.bosluk(kokSutun, 12);

        // Adımların çizileceği dinamik gövde
        final LinearLayout adimKabi = new LinearLayout(a);
        adimKabi.setOrientation(LinearLayout.VERTICAL);
        kokSutun.addView(adimKabi, new LinearLayout.LayoutParams(-1, -2));

        final Runnable[] ekraniCiz = new Runnable[1];
        ekraniCiz[0] = () -> {
            sesDurdur.run();
            cipSatiri.removeAllViews();
            for (int i = 0; i < VAKITLER.length; i++) {
                final int idx = i;
                boolean aktif = (i == seciliVakit[0]);
                TextView cip = metin(a, tm, VAKITLER[i] + " Namazı", 14,
                        aktif ? tm.birincilDugmeYaziRengi() : tm.metin, true);
                cip.setShadowLayer(0, 0, 0, 0);
                cip.setPadding(a.dp(16), a.dp(9), a.dp(16), a.dp(9));
                cip.setBackground(tm.cipArkaPlani(a, aktif, 18));
                LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-2, -2);
                lp.setMargins(0, 0, a.dp(8), 0);
                cip.setLayoutParams(lp);
                cip.setClickable(true);
                a.basmaEfekti(cip);
                cip.setOnClickListener(v -> {
                    v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
                    seciliVakit[0] = idx;
                    ekraniCiz[0].run();
                });
                cipSatiri.addView(cip);
            }

            adimKabi.removeAllViews();
            adimlariOlustur(a, tm, zikirDepo, adimKabi, seciliVakit[0], oynatici, caliyor, sesDugmesiGuncelle, sesDurdur, ekraniCiz[0]);
        };

        ekraniCiz[0].run();

        ScrollView sv = new ScrollView(a);
        sv.setVerticalScrollBarEnabled(false);
        sv.setOverScrollMode(View.OVER_SCROLL_NEVER);
        sv.setClipToPadding(false);
        sv.addView(kokSutun);
        sv.addOnAttachStateChangeListener(new View.OnAttachStateChangeListener() {
            @Override
            public void onViewAttachedToWindow(View v) {}

            @Override
            public void onViewDetachedFromWindow(View v) {
                sesDurdur.run();
            }
        });

        a.altSayfa("Namaz Tesbihatı Rehberi", sv, "zikir_bg");
    }

    private static void adimlariOlustur(final DurumAktivitesi a, final TemaMotoru.Durum tm, final Zikir zikirDepo,
                                        final LinearLayout kap, final int vakitIdx,
                                        final MediaPlayer[] oynatici, final boolean[] caliyor,
                                        final Runnable[] sesDugmesiGuncelle, final Runnable sesDurdur,
                                        final Runnable sifirlaYenile) {
        final boolean sabah = (vakitIdx == 0);
        final boolean ikindi = (vakitIdx == 2);
        final boolean aksam = (vakitIdx == 3);
        final boolean sabahVeyaAksam = (sabah || aksam);
        final String vakitAdi = VAKITLER[vakitIdx];

        final boolean[] adimTamam = new boolean[8];
        final TextView ilerlemeBaslik = metin(a, tm, "", 15, tm.metin, true);
        final View ilerlemeDolgu = new View(a);
        final FrameLayout ilerlemeCubukKabi = new FrameLayout(a);

        final Runnable ilerlemeGuncelle = () -> {
            int biten = 0;
            for (boolean b : adimTamam) if (b) biten++;
            ilerlemeBaslik.setText(vakitAdi + " Tesbihatı  ·  " + biten + " / 8 Adım Tamamlandı");
            int toplamGen = ilerlemeCubukKabi.getWidth();
            if (toplamGen > 0) {
                FrameLayout.LayoutParams lp = (FrameLayout.LayoutParams) ilerlemeDolgu.getLayoutParams();
                lp.width = Math.round(toplamGen * (biten / 8f));
                ilerlemeDolgu.setLayoutParams(lp);
            }
        };

        // Vakit özeti ve ilerleme kartı
        LinearLayout ozetKart = kart(a, tm);
        ozetKart.addView(ilerlemeBaslik);
        String vakitRehberNotu;
        if (sabah) {
            vakitRehberNotu = "Sabah namazının 2 rekât farzından sonra son sünnet yoktur. Selâmdan hemen sonra "
                    + "dünyevî kelâm etmeden 10× Tehlîl, 7× Allâhümme ecirnâ mine'n-nâr ve 3× İstiâze ile Haşr 22–24 okunması sünnettir.";
        } else if (aksam) {
            vakitRehberNotu = "Akşam namazının 3 rekât farzından sonra istiğfâr ve Allâhümme ente's-selâm okunur; "
                    + "2 rekât son sünnetin ardından 10× Tehlîl, 7× Allâhümme ecirnâ mine'n-nâr ve Hüvallâhüllezî ile tesbihat tamamlanır.";
        } else if (ikindi) {
            vakitRehberNotu = "İkindi namazının 4 rekât farzından sonra son sünnet olmadığı için selâm ve istiğfârdan "
                    + "hemen sonra Salât-ı Münciye ve Âyetü'l-Kürsî ile tesbihata geçilir.";
        } else {
            vakitRehberNotu = vakitAdi + " namazının 4 rekât farzından sonra 3× İstiğfâr ve Allâhümme ente's-selâm okunur; "
                    + "son sünnet (ve Yatsı'da Vitir) edâ edildikten sonra Salât-ı Münciye ile tesbihata devam edilir.";
        }
        ozetKart.addView(metin(a, tm, vakitRehberNotu, 13, tm.soluk, false));
        a.bosluk(ozetKart, 8);

        GradientDrawable cubukArka = new GradientDrawable();
        cubukArka.setCornerRadius(a.dp(6));
        cubukArka.setColor(tm.acik ? 0x2214211C : 0x28FFFFFF);
        ilerlemeCubukKabi.setBackground(cubukArka);

        GradientDrawable cubukOn = new GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT,
                new int[]{tm.vurgu, tm.ana});
        cubukOn.setCornerRadius(a.dp(6));
        ilerlemeDolgu.setBackground(cubukOn);
        ilerlemeCubukKabi.addView(ilerlemeDolgu, new FrameLayout.LayoutParams(0, a.dp(8)));
        ilerlemeCubukKabi.post(ilerlemeGuncelle);
        ozetKart.addView(ilerlemeCubukKabi, new LinearLayout.LayoutParams(-1, a.dp(8)));

        TextView sifirlaDugme = metin(a, tm, "↺ Sayaçları Sıfırla", 13, tm.vurgu, true);
        sifirlaDugme.setPadding(0, a.dp(10), a.dp(8), a.dp(2));
        sifirlaDugme.setOnClickListener(v -> {
            v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            sifirlaYenile.run();
        });
        ozetKart.addView(sifirlaDugme);
        kap.addView(ozetKart);

        // ----------------------------------------------------------------
        // ADIM 1 · Selâm ve İstiğfâr
        // ----------------------------------------------------------------
        LinearLayout adim1 = adimKarti(a, tm, 1, "Selâm ve İstiğfâr", "Farz selâmının hemen ardından");
        adim1.addView(arapcaMetin(a, tm,
                "أَسْتَغْفِرُ اللّٰهَ الْعَظِيمَ (٣)\n"
                        + "اَللّٰهُمَّ أَنْتَ السَّلَامُ وَمِنْكَ السَّلَامُ، تَبَارَكْتَ يَا ذَا الْجَلَالِ وَالْإِكْرَامِ"));
        adim1.addView(okunusMetin(a, tm,
                "Estağfirullâhe'l-azîm (3 defa).\n"
                        + "Allâhümme ente's-selâmü ve minke's-selâm, tebârekte yâ ze'l-celâli ve'l-ikrâm."));
        adim1.addView(mealMetin(a, tm,
                "Azîm olan Allah'tan bağışlanma dilerim (3 defa). Allah'ım! Sen Selâm'sın; esenlik ve kurtuluş "
                        + "ancak Sendendir. Ey celâl ve ikrâm sahibi Rabbimiz, Sen ne yücesin!"));
        if (!sabah && !ikindi) {
            adim1.addView(faziletRozeti(a, tm,
                    "Sünnet Tertibi: Bu duânın ardından " + vakitAdi + " namazının son sünneti kılınır; sonra 2. adımdan devam edilir."));
        }
        adim1.addView(sayacHapi(a, tm, zikirDepo, 3, "İstiğfâr", tamam -> {
            adimTamam[0] = tamam;
            ilerlemeGuncelle.run();
        }));
        kap.addView(adim1);

        // ----------------------------------------------------------------
        // ADIM 2 · Salât-ı Münciye (Salâten Tüncînâ)
        // ----------------------------------------------------------------
        LinearLayout adim2 = adimKarti(a, tm, 2, "Salât-ı Münciye (Salâten Tüncînâ)", "Sıkıntılardan kurtuluş salavâtı");
        adim2.addView(arapcaMetin(a, tm,
                "اَللّٰهُمَّ صَلِّ عَلٰى سَيِّدِنَا مُحَمَّدٍ وَعَلٰى آلِ سَيِّدِنَا مُحَمَّدٍ، صَلَاةً تُنْجِينَا بِهَا "
                        + "مِنْ جَمِيعِ الْأَهْوَالِ وَالْآفَاتِ، وَتَقْضِي لَنَا بِهَا جَمِيعَ الْحَاجَاتِ، وَتُطَهِّرُنَا بِهَا "
                        + "مِنْ جَمِيعِ السَّيِّئَاتِ، وَتَرْفَعُنَا بِهَا عِنْدَكَ أَعْلَى الدَّرَجَاتِ، وَتُبَلِّغُنَا بِهَا أَقْصَى "
                        + "الْغَايَاتِ مِنْ جَمِيعِ الْخَيْرَاتِ فِي الْحَيَاةِ وَبَعْدَ الْمَمَاتِ، إِنَّكَ عَلٰى كُلِّ شَيْءٍ قَدِيرٌ"));
        adim2.addView(okunusMetin(a, tm,
                "Allâhümme salli alâ seyyidinâ Muhammedin ve alâ âli seyyidinâ Muhammed, salâten tüncînâ bihâ "
                        + "min cemîi'l-ehvâli ve'l-âfât, ve takdî lenâ bihâ cemîa'l-hâcât, ve tütahhirunâ bihâ min "
                        + "cemîi's-seyyiât, ve terfeunâ bihâ indeke a'le'd-derecât, ve tübelliğunâ bihâ aksa'l-ğâyât "
                        + "min cemîi'l-hayrâti fi'l-hayâti ve ba'de'l-memât. İnneke alâ külli şey'in kadîr."));
        adim2.addView(mealMetin(a, tm,
                "Allah'ım! Efendimiz Muhammed'e (s.a.v.) ve Efendimiz Muhammed'in âline öyle bir salât eyle ki; "
                        + "o salât vesilesiyle bizi bütün korku ve âfetlerden kurtarasın, bütün ihtiyaçlarımızı gideresin, "
                        + "bizi bütün günahlardan arındırasın, katındaki en yüce derecelere yükseltesin ve hayatta da "
                        + "ölümden sonra da bütün hayırların en üstün gayelerine ulaştırasın. Şüphesiz Sen her şeye kadirsin."));
        adim2.addView(sayacHapi(a, tm, zikirDepo, 1, "Okudum", tamam -> {
            adimTamam[1] = tamam;
            ilerlemeGuncelle.run();
        }));
        kap.addView(adim2);

        // ----------------------------------------------------------------
        // ADIM 3 · Tesbih Girişi & Âyetü'l-Kürsî (Çevrimdışı Sesli)
        // ----------------------------------------------------------------
        LinearLayout adim3 = adimKarti(a, tm, 3, "Tesbih Girişi & Âyetü'l-Kürsî", "Bakara Sûresi 255. Âyet · Çevrimdışı Sesli");
        adim3.addView(arapcaMetin(a, tm,
                "سُبْحَانَ اللّٰهِ وَالْحَمْدُ لِلّٰهِ وَلَا إِلٰهَ إِلَّا اللّٰهُ وَاللّٰهُ أَكْبَرُ، "
                        + "وَلَا حَوْلَ وَلَا قُوَّةَ إِلَّا بِاللّٰهِ الْعَلِيِّ الْعَظِيمِ"));
        adim3.addView(okunusMetin(a, tm,
                "Sübhânallâhi ve'l-hamdü lillâhi ve lâ ilâhe illallâhu vallâhu ekber, ve lâ havle ve lâ kuvvete "
                        + "illâ billâhi'l-aliyyi'l-azîm."));
        adim3.addView(mealMetin(a, tm,
                "Allah her türlü noksandan münezzehtir, hamd Allah'adır, Allah'tan başka ilâh yoktur ve Allah en büyüktür. "
                        + "Güç ve kuvvet ancak yüce ve büyük olan Allah'ın yardımıyladır."));
        a.bosluk(adim3, 6);

        String[] kursVeri = ayetelKursiMetni(a);
        adim3.addView(arapcaMetin(a, tm, "أَعُوذُ بِاللّٰهِ مِنَ الشَّيْطَانِ الرَّجِيمِ ۝ بِسْمِ اللّٰهِ الرَّحْمٰنِ الرَّحِيمِ\n" + kursVeri[0]));
        adim3.addView(okunusMetin(a, tm, AYETEL_KURSI_OKUNUS));
        adim3.addView(mealMetin(a, tm, kursVeri[1]));

        // Çevrimdışı ses oynat/durdur düğmesi
        final TextView sesDugme = metin(a, tm, "▶ Âyetü'l-Kürsî Dinle (Çevrimdışı)", 14, tm.birincilDugmeYaziRengi(), true);
        sesDugme.setShadowLayer(0, 0, 0, 0);
        sesDugme.setGravity(Gravity.CENTER);
        sesDugme.setMinHeight(a.dp(44));
        sesDugme.setPadding(a.dp(16), a.dp(10), a.dp(16), a.dp(10));
        sesDugme.setBackground(tm.birincilDugme(a, 14));
        LinearLayout.LayoutParams sesLp = new LinearLayout.LayoutParams(-1, -2);
        sesLp.setMargins(0, a.dp(10), 0, a.dp(4));
        sesDugme.setLayoutParams(sesLp);
        sesDugme.setClickable(true);
        a.basmaEfekti(sesDugme);

        sesDugmesiGuncelle[0] = () -> {
            boolean aktifSes = caliyor[0];
            sesDugme.setText(aktifSes ? "⏹ Âyetü'l-Kürsî Tilâvetini Durdur" : "▶ Âyetü'l-Kürsî Dinle (Çevrimdışı)");
            sesDugme.setBackground(aktifSes ? tm.ikincilDugme(a, 14) : tm.birincilDugme(a, 14));
            sesDugme.setTextColor(aktifSes ? tm.vurgu : tm.birincilDugmeYaziRengi());
        };

        sesDugme.setOnClickListener(v -> {
            v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            if (caliyor[0]) {
                sesDurdur.run();
            } else {
                ayetelKursiCal(a, oynatici, caliyor, sesDugmesiGuncelle[0], sesDurdur);
            }
        });
        adim3.addView(sesDugme);
        adim3.addView(sayacHapi(a, tm, zikirDepo, 1, "Âyetü'l-Kürsî", tamam -> {
            adimTamam[2] = tamam;
            ilerlemeGuncelle.run();
        }));
        kap.addView(adim3);

        // ----------------------------------------------------------------
        // ADIM 4 · 33× Sübhânallah
        // ----------------------------------------------------------------
        LinearLayout adim4 = adimKarti(a, tm, 4, "33× Sübhânallah", "Tesbîh · Zülcelâli Sübhânallah");
        adim4.addView(arapcaMetin(a, tm, "ذُو الْجَلَالِ سُبْحَانَ اللّٰهِ  —  سُبْحَانَ اللّٰهِ"));
        adim4.addView(okunusMetin(a, tm, "Zü'l-celâli Sübhânallâh  ·  Sübhânallâh (33 defa)"));
        adim4.addView(mealMetin(a, tm, "Celâl sahibi Allah'ı her türlü eksiklik ve noksanlıktan tenzîh ederim."));
        adim4.addView(sayacHapi(a, tm, zikirDepo, 33, "Sübhânallah", tamam -> {
            adimTamam[3] = tamam;
            ilerlemeGuncelle.run();
        }));
        kap.addView(adim4);

        // ----------------------------------------------------------------
        // ADIM 5 · 33× Elhamdülillah
        // ----------------------------------------------------------------
        LinearLayout adim5 = adimKarti(a, tm, 5, "33× Elhamdülillah", "Tahmîd · Zülkemâli Elhamdülillah");
        adim5.addView(arapcaMetin(a, tm, "ذُو الْكَمَالِ اَلْحَمْدُ لِلّٰهِ  —  اَلْحَمْدُ لِلّٰهِ"));
        adim5.addView(okunusMetin(a, tm, "Zü'l-kemâli Elhamdülillâh  ·  Elhamdülillâh (33 defa)"));
        adim5.addView(mealMetin(a, tm, "Kemâl sahibi Allah'a sonsuz hamd ve şükürler olsun."));
        adim5.addView(sayacHapi(a, tm, zikirDepo, 33, "Elhamdülillah", tamam -> {
            adimTamam[4] = tamam;
            ilerlemeGuncelle.run();
        }));
        kap.addView(adim5);

        // ----------------------------------------------------------------
        // ADIM 6 · 33× Allâhu Ekber
        // ----------------------------------------------------------------
        LinearLayout adim6 = adimKarti(a, tm, 6, "33× Allâhu Ekber", "Tekbîr · Zülkudreti Allâhu Ekber");
        adim6.addView(arapcaMetin(a, tm, "ذُو الْقُدْرَةِ اَللّٰهُ أَكْبَرُ  —  اَللّٰهُ أَكْبَرُ"));
        adim6.addView(okunusMetin(a, tm, "Zü'l-kudreti Allâhu Ekber  ·  Allâhu Ekber (33 defa)"));
        adim6.addView(mealMetin(a, tm, "Sonsuz kudret sahibi Allah her şeyden yücedir, en büyüktür."));
        adim6.addView(sayacHapi(a, tm, zikirDepo, 33, "Allâhu Ekber", tamam -> {
            adimTamam[5] = tamam;
            ilerlemeGuncelle.run();
        }));
        kap.addView(adim6);

        // ----------------------------------------------------------------
        // ADIM 7 · Tehlîl ve Kelime-i Tevhîd
        // ----------------------------------------------------------------
        LinearLayout adim7 = adimKarti(a, tm, 7, "Tehlîl ve Kelime-i Tevhîd",
                sabahVeyaAksam ? (vakitAdi + " Vaktine Özel: 10× Tehlîl + 7× Ecirnâ mine'n-nâr") : "99'u 100'e tamamlayan tevhîd ikrârı");
        adim7.addView(arapcaMetin(a, tm,
                "لَا إِلٰهَ إِلَّا اللّٰهُ وَحْدَهُ لَا شَرِيكَ لَهُ، لَهُ الْمُلْكُ وَلَهُ الْحَمْدُ يُحْيِي وَيُمِيتُ "
                        + "وَهُوَ حَيٌّ لَا يَمُوتُ بِيَدِهِ الْخَيْرُ وَهُوَ عَلٰى كُلِّ شَيْءٍ قَدِيرٌ"));
        adim7.addView(okunusMetin(a, tm,
                "Lâ ilâhe illallâhu vahdehû lâ şerîke leh, lehü'l-mülkü ve lehü'l-hamdü yuhyî ve yumîtü ve hüve hayyün "
                        + "lâ yemût, biyedihi'l-hayr ve hüve alâ külli şey'in kadîr."
                        + (sabahVeyaAksam ? " (10 defa)" : " (1 defa)")));
        adim7.addView(mealMetin(a, tm,
                "Allah'tan başka hiçbir ilâh yoktur; O tektir, ortağı yoktur. Mülk O'nundur, hamd O'na mahsustur. "
                        + "Diriltir ve öldürür; O ölmeyen diridir. Hayır yalnız O'nun elindedir ve O her şeye kadirdir."));

        if (sabahVeyaAksam) {
            adim7.addView(faziletRozeti(a, tm,
                    "Fazîlet-i Nebevî: Sabah ve Akşam namazlarının ardından bu tehlîli 10 defa okuyana her biri için "
                            + "10 sevap yazılır, 10 günahı silinir ve o gün/gece her türlü şerden korunur. (Tirmizî, Deavât 64)"));
            adim7.addView(sayacHapi(a, tm, zikirDepo, 10, "Tehlîl", tamam -> {
                adimTamam[6] = tamam;
                ilerlemeGuncelle.run();
            }));
            a.bosluk(adim7, 8);
            adim7.addView(arapcaMetin(a, tm, "اَللّٰهُمَّ أَجِرْنَا مِنَ النَّارِ (٧)"));
            adim7.addView(okunusMetin(a, tm, "Allâhümme ecirnâ mine'n-nâr (7 defa)"));
            adim7.addView(mealMetin(a, tm,
                    "Allah'ım! Bizi cehennem ateşinden koru ve muhâfaza eyle. (Ebû Dâvûd, Edeb 101)"));
            adim7.addView(sayacHapi(a, tm, zikirDepo, 7, "Ecirnâ mine'n-nâr", tamam -> {}));
        } else {
            a.bosluk(adim7, 6);
            adim7.addView(arapcaMetin(a, tm,
                    "فَاعْلَمْ أَنَّهُ لَا إِلٰهَ إِلَّا اللّٰهُ ۝ مُحَمَّدٌ رَسُولُ اللّٰهِ صَلَّى اللّٰهُ تَعَالٰى عَلَيْهِ وَسَلَّمَ"));
            adim7.addView(okunusMetin(a, tm,
                    "Fa'lem ennehû: Lâ ilâhe illallâh (33 defa) · Muhammedü'r-Rasûlullâhi sallallâhu teâlâ aleyhi ve sellem."));
            adim7.addView(mealMetin(a, tm,
                    "Bil ki Allah'tan başka hiçbir ilâh yoktur; Muhammed (s.a.v.) Allah'ın Rasûlüdür."));
            adim7.addView(sayacHapi(a, tm, zikirDepo, 33, "Kelime-i Tevhîd", tamam -> {
                adimTamam[6] = tamam;
                ilerlemeGuncelle.run();
            }));
        }
        kap.addView(adim7);

        // ----------------------------------------------------------------
        // ADIM 8 · Namaz Duâsı & Hüvallâhüllezî (Haşr 22–24)
        // ----------------------------------------------------------------
        LinearLayout adim8 = adimKarti(a, tm, 8, "Namaz Duâsı & Hüvallâhüllezî (Haşr 22–24)",
                sabah ? "Sabah Vaktine Özel: 3× İstiâze + Haşr 22–24"
                        : aksam ? "Akşam Vaktine Özel: Hüvallâhüllezî (Haşr 22–24)"
                        : "Duâ ve Haşr Sûresi'nin son üç âyeti");

        // Namaz Duâsı
        adim8.addView(arapcaMetin(a, tm,
                "اَلْحَمْدُ لِلّٰهِ رَبِّ الْعَالَمِينَ، وَالصَّلَاةُ وَالسَّلَامُ عَلٰى رَسُولِنَا مُحَمَّدٍ وَعَلٰى آلِهِ وَصَحْبِهِ أَجْمَعِينَ ۝ "
                        + "رَبَّنَا آتِنَا فِي الدُّنْيَا حَسَنَةً وَفِي الْآخِرَةِ حَسَنَةً وَقِنَا عَذَابَ النَّارِ ۝ "
                        + "رَبَّنَا اغْفِرْ لِي وَلِوَالِدَيَّ وَلِلْمُؤْمِنِينَ يَوْمَ يَقُومُ الْحِسَابُ"));
        adim8.addView(okunusMetin(a, tm,
                "Elhamdülillâhi Rabbi'l-âlemîn, ve's-salâtü ve's-selâmü alâ rasûlinâ Muhammedin ve alâ âlihî ve sahbihî ecmaîn. "
                        + "Rabbenâ âtinâ fi'd-dünyâ haseneten ve fi'l-âhirati haseneten ve kınâ azâbe'n-nâr. "
                        + "Rabbenağfirlî ve li-vâlideyye ve li'l-mü'minîne yevme yekûmü'l-hisâb."));
        adim8.addView(mealMetin(a, tm,
                "Âlemlerin Rabbi Allah'a hamd, Rasûlümüz Muhammed'e, âline ve ashâbına salât ve selâm olsun. "
                        + "Rabbimiz! Bize dünyada da iyilik ver, âhirette de iyilik ver ve bizi ateş azabından koru. "
                        + "Rabbimiz! Hesap kurulacağı gün beni, anne-babamı ve bütün mü'minleri bağışla."));
        a.bosluk(adim8, 8);

        if (sabah) {
            adim8.addView(faziletRozeti(a, tm,
                    "Sabah Vakti Sünneti: \"Kim sabahleyin üç defa 'Eûzü billâhi's-semîi'l-alîmi mine'ş-şeytâni'r-racîm' "
                            + "deyip Haşr Sûresi'nin son üç âyetini okursa, Allah ona akşama kadar istiğfâr edecek "
                            + "yetmiş bin melek vekil kılar.\" (Tirmizî, Fedâilü'l-Kur'ân 22)"));
            adim8.addView(arapcaMetin(a, tm,
                    "أَعُوذُ بِاللّٰهِ السَّمِيعِ الْعَلِيمِ مِنَ الشَّيْطَانِ الرَّجِيمِ (٣)"));
            adim8.addView(okunusMetin(a, tm,
                    "Eûzü billâhi's-semîi'l-alîmi mine'ş-şeytâni'r-racîm (3 defa) · Bismillâhirrahmânirrahîm"));
            adim8.addView(mealMetin(a, tm,
                    "Kovulmuş şeytanın şerrinden, her şeyi işiten ve bilen Allah'a sığınırım (3 defa)."));
            adim8.addView(sayacHapi(a, tm, zikirDepo, 3, "İstiâze", tamam -> {}));
            a.bosluk(adim8, 8);
        } else if (aksam) {
            adim8.addView(faziletRozeti(a, tm,
                    "Akşam Vakti Sünneti: Akşam namazının ardından Haşr Sûresi'nin son üç âyeti (Hüvallâhüllezî) "
                            + "okunduğunda sabaha kadar yetmiş bin melek istiğfâr eder."));
        }

        String[] hasrVeri = hasrSonUcAyet(a);
        adim8.addView(arapcaMetin(a, tm, hasrVeri[0]));
        adim8.addView(okunusMetin(a, tm, HUVALLAHULLEZI_OKUNUS));
        adim8.addView(mealMetin(a, tm, hasrVeri[1]));
        adim8.addView(sayacHapi(a, tm, zikirDepo, 1, "Duâ & Hüvallâhüllezî", tamam -> {
            adimTamam[7] = tamam;
            ilerlemeGuncelle.run();
        }));
        kap.addView(adim8);

        ilerlemeGuncelle.run();
    }

    private static void ayetelKursiCal(final DurumAktivitesi a, final MediaPlayer[] oynatici,
                                       final boolean[] caliyor, final Runnable guncelle, final Runnable sesDurdur) {
        sesDurdur.run();
        if (TilavetServisi.caliyor()) {
            TilavetServisi.komut(a, TilavetServisi.DURAKLAT);
        }
        try {
            MediaPlayer mp = new MediaPlayer();
            mp.setAudioAttributes(new AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build());
            AssetFileDescriptor afd = Varlik.flutterSes(a, "assets/audio/ayetel_kursi.mp3");
            if (afd != null) {
                mp.setDataSource(afd.getFileDescriptor(), afd.getStartOffset(), afd.getLength());
                afd.close();
            } else {
                String dizin = System.getProperty("secde.flutter.dizin");
                File yedek = dizin == null ? null : new File(dizin, "assets/audio/ayetel_kursi.mp3");
                if (yedek != null && yedek.isFile()) {
                    mp.setDataSource(yedek.getAbsolutePath());
                } else {
                    mp.release();
                    Toast.makeText(a, "Çevrimdışı Âyetü'l-Kürsî ses dosyası bulunamadı.", Toast.LENGTH_SHORT).show();
                    return;
                }
            }
            oynatici[0] = mp;
            caliyor[0] = true;
            guncelle.run();
            mp.setOnPreparedListener(MediaPlayer::start);
            mp.setOnCompletionListener(m -> sesDurdur.run());
            mp.setOnErrorListener((m, w, ex) -> {
                sesDurdur.run();
                return true;
            });
            mp.prepareAsync();
        } catch (Throwable t) {
            sesDurdur.run();
            Toast.makeText(a, "Ses başlatılamadı.", Toast.LENGTH_SHORT).show();
        }
    }

    private static String[] ayetelKursiMetni(DurumAktivitesi a) {
        try {
            List<Kuran.Ayet> l = Kuran.ayetler(a, 2);
            if (l != null && l.size() >= 255) {
                Kuran.Ayet ay = l.get(254);
                if (ay != null && ay.arapca != null && !ay.arapca.isEmpty()) {
                    return new String[]{ay.arapca, (ay.meal != null && !ay.meal.isEmpty()) ? ay.meal : AYETEL_KURSI_MEAL};
                }
            }
        } catch (Throwable ignored) {
        }
        return new String[]{AYETEL_KURSI_ARAPCA, AYETEL_KURSI_MEAL};
    }

    private static String[] hasrSonUcAyet(DurumAktivitesi a) {
        try {
            List<Kuran.Ayet> l = Kuran.ayetler(a, 59);
            if (l != null && l.size() >= 24) {
                StringBuilder ar = new StringBuilder();
                StringBuilder tr = new StringBuilder();
                for (int n = 21; n <= 23; n++) {
                    Kuran.Ayet ay = l.get(n);
                    if (ar.length() > 0) ar.append(" ۝ ");
                    ar.append(ay.arapca);
                    if (tr.length() > 0) tr.append(" ");
                    tr.append("(").append(ay.no).append(") ").append(ay.meal);
                }
                if (ar.length() > 0) return new String[]{ar.toString(), tr.toString()};
            }
        } catch (Throwable ignored) {
        }
        return new String[]{HUVALLAHULLEZI_ARAPCA, HUVALLAHULLEZI_MEAL};
    }

    private interface TamamDinleyici {
        void degisti(boolean tamamlandi);
    }

    private static View sayacHapi(final DurumAktivitesi a, final TemaMotoru.Durum tm, final Zikir zikirDepo,
                                  final int hedef, final String etiket, final TamamDinleyici dinleyici) {
        final int[] sayac = {0};
        LinearLayout satir = new LinearLayout(a);
        satir.setOrientation(LinearLayout.HORIZONTAL);
        satir.setGravity(Gravity.CENTER_VERTICAL);
        LinearLayout.LayoutParams sLp = new LinearLayout.LayoutParams(-1, -2);
        sLp.setMargins(0, a.dp(10), 0, 0);
        satir.setLayoutParams(sLp);

        final TextView hap = metin(a, tm, "", 15, tm.birincilDugmeYaziRengi(), true);
        hap.setShadowLayer(0, 0, 0, 0);
        hap.setGravity(Gravity.CENTER);
        hap.setMinHeight(a.dp(46));
        hap.setPadding(a.dp(16), a.dp(10), a.dp(16), a.dp(10));
        hap.setClickable(true);
        a.basmaEfekti(hap);

        final TextView sifirla = metin(a, tm, "↺", 17, tm.soluk, true);
        sifirla.setShadowLayer(0, 0, 0, 0);
        sifirla.setGravity(Gravity.CENTER);
        sifirla.setMinHeight(a.dp(46));
        sifirla.setMinWidth(a.dp(46));
        sifirla.setBackground(tm.ikincilDugme(a, 14));
        LinearLayout.LayoutParams rLp = new LinearLayout.LayoutParams(a.dp(46), a.dp(46));
        rLp.setMargins(a.dp(8), 0, 0, 0);
        sifirla.setLayoutParams(rLp);
        sifirla.setClickable(true);

        final Runnable guncelle = () -> {
            boolean doldu = sayac[0] >= hedef;
            if (hedef == 1) {
                hap.setText(doldu ? ("✓ " + etiket + " Tamamlandı") : ("○ " + etiket + "  ·  Dokun Tamamla"));
            } else {
                hap.setText(doldu
                        ? ("✓ " + sayac[0] + " / " + hedef + "  ·  " + etiket + " Tamam")
                        : (sayac[0] + " / " + hedef + "  ·  Dokun +1"));
            }
            if (doldu) {
                GradientDrawable basari = new GradientDrawable();
                basari.setCornerRadius(a.dp(15));
                basari.setColor(tm.acik ? 0x241B7A50 : 0x332E9E6B);
                basari.setStroke(Math.max(1, a.dp(1)), tm.iyi);
                hap.setBackground(basari);
                hap.setTextColor(tm.iyi);
            } else {
                hap.setBackground(tm.birincilDugme(a, 15));
                hap.setTextColor(tm.birincilDugmeYaziRengi());
            }
            sifirla.setVisibility(sayac[0] > 0 ? View.VISIBLE : View.GONE);
            if (dinleyici != null) dinleyici.degisti(doldu);
        };

        hap.setOnClickListener(v -> {
            sayac[0]++;
            if (hedef == 33) {
                int zIdx = "Sübhânallah".equals(etiket) ? 0 : "Elhamdülillah".equals(etiket) ? 1 : 2;
                zikirDepo.artir(zIdx);
            }
            if (sayac[0] == hedef) {
                v.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS);
            } else {
                v.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK);
            }
            guncelle.run();
        });

        sifirla.setOnClickListener(v -> {
            v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            sayac[0] = 0;
            guncelle.run();
        });

        satir.addView(hap, new LinearLayout.LayoutParams(0, -2, 1f));
        satir.addView(sifirla);
        guncelle.run();
        return satir;
    }

    private static LinearLayout adimKarti(DurumAktivitesi a, TemaMotoru.Durum tm, int adimNo, String baslik, String alt) {
        LinearLayout k = kart(a, tm);
        LinearLayout ust = new LinearLayout(a);
        ust.setOrientation(LinearLayout.HORIZONTAL);
        ust.setGravity(Gravity.CENTER_VERTICAL);

        TextView rozet = metin(a, tm, String.valueOf(adimNo), 14, tm.birincilDugmeYaziRengi(), true);
        rozet.setShadowLayer(0, 0, 0, 0);
        rozet.setGravity(Gravity.CENTER);
        GradientDrawable rg = tm.birincilDugme(a, 16);
        rozet.setBackground(rg);
        ust.addView(rozet, new LinearLayout.LayoutParams(a.dp(32), a.dp(32)));

        LinearLayout baslikSutun = new LinearLayout(a);
        baslikSutun.setOrientation(LinearLayout.VERTICAL);
        baslikSutun.setPadding(a.dp(10), 0, 0, 0);
        baslikSutun.addView(metin(a, tm, baslik, 16, tm.metin, true));
        if (alt != null && !alt.isEmpty()) {
            baslikSutun.addView(metin(a, tm, alt, 12, tm.vurgu, false));
        }
        ust.addView(baslikSutun, new LinearLayout.LayoutParams(0, -2, 1f));
        k.addView(ust);
        a.bosluk(k, 8);
        return k;
    }

    private static TextView arapcaMetin(DurumAktivitesi a, TemaMotoru.Durum tm, String arapca) {
        TextView t = new TextView(a);
        t.setText(arapca);
        t.setTypeface(Varlik.kuranYazisi(a));
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, TemaMotoru.olcekliSp(a, 23));
        t.setTextColor(tm.metin);
        t.setLineSpacing(0, 1.45f);
        t.setGravity(Gravity.RIGHT);
        t.setPadding(a.dp(12), a.dp(10), a.dp(12), a.dp(10));
        GradientDrawable g = new GradientDrawable();
        g.setCornerRadius(a.dp(14));
        g.setColor(tm.acik ? 0x101E6B55 : 0x22000000);
        g.setStroke(1, tm.acik ? 0x221E6B55 : 0x26FFFFFF);
        t.setBackground(g);
        return t;
    }

    private static TextView okunusMetin(DurumAktivitesi a, TemaMotoru.Durum tm, String okunus) {
        TextView t = metin(a, tm, "Okunuşu: " + okunus, 13, tm.vurgu, false);
        t.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.ITALIC));
        t.setPadding(0, a.dp(8), 0, a.dp(2));
        return t;
    }

    private static TextView mealMetin(DurumAktivitesi a, TemaMotoru.Durum tm, String meal) {
        TextView t = metin(a, tm, "Anlamı: " + meal, 13, tm.soluk, false);
        t.setPadding(0, a.dp(2), 0, a.dp(2));
        return t;
    }

    private static View faziletRozeti(DurumAktivitesi a, TemaMotoru.Durum tm, String yazi) {
        TextView t = metin(a, tm, "✦ " + yazi, 12, tm.acik ? tm.ana : tm.vurgu, true);
        t.setShadowLayer(0, 0, 0, 0);
        t.setPadding(a.dp(12), a.dp(8), a.dp(12), a.dp(8));
        GradientDrawable g = new GradientDrawable();
        g.setCornerRadius(a.dp(12));
        g.setColor(tm.acik ? 0x161E6B55 : (tm.vurgu & 0x00FFFFFF) | 0x22000000);
        g.setStroke(1, (tm.vurgu & 0x00FFFFFF) | 0x66000000);
        t.setBackground(g);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(0, a.dp(6), 0, a.dp(6));
        t.setLayoutParams(lp);
        return t;
    }

    private static LinearLayout kart(DurumAktivitesi a, TemaMotoru.Durum tm) {
        LinearLayout k = new LinearLayout(a);
        k.setOrientation(LinearLayout.VERTICAL);
        k.setPadding(a.dp(16), a.dp(14), a.dp(16), a.dp(14));
        k.setBackground(tm.kartArkaPlani(a));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(0, 0, 0, a.dp(12));
        k.setLayoutParams(lp);
        return k;
    }

    private static TextView metin(DurumAktivitesi a, TemaMotoru.Durum tm, String s, int sp, int renk, boolean kalin) {
        TextView t = new TextView(a);
        t.setText(s);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, TemaMotoru.olcekliSp(a, sp));
        t.setTextColor(renk);
        t.setTypeface(kalin ? Typeface.create("sans-serif-medium", Typeface.NORMAL) : Typeface.DEFAULT);
        t.setLineSpacing(0, 1.16f);
        t.setPadding(0, a.dp(2), 0, a.dp(2));
        if (!tm.acik) {
            t.setShadowLayer(a.dp(4), 0, a.dp(1), 0x55000000);
        }
        return t;
    }

    private static int vakitIndeksi(DurumAktivitesi a, String ham) {
        String s = ham;
        if (s == null || s.trim().isEmpty()) {
            try {
                VakitTakvimi.An simdiki = VakitTakvimi.oku(a).simdiki();
                if (simdiki != null) s = simdiki.namaz;
            } catch (Throwable ignored) {
            }
        }
        if (s == null) return 0;
        String k = s.trim().toLowerCase(new Locale("tr", "TR"));
        if (k.contains("fajr") || k.contains("sunrise") || k.contains("sabah") || k.contains("imsak") || k.contains("güneş") || k.contains("gunes")) {
            return 0;
        }
        if (k.contains("dhuhr") || k.contains("öğle") || k.contains("ogle") || k.contains("cuma")) {
            return 1;
        }
        if (k.contains("asr") || k.contains("ikindi")) {
            return 2;
        }
        if (k.contains("maghrib") || k.contains("akşam") || k.contains("aksam")) {
            return 3;
        }
        if (k.contains("isha") || k.contains("yatsı") || k.contains("yatsi")) {
            return 4;
        }
        return 0;
    }
}
