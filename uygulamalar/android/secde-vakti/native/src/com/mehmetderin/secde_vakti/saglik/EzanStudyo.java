package com.mehmetderin.secde_vakti.saglik;

import android.content.Context;
import android.content.SharedPreferences;
import android.content.res.AssetFileDescriptor;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.media.AudioAttributes;
import android.media.MediaPlayer;
import android.os.Handler;
import android.os.Looper;
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
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * Çevrimdışı Ezan Makamları, Kâbe İmâmı Tilâvetleri, Türkçe Sesli Meal Önizlemeleri
 * ve Tekrar Döngülü Namaz Sûreleri Ezber Stüdyosu.
 * Tüm ses dosyalarını internet gerektirmeden doğrudan uygulama paketinden (Varlik.flutterSes) çalar.
 */
public final class EzanStudyo {

    private static final class EzanKaydi {
        final String dosya, baslik, altBaslik;

        EzanKaydi(String dosya, String baslik, String altBaslik) {
            this.dosya = dosya;
            this.baslik = baslik;
            this.altBaslik = altBaslik;
        }
    }

    private static final class EzberKaydi {
        final String dosya, baslik, altBaslik;
        final int sureNo, tekAyetNo;
        final String yedekArapca, okunus, yedekMeal;

        EzberKaydi(String dosya, String baslik, String altBaslik, int sureNo, int tekAyetNo,
                   String yedekArapca, String okunus, String yedekMeal) {
            this.dosya = dosya;
            this.baslik = baslik;
            this.altBaslik = altBaslik;
            this.sureNo = sureNo;
            this.tekAyetNo = tekAyetNo;
            this.yedekArapca = yedekArapca;
            this.okunus = okunus;
            this.yedekMeal = yedekMeal;
        }
    }

    private static final EzanKaydi[] EZAN_LISTESI = {
            new EzanKaydi("ezan-full.mp3",
                    "Tam Ezan-ı Muhammedî",
                    "İstanbul Tavrı · Çevrimdışı Tam Kayıt"),
            new EzanKaydi("ezan-medine.mp3",
                    "Medîne-i Münevvere Ezanı",
                    "Harem-i Şerîf Ravza Makamı · Çevrimdışı"),
            new EzanKaydi("besmele.mp3",
                    "Besmele-i Şerîfe",
                    "Bismillâhirrahmânirrahîm · İftitah Tilâveti"),
            new EzanKaydi("shuraim_001_fatiha.mp3",
                    "Fâtiha Sûresi · Harem Tilâveti",
                    "Kâbe İmâmı Suûd eş-Şureym · Çevrimdışı"),
            new EzanKaydi("shuraim_112_ihlas.mp3",
                    "İhlâs Sûresi · Harem Tilâveti",
                    "Kâbe İmâmı Suûd eş-Şureym · Çevrimdışı"),
    };

    private static final EzberKaydi[] EZBER_LISTESI = {
            new EzberKaydi(
                    "ayetel_kursi.mp3",
                    "Âyetü'l-Kürsî",
                    "Bakara Sûresi · 255. Âyet-i Kerîme",
                    2, 255,
                    "اَللّٰهُ لَا إِلٰهَ إِلَّا هُوَ الْحَيُّ الْقَيُّومُ ۚ لَا تَأْخُذُهُ سِنَةٌ وَلَا نَوْمٌ ۚ "
                            + "لَهُ مَا فِي السَّمَاوَاتِ وَمَا فِي الْأَرْضِ ۗ مَنْ ذَا الَّذِي يَشْفَعُ عِنْدَهُ إِلَّا بِإِذْنِهِ ۚ "
                            + "يَعْلَمُ مَا بَيْنَ أَيْدِيهِمْ وَمَا خَلْفَهُمْ ۖ وَلَا يُحِيطُونَ بِشَيْءٍ مِنْ عِلْمِهِ إِلَّا بِمَا شَاءَ ۚ "
                            + "وَسِعَ كُرْسِيُّهُ السَّمَاوَاتِ وَالْأَرْضَ ۖ وَلَا يَئُودُهُ حِفْظُهُمَا ۚ وَهُوَ الْعَلِيُّ الْعَظِيمُ",
                    "Allâhü lâ ilâhe illâ hüve'l-hayyü'l-kayyûm. Lâ te'huzühû sinetün ve lâ nevm. "
                            + "Lehû mâ fi's-semâvâti ve mâ fi'l-ard. Men ze'llezî yeşfeu indehû illâ bi-iznih. "
                            + "Ya'lemü mâ beyne eydîhim ve mâ halfehüm ve lâ yuhîtûne bi-şey'in min ilmihî illâ bimâ şâe. "
                            + "Vesia kürsiyyühü's-semâvâti ve'l-ard. Ve lâ yeûdühû hıfzuhümâ ve hüve'l-aliyyü'l-azîm.",
                    "Allah'tan başka hiçbir ilâh yoktur. O daima diridir (Hayy), bütün varlığın idaresini yürütendir (Kayyûm). "
                            + "O'nu ne uyuklama tutar ne de uyku. Göklerde ve yerde ne varsa hepsi O'nundur. İzni olmadan huzurunda "
                            + "şefaat edecek olan kimdir? O, kullarının önlerinde ve arkalarında ne varsa hepsini bilir. Onlar ise "
                            + "O'nun dilediği kadarından başka ilminden hiçbir şey kavrayamazlar. O'nun kürsüsü gökleri ve yeri "
                            + "kuşatmıştır; onları koruyup gözetmek O'na ağır gelmez. O yücedir, büyüktür."
            ),
            new EzberKaydi(
                    "ikra_001_fatiha.mp3",
                    "Fâtiha Sûresi",
                    "1. Sûre · 7 Âyet · Namazın Her Rekâtında Okunur",
                    1, 0,
                    "بِسْمِ اللّٰهِ الرَّحْمٰنِ الرَّحِيمِ ۝ اَلْحَمْدُ لِلّٰهِ رَبِّ الْعَالَمِينَ ۝ الرَّحْمٰنِ الرَّحِيمِ ۝ "
                            + "مَالِكِ يَوْمِ الدِّينِ ۝ إِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينُ ۝ اهْدِنَا الصِّرَاطَ الْمُسْتَقِيمَ ۝ "
                            + "صِرَاطَ الَّذِينَ أَنْعَمْتَ عَلَيْهِمْ غَيْرِ الْمَغْضُوبِ عَلَيْهِمْ وَلَا الضَّالِّينَ",
                    "Bismillâhirrahmânirrahîm. Elhamdü lillâhi Rabbi'l-âlemîn. Er-Rahmâni'r-Rahîm. Mâliki yevmi'd-dîn. "
                            + "İyyâke na'büdü ve iyyâke nestaîn. İhdine's-sırâta'l-müstakîm. Sırâtallezîne en'amte aleyhim "
                            + "ğayri'l-mağdûbi aleyhim ve le'd-dâllîn. (Âmîn)",
                    "Rahmân ve Rahîm olan Allah'ın adıyla. Hamd, âlemlerin Rabbi, Rahmân, Rahîm, hesap ve ceza gününün mâliki "
                            + "olan Allah'a mahsustur. Yalnız Sana ibadet ederiz ve yalnız Senden yardım dileriz. Bizi doğru yola, "
                            + "kendilerine nimet verdiklerinin yoluna ilet; gazaba uğrayanlarınkine ve sapkınlarınkine değil."
            ),
            new EzberKaydi(
                    "ikra_103_asr.mp3",
                    "Asr Sûresi",
                    "103. Sûre · 3 Âyet · Mekkî",
                    103, 0,
                    "وَالْعَصْرِ ۝ إِنَّ الْإِنْسَانَ لَفِي خُسْرٍ ۝ إِلَّا الَّذِينَ آمَنُوا وَعَمِلُوا الصَّالِحَاتِ "
                            + "وَتَوَاصَوْا بِالْحَقِّ وَتَوَاصَوْا بِالصَّبْرِ",
                    "Bismillâhirrahmânirrahîm. Ve'l-asr. İnne'l-insâne lefî husr. İllellezîne âmenû ve amilü's-sâlihâti "
                            + "ve tevâsav bi'l-hakkı ve tevâsav bi's-sabr.",
                    "Asra yemin olsun ki insan gerçekten ziyan içindedir. Ancak iman edip sâlih ameller işleyenler, "
                            + "birbirlerine hakkı tavsiye edenler ve birbirlerine sabrı tavsiye edenler başka."
            ),
            new EzberKaydi(
                    "ikra_108_kevser.mp3",
                    "Kevser Sûresi",
                    "108. Sûre · 3 Âyet · Kur'ân'ın En Kısa Sûresi",
                    108, 0,
                    "إِنَّا أَعْطَيْنَاكَ الْكَوْثَرَ ۝ فَصَلِّ لِرَبِّكَ وَانْحَرْ ۝ إِنَّ شَانِئَكَ هُوَ الْأَبْتَرُ",
                    "Bismillâhirrahmânirrahîm. İnnâ a'taynâke'l-kevser. Fesalli li-Rabbike venhar. İnne şânieke hüve'l-ebter.",
                    "Şüphesiz biz sana Kevser'i verdik. O hâlde Rabbin için namaz kıl ve kurban kes. "
                            + "Doğrusu sana buğzeden, soyu kesik olanın ta kendisidir."
            ),
            new EzberKaydi(
                    "ikra_112_ihlas.mp3",
                    "İhlâs Sûresi",
                    "112. Sûre · 4 Âyet · Tevhîd Sûresi",
                    112, 0,
                    "قُلْ هُوَ اللّٰهُ أَحَدٌ ۝ اَللّٰهُ الصَّمَدُ ۝ لَمْ يَلِدْ وَلَمْ يُولَدْ ۝ وَلَمْ يَكُنْ لَهُ كُفُوًا أَحَدٌ",
                    "Bismillâhirrahmânirrahîm. Kul hüvallâhü ehad. Allâhü's-samed. Lem yelid ve lem yûled. Ve lem yekün lehû küfüven ehad.",
                    "De ki: O, Allah'tır, bir tektir. Allah Samed'dir (her şey O'na muhtaçtır; O hiçbir şeye muhtaç değildir). "
                            + "O doğurmamıştır ve doğurulmamıştır. Hiçbir şey O'na denk ve benzer değildir."
            ),
            new EzberKaydi(
                    "ikra_113_felak.mp3",
                    "Felak Sûresi",
                    "113. Sûre · 5 Âyet · Muavvizeteyn",
                    113, 0,
                    "قُلْ أَعُوذُ بِرَبِّ الْفَلَقِ ۝ مِنْ شَرِّ مَا خَلَقَ ۝ وَمِنْ شَرِّ غَاسِقٍ إِذَا وَقَبَ ۝ "
                            + "وَمِنْ شَرِّ النَّفَّاثَاتِ فِي الْعُقَدِ ۝ وَمِنْ شَرِّ حَاسِدٍ إِذَا حَسَدَ",
                    "Bismillâhirrahmânirrahîm. Kul eûzü bi-Rabbi'l-felak. Min şerri mâ halak. Ve min şerri ğâsikın izâ vekab. "
                            + "Ve min şerri'n-neffâsâti fi'l-ukad. Ve min şerri hâsidin izâ hased.",
                    "De ki: Yarattığı şeylerin şerrinden, karanlığı çöktüğü zaman gecenin şerrinden, düğümlere üfleyenlerin "
                            + "şerrinden ve kıskandığı vakit kıskanç kişinin şerrinden sabah aydınlığının Rabbine sığınırım."
            ),
            new EzberKaydi(
                    "ikra_114_nas.mp3",
                    "Nâs Sûresi",
                    "114. Sûre · 6 Âyet · Muavvizeteyn",
                    114, 0,
                    "قُلْ أَعُوذُ بِرَبِّ النَّاسِ ۝ مَلِكِ النَّاسِ ۝ إِلٰهِ النَّاسِ ۝ مِنْ شَرِّ الْوَسْوَاسِ الْخَنَّاسِ ۝ "
                            + "الَّذِي يُوَسْوِسُ فِي صُدُورِ النَّاسِ ۝ مِنَ الْجِنَّةِ وَالنَّاسِ",
                    "Bismillâhirrahmânirrahîm. Kul eûzü bi-Rabbi'n-nâs. Meliki'n-nâs. İlâhi'n-nâs. Min şerri'l-vesvâsi'l-hannâs. "
                            + "Ellezî yüvesvisü fî sudûri'n-nâs. Mine'l-cinneti ve'n-nâs.",
                    "De ki: İnsanların kalplerine vesvese veren sinsi vesvesecinin şerrinden —o ki cinlerden de olur, "
                            + "insanlardan da— insanların Rabbine, insanların Melik'ine, insanların İlâh'ına sığınırım."
            ),
    };

    private static final EzanKaydi[] CEVRIMDISI_MEALLER = {
            new EzanKaydi("meal_ahmet_deniz_001.mp3",
                    "Fâtiha Sûresi Türkçe Meali",
                    "Seslendiren: Ahmet Deniz · Çevrimdışı Paket"),
            new EzanKaydi("meal_ahmet_deniz_112.mp3",
                    "İhlâs Sûresi Türkçe Meali",
                    "Seslendiren: Ahmet Deniz · Çevrimdışı Paket"),
            new EzanKaydi("meal_mehmet_emin_ay_001.mp3",
                    "Fâtiha Sûresi Türkçe Meali",
                    "Seslendiren: Mehmet Emin Ay · Çevrimdışı Paket"),
    };

    private static final int[] TEKRAR_DEGERLERI = {1, 3, 7, -1};
    private static final String[] TEKRAR_ETIKETLERI = {
            "1× Tek Sefer",
            "3× Ezber Tekrarı",
            "7× Pekiştirme",
            "∞ Sürekli"
    };

    private EzanStudyo() {}

    private static SharedPreferences sp(Context c) {
        return c.getSharedPreferences("secde_ezber", Context.MODE_PRIVATE);
    }

    public static int ezberlenenSayisi(Context c) {
        SharedPreferences p = sp(c);
        int n = 0;
        for (EzberKaydi e : EZBER_LISTESI) {
            if (p.getBoolean("ezber_" + e.dosya, false)) n++;
        }
        return n;
    }

    public static void sayfaAc(final DurumAktivitesi a) {
        a.guvenli("EzanStudyo", () -> sayfaAcIc(a));
    }

    private static void sayfaAcIc(final DurumAktivitesi a) {
        final TemaMotoru.Durum tm = TemaMotoru.aktif(a);
        final SharedPreferences p = sp(a);
        final Handler zamanlayici = new Handler(Looper.getMainLooper());

        // Çalma durumu
        final MediaPlayer[] oynatici = {null};
        final String[] aktifDosya = {null};
        final String[] aktifBaslik = {""};
        final boolean[] aktifDongulu = {false};
        final boolean[] duraklatildi = {false};
        final int[] seciliTekrar = {p.getInt("tekrar_modu", 3)};
        final int[] mevcutTur = {1};
        final List<Runnable> satirYenileyiciler = new ArrayList<>();

        final LinearLayout sutun = a.sutun();
        sutun.addView(metin(a, tm,
                "Tüm kayıtlar %100 çevrimdışı çalışır; internet kotası harcamaz. "
                        + "Namaz sûrelerini tekrar döngüsüyle dinleyerek kolayca ezberleyebilirsiniz.",
                13, tm.soluk, false));
        a.bosluk(sutun, 10);

        // ----------------------------------------------------------------
        // Canlı Stüdyo Çalar Çubuğu (Çalma başladığında görünür)
        // ----------------------------------------------------------------
        final LinearLayout calarKart = kart(a, tm);
        calarKart.setVisibility(View.GONE);

        LinearLayout calarUst = new LinearLayout(a);
        calarUst.setOrientation(LinearLayout.HORIZONTAL);
        calarUst.setGravity(Gravity.CENTER_VERTICAL);

        LinearLayout calarBilgi = new LinearLayout(a);
        calarBilgi.setOrientation(LinearLayout.VERTICAL);
        final TextView calarBaslik = metin(a, tm, "", 15, tm.metin, true);
        final TextView calarAlt = metin(a, tm, "", 12, tm.vurgu, false);
        calarBilgi.addView(calarBaslik);
        calarBilgi.addView(calarAlt);
        calarUst.addView(calarBilgi, new LinearLayout.LayoutParams(0, -2, 1f));

        final TextView duraklatDugme = yuvarlakSimgeDugmesi(a, tm, "⏸");
        final TextView durdurDugme = yuvarlakSimgeDugmesi(a, tm, "⏹");
        calarUst.addView(duraklatDugme);
        calarUst.addView(durdurDugme);
        calarKart.addView(calarUst);
        a.bosluk(calarKart, 8);

        final FrameLayout sureDis = new FrameLayout(a);
        GradientDrawable sureDisArka = new GradientDrawable();
        sureDisArka.setCornerRadius(a.dp(4));
        sureDisArka.setColor(tm.acik ? 0x2014211C : 0x28FFFFFF);
        sureDis.setBackground(sureDisArka);

        final View sureIc = new View(a);
        GradientDrawable sureIcArka = new GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT,
                new int[]{tm.vurgu, tm.ana});
        sureIcArka.setCornerRadius(a.dp(4));
        sureIc.setBackground(sureIcArka);
        sureDis.addView(sureIc, new FrameLayout.LayoutParams(0, a.dp(6)));
        calarKart.addView(sureDis, new LinearLayout.LayoutParams(-1, a.dp(6)));

        sutun.addView(calarKart);

        final Runnable tumSatirlariYenile = () -> {
            for (Runnable r : satirYenileyiciler) r.run();
        };

        final Runnable[] sureTakip = new Runnable[1];
        sureTakip[0] = () -> {
            MediaPlayer mp = oynatici[0];
            if (mp == null || aktifDosya[0] == null) return;
            try {
                int gecen = Math.max(0, mp.getCurrentPosition());
                int toplam = Math.max(1, mp.getDuration());
                int gen = sureDis.getWidth();
                if (gen > 0) {
                    FrameLayout.LayoutParams lp = (FrameLayout.LayoutParams) sureIc.getLayoutParams();
                    lp.width = Math.round(gen * Math.min(1f, gecen / (float) toplam));
                    sureIc.setLayoutParams(lp);
                }
                String zamanMetni = sureBicimle(gecen) + " / " + sureBicimle(toplam);
                String turMetni;
                if (!aktifDongulu[0] || seciliTekrar[0] == 1) {
                    turMetni = "Çevrimdışı Stüdyo  ·  " + zamanMetni;
                } else if (seciliTekrar[0] < 0) {
                    turMetni = "∞ Sürekli Döngü (" + mevcutTur[0] + ". okuma)  ·  " + zamanMetni;
                } else {
                    turMetni = "Tekrar: " + mevcutTur[0] + " / " + seciliTekrar[0] + "  ·  " + zamanMetni;
                }
                calarAlt.setText(turMetni);
            } catch (Throwable ignored) {
            }
            if (!duraklatildi[0] && oynatici[0] != null) {
                zamanlayici.postDelayed(sureTakip[0], 250L);
            }
        };

        final Runnable tamamenDurdur = () -> {
            zamanlayici.removeCallbacksAndMessages(null);
            aktifDosya[0] = null;
            duraklatildi[0] = false;
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
            calarKart.setVisibility(View.GONE);
            tumSatirlariYenile.run();
        };

        duraklatDugme.setOnClickListener(v -> {
            v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            MediaPlayer mp = oynatici[0];
            if (mp == null) return;
            try {
                if (duraklatildi[0]) {
                    mp.start();
                    duraklatildi[0] = false;
                    duraklatDugme.setText("⏸");
                    calarBaslik.setText("▶ " + aktifBaslik[0]);
                    zamanlayici.post(sureTakip[0]);
                } else if (mp.isPlaying()) {
                    mp.pause();
                    duraklatildi[0] = true;
                    duraklatDugme.setText("▶");
                    calarBaslik.setText("❚❚ " + aktifBaslik[0]);
                }
                tumSatirlariYenile.run();
            } catch (Throwable ignored) {
            }
        });

        durdurDugme.setOnClickListener(v -> {
            v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            tamamenDurdur.run();
        });

        final ParcaBaslatici parcaBaslat = (dosya, baslik, dongulu) -> {
            if (dosya.equals(aktifDosya[0])) {
                tamamenDurdur.run();
                return;
            }
            tamamenDurdur.run();
            if (TilavetServisi.caliyor()) {
                TilavetServisi.komut(a, TilavetServisi.DURAKLAT);
            }
            try {
                MediaPlayer mp = new MediaPlayer();
                mp.setAudioAttributes(new AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build());

                AssetFileDescriptor afd = Varlik.flutterSes(a, "assets/audio/" + dosya);
                if (afd != null) {
                    mp.setDataSource(afd.getFileDescriptor(), afd.getStartOffset(), afd.getLength());
                    afd.close();
                } else {
                    String dizin = System.getProperty("secde.flutter.dizin");
                    File yedek = dizin == null ? null : new File(dizin, "assets/audio/" + dosya);
                    if (yedek != null && yedek.isFile()) {
                        mp.setDataSource(yedek.getAbsolutePath());
                    } else {
                        mp.release();
                        Toast.makeText(a, "Ses dosyası bulunamadı: " + dosya, Toast.LENGTH_SHORT).show();
                        return;
                    }
                }

                oynatici[0] = mp;
                aktifDosya[0] = dosya;
                aktifBaslik[0] = baslik;
                aktifDongulu[0] = dongulu;
                duraklatildi[0] = false;
                mevcutTur[0] = 1;

                calarKart.setVisibility(View.VISIBLE);
                calarBaslik.setText("▶ " + baslik);
                calarAlt.setText("Hazırlanıyor…");
                duraklatDugme.setText("⏸");
                tumSatirlariYenile.run();

                mp.setOnPreparedListener(m -> {
                    m.start();
                    zamanlayici.post(sureTakip[0]);
                    tumSatirlariYenile.run();
                });
                mp.setOnCompletionListener(m -> {
                    int hedefTur = aktifDongulu[0] ? seciliTekrar[0] : 1;
                    if (hedefTur < 0 || mevcutTur[0] < hedefTur) {
                        mevcutTur[0]++;
                        try {
                            m.seekTo(0);
                            m.start();
                            zamanlayici.post(sureTakip[0]);
                            return;
                        } catch (Throwable ignored) {
                        }
                    }
                    tamamenDurdur.run();
                });
                mp.setOnErrorListener((m, w, ex) -> {
                    tamamenDurdur.run();
                    Toast.makeText(a, "Ses oynatılamadı.", Toast.LENGTH_SHORT).show();
                    return true;
                });
                mp.prepareAsync();
            } catch (Throwable t) {
                tamamenDurdur.run();
                Toast.makeText(a, "Ses açılamadı.", Toast.LENGTH_SHORT).show();
            }
        };

        // ----------------------------------------------------------------
        // BÖLÜM 1 · Ezan ve İftitah Sesleri Önizleme
        // ----------------------------------------------------------------
        TextView bolum1Baslik = metin(a, tm, "EZAN VE İFTİTAH SESLERİ ÖNİZLEME (ÇEVRİMDIŞI)", 12, tm.vurgu, true);
        bolum1Baslik.setPadding(a.dp(4), a.dp(2), 0, a.dp(8));
        sutun.addView(bolum1Baslik);

        LinearLayout ezanKart = kart(a, tm);
        ezanKart.setPadding(a.dp(12), a.dp(8), a.dp(12), a.dp(8));
        for (int i = 0; i < EZAN_LISTESI.length; i++) {
            final EzanKaydi ek = EZAN_LISTESI[i];
            ezanKart.addView(onizlemeSatiri(a, tm, ek, aktifDosya, duraklatildi, satirYenileyiciler, parcaBaslat));
            if (i < EZAN_LISTESI.length - 1) {
                View cizgi = new View(a);
                cizgi.setBackgroundColor(tm.acik ? 0x1814211C : 0x1EFFFFFF);
                ezanKart.addView(cizgi, new LinearLayout.LayoutParams(-1, 1));
            }
        }
        sutun.addView(ezanKart);

        // ----------------------------------------------------------------
        // BÖLÜM 2 · Namaz Sûreleri & Âyetü'l-Kürsî Ezber Modu (Tekrar Döngülü)
        // ----------------------------------------------------------------
        a.bosluk(sutun, 6);
        TextView bolum2Baslik = metin(a, tm, "NAMAZ SÛRELERİ & ÂYETÜ'L-KÜRSÎ EZBER MODU", 12, tm.vurgu, true);
        bolum2Baslik.setPadding(a.dp(4), a.dp(4), 0, a.dp(8));
        sutun.addView(bolum2Baslik);

        // Ezber ilerleme + Tekrar döngüsü seçici kartı
        LinearLayout ezberKontrolKart = kart(a, tm);
        final TextView ezberIlerlemeMetni = metin(a, tm, "", 15, tm.metin, true);
        ezberKontrolKart.addView(ezberIlerlemeMetni);

        final FrameLayout ezberBarDis = new FrameLayout(a);
        GradientDrawable ebDisArka = new GradientDrawable();
        ebDisArka.setCornerRadius(a.dp(5));
        ebDisArka.setColor(tm.acik ? 0x2014211C : 0x28FFFFFF);
        ezberBarDis.setBackground(ebDisArka);

        final View ezberBarIc = new View(a);
        GradientDrawable ebIcArka = new GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT,
                new int[]{tm.iyi, tm.ana});
        ebIcArka.setCornerRadius(a.dp(5));
        ezberBarIc.setBackground(ebIcArka);
        ezberBarDis.addView(ezberBarIc, new FrameLayout.LayoutParams(0, a.dp(7)));
        LinearLayout.LayoutParams ebLp = new LinearLayout.LayoutParams(-1, a.dp(7));
        ebLp.setMargins(0, a.dp(6), 0, a.dp(12));
        ezberKontrolKart.addView(ezberBarDis, ebLp);

        final Runnable ezberOzetiGuncelle = () -> {
            int tamam = ezberlenenSayisi(a);
            int toplam = EZBER_LISTESI.length;
            ezberIlerlemeMetni.setText("Ezber Durumu: " + tamam + " / " + toplam + " Tamamlandı");
            ezberBarDis.post(() -> {
                int gen = ezberBarDis.getWidth();
                if (gen > 0) {
                    FrameLayout.LayoutParams lp = (FrameLayout.LayoutParams) ezberBarIc.getLayoutParams();
                    lp.width = Math.round(gen * (tamam / (float) toplam));
                    ezberBarIc.setLayoutParams(lp);
                }
            });
        };
        ezberOzetiGuncelle.run();

        ezberKontrolKart.addView(metin(a, tm, "TEKRAR DÖNGÜSÜ SEÇİMİ", 11, tm.vurgu, true));
        a.bosluk(ezberKontrolKart, 4);

        HorizontalScrollView tekrarYatay = new HorizontalScrollView(a);
        tekrarYatay.setHorizontalScrollBarEnabled(false);
        tekrarYatay.setOverScrollMode(View.OVER_SCROLL_NEVER);
        final LinearLayout tekrarCipler = new LinearLayout(a);
        tekrarCipler.setOrientation(LinearLayout.HORIZONTAL);
        tekrarYatay.addView(tekrarCipler);
        ezberKontrolKart.addView(tekrarYatay);

        final Runnable[] tekrarCiz = new Runnable[1];
        tekrarCiz[0] = () -> {
            tekrarCipler.removeAllViews();
            for (int i = 0; i < TEKRAR_DEGERLERI.length; i++) {
                final int deger = TEKRAR_DEGERLERI[i];
                boolean sec = (seciliTekrar[0] == deger);
                TextView cip = metin(a, tm, TEKRAR_ETIKETLERI[i], 13,
                        sec ? tm.birincilDugmeYaziRengi() : tm.metin, true);
                cip.setShadowLayer(0, 0, 0, 0);
                cip.setPadding(a.dp(13), a.dp(8), a.dp(13), a.dp(8));
                cip.setBackground(tm.cipArkaPlani(a, sec, 16));
                LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-2, -2);
                lp.setMargins(0, 0, a.dp(8), 0);
                cip.setLayoutParams(lp);
                cip.setClickable(true);
                cip.setOnClickListener(v -> {
                    v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
                    seciliTekrar[0] = deger;
                    p.edit().putInt("tekrar_modu", deger).apply();
                    tekrarCiz[0].run();
                });
                tekrarCipler.addView(cip);
            }
        };
        tekrarCiz[0].run();
        sutun.addView(ezberKontrolKart);

        // 7 Ezber Sûre / Âyet Kartı
        for (final EzberKaydi ez : EZBER_LISTESI) {
            sutun.addView(ezberKartiOlustur(a, tm, p, ez, aktifDosya, duraklatildi,
                    satirYenileyiciler, parcaBaslat, ezberOzetiGuncelle));
        }

        // ----------------------------------------------------------------
        // BÖLÜM 3 · Çevrimdışı Türkçe Meal Ses Önizlemeleri
        // ----------------------------------------------------------------
        a.bosluk(sutun, 6);
        TextView bolum3Baslik = metin(a, tm, "TÜRKÇE SESLİ MEAL ÖNİZLEMELERİ (ÇEVRİMDIŞI)", 12, tm.vurgu, true);
        bolum3Baslik.setPadding(a.dp(4), a.dp(4), 0, a.dp(8));
        sutun.addView(bolum3Baslik);

        LinearLayout mealKart = kart(a, tm);
        mealKart.setPadding(a.dp(12), a.dp(8), a.dp(12), a.dp(8));
        for (int i = 0; i < CEVRIMDISI_MEALLER.length; i++) {
            final EzanKaydi mk = CEVRIMDISI_MEALLER[i];
            mealKart.addView(onizlemeSatiri(a, tm, mk, aktifDosya, duraklatildi, satirYenileyiciler, parcaBaslat));
            if (i < CEVRIMDISI_MEALLER.length - 1) {
                View cizgi = new View(a);
                cizgi.setBackgroundColor(tm.acik ? 0x1814211C : 0x1EFFFFFF);
                mealKart.addView(cizgi, new LinearLayout.LayoutParams(-1, 1));
            }
        }
        sutun.addView(mealKart);

        ScrollView sv = new ScrollView(a);
        sv.setVerticalScrollBarEnabled(false);
        sv.setOverScrollMode(View.OVER_SCROLL_NEVER);
        sv.setClipToPadding(false);
        sv.addView(sutun);
        sv.addOnAttachStateChangeListener(new View.OnAttachStateChangeListener() {
            @Override
            public void onViewAttachedToWindow(View v) {}

            @Override
            public void onViewDetachedFromWindow(View v) {
                tamamenDurdur.run();
            }
        });

        a.altSayfa("Ezan ve Namaz Sûreleri Stüdyosu", sv, "kandil");
    }

    private interface ParcaBaslatici {
        void baslat(String dosya, String baslik, boolean dongulu);
    }

    private static View onizlemeSatiri(final DurumAktivitesi a, final TemaMotoru.Durum tm,
                                       final EzanKaydi kayit, final String[] aktifDosya,
                                       final boolean[] duraklatildi, final List<Runnable> yenileyiciler,
                                       final ParcaBaslatici baslatici) {
        LinearLayout satir = new LinearLayout(a);
        satir.setOrientation(LinearLayout.HORIZONTAL);
        satir.setGravity(Gravity.CENTER_VERTICAL);
        satir.setPadding(a.dp(4), a.dp(10), a.dp(4), a.dp(10));

        LinearLayout yaziKabi = new LinearLayout(a);
        yaziKabi.setOrientation(LinearLayout.VERTICAL);
        final TextView baslikTv = metin(a, tm, kayit.baslik, 15, tm.metin, true);
        final TextView altTv = metin(a, tm, kayit.altBaslik, 12, tm.soluk, false);
        yaziKabi.addView(baslikTv);
        yaziKabi.addView(altTv);
        satir.addView(yaziKabi, new LinearLayout.LayoutParams(0, -2, 1f));

        final TextView oynatDugme = metin(a, tm, "▶ Dinle", 13, tm.birincilDugmeYaziRengi(), true);
        oynatDugme.setShadowLayer(0, 0, 0, 0);
        oynatDugme.setGravity(Gravity.CENTER);
        oynatDugme.setPadding(a.dp(14), a.dp(8), a.dp(14), a.dp(8));

        Runnable guncelle = () -> {
            boolean buAktif = kayit.dosya.equals(aktifDosya[0]);
            if (buAktif) {
                oynatDugme.setText(duraklatildi[0] ? "❚❚ Durakladı" : "⏹ Durdur");
                oynatDugme.setBackground(tm.ikincilDugme(a, 14));
                oynatDugme.setTextColor(tm.vurgu);
                baslikTv.setTextColor(tm.vurgu);
            } else {
                oynatDugme.setText("▶ Dinle");
                oynatDugme.setBackground(tm.birincilDugme(a, 14));
                oynatDugme.setTextColor(tm.birincilDugmeYaziRengi());
                baslikTv.setTextColor(tm.metin);
            }
        };
        yenileyiciler.add(guncelle);
        guncelle.run();

        satir.setClickable(true);
        a.basmaEfekti(satir);
        satir.setOnClickListener(v -> {
            v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            baslatici.baslat(kayit.dosya, kayit.baslik, false);
        });
        return satir;
    }

    private static View ezberKartiOlustur(final DurumAktivitesi a, final TemaMotoru.Durum tm,
                                          final SharedPreferences p, final EzberKaydi ez,
                                          final String[] aktifDosya, final boolean[] duraklatildi,
                                          final List<Runnable> yenileyiciler, final ParcaBaslatici baslatici,
                                          final Runnable ezberOzetiGuncelle) {
        LinearLayout k = kart(a, tm);

        // Üst satır: Başlık + Oynat düğmesi
        LinearLayout ust = new LinearLayout(a);
        ust.setOrientation(LinearLayout.HORIZONTAL);
        ust.setGravity(Gravity.CENTER_VERTICAL);

        LinearLayout baslikSutun = new LinearLayout(a);
        baslikSutun.setOrientation(LinearLayout.VERTICAL);
        final TextView adTv = metin(a, tm, ez.baslik, 16, tm.metin, true);
        TextView altTv = metin(a, tm, ez.altBaslik, 12, tm.soluk, false);
        baslikSutun.addView(adTv);
        baslikSutun.addView(altTv);
        ust.addView(baslikSutun, new LinearLayout.LayoutParams(0, -2, 1f));

        final TextView calDugme = metin(a, tm, "▶ Tekrarlı Dinle", 13, tm.birincilDugmeYaziRengi(), true);
        calDugme.setShadowLayer(0, 0, 0, 0);
        calDugme.setGravity(Gravity.CENTER);
        calDugme.setPadding(a.dp(14), a.dp(9), a.dp(14), a.dp(9));
        calDugme.setClickable(true);
        a.basmaEfekti(calDugme);
        calDugme.setOnClickListener(v -> {
            v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            baslatici.baslat(ez.dosya, ez.baslik, true);
        });
        ust.addView(calDugme);
        k.addView(ust);

        Runnable calGuncelle = () -> {
            boolean buAktif = ez.dosya.equals(aktifDosya[0]);
            if (buAktif) {
                calDugme.setText(duraklatildi[0] ? "❚❚ Durakladı" : "⏹ Durdur");
                calDugme.setBackground(tm.ikincilDugme(a, 14));
                calDugme.setTextColor(tm.vurgu);
                adTv.setTextColor(tm.vurgu);
            } else {
                calDugme.setText("▶ Dinle");
                calDugme.setBackground(tm.birincilDugme(a, 14));
                calDugme.setTextColor(tm.birincilDugmeYaziRengi());
                adTv.setTextColor(tm.metin);
            }
        };
        yenileyiciler.add(calGuncelle);
        calGuncelle.run();

        // Açılır-kapanır Arapça hat + Türkçe okunuş + Diyanet meali bölümü
        final LinearLayout detayKabi = new LinearLayout(a);
        detayKabi.setOrientation(LinearLayout.VERTICAL);
        detayKabi.setVisibility(View.GONE);
        detayKabi.setPadding(0, a.dp(10), 0, a.dp(2));

        String[] kuranMetin = kuranMetniniCek(a, ez);
        TextView arTv = new TextView(a);
        arTv.setText(kuranMetin[0]);
        arTv.setTypeface(Varlik.kuranYazisi(a));
        arTv.setTextSize(TypedValue.COMPLEX_UNIT_SP, TemaMotoru.olcekliSp(a, 24));
        arTv.setTextColor(tm.metin);
        arTv.setLineSpacing(0, 1.48f);
        arTv.setGravity(Gravity.RIGHT);
        arTv.setPadding(a.dp(12), a.dp(10), a.dp(12), a.dp(10));
        GradientDrawable arArka = new GradientDrawable();
        arArka.setCornerRadius(a.dp(14));
        arArka.setColor(tm.acik ? 0x101E6B55 : 0x24000000);
        arArka.setStroke(1, tm.acik ? 0x221E6B55 : 0x28FFFFFF);
        arTv.setBackground(arArka);
        detayKabi.addView(arTv);

        TextView okTv = metin(a, tm, "Okunuşu: " + ez.okunus, 13, tm.vurgu, false);
        okTv.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.ITALIC));
        okTv.setPadding(0, a.dp(8), 0, a.dp(4));
        detayKabi.addView(okTv);

        detayKabi.addView(metin(a, tm, "Meali: " + kuranMetin[1], 13, tm.soluk, false));

        // Alt eylem çubuğu: Metin & Meal Aç/Kapat  |  Ezberledim ✓
        LinearLayout altEylemler = new LinearLayout(a);
        altEylemler.setOrientation(LinearLayout.HORIZONTAL);
        LinearLayout.LayoutParams aeLp = new LinearLayout.LayoutParams(-1, -2);
        aeLp.setMargins(0, a.dp(10), 0, 0);
        altEylemler.setLayoutParams(aeLp);

        final TextView acKapatDugme = metin(a, tm, "Metin & Meal ▾", 13, tm.metin, true);
        acKapatDugme.setShadowLayer(0, 0, 0, 0);
        acKapatDugme.setGravity(Gravity.CENTER);
        acKapatDugme.setMinHeight(a.dp(38));
        acKapatDugme.setPadding(a.dp(12), a.dp(7), a.dp(12), a.dp(7));
        acKapatDugme.setBackground(tm.ikincilDugme(a, 12));
        acKapatDugme.setClickable(true);
        acKapatDugme.setOnClickListener(v -> {
            v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            boolean acik = detayKabi.getVisibility() == View.VISIBLE;
            detayKabi.setVisibility(acik ? View.GONE : View.VISIBLE);
            acKapatDugme.setText(acik ? "Metin & Meal ▾" : "Metni Gizle ▴");
        });
        LinearLayout.LayoutParams solLp = new LinearLayout.LayoutParams(0, -2, 1f);
        solLp.setMargins(0, 0, a.dp(5), 0);
        altEylemler.addView(acKapatDugme, solLp);

        final String anahtar = "ezber_" + ez.dosya;
        final TextView ezberDugme = metin(a, tm, "", 13, tm.metin, true);
        ezberDugme.setShadowLayer(0, 0, 0, 0);
        ezberDugme.setGravity(Gravity.CENTER);
        ezberDugme.setMinHeight(a.dp(38));
        ezberDugme.setPadding(a.dp(12), a.dp(7), a.dp(12), a.dp(7));
        ezberDugme.setClickable(true);
        a.basmaEfekti(ezberDugme);

        final Runnable ezberDurumCiz = () -> {
            boolean tamam = p.getBoolean(anahtar, false);
            GradientDrawable g = new GradientDrawable();
            g.setCornerRadius(a.dp(12));
            if (tamam) {
                ezberDugme.setText("Ezberledim ✓");
                ezberDugme.setTextColor(tm.iyi);
                g.setColor(tm.acik ? 0x221B7A50 : 0x332E9E6B);
                g.setStroke(Math.max(1, a.dp(1)), tm.iyi);
            } else {
                ezberDugme.setText("○ Ezberledim");
                ezberDugme.setTextColor(tm.soluk);
                g.setColor(tm.acik ? 0x1214211C : 0x1EFFFFFF);
                g.setStroke(1, tm.acik ? 0x3314211C : 0x38FFFFFF);
            }
            ezberDugme.setBackground(g);
        };
        ezberDurumCiz.run();

        ezberDugme.setOnClickListener(v -> {
            boolean yeni = !p.getBoolean(anahtar, false);
            p.edit().putBoolean(anahtar, yeni).apply();
            v.performHapticFeedback(yeni ? HapticFeedbackConstants.LONG_PRESS : HapticFeedbackConstants.CLOCK_TICK);
            ezberDurumCiz.run();
            ezberOzetiGuncelle.run();
        });

        LinearLayout.LayoutParams sagLp = new LinearLayout.LayoutParams(0, -2, 1f);
        sagLp.setMargins(a.dp(5), 0, 0, 0);
        altEylemler.addView(ezberDugme, sagLp);

        k.addView(altEylemler);
        k.addView(detayKabi);
        return k;
    }

    private static String[] kuranMetniniCek(DurumAktivitesi a, EzberKaydi ez) {
        try {
            List<Kuran.Ayet> ayetler = Kuran.ayetler(a, ez.sureNo);
            if (ayetler != null && !ayetler.isEmpty()) {
                if (ez.tekAyetNo > 0) {
                    if (ez.tekAyetNo <= ayetler.size()) {
                        Kuran.Ayet ay = ayetler.get(ez.tekAyetNo - 1);
                        if (ay.arapca != null && !ay.arapca.isEmpty()) {
                            return new String[]{
                                    ay.arapca,
                                    (ay.meal != null && !ay.meal.isEmpty()) ? ay.meal : ez.yedekMeal
                            };
                        }
                    }
                } else {
                    StringBuilder ar = new StringBuilder();
                    StringBuilder tr = new StringBuilder();
                    if (ez.sureNo != 1 && ez.sureNo != 9) {
                        ar.append("بِسْمِ اللّٰهِ الرَّحْمٰنِ الرَّحِيمِ\n");
                    }
                    for (Kuran.Ayet ay : ayetler) {
                        if (ar.length() > 0 && ar.charAt(ar.length() - 1) != '\n') ar.append(" ۝ ");
                        ar.append(ay.arapca);
                        if (tr.length() > 0) tr.append(" ");
                        tr.append("(").append(ay.no).append(") ").append(ay.meal);
                    }
                    if (ar.length() > 0) {
                        return new String[]{ar.toString(), tr.length() > 0 ? tr.toString() : ez.yedekMeal};
                    }
                }
            }
        } catch (Throwable ignored) {
        }
        return new String[]{ez.yedekArapca, ez.yedekMeal};
    }

    private static TextView yuvarlakSimgeDugmesi(DurumAktivitesi a, TemaMotoru.Durum tm, String simge) {
        TextView t = metin(a, tm, simge, 16, tm.birincilDugmeYaziRengi(), true);
        t.setShadowLayer(0, 0, 0, 0);
        t.setGravity(Gravity.CENTER);
        GradientDrawable g = tm.birincilDugme(a, 20);
        g.setShape(GradientDrawable.OVAL);
        t.setBackground(g);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(a.dp(40), a.dp(40));
        lp.setMargins(a.dp(6), 0, 0, 0);
        t.setLayoutParams(lp);
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

    private static String sureBicimle(int ms) {
        int topSn = Math.max(0, ms / 1000);
        return String.format(Locale.ROOT, "%02d:%02d", topSn / 60, topSn % 60);
    }
}
