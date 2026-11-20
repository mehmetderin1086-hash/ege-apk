package com.mehmetderin.secde_vakti.saglik;

import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.LinearGradient;
import android.graphics.Outline;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RadialGradient;
import android.graphics.RectF;
import android.graphics.Shader;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.MediaStore;
import android.text.Layout;
import android.text.StaticLayout;
import android.text.TextPaint;
import android.text.TextUtils;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.HapticFeedbackConstants;
import android.view.View;
import android.view.ViewOutlineProvider;
import android.widget.FrameLayout;
import android.widget.HorizontalScrollView;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStream;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Date;
import java.util.List;

/**
 * Yüksek Çözünürlüklü (1080×1350 Gönderi & 1080×1920 Hikâye) Saf Canvas Paylaşım Kartı Stüdyosu.
 * 4 şablon:
 *   0 = Günün Vakitleri
 *   1 = Günün Âyeti
 *   2 = Hadîs-i Şerîf & Duâ
 *   3 = Cuma & Kandil Tebriği
 */
public final class PaylasimKarti {

    public static final int SABLON_VAKITLER = 0;
    public static final int SABLON_AYET = 1;
    public static final int SABLON_HADIS_DUA = 2;
    public static final int SABLON_CUMA_KANDIL = 3;

    private static final String BESMELE = "بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ";
    private static final String SALAVAT = "اللَّهُمَّ صَلِّ عَلَىٰ سَيِّدِنَا مُحَمَّدٍ وَعَلَىٰ آلِ سَيِّدِنَا مُحَمَّدٍ";

    /** Yerleşik âyet yedekleri ve DailyVerses.json kaynaklarına karşılık gelen Arapça metinler. */
    private static final String[][] YEDEK_AYETLER = {
            {"فَإِنَّ مَعَ الْعُسْرِ يُسْرًا", "Şüphesiz zorlukla beraber bir kolaylık vardır.", "İnşirah 94/6"},
            {"أَلَا بِذِكْرِ اللَّهِ تَطْمَئِنُّ الْقُلُوبُ", "Bilesiniz ki kalpler ancak Allah'ı anmakla huzur bulur.", "Ra'd 13/28"},
            {"لَا يُكَلِّفُ اللَّهُ نَفْسًا إِلَّا وُسْعَهَا", "Allah hiçbir kimseye gücünün üstünde bir şey yüklemez.", "Bakara 2/286"},
            {"وَقَالَ رَبُّكُمُ ادْعُونِي أَسْتَجِبْ لَكُمْ", "Rabbiniz şöyle buyurdu: Bana duâ edin ki size karşılık vereyim.", "Mü'min 40/60"},
            {"إِنَّمَا يُوَفَّى الصَّابِرُونَ أَجْرَهُمْ بِغَيْرِ حِسَابٍ", "Sabredenlere mükâfatları hesapsız ödenecektir.", "Zümer 39/10"},
            {"وَمَنْ يَتَوَكَّلْ عَلَى اللَّهِ فَهُوَ حَسْبُهُ", "Kim Allah'a tevekkül ederse, O ona yeter.", "Talâk 65/3"},
            {"فَاذْكُرُونِي أَذْكُرْكُمْ وَاشْكُرُوا لِي وَلَا تَكْفُرُونِ", "Beni anın ki ben de sizi anayım. Bana şükredin, sakın nankörlük etmeyin.", "Bakara 2/152"},
            {"رَبِّ اشْرَحْ لِي صَدْرِي وَيَسِّرْ لِي أَمْرِي", "Rabbim! Gönlüme genişlik ver, işimi bana kolaylaştır.", "Tâhâ 20/25-26"},
            {"إِنَّ اللَّهَ مَعَ الصَّابِرِينَ", "Ey îmân edenler! Sabır ve namazla Allah'tan yardım isteyin. Muhakkak ki Allah sabredenlerle beraberdir.", "Bakara 2/153"},
            {"لَا تَقْنَطُوا مِنْ رَحْمَةِ اللَّهِ", "Allah'ın rahmetinden ümit kesmeyin. Şüphesiz Allah bütün günahları bağışlar.", "Zümer 39/53"},
            {"رَبِّ اجْعَلْنِي مُقِيمَ الصَّلَاةِ وَمِنْ ذُرِّيَّتِي", "Rabbim! Beni ve soyumdan gelenleri namazı devamlı kılanlardan eyle.", "İbrâhîm 14/40"},
            {"إِنَّمَا الْمُؤْمِنُونَ إِخْوَةٌ فَأَصْلِحُوا بَيْنَ أَخَوَيْكُمْ", "Mü'minler ancak kardeştir; öyleyse kardeşlerinizin arasını düzeltin.", "Hucurât 49/10"}
    };

    /** Özenle seçilmiş 12 sahîh Hadîs-i Şerîf ve Nebevî Duâ koleksiyonu. */
    private static final String[][] HADIS_VE_DUALAR = {
            {"يَسِّرُوا وَلَا تُعَسِّرُوا وَبَشِّرُوا وَلَا تُنَفِّرُوا",
                    "Kolaylaştırınız, güçleştirmeyiniz; müjdeleyiniz, nefret ettirmeyiniz.",
                    "Buhârî, İlim 11 · Müslim, Cihâd 6"},
            {"إِنَّمَا الْأَعْمَالُ بِالنِّيَّاتِ",
                    "Ameller niyetlere göredir. Herkese ancak niyet ettiği şey vardır.",
                    "Buhârî, Bed'ü'l-Vahy 1"},
            {"خَيْرُكُمْ مَنْ تَعَلَّمَ الْقُرْآنَ وَعَلَّمَهُ",
                    "Sizin en hayırlınız, Kur'ân'ı öğrenen ve öğreteninizdir.",
                    "Buhârî, Fezâilü'l-Kur'ân 21"},
            {"إِنَّ اللَّهَ لَا يَنْظُرُ إِلَىٰ صُوَرِكُمْ وَأَمْوَالِكُمْ وَلَٰكِنْ يَنْظُرُ إِلَىٰ قُلُوبِكُمْ وَأَعْمَالِكُمْ",
                    "Allah sizin sûretlerinize ve mallarınıza bakmaz; ancak kalplerinize ve amellerinize bakar.",
                    "Müslim, Birr 34"},
            {"الْكَلِمَةُ الطَّيِّبَةُ صَدَقَةٌ",
                    "Güzel söz sadakadır. Kardeşinin yüzüne tebessüm etmen de senin için sadakadır.",
                    "Buhârî, Edeb 34 · Tirmizî, Birr 36"},
            {"يَا مُقَلِّبَ الْقُلُوبِ ثَبِّتْ قَلْبِي عَلَىٰ دِينِكَ",
                    "Ey kalpleri hâlden hâle çeviren Allah'ım! Kalbimi dînin üzere sâbit kıl.",
                    "Tirmizî, Daavât 89"},
            {"اللَّهُمَّ إِنَّكَ عَفُوٌّ كَرِيمٌ تُحِبُّ الْعَفْوَ فَاعْفُ عَنِّي",
                    "Allah'ım! Şüphesiz Sen çok affedicisin, kerem sâhibisin, affetmeyi seversin; beni de affeyle.",
                    "Tirmizî, Daavât 84"},
            {"اللَّهُمَّ أَعِنِّي عَلَىٰ ذِكْرِكَ وَشُكْرِكَ وَحُسْنِ عِبَادَتِكَ",
                    "Allah'ım! Seni zikretmek, Sana şükretmek ve Sana güzelce ibâdet etmek için bana yardım eyle.",
                    "Ebû Dâvûd, Vitir 26"},
            {"اللَّهُمَّ إِنِّي أَسْأَلُكَ الْهُدَىٰ وَالتُّقَىٰ وَالْعَفَافَ وَالْغِنَىٰ",
                    "Allah'ım! Senden hidâyet, takvâ, iffet ve gönül zenginliği isterim.",
                    "Müslim, Zikir 72"},
            {"مَنْ سَلَكَ طَرِيقًا يَلْتَمِسُ فِيهِ عِلْمًا سَهَّلَ اللَّهُ لَهُ بِهِ طَرِيقًا إِلَى الْجَنَّةِ",
                    "Kim ilim tahsil etmek için bir yola girerse, Allah ona cennete giden yolu kolaylaştırır.",
                    "Müslim, Zikir 39"},
            {"أَحَبُّ الْأَعْمَالِ إِلَى اللَّهِ أَدْوَمُهَا وَإِنْ قَلَّ",
                    "Allah katında amellerin en sevimlisi, az da olsa devamlı olanıdır.",
                    "Buhârî, Rikâk 18 · Müslim, Müsâfirîn 218"},
            {"رَبَّنَا آتِنَا فِي الدُّنْيَا حَسَنَةً وَفِي الْآخِرَةِ حَسَنَةً وَقِنَا عَذَابَ النَّارِ",
                    "Rabbimiz! Bize dünyada da iyilik ver, âhirette de iyilik ver ve bizi ateş azâbından koru.",
                    "Bakara 2/201 · Buhârî, Daavât 55"}
    };

    /** Cuma, Kandil, Ramazan ve Bayram tebriği koleksiyonu. */
    private static final String[][] TEBRIKLER = {
            {SALAVAT,
                    "Cum'amız Mübârek Olsun",
                    "Gönüllerimiz huzurla dolsun, duâlarımız Rahmân katında kabûl bulsun. Hayırlı ve bereketli Cumalar."},
            {BESMELE,
                    "Hayırlı Kandiller — Geceniz Nûr, Duânız Kabûl Olsun",
                    "Bu mübârek gecenin feyzi, rahmeti ve sekîneti hânelerinize ve tüm İslâm âlemine bereket getirsin."},
            {BESMELE,
                    "Ramazan-ı Şerîfiniz Mübârek Olsun",
                    "Evveli rahmet, ortası mağfiret, sonu ebedî kurtuluş olan on bir ayın sultanı gönüllerimize şifâ olsun."},
            {SALAVAT,
                    "Bayramınız Mübârek Olsun",
                    "Sevdiklerinizle bir arada; sağlık, muhabbet, afiyet ve huzur dolu nice mübârek bayramlara erişmeniz duâsıyla."},
            {BESMELE,
                    "Kadir Geceniz Mübârek Olsun",
                    "Bin aydan daha hayırlı olan bu müstesnâ gecede edilen tüm samîmî duâların kabûl olması niyâzıyla."},
            {SALAVAT,
                    "Seher ve Vakit Bereketi Üzerinize Olsun",
                    "Rabbimiz ömrümüze bereket, kalplerimize inşirah, secdelerimize huşû ihsân eylesin."}
    };

    private PaylasimKarti() {}

    /** Paylaşım Kartı Stüdyosu'nu varsayılan (Günün Vakitleri) şablonuyla açar. */
    public static void sayfaAc(DurumAktivitesi a, VakitTakvimi.Takvim t) {
        ozelMetinleAc(a, t, SABLON_VAKITLER, null, null, null);
    }

    /**
     * Kur'ân-ı Kerîm, Duâ veya Manevî Paket ekranlarından özel âyet/duâ/hadîs ile
     * Paylaşım Kartı Stüdyosu'nu önceden doldurulmuş olarak açar.
     */
    public static void ozelMetinleAc(DurumAktivitesi a, VakitTakvimi.Takvim t,
                                     int sablon, String arapca, String turkceMetin, String kaynak) {
        final VakitTakvimi.Takvim takvim = (t != null) ? t : VakitTakvimi.oku(a);
        final TemaMotoru.Durum UI = TemaMotoru.aktif(a);

        // Stüdyo durumu
        final int[] aktifSablon = {Math.max(0, Math.min(3, sablon))};
        final boolean[] hikayeModu = {false};
        final TemaMotoru.Tema[] seciliPalet = {UI.tema};
        final int[] sozIndeksi = {gununBaslangicIndeksi()};
        final String[] ozelAr = {bosMu(arapca) ? null : arapca.trim()};
        final String[] ozelTr = {bosMu(turkceMetin) ? null : turkceMetin.trim()};
        final String[] ozelKy = {bosMu(kaynak) ? null : kaynak.trim()};
        final Bitmap[] sonBitmap = {null};

        final ScrollView sv = new ScrollView(a);
        sv.setPadding(0, 0, 0, 0);
        sv.setVerticalScrollBarEnabled(false);

        final LinearLayout icerik = new LinearLayout(a);
        icerik.setOrientation(LinearLayout.VERTICAL);
        icerik.setPadding(a.dp(16), a.dp(6), a.dp(16), a.dp(32));
        sv.addView(icerik, new ScrollView.LayoutParams(-1, -2));

        // 1. Canlı Kart Önizleme Çerçevesi
        FrameLayout onizlemeSarmal = new FrameLayout(a);
        onizlemeSarmal.setPadding(a.dp(12), a.dp(12), a.dp(12), a.dp(12));
        onizlemeSarmal.setBackground(UI.kartArkaPlani(a));
        LinearLayout.LayoutParams oslp = new LinearLayout.LayoutParams(-1, -2);
        oslp.setMargins(0, 0, 0, a.dp(12));
        onizlemeSarmal.setLayoutParams(oslp);

        final ImageView onizlemeGorsel = new ImageView(a);
        onizlemeGorsel.setAdjustViewBounds(true);
        onizlemeGorsel.setScaleType(ImageView.ScaleType.FIT_CENTER);
        onizlemeGorsel.setMaxHeight(a.dp(420));
        onizlemeGorsel.setContentDescription("Paylaşım Kartı Önizlemesi");
        final float koseR = a.dp(16);
        onizlemeGorsel.setOutlineProvider(new ViewOutlineProvider() {
            @Override
            public void getOutline(View view, Outline outline) {
                outline.setRoundRect(0, 0, view.getWidth(), view.getHeight(), koseR);
            }
        });
        onizlemeGorsel.setClipToOutline(true);
        onizlemeGorsel.setElevation(a.dp(8));

        FrameLayout.LayoutParams ivLp = new FrameLayout.LayoutParams(-1, -2, Gravity.CENTER);
        onizlemeSarmal.addView(onizlemeGorsel, ivLp);
        icerik.addView(onizlemeSarmal);

        // Dinamik kontrol paneli sarmalı
        final LinearLayout kontroller = new LinearLayout(a);
        kontroller.setOrientation(LinearLayout.VERTICAL);
        icerik.addView(kontroller, new LinearLayout.LayoutParams(-1, -2));

        final Runnable[] panelYenile = new Runnable[1];
        final Runnable onizlemeYenile = () -> {
            String[] veri = aktifSablonMetni(a, aktifSablon[0], sozIndeksi[0], ozelAr[0], ozelTr[0], ozelKy[0]);
            Bitmap yeni = kartUret(a, takvim, seciliPalet[0], aktifSablon[0], hikayeModu[0],
                    veri[0], veri[1], veri[2]);
            sonBitmap[0] = yeni;
            onizlemeGorsel.setImageBitmap(yeni);
        };

        panelYenile[0] = () -> {
            kontroller.removeAllViews();
            TemaMotoru.Durum d = TemaMotoru.aktif(a);

            // A) Şablon seçici + Metni Değiştir ↻
            LinearLayout sablonKart = panelKarti(a, d);
            sablonKart.addView(panelBaslik(a, "Kart Şablonu", d));

            String[][] sablonlar = {
                    {"0", "Günün Vakitleri"},
                    {"1", "Günün Âyeti"},
                    {"2", "Hadîs & Duâ"},
                    {"3", "Cuma / Kandil"}
            };
            for (int i = 0; i < sablonlar.length; i += 2) {
                LinearLayout satir = new LinearLayout(a);
                satir.setOrientation(LinearLayout.HORIZONTAL);
                LinearLayout.LayoutParams slp = new LinearLayout.LayoutParams(-1, -2);
                slp.setMargins(0, i == 0 ? a.dp(4) : a.dp(8), 0, 0);
                satir.setLayoutParams(slp);

                for (int j = 0; j < 2; j++) {
                    final int idx = i + j;
                    boolean secili = (aktifSablon[0] == idx);
                    TextView cip = cipDugme(a, d, sablonlar[idx][1], secili, () -> {
                        aktifSablon[0] = idx;
                        onizlemeYenile.run();
                        panelYenile[0].run();
                    });
                    LinearLayout.LayoutParams clp = new LinearLayout.LayoutParams(0, -2, 1f);
                    clp.setMargins(j == 0 ? 0 : a.dp(4), 0, j == 0 ? a.dp(4) : 0, 0);
                    satir.addView(cip, clp);
                }
                sablonKart.addView(satir);
            }

            if (aktifSablon[0] != SABLON_VAKITLER) {
                String degistirEtiket = aktifSablon[0] == SABLON_HADIS_DUA
                        ? "Başka Söz Seç ↻" : "Metni Değiştir ↻";
                TextView degistirBtn = cipDugme(a, d, degistirEtiket, false, () -> {
                    // Özel metin varsa temizleyip koleksiyondaki diğer sözlere geç
                    ozelAr[0] = null;
                    ozelTr[0] = null;
                    ozelKy[0] = null;
                    sozIndeksi[0] = sozIndeksi[0] + 1;
                    onizlemeYenile.run();
                });
                LinearLayout.LayoutParams dlp = new LinearLayout.LayoutParams(-1, -2);
                dlp.setMargins(0, a.dp(10), 0, 0);
                degistirBtn.setLayoutParams(dlp);
                sablonKart.addView(degistirBtn);
            }
            kontroller.addView(sablonKart);

            // B) En-Boy Oranı & 16 Tema Paleti Şeridi
            LinearLayout gorunumKart = panelKarti(a, d);
            gorunumKart.addView(panelBaslik(a, "Boyut & Renk Paleti", d));

            LinearLayout boyutSatir = new LinearLayout(a);
            boyutSatir.setOrientation(LinearLayout.HORIZONTAL);
            LinearLayout.LayoutParams bslp = new LinearLayout.LayoutParams(-1, -2);
            bslp.setMargins(0, a.dp(4), 0, a.dp(12));
            boyutSatir.setLayoutParams(bslp);

            TextView gonderiCip = cipDugme(a, d, "4:5 Gönderi (1080×1350)", !hikayeModu[0], () -> {
                hikayeModu[0] = false;
                onizlemeYenile.run();
                panelYenile[0].run();
            });
            LinearLayout.LayoutParams gLp = new LinearLayout.LayoutParams(0, -2, 1f);
            gLp.setMargins(0, 0, a.dp(4), 0);
            boyutSatir.addView(gonderiCip, gLp);

            TextView hikayeCip = cipDugme(a, d, "9:16 Hikâye (1080×1920)", hikayeModu[0], () -> {
                hikayeModu[0] = true;
                onizlemeYenile.run();
                panelYenile[0].run();
            });
            LinearLayout.LayoutParams hLp = new LinearLayout.LayoutParams(0, -2, 1f);
            hLp.setMargins(a.dp(4), 0, 0, 0);
            boyutSatir.addView(hikayeCip, hLp);
            gorunumKart.addView(boyutSatir);

            TextView paletEtiket = new TextView(a);
            paletEtiket.setText("Kart Renk Teması (" + seciliPalet[0].ad + ")");
            paletEtiket.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12.5f);
            paletEtiket.setTextColor(d.vurgu);
            paletEtiket.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
            paletEtiket.setPadding(0, 0, 0, a.dp(8));
            gorunumKart.addView(paletEtiket);

            HorizontalScrollView hsv = new HorizontalScrollView(a);
            hsv.setHorizontalScrollBarEnabled(false);
            LinearLayout serit = new LinearLayout(a);
            serit.setOrientation(LinearLayout.HORIZONTAL);

            for (int i = 0; i < TemaMotoru.TEMALAR.length; i++) {
                final TemaMotoru.Tema pt = TemaMotoru.TEMALAR[i];
                boolean pSecili = pt.kod.equals(seciliPalet[0].kod);
                View kutu = paletYatayElemani(a, pt, pSecili, () -> {
                    seciliPalet[0] = pt;
                    onizlemeYenile.run();
                    panelYenile[0].run();
                });
                LinearLayout.LayoutParams klp = new LinearLayout.LayoutParams(a.dp(98), a.dp(58));
                if (i > 0) klp.setMargins(a.dp(8), 0, 0, 0);
                serit.addView(kutu, klp);
            }
            hsv.addView(serit);
            gorunumKart.addView(hsv);
            kontroller.addView(gorunumKart);

            // C) Galeriye Kaydet & Görseli Paylaş Eylem Düğmeleri
            LinearLayout eylemSatir = new LinearLayout(a);
            eylemSatir.setOrientation(LinearLayout.HORIZONTAL);
            LinearLayout.LayoutParams elp = new LinearLayout.LayoutParams(-1, -2);
            elp.setMargins(0, a.dp(2), 0, a.dp(8));
            eylemSatir.setLayoutParams(elp);

            TextView kaydetBtn = eylemDugmesi(a, d, "Galeriye Kaydet", false, () -> {
                if (sonBitmap[0] == null) onizlemeYenile.run();
                Uri uri = galeriyeKaydet(a, sonBitmap[0], aktifSablon[0]);
                if (uri != null) {
                    Toast.makeText(a, "Görsel galeriye kaydedildi (Pictures/SecdeVakti)", Toast.LENGTH_SHORT).show();
                } else {
                    Toast.makeText(a, "Görsel kaydedilemedi", Toast.LENGTH_SHORT).show();
                }
            });
            LinearLayout.LayoutParams kblp = new LinearLayout.LayoutParams(0, -2, 1f);
            kblp.setMargins(0, 0, a.dp(5), 0);
            eylemSatir.addView(kaydetBtn, kblp);

            TextView paylasBtn = eylemDugmesi(a, d, "Görseli Paylaş", true, () -> {
                if (sonBitmap[0] == null) onizlemeYenile.run();
                String[] veri = aktifSablonMetni(a, aktifSablon[0], sozIndeksi[0], ozelAr[0], ozelTr[0], ozelKy[0]);
                gorseliPaylas(a, sonBitmap[0], aktifSablon[0], takvim, veri[1], veri[2]);
            });
            LinearLayout.LayoutParams pblp = new LinearLayout.LayoutParams(0, -2, 1f);
            pblp.setMargins(a.dp(5), 0, 0, 0);
            eylemSatir.addView(paylasBtn, pblp);

            kontroller.addView(eylemSatir);
        };

        onizlemeYenile.run();
        panelYenile[0].run();

        a.altSayfa("Paylaşım Kartı Stüdyosu", sv, "kandil");
    }

    // ================================================================ 1080p Saf Canvas Kart Üretici

    /**
     * 1080×1350 (4:5 Gönderi) veya 1080×1920 (9:16 Hikâye) ARGB_8888 paylaşım kartı üretir.
     */
    public static Bitmap kartUret(Context c, VakitTakvimi.Takvim t, TemaMotoru.Tema palet,
                                  int sablon, boolean hikayeBoyutu,
                                  String ozelArapca, String ozelMetin, String ozelKaynak) {
        if (palet == null) palet = TemaMotoru.aktif(c).tema;
        if (t == null) t = VakitTakvimi.oku(c);

        final int W = 1080;
        final int H = hikayeBoyutu ? 1920 : 1350;
        final Bitmap bmp = Bitmap.createBitmap(W, H, Bitmap.Config.ARGB_8888);
        final Canvas canvas = new Canvas(bmp);
        final Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);

        final boolean acik = palet.acikTema;
        final int vurgu = palet.vurgu;
        final int anaRenk = palet.ana;
        final int metinRenk = acik ? 0xFF14211C : Color.WHITE;
        final int solukRenk = acik ? 0xCC263A32 : 0xDDFFFFFF;

        // 1. Çok duraklı doğrusal + radyal arka plan geçişi
        int[] arkaGecis = acik
                ? new int[]{0xFFFCFBF7, 0xFFF3EFE6, 0xFFE9E2D4}
                : new int[]{palet.heroBas, palet.heroSon, palet.zemin};
        p.setStyle(Paint.Style.FILL);
        p.setShader(new LinearGradient(0, 0, 0, H, arkaGecis, new float[]{0f, 0.50f, 1f}, Shader.TileMode.CLAMP));
        canvas.drawRect(0, 0, W, H, p);
        p.setShader(null);

        // Üst mihrap kubbe ışıması
        p.setShader(new RadialGradient(W * 0.5f, H * 0.28f, W * 0.68f,
                (vurgu & 0x00FFFFFF) | (acik ? 0x20000000 : 0x38000000),
                0x00000000, Shader.TileMode.CLAMP));
        canvas.drawRect(0, 0, W, H, p);
        p.setShader(null);

        // 2. İslâmî geometrik tezhip kafesi
        int desenKod = palet.varsayilanDesen == GeometrikDesen.KAPALI
                ? GeometrikDesen.SELCUKLU_YILDIZI : palet.varsayilanDesen;
        GeometrikDesen.ciz(canvas, W, H, 2.35f, desenKod, vurgu, acik ? 22 : 24);

        // 3. Çift katmanlı tezhipli altın mihrap kemeri çerçevesi ve köşe rozetleri
        cizMihrapCercevesi(canvas, W, H, p, vurgu, anaRenk, acik);

        // 4. Üst hilâl ve 8 köşeli yıldız arması
        float armaY = hikayeBoyutu ? 172f : 132f;
        cizHilalYildizArmasi(canvas, W * 0.5f, armaY, 30f, p, vurgu);

        // 5. Şablona göre ana içerik çizimi
        long simdi = System.currentTimeMillis();
        String yer = !bosMu(t.yer) ? t.yer.trim() : "Türkiye";
        String miladiTarih = Metinler.tarih(simdi);
        String hicriTarih = !bosMu(t.hicri) ? t.hicri : t.bugunHicri();

        int s = Math.max(0, Math.min(3, sablon));
        if (s == SABLON_VAKITLER) {
            cizVakitlerSablonu(c, canvas, W, H, hikayeBoyutu, t, simdi, yer, miladiTarih, hicriTarih,
                    vurgu, anaRenk, metinRenk, solukRenk, acik);
        } else {
            String[] cozulmus = cozMetinUclusu(c, s, ozelArapca, ozelMetin, ozelKaynak);
            String kategoriEtiketi = s == SABLON_AYET ? "GÜNÜN ÂYET-İ KERÎMESİ"
                    : (s == SABLON_HADIS_DUA ? "HADÎS-İ ŞERİF & DUÂ" : "MÜBÂREK GÜN TEBRİĞİ");
            cizHatVeMetinSablonu(c, canvas, W, H, hikayeBoyutu, s, kategoriEtiketi,
                    cozulmus[0], cozulmus[1], cozulmus[2],
                    vurgu, anaRenk, metinRenk, solukRenk, acik);
        }

        // 6. Alt mühür / bilgi satırı: "Secde Vakti  ·  Yer  ·  Tarih"
        float altY = H - (hikayeBoyutu ? 104f : 82f);
        p.setStyle(Paint.Style.STROKE);
        p.setStrokeWidth(1.6f);
        p.setColor((vurgu & 0x00FFFFFF) | 0x66000000);
        canvas.drawLine(W * 0.28f, altY - 34f, W * 0.72f, altY - 34f, p);

        TextPaint altBoya = new TextPaint(Paint.ANTI_ALIAS_FLAG);
        altBoya.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        altBoya.setTextSize(23f);
        altBoya.setLetterSpacing(0.04f);
        altBoya.setColor(solukRenk);
        String altMetin = "Secde Vakti  ·  " + yer + "  ·  " + miladiTarih;
        CharSequence altKisalt = TextUtils.ellipsize(altMetin, altBoya, W - 200f, TextUtils.TruncateAt.END);
        float aw = altBoya.measureText(altKisalt, 0, altKisalt.length());
        canvas.drawText(altKisalt, 0, altKisalt.length(), (W - aw) * 0.5f, altY, altBoya);

        return bmp;
    }

    private static void cizVakitlerSablonu(Context c, Canvas canvas, int W, int H, boolean hikaye,
                                           VakitTakvimi.Takvim takvim, long simdi,
                                           String yer, String miladi, String hicri,
                                           int vurgu, int anaRenk, int metinRenk, int solukRenk, boolean acik) {
        Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
        TextPaint tp = new TextPaint(Paint.ANTI_ALIAS_FLAG);

        float y = hikaye ? 248f : 196f;

        // Üst küçük başlık
        tp.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
        tp.setTextSize(22f);
        tp.setLetterSpacing(0.14f);
        tp.setColor(vurgu);
        merkezliYazi(canvas, "GÜNÜN NAMAZ VAKİTLERİ", W * 0.5f, y, tp);

        // Şehir / Konum başlığı
        y += hikaye ? 68f : 58f;
        tp.setLetterSpacing(0f);
        tp.setTypeface(TemaMotoru.baslikTipi(c));
        tp.setTextSize(hikaye ? 58f : 52f);
        tp.setColor(metinRenk);
        CharSequence yerMetin = TextUtils.ellipsize(yer, tp, W - 240f, TextUtils.TruncateAt.END);
        merkezliYazi(canvas, yerMetin.toString(), W * 0.5f, y, tp);

        // Milâdî ve Hicrî tarih satırı
        y += 44f;
        tp.setTypeface(Typeface.create("sans-serif", Typeface.NORMAL));
        tp.setTextSize(25f);
        tp.setColor(solukRenk);
        String tarihSatiri = !bosMu(hicri) ? (miladi + "  ·  " + hicri) : miladi;
        CharSequence tarihKisalt = TextUtils.ellipsize(tarihSatiri, tp, W - 220f, TextUtils.TruncateAt.END);
        merkezliYazi(canvas, tarihKisalt.toString(), W * 0.5f, y, tp);

        // Günün 6 vakti ve sıradaki/mevcut vakit tespiti
        HesapMotoru.GunVakitleri gv = HesapMotoru.gun(c, takvim, simdi);
        String[] adlar = {"İmsak", "Güneş", "Öğle", "İkindi", "Akşam", "Yatsı"};
        String[] arapcalar = {"الفجر", "الشروق", "الظهر", "العصر", "المغرب", "العشاء"};
        long[] saatler = {gv.imsak, gv.gunes, gv.ogle, gv.ikindi, gv.aksam, gv.yatsi};

        int vurguIndeks = -1;
        for (int i = 0; i < 6; i++) {
            if (saatler[i] > simdi) {
                vurguIndeks = i;
                break;
            }
        }
        if (vurguIndeks < 0) vurguIndeks = 5; // Yatsı sonrası

        float tabloUst = y + (hikaye ? 66f : 44f);
        float tabloAlt = H - (hikaye ? 200f : 150f);
        float satirAralik = hikaye ? 18f : 13f;
        float satirYukseklik = (tabloAlt - tabloUst - 5f * satirAralik) / 6f;
        satirYukseklik = Math.min(satirYukseklik, hikaye ? 142f : 108f);

        float toplamBoy = 6f * satirYukseklik + 5f * satirAralik;
        float basY = tabloUst + Math.max(0f, (tabloAlt - tabloUst - toplamBoy) * 0.45f);
        float sol = 128f;
        float sag = W - 128f;
        RectF satirKutu = new RectF();

        for (int i = 0; i < 6; i++) {
            float ust = basY + i * (satirYukseklik + satirAralik);
            float alt = ust + satirYukseklik;
            satirKutu.set(sol, ust, sag, alt);
            boolean aktif = (i == vurguIndeks);

            p.setStyle(Paint.Style.FILL);
            if (aktif) {
                p.setShader(new LinearGradient(sol, ust, sag, alt,
                        (vurgu & 0x00FFFFFF) | (acik ? 0x2A000000 : 0x3D000000),
                        (vurgu & 0x00FFFFFF) | (acik ? 0x14000000 : 0x1F000000),
                        Shader.TileMode.CLAMP));
            } else {
                p.setShader(null);
                p.setColor(acik ? 0x1214211C : 0x1CFFFFFF);
            }
            canvas.drawRoundRect(satirKutu, 26f, 26f, p);
            p.setShader(null);

            p.setStyle(Paint.Style.STROKE);
            p.setStrokeWidth(aktif ? 3.0f : 1.4f);
            p.setColor(aktif ? vurgu : (acik ? 0x2614211C : 0x2CFFFFFF));
            canvas.drawRoundRect(satirKutu, 26f, 26f, p);

            float merkezY = (ust + alt) * 0.5f;

            // Sol altın elmas işaretçisi + Türkçe Vakit Adı
            p.setStyle(Paint.Style.FILL);
            p.setColor(aktif ? vurgu : anaRenk);
            cizElmas(canvas, sol + 36f, merkezY, aktif ? 9f : 6.5f, p);

            tp.setTypeface(Typeface.create("sans-serif-medium", aktif ? Typeface.BOLD : Typeface.NORMAL));
            tp.setTextSize(34f);
            tp.setColor(aktif ? vurgu : metinRenk);
            Paint.FontMetrics fm = tp.getFontMetrics();
            float metinY = merkezY - (fm.ascent + fm.descent) * 0.5f;
            canvas.drawText(adlar[i], sol + 64f, metinY, tp);

            if (aktif) {
                float adGen = tp.measureText(adlar[i]);
                tp.setTextSize(19f);
                tp.setLetterSpacing(0.08f);
                String rozet = saatler[i] > simdi ? "SIRADAKİ" : "VAKTİ";
                float rx = sol + 84f + adGen;
                RectF rKutu = new RectF(rx, merkezY - 18f, rx + tp.measureText(rozet) + 28f, merkezY + 18f);
                p.setColor(vurgu);
                canvas.drawRoundRect(rKutu, 18f, 18f, p);
                tp.setColor(acik ? Color.WHITE : 0xFF171104);
                Paint.FontMetrics rfm = tp.getFontMetrics();
                canvas.drawText(rozet, rKutu.left + 14f, merkezY - (rfm.ascent + rfm.descent) * 0.5f, tp);
                tp.setLetterSpacing(0f);
            }

            // Orta zarif Arapça vakit adı
            tp.setTypeface(Varlik.kuranYazisi(c));
            tp.setTextSize(28f);
            tp.setColor((vurgu & 0x00FFFFFF) | (aktif ? 0xDD000000 : 0x77000000));
            Paint.FontMetrics afm = tp.getFontMetrics();
            String arVakit = arapcalar[i];
            float arGen = tp.measureText(arVakit);
            canvas.drawText(arVakit, sag - 210f - arGen, merkezY - (afm.ascent + afm.descent) * 0.5f, tp);

            // Sağda saat
            tp.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
            tp.setTextSize(38f);
            tp.setColor(aktif ? vurgu : metinRenk);
            String saatMetni = Metinler.saat(saatler[i]);
            float sGen = tp.measureText(saatMetni);
            fm = tp.getFontMetrics();
            canvas.drawText(saatMetni, sag - 36f - sGen, merkezY - (fm.ascent + fm.descent) * 0.5f, tp);
        }
    }

    private static void cizHatVeMetinSablonu(Context c, Canvas canvas, int W, int H, boolean hikaye,
                                             int sablon, String kategori,
                                             String arapca, String turkceMetin, String kaynak,
                                             int vurgu, int anaRenk, int metinRenk, int solukRenk, boolean acik) {
        Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
        TextPaint tp = new TextPaint(Paint.ANTI_ALIAS_FLAG);

        float ustEtiketY = hikaye ? 252f : 200f;
        tp.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
        tp.setTextSize(22f);
        tp.setLetterSpacing(0.15f);
        tp.setColor(vurgu);
        merkezliYazi(canvas, kategori, W * 0.5f, ustEtiketY, tp);
        tp.setLetterSpacing(0f);

        // İçerik dikey alanı
        float alanUst = ustEtiketY + (hikaye ? 58f : 42f);
        float alanAlt = H - (hikaye ? 190f : 148f);
        float kullanilabilirYukseklik = alanAlt - alanUst;
        int metinGenislik = W - 240; // her iki yandan 120px tezhip payı

        String arMetin = bosMu(arapca) ? BESMELE : arapca.trim();
        String trMetin = bosMu(turkceMetin) ? "Şüphesiz zorlukla beraber bir kolaylık vardır." : turkceMetin.trim();
        if (sablon != SABLON_CUMA_KANDIL && !trMetin.startsWith("“") && !trMetin.startsWith("\"")) {
            trMetin = "“" + trMetin + "”";
        }
        String altKaynak = bosMu(kaynak) ? "" : kaynak.trim();

        // Uygun yazı boyutunu taşma olmayacak şekilde dinamik hesapla
        float arBoyut = sablon == SABLON_CUMA_KANDIL ? 46f : (hikaye ? 54f : 48f);
        float trBoyut = sablon == SABLON_CUMA_KANDIL ? (hikaye ? 56f : 50f) : (hikaye ? 44f : 39f);
        float altBoyut = sablon == SABLON_CUMA_KANDIL ? 31f : 27f;

        TextPaint arPaint = new TextPaint(Paint.ANTI_ALIAS_FLAG);
        arPaint.setTypeface(Varlik.kuranYazisi(c));
        arPaint.setColor(vurgu);

        TextPaint trPaint = new TextPaint(Paint.ANTI_ALIAS_FLAG);
        trPaint.setTypeface(TemaMotoru.baslikTipi(c));
        trPaint.setColor(metinRenk);

        TextPaint kyPaint = new TextPaint(Paint.ANTI_ALIAS_FLAG);
        kyPaint.setTypeface(sablon == SABLON_CUMA_KANDIL
                ? Typeface.create("sans-serif", Typeface.NORMAL)
                : Typeface.create("sans-serif-medium", Typeface.BOLD));
        kyPaint.setColor(sablon == SABLON_CUMA_KANDIL ? solukRenk : anaRenk);

        StaticLayout arLayout = null;
        StaticLayout trLayout = null;
        StaticLayout kyLayout = null;

        float araBosluk1 = hikaye ? 52f : 38f;
        float araBosluk2 = hikaye ? 46f : 34f;

        for (int deneme = 0; deneme < 12; deneme++) {
            arPaint.setTextSize(arBoyut);
            trPaint.setTextSize(trBoyut);
            kyPaint.setTextSize(altBoyut);

            arLayout = statikMetin(arMetin, arPaint, metinGenislik, 1.25f);
            trLayout = statikMetin(trMetin, trPaint, metinGenislik, 1.28f);
            kyLayout = altKaynak.isEmpty() ? null : statikMetin(altKaynak, kyPaint, metinGenislik - 40, 1.24f);

            float toplam = arLayout.getHeight() + araBosluk1 + trLayout.getHeight()
                    + (kyLayout != null ? araBosluk2 + kyLayout.getHeight() : 0f);
            if (toplam <= kullanilabilirYukseklik) break;

            arBoyut = Math.max(26f, arBoyut * 0.91f);
            trBoyut = Math.max(24f, trBoyut * 0.91f);
            altBoyut = Math.max(20f, altBoyut * 0.93f);
            araBosluk1 *= 0.92f;
            araBosluk2 *= 0.92f;
        }

        float toplamYukseklik = arLayout.getHeight() + araBosluk1 + trLayout.getHeight()
                + (kyLayout != null ? araBosluk2 + kyLayout.getHeight() : 0f);
        float baslangicY = alanUst + Math.max(0f, (kullanilabilirYukseklik - toplamYukseklik) * 0.48f);

        // 1) Arapça Hat bloğu
        canvas.save();
        canvas.translate((W - metinGenislik) * 0.5f, baslangicY);
        arLayout.draw(canvas);
        canvas.restore();

        // Zarif tezhip ayraç çizgisi + merkez elmas
        float ayracY = baslangicY + arLayout.getHeight() + araBosluk1 * 0.5f;
        p.setStyle(Paint.Style.STROKE);
        p.setStrokeWidth(1.8f);
        p.setColor((vurgu & 0x00FFFFFF) | 0x88000000);
        canvas.drawLine(W * 0.5f - 140f, ayracY, W * 0.5f - 22f, ayracY, p);
        canvas.drawLine(W * 0.5f + 22f, ayracY, W * 0.5f + 140f, ayracY, p);
        p.setStyle(Paint.Style.FILL);
        p.setColor(vurgu);
        cizElmas(canvas, W * 0.5f, ayracY, 8f, p);

        // 2) Ana Türkçe metin / meal / tebrik başlığı
        float trY = baslangicY + arLayout.getHeight() + araBosluk1;
        canvas.save();
        canvas.translate((W - metinGenislik) * 0.5f, trY);
        trLayout.draw(canvas);
        canvas.restore();

        // 3) Kaynak rozeti veya Cuma/Kandil duâ alt metni
        if (kyLayout != null) {
            float kyY = trY + trLayout.getHeight() + araBosluk2;
            if (sablon != SABLON_CUMA_KANDIL && kyLayout.getLineCount() == 1) {
                float satGen = kyLayout.getLineWidth(0);
                RectF rozetKutu = new RectF(
                        W * 0.5f - satGen * 0.5f - 34f,
                        kyY - 12f,
                        W * 0.5f + satGen * 0.5f + 34f,
                        kyY + kyLayout.getHeight() + 12f);
                p.setStyle(Paint.Style.FILL);
                p.setColor((vurgu & 0x00FFFFFF) | (acik ? 0x1E000000 : 0x26000000));
                canvas.drawRoundRect(rozetKutu, 30f, 30f, p);
                p.setStyle(Paint.Style.STROKE);
                p.setStrokeWidth(1.8f);
                p.setColor((vurgu & 0x00FFFFFF) | 0x88000000);
                canvas.drawRoundRect(rozetKutu, 30f, 30f, p);
            }
            canvas.save();
            canvas.translate((W - (metinGenislik - 40)) * 0.5f, kyY);
            kyLayout.draw(canvas);
            canvas.restore();
        }
    }

    private static StaticLayout statikMetin(String metin, TextPaint tp, int genislik, float satirCarpani) {
        return StaticLayout.Builder.obtain(metin, 0, metin.length(), tp, Math.max(120, genislik))
                .setAlignment(Layout.Alignment.ALIGN_CENTER)
                .setLineSpacing(0f, satirCarpani)
                .setIncludePad(false)
                .build();
    }

    private static void cizMihrapCercevesi(Canvas c, int W, int H, Paint p, int vurgu, int ana, boolean acik) {
        float disPay = 44f;
        float icPay = 62f;

        // Dış dikdörtgen altın cetvel çerçeve
        p.setStyle(Paint.Style.STROKE);
        p.setStrokeWidth(2.6f);
        p.setColor((vurgu & 0x00FFFFFF) | (acik ? 0x99000000 : 0xAA000000));
        c.drawRoundRect(new RectF(disPay, disPay, W - disPay, H - disPay), 28f, 28f, p);

        // İç ince dikdörtgen cetvel
        p.setStrokeWidth(1.3f);
        p.setColor((vurgu & 0x00FFFFFF) | 0x55000000);
        c.drawRoundRect(new RectF(icPay, icPay, W - icPay, H - icPay), 20f, 20f, p);

        // Çift katmanlı sivri Osmanlı/Selçuklu mihrap kemeri
        float kemerSol = 78f;
        float kemerSag = W - 78f;
        float kemerTepe = 76f;
        float kemerOmuz = H * 0.25f;
        float kemerAlt = H - 128f;

        Path kemer = mihrapYolu(kemerSol, kemerSag, kemerTepe, kemerOmuz, kemerAlt, W * 0.5f);
        p.setStrokeWidth(2.8f);
        p.setColor((vurgu & 0x00FFFFFF) | 0x99000000);
        c.drawPath(kemer, p);

        Path icKemer = mihrapYolu(kemerSol + 12f, kemerSag - 12f, kemerTepe + 14f, kemerOmuz + 8f, kemerAlt - 10f, W * 0.5f);
        p.setStrokeWidth(1.4f);
        p.setColor((ana & 0x00FFFFFF) | 0x66000000);
        c.drawPath(icKemer, p);

        // 4 köşe 8 köşeli tezhip şemse rozetleri
        float[][] koseler = {
                {disPay + 48f, disPay + 48f},
                {W - disPay - 48f, disPay + 48f},
                {disPay + 48f, H - disPay - 48f},
                {W - disPay - 48f, H - disPay - 48f}
        };
        p.setStrokeWidth(2.0f);
        p.setColor((vurgu & 0x00FFFFFF) | 0x88000000);
        for (float[] k : koseler) {
            cizSekizliRozet(c, k[0], k[1], 20f, p);
        }
    }

    private static Path mihrapYolu(float sol, float sag, float tepe, float omuzY, float alt, float ox) {
        Path kemer = new Path();
        kemer.moveTo(sol, alt);
        kemer.lineTo(sol, omuzY);
        kemer.cubicTo(sol, tepe + (omuzY - tepe) * 0.36f, ox - (sag - sol) * 0.16f, tepe + 18f, ox, tepe);
        kemer.cubicTo(ox + (sag - sol) * 0.16f, tepe + 18f, sag, tepe + (omuzY - tepe) * 0.36f, sag, omuzY);
        kemer.lineTo(sag, alt);
        return kemer;
    }

    private static void cizSekizliRozet(Canvas c, float cx, float cy, float r, Paint p) {
        Path y = new Path();
        float k = r * 0.7071f;
        y.moveTo(cx - k, cy - k);
        y.lineTo(cx + k, cy - k);
        y.lineTo(cx + k, cy + k);
        y.lineTo(cx - k, cy + k);
        y.close();
        y.moveTo(cx, cy - r);
        y.lineTo(cx + r, cy);
        y.lineTo(cx, cy + r);
        y.lineTo(cx - r, cy);
        y.close();
        c.drawPath(y, p);
        c.drawCircle(cx, cy, r * 0.34f, p);
    }

    private static void cizHilalYildizArmasi(Canvas c, float cx, float cy, float r, Paint p, int vurgu) {
        // Üst kandil askı zinciri
        p.setStyle(Paint.Style.STROKE);
        p.setStrokeWidth(2f);
        p.setColor((vurgu & 0x00FFFFFF) | 0x77000000);
        c.drawLine(cx, 78f, cx, cy - r - 6f, p);

        // Hilâl
        Path dis = new Path();
        dis.addCircle(cx - 4f, cy, r, Path.Direction.CW);
        Path ic = new Path();
        ic.addCircle(cx + r * 0.36f, cy - r * 0.14f, r * 0.80f, Path.Direction.CW);
        dis.op(ic, Path.Op.DIFFERENCE);

        p.setStyle(Paint.Style.FILL);
        p.setColor(vurgu);
        c.drawPath(dis, p);

        // Yan yıldız
        cizBesKoseliYildiz(c, cx + r * 0.62f, cy - r * 0.18f, r * 0.32f, p);
    }

    private static void cizBesKoseliYildiz(Canvas c, float cx, float cy, float disR, Paint p) {
        Path y = new Path();
        float icR = disR * 0.42f;
        for (int i = 0; i < 10; i++) {
            double aci = Math.toRadians(-90 + i * 36);
            float rad = (i % 2 == 0) ? disR : icR;
            float x = cx + (float) (Math.cos(aci) * rad);
            float yy = cy + (float) (Math.sin(aci) * rad);
            if (i == 0) y.moveTo(x, yy);
            else y.lineTo(x, yy);
        }
        y.close();
        c.drawPath(y, p);
    }

    private static void cizElmas(Canvas c, float cx, float cy, float r, Paint p) {
        Path elmas = new Path();
        elmas.moveTo(cx, cy - r);
        elmas.lineTo(cx + r, cy);
        elmas.lineTo(cx, cy + r);
        elmas.lineTo(cx - r, cy);
        elmas.close();
        c.drawPath(elmas, p);
    }

    private static void merkezliYazi(Canvas c, String s, float cx, float y, TextPaint tp) {
        float w = tp.measureText(s);
        c.drawText(s, cx - w * 0.5f, y, tp);
    }

    // ================================================================ veri & şablon metin çözümleyici

    private static String[] cozMetinUclusu(Context c, int sablon,
                                           String ozelArapca, String ozelMetin, String ozelKaynak) {
        if (!bosMu(ozelMetin)) {
            String ar = !bosMu(ozelArapca) ? ozelArapca.trim()
                    : arapcaBulVeyaVarsayilan(sablon, ozelKaynak);
            String ky = ozelKaynak == null ? "" : ozelKaynak.trim();
            return new String[]{ar, ozelMetin.trim(), ky};
        }
        return aktifSablonMetni(c, sablon, gununBaslangicIndeksi(), null, null, null);
    }

    private static String[] aktifSablonMetni(Context c, int sablon, int indeks,
                                             String ozelArapca, String ozelMetin, String ozelKaynak) {
        if (!bosMu(ozelMetin)) {
            String ar = !bosMu(ozelArapca) ? ozelArapca : arapcaBulVeyaVarsayilan(sablon, ozelKaynak);
            return new String[]{ar, ozelMetin, ozelKaynak == null ? "" : ozelKaynak};
        }
        int pozitif = Math.abs(indeks);
        if (sablon == SABLON_AYET) {
            List<String[]> ayetler = ayetListesiYukle(c);
            String[] secim = ayetler.get(pozitif % ayetler.size());
            return new String[]{secim[0], secim[1], secim[2]};
        }
        if (sablon == SABLON_HADIS_DUA) {
            String[] secim = HADIS_VE_DUALAR[pozitif % HADIS_VE_DUALAR.length];
            return new String[]{secim[0], secim[1], secim[2]};
        }
        if (sablon == SABLON_CUMA_KANDIL) {
            String[] secim = TEBRIKLER[pozitif % TEBRIKLER.length];
            return new String[]{secim[0], secim[1], secim[2]};
        }
        return new String[]{"", "", ""};
    }

    private static List<String[]> ayetListesiYukle(Context c) {
        List<String[]> liste = new ArrayList<>();
        try {
            String ham = Varlik.flutterMetin(c, "assets/data/DailyVerses.json");
            if (!bosMu(ham)) {
                JSONArray dizi = new JSONArray(ham);
                for (int i = 0; i < dizi.length(); i++) {
                    JSONObject o = dizi.optJSONObject(i);
                    if (o == null) continue;
                    String metin = o.optString("text", "").trim();
                    String kaynak = o.optString("source", "").trim();
                    String arapca = o.optString("arabic", "").trim();
                    if (metin.isEmpty()) continue;
                    // Buhârî vb. hadis kaynaklarını Günün Âyeti şablonunda ayıkla
                    if (kaynak.startsWith("Buhârî") || kaynak.startsWith("Müslim") || kaynak.startsWith("Tirmizî")) {
                        continue;
                    }
                    if (arapca.isEmpty()) arapca = arapcaBulVeyaVarsayilan(SABLON_AYET, kaynak);
                    liste.add(new String[]{arapca, metin, kaynak});
                }
            }
        } catch (Throwable ignored) {
        }
        if (liste.isEmpty()) {
            for (String[] y : YEDEK_AYETLER) liste.add(y);
        }
        return liste;
    }

    private static String arapcaBulVeyaVarsayilan(int sablon, String kaynak) {
        if (!bosMu(kaynak)) {
            String k = kaynak.trim();
            for (String[] y : YEDEK_AYETLER) {
                if (k.contains(y[2]) || y[2].contains(k)) return y[0];
            }
        }
        return sablon == SABLON_CUMA_KANDIL ? SALAVAT : BESMELE;
    }

    private static int gununBaslangicIndeksi() {
        Calendar cal = Calendar.getInstance();
        boolean cuma = cal.get(Calendar.DAY_OF_WEEK) == Calendar.FRIDAY;
        return cuma ? 0 : Math.max(0, cal.get(Calendar.DAY_OF_YEAR));
    }

    // ================================================================ Galeriye Kaydet & Paylaş

    private static Uri galeriyeKaydet(Context c, Bitmap bmp, int sablon) {
        if (bmp == null) return null;
        String zamanDamgasi = new SimpleDateFormat("yyyyMMdd_HHmmss", Metinler.TR).format(new Date());
        String dosyaAdi = "SecdeVakti_" + sablonDosyaEki(sablon) + "_" + zamanDamgasi + ".png";

        try {
            ContentResolver cr = c.getContentResolver();
            ContentValues cv = new ContentValues();
            cv.put(MediaStore.Images.Media.DISPLAY_NAME, dosyaAdi);
            cv.put(MediaStore.Images.Media.MIME_TYPE, "image/png");
            if (Build.VERSION.SDK_INT >= 29) {
                cv.put("relative_path", "Pictures/SecdeVakti");
                cv.put("is_pending", 1);
            }
            Uri koleksiyon = MediaStore.Images.Media.EXTERNAL_CONTENT_URI;
            Uri hedef = cr.insert(koleksiyon, cv);
            if (hedef != null) {
                try (OutputStream out = cr.openOutputStream(hedef)) {
                    if (out != null && bmp.compress(Bitmap.CompressFormat.PNG, 100, out)) {
                        out.flush();
                        if (Build.VERSION.SDK_INT >= 29) {
                            ContentValues hazir = new ContentValues();
                            hazir.put("is_pending", 0);
                            cr.update(hedef, hazir, null, null);
                        }
                        return hedef;
                    }
                }
            }
        } catch (Throwable ignored) {
        }

        // MediaStore erişilemezse (ör. test ortamı veya kısıtlı depolama) uygulama dizinine güvenli yedek kayıt
        try {
            File bazDizin = c.getExternalFilesDir(Environment.DIRECTORY_PICTURES);
            if (bazDizin == null) bazDizin = new File(c.getCacheDir(), "Pictures");
            File altDizin = new File(bazDizin, "SecdeVakti");
            if (!altDizin.exists()) altDizin.mkdirs();
            File hedefDosya = new File(altDizin, dosyaAdi);
            try (FileOutputStream fos = new FileOutputStream(hedefDosya)) {
                if (bmp.compress(Bitmap.CompressFormat.PNG, 100, fos)) {
                    fos.flush();
                    return Uri.fromFile(hedefDosya);
                }
            }
        } catch (Throwable ignored) {
        }
        return null;
    }

    private static void gorseliPaylas(DurumAktivitesi a, Bitmap bmp, int sablon,
                                      VakitTakvimi.Takvim takvim, String metin, String kaynak) {
        String paylasimMetni = paylasimAciklamasiUret(sablon, takvim, metin, kaynak);

        Uri gorselUri = null;
        try {
            ContentResolver cr = a.getContentResolver();
            ContentValues cv = new ContentValues();
            String ad = "SecdeVakti_Paylasim_" + System.currentTimeMillis() + ".png";
            cv.put(MediaStore.Images.Media.DISPLAY_NAME, ad);
            cv.put(MediaStore.Images.Media.MIME_TYPE, "image/png");
            if (Build.VERSION.SDK_INT >= 29) {
                cv.put("relative_path", "Pictures/SecdeVakti");
                cv.put("is_pending", 1);
            }
            Uri u = cr.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, cv);
            if (u != null) {
                try (OutputStream out = cr.openOutputStream(u)) {
                    if (out != null && bmp.compress(Bitmap.CompressFormat.PNG, 100, out)) {
                        out.flush();
                        if (Build.VERSION.SDK_INT >= 29) {
                            ContentValues hazir = new ContentValues();
                            hazir.put("is_pending", 0);
                            cr.update(u, hazir, null, null);
                        }
                        gorselUri = u;
                    }
                }
            }
        } catch (Throwable ignored) {
        }

        try {
            Intent niyet = new Intent(Intent.ACTION_SEND);
            if (gorselUri != null && "content".equals(gorselUri.getScheme())) {
                niyet.setType("image/png");
                niyet.putExtra(Intent.EXTRA_STREAM, gorselUri);
                niyet.putExtra(Intent.EXTRA_TEXT, paylasimMetni);
                niyet.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            } else {
                niyet.setType("text/plain");
                niyet.putExtra(Intent.EXTRA_TEXT, paylasimMetni);
            }
            Intent secici = Intent.createChooser(niyet, "Kartı Paylaş");
            a.startActivity(secici);
        } catch (Throwable e) {
            Toast.makeText(a, "Paylaşım ekranı açılamadı", Toast.LENGTH_SHORT).show();
        }
    }

    private static String paylasimAciklamasiUret(int sablon, VakitTakvimi.Takvim t, String metin, String kaynak) {
        String yer = (t != null && !bosMu(t.yer)) ? t.yer : "Türkiye";
        if (sablon == SABLON_VAKITLER) {
            return yer + " — Günün Namaz Vakitleri (" + Metinler.tarih(System.currentTimeMillis()) + ") · Secde Vakti";
        }
        StringBuilder sb = new StringBuilder();
        if (!bosMu(metin)) sb.append("“").append(metin.trim()).append("”");
        if (!bosMu(kaynak)) sb.append("\n— ").append(kaynak.trim());
        sb.append("\n\nSecde Vakti");
        return sb.toString();
    }

    private static String sablonDosyaEki(int sablon) {
        switch (sablon) {
            case SABLON_VAKITLER: return "Vakitler";
            case SABLON_AYET: return "Ayet";
            case SABLON_HADIS_DUA: return "HadisDua";
            default: return "Tebrik";
        }
    }

    // ================================================================ Stüdyo UI yardımcıları

    private static LinearLayout panelKarti(DurumAktivitesi a, TemaMotoru.Durum d) {
        LinearLayout k = new LinearLayout(a);
        k.setOrientation(LinearLayout.VERTICAL);
        k.setPadding(a.dp(15), a.dp(14), a.dp(15), a.dp(14));
        k.setBackground(d.kartArkaPlani(a));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(0, 0, 0, a.dp(12));
        k.setLayoutParams(lp);
        return k;
    }

    private static TextView panelBaslik(DurumAktivitesi a, String s, TemaMotoru.Durum d) {
        TextView t = new TextView(a);
        t.setText(s);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, TemaMotoru.olcekliSp(a, 15));
        t.setTextColor(d.metin);
        t.setTypeface(TemaMotoru.baslikTipi(a), Typeface.BOLD);
        t.setPadding(0, 0, 0, a.dp(6));
        return t;
    }

    private static TextView cipDugme(DurumAktivitesi a, TemaMotoru.Durum d, String s, boolean secili, Runnable eylem) {
        TextView t = new TextView(a);
        t.setText(secili ? "✓  " + s : s);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12.5f);
        t.setTextColor(secili ? d.birincilDugmeYaziRengi() : d.metin);
        t.setTypeface(Typeface.create("sans-serif-medium", secili ? Typeface.BOLD : Typeface.NORMAL));
        t.setGravity(Gravity.CENTER);
        t.setMinHeight(a.dp(42));
        t.setPadding(a.dp(10), a.dp(8), a.dp(10), a.dp(8));
        t.setBackground(d.cipArkaPlani(a, secili, 14));
        t.setClickable(true);
        t.setContentDescription(s);
        a.basmaEfekti(t);
        t.setOnClickListener(v -> {
            v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            eylem.run();
        });
        return t;
    }

    private static View paletYatayElemani(DurumAktivitesi a, TemaMotoru.Tema pt, boolean secili, Runnable eylem) {
        LinearLayout kutu = new LinearLayout(a);
        kutu.setOrientation(LinearLayout.VERTICAL);
        kutu.setGravity(Gravity.BOTTOM);
        kutu.setPadding(a.dp(8), a.dp(6), a.dp(8), a.dp(7));
        kutu.setClickable(true);
        kutu.setContentDescription("Kart Paleti " + pt.ad);

        GradientDrawable g = new GradientDrawable(
                GradientDrawable.Orientation.TL_BR,
                pt.acikTema ? new int[]{0xFFFAF8F2, pt.zemin} : new int[]{pt.heroBas, pt.zemin});
        g.setCornerRadius(a.dp(14));
        g.setStroke(secili ? a.dp(2) : Math.max(1, a.dp(1)),
                secili ? pt.vurgu : (pt.acikTema ? 0x3314211C : 0x38FFFFFF));
        kutu.setBackground(g);
        a.basmaEfekti(kutu);
        kutu.setOnClickListener(v -> {
            v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            eylem.run();
        });

        // Üst renk noktası
        View nokta = new View(a);
        GradientDrawable ng = new GradientDrawable();
        ng.setShape(GradientDrawable.OVAL);
        ng.setColor(pt.vurgu);
        nokta.setBackground(ng);
        LinearLayout.LayoutParams nlp = new LinearLayout.LayoutParams(a.dp(10), a.dp(10));
        nlp.setMargins(0, 0, 0, a.dp(6));
        kutu.addView(nokta, nlp);

        TextView ad = new TextView(a);
        ad.setText(secili ? "✓ " + pt.ad : pt.ad);
        ad.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f);
        ad.setTextColor(pt.acikTema ? 0xFF14211C : Color.WHITE);
        ad.setTypeface(Typeface.create("sans-serif-medium", secili ? Typeface.BOLD : Typeface.NORMAL));
        ad.setSingleLine(true);
        ad.setEllipsize(TextUtils.TruncateAt.END);
        kutu.addView(ad);

        return kutu;
    }

    private static TextView eylemDugmesi(DurumAktivitesi a, TemaMotoru.Durum d, String metin,
                                         boolean birincil, Runnable eylem) {
        TextView b = new TextView(a);
        b.setText(metin);
        b.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f);
        b.setTextColor(birincil ? d.birincilDugmeYaziRengi() : d.metin);
        b.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
        b.setGravity(Gravity.CENTER);
        b.setMinHeight(a.dp(48));
        b.setPadding(a.dp(12), a.dp(12), a.dp(12), a.dp(12));
        b.setBackground(birincil ? d.birincilDugme(a, 16) : d.ikincilDugme(a, 16));
        b.setClickable(true);
        b.setContentDescription(metin);
        a.basmaEfekti(b);
        b.setOnClickListener(v -> {
            v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            eylem.run();
        });
        return b;
    }

    private static boolean bosMu(String s) {
        return s == null || s.trim().isEmpty() || "null".equals(s);
    }
}
