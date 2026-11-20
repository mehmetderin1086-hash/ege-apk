package com.mehmetderin.secde_vakti.saglik;

import android.content.Context;
import android.content.res.ColorStateList;
import android.graphics.Bitmap;
import android.graphics.BitmapShader;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.ColorFilter;
import android.graphics.LinearGradient;
import android.graphics.Matrix;
import android.graphics.Outline;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.PixelFormat;
import android.graphics.RadialGradient;
import android.graphics.Rect;
import android.graphics.RectF;
import android.graphics.Shader;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.text.TextUtils;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.HapticFeedbackConstants;
import android.view.View;
import android.view.ViewOutlineProvider;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

/**
 * Zengin Tema Galerisi, Görünüm Stüdyosu ve Namaz Vakti Hesaplama Metodu Seçicisi.
 * Her tercih değişiminde alt sayfa kaydırma konumunu koruyarak anında yenilenir ve
 * ana ekranı canlı olarak günceller.
 */
public final class TemaGalerisi {

    private static final String BESMELE = "بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ";

    private TemaGalerisi() {}

    /**
     * Menü veya Vakitler sekmesinde aktif temayı, 5 renk noktasını, seçili tezhip desenini ve
     * hesaplama metodunu gösteren lüks özet afiş kartı.
     */
    public static View ozetKart(DurumAktivitesi a, Runnable acEylem) {
        final TemaMotoru.Durum d = TemaMotoru.aktif(a);
        final HesapMotoru.Metot metot = HesapMotoru.aktifMetot(a);

        LinearLayout dis = new LinearLayout(a);
        dis.setOrientation(LinearLayout.VERTICAL);
        dis.setPadding(a.dp(16), a.dp(15), a.dp(16), a.dp(15));
        dis.setBackground(d.kartArkaPlani(a));
        LinearLayout.LayoutParams disLp = new LinearLayout.LayoutParams(-1, -2);
        disLp.setMargins(0, 0, 0, a.dp(12));
        dis.setLayoutParams(disLp);
        dis.setClickable(true);
        dis.setContentDescription("Tema ve Görünüm Stüdyosu: " + d.tema.ad);
        a.basmaEfekti(dis);
        dis.setOnClickListener(v -> {
            v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            if (acEylem != null) acEylem.run();
        });

        // Üst satır: rozet + 5 renkli palet noktası
        LinearLayout ust = new LinearLayout(a);
        ust.setGravity(Gravity.CENTER_VERTICAL);

        TextView rozet = metinOlustur(a, "✦ TEMA VE GÖRÜNÜM STÜDYOSU", 11, d.vurgu, true);
        rozet.setLetterSpacing(0.08f);
        ust.addView(rozet, new LinearLayout.LayoutParams(0, -2, 1f));

        LinearLayout noktalar = new LinearLayout(a);
        noktalar.setGravity(Gravity.CENTER_VERTICAL);
        int[] paletRenkleri = {d.vurgu, d.ana, d.heroBas, d.heroSon, d.zemin};
        for (int i = 0; i < paletRenkleri.length; i++) {
            View nokta = renkNoktasi(a, paletRenkleri[i], 13, d.acik ? 0x4414211C : 0x66FFFFFF);
            LinearLayout.LayoutParams nlp = new LinearLayout.LayoutParams(a.dp(13), a.dp(13));
            if (i > 0) nlp.setMargins(a.dp(5), 0, 0, 0);
            noktalar.addView(nokta, nlp);
        }
        ust.addView(noktalar);
        dis.addView(ust);

        // Orta satır: aktif tema adı + desen/metot alt başlığı ve sağda "Stüdyoyu Aç ›"
        LinearLayout orta = new LinearLayout(a);
        orta.setGravity(Gravity.CENTER_VERTICAL);
        orta.setPadding(0, a.dp(8), 0, 0);

        LinearLayout sol = new LinearLayout(a);
        sol.setOrientation(LinearLayout.VERTICAL);

        TextView baslik = metinOlustur(a, d.tema.ad, 18, d.metin, true);
        baslik.setTypeface(TemaMotoru.baslikTipi(a), Typeface.BOLD);
        sol.addView(baslik);

        String desenAdi = (d.desen >= 0 && d.desen < GeometrikDesen.ADLAR.length)
                ? GeometrikDesen.ADLAR[d.desen] : "Tezhip Deseni";
        String altBilgi = desenAdi + "  ·  " + kisaMetotAdi(metot);
        if (HesapMotoru.asriSani(a)) altBilgi += " (Asr-ı Sânî)";
        TextView alt = metinOlustur(a, altBilgi, 12, d.soluk, false);
        alt.setPadding(0, a.dp(2), 0, 0);
        sol.addView(alt);

        orta.addView(sol, new LinearLayout.LayoutParams(0, -2, 1f));

        TextView eylem = metinOlustur(a, "Stüdyoyu Aç ›", 13, d.birincilDugmeYaziRengi(), true);
        eylem.setShadowLayer(0, 0, 0, 0);
        eylem.setGravity(Gravity.CENTER);
        eylem.setPadding(a.dp(13), a.dp(8), a.dp(13), a.dp(8));
        eylem.setBackground(d.birincilDugme(a, 14));
        LinearLayout.LayoutParams elp = new LinearLayout.LayoutParams(-2, -2);
        elp.setMargins(a.dp(10), 0, 0, 0);
        orta.addView(eylem, elp);

        dis.addView(orta);
        return dis;
    }

    /**
     * Tema ve Görünüm Stüdyosu alt sayfasını açar.
     */
    public static void sayfaAc(DurumAktivitesi a, Runnable anaEkraniYenile) {
        final ScrollView sv = new ScrollView(a);
        sv.setPadding(0, 0, 0, 0);
        sv.setVerticalScrollBarEnabled(false);
        sv.setClipToPadding(false);

        final LinearLayout icerik = new LinearLayout(a);
        icerik.setOrientation(LinearLayout.VERTICAL);
        icerik.setPadding(a.dp(16), a.dp(6), a.dp(16), a.dp(32));
        sv.addView(icerik, new ScrollView.LayoutParams(-1, -2));

        final Runnable[] yenileRef = new Runnable[1];
        yenileRef[0] = () -> {
            final int kaydirmaY = sv.getScrollY();
            icerikDoldur(a, icerik, () -> {
                if (anaEkraniYenile != null) anaEkraniYenile.run();
                if (yenileRef[0] != null) yenileRef[0].run();
            });
            sv.scrollTo(0, kaydirmaY);
            sv.post(() -> sv.scrollTo(0, kaydirmaY));
        };

        icerikDoldur(a, icerik, () -> {
            if (anaEkraniYenile != null) anaEkraniYenile.run();
            yenileRef[0].run();
        });

        TextView sifirla = a.metin("Varsayılan", 13, DurumAktivitesi.ALTIN, true);
        sifirla.setPadding(a.dp(10), a.dp(6), a.dp(6), a.dp(6));
        sifirla.setContentDescription("Görünüm ayarlarını sıfırla");
        sifirla.setOnClickListener(v -> {
            v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            TemaMotoru.temaSec(a, "zumrut");
            TemaMotoru.kartBicimiSec(a, TemaMotoru.KART_YUMUSAK);
            TemaMotoru.desenSec(a, -1);
            TemaMotoru.sahneModuSec(a, "");
            TemaMotoru.sahnePaketiSec(a, TemaMotoru.PAKET_KLASIK);
            TemaMotoru.sabitArkaPlanSec(a, "");
            TemaMotoru.efektYogunluguSec(a, TemaMotoru.EFEKT_ZENGIN);
            TemaMotoru.sahneNetlikSec(a, TemaMotoru.NETLIK_CANLI);
            TemaMotoru.yaziOlcegiSec(a, 1.0f);
            TemaMotoru.arapcaYaziTipiSec(a, TemaMotoru.ARAPCA_FONTLAR[0][0]);
            TemaMotoru.serifBaslikSec(a, true);
            TemaMotoru.yuksekKontrastSec(a, false);
            HesapMotoru.metotSec(a, "diyanet");
            HesapMotoru.asriSaniSec(a, false);
            Toast.makeText(a, "Varsayılan görünüm ve Diyanet ayarı yüklendi", Toast.LENGTH_SHORT).show();
            if (anaEkraniYenile != null) anaEkraniYenile.run();
            yenileRef[0].run();
        });

        a.altSayfa("Tema ve Görünüm Stüdyosu", sv, "mihrap", sifirla);
    }

    private static void icerikDoldur(DurumAktivitesi a, LinearLayout ana, Runnable degisti) {
        ana.removeAllViews();
        final TemaMotoru.Durum d = TemaMotoru.aktif(a);

        // ============================================================ 1. CANLI ÖNİZLEME SAHNESİ
        ana.addView(bolumBasligi(a, "CANLI ÖNİZLEME SAHNESİ", d));
        OnizlemeView onizleme = new OnizlemeView(a, d);
        LinearLayout.LayoutParams olp = new LinearLayout.LayoutParams(-1, a.dp(194));
        olp.setMargins(0, 0, 0, a.dp(14));
        onizleme.setLayoutParams(olp);
        onizleme.setContentDescription("Canlı Tema Önizleme: " + d.tema.ad);
        ana.addView(onizleme);

        // ============================================================ 2. 16 İSLÂMÎ RENK TEMASI GALERİSİ
        ana.addView(bolumBasligi(a, "16 İSLÂMÎ RENK TEMASI GALERİSİ", d));
        TextView galeriAciklama = metinOlustur(a,
                "Osmanlı, Selçuklu, Haremeyn ve Kudüs mimarisinden ilham alan 16 özgün renk paleti.",
                13, DurumAktivitesi.SOLUK, false);
        galeriAciklama.setPadding(a.dp(4), 0, a.dp(4), a.dp(8));
        ana.addView(galeriAciklama);

        String aktifTemaKodu = TemaMotoru.temaKodu(a);
        TemaMotoru.Tema[] temalar = TemaMotoru.TEMALAR;
        for (int i = 0; i < temalar.length; i += 2) {
            LinearLayout satir = new LinearLayout(a);
            satir.setOrientation(LinearLayout.HORIZONTAL);
            LinearLayout.LayoutParams slp = new LinearLayout.LayoutParams(-1, -2);
            slp.setMargins(0, 0, 0, a.dp(10));
            satir.setLayoutParams(slp);

            View solKart = temaKartiOlustur(a, temalar[i], temalar[i].kod.equals(aktifTemaKodu), degisti);
            LinearLayout.LayoutParams lpSol = new LinearLayout.LayoutParams(0, a.dp(108), 1f);
            lpSol.setMargins(0, 0, a.dp(5), 0);
            satir.addView(solKart, lpSol);

            if (i + 1 < temalar.length) {
                TemaMotoru.Tema tSag = temalar[i + 1];
                View sagKart = temaKartiOlustur(a, tSag, tSag.kod.equals(aktifTemaKodu), degisti);
                LinearLayout.LayoutParams lpSag = new LinearLayout.LayoutParams(0, a.dp(108), 1f);
                lpSag.setMargins(a.dp(5), 0, 0, 0);
                satir.addView(sagKart, lpSag);
            } else {
                View bos = new View(a);
                LinearLayout.LayoutParams lpBos = new LinearLayout.LayoutParams(0, a.dp(108), 1f);
                lpBos.setMargins(a.dp(5), 0, 0, 0);
                satir.addView(bos, lpBos);
            }
            ana.addView(satir);
        }

        // ============================================================ 3. KART BİÇİMİ SEÇİCİ
        LinearLayout kartBolumu = studyoKarti(a, d);
        kartBolumu.addView(kartIciBaslik(a, "Kart Biçimi", "Yüzey dokusu, köşe yuvarlaklığı ve çerçeve üslûbu", d));

        String aktifKart = TemaMotoru.kartBicimi(a);
        String[][] kartSecenekleri = {
                {TemaMotoru.KART_YUMUSAK, "Yumuşak Cam"},
                {TemaMotoru.KART_CERCEVELI, "Altın Çerçeveli"},
                {TemaMotoru.KART_MAT, "Sade Mat"},
                {TemaMotoru.KART_KOMPAKT, "Kompakt"}
        };
        cipIzgarasiEkle(a, kartBolumu, d, kartSecenekleri, aktifKart, secilenKod -> {
            TemaMotoru.kartBicimiSec(a, secilenKod);
            degisti.run();
        });
        ana.addView(kartBolumu);

        // ============================================================ 4. GEOMETRİK TEZHİP DESENİ SEÇİCİ
        LinearLayout desenBolumu = studyoKarti(a, d);
        desenBolumu.addView(kartIciBaslik(a, "İslâmî Geometrik Tezhip Deseni",
                "Kart ve sahne yüzeylerinde ince hatlı geleneksel bezeme", d));

        String aktifDesen = String.valueOf(TemaMotoru.desenTercihi(a));
        String[][] desenSecenekleri = {
                {"-1", "Tema Varsayılanı"},
                {"0", "Kapalı"},
                {"1", "Selçuklu Yıldızı"},
                {"2", "İznik Rûmî"},
                {"3", "Mihrap Kemeri"},
                {"4", "Kâbe Kisvesi"},
                {"5", "Kubbe Halkaları"}
        };
        cipIzgarasiEkle(a, desenBolumu, d, desenSecenekleri, aktifDesen, secilenKod -> {
            TemaMotoru.desenSec(a, Integer.parseInt(secilenKod));
            degisti.run();
        });
        ana.addView(desenBolumu);

        // ============================================================ 5. ARKA PLAN SAHNE MODU & PİL TASARRUFU
        LinearLayout sahneBolumu = studyoKarti(a, d);
        sahneBolumu.addView(kartIciBaslik(a, "Arka Plan Sahne Modu & Pil Tasarrufu",
                "Canlı cami atmosferi veya AMOLED ekranlar için sıfır pil tüketimli saf siyah zemin", d));

        String aktifSahne = TemaMotoru.sahneTercihi(a);
        if (aktifSahne == null) aktifSahne = "";
        String[][] sahneSecenekleri = {
                {"", "Tema Varsayılanı"},
                {TemaMotoru.SAHNE_CANLI_FOTO, "Canlı Fotoğraf"},
                {TemaMotoru.SAHNE_CIZIM, "Çizim Cami Silüeti"},
                {TemaMotoru.SAHNE_DINAMIK_GOK, "Dinamik Gökyüzü"},
                {TemaMotoru.SAHNE_DUZ_AMOLED, "Saf Düz / AMOLED Pil Dostu"}
        };
        cipIzgarasiEkle(a, sahneBolumu, d, sahneSecenekleri, aktifSahne, secilenKod -> {
            TemaMotoru.sahneModuSec(a, secilenKod);
            degisti.run();
        });

        TextView paketEtiket = metinOlustur(a, "Manzara Paketi (Vakitle Otomatik)", 13, d.vurgu, true);
        paketEtiket.setPadding(0, a.dp(12), 0, a.dp(4));
        sahneBolumu.addView(paketEtiket);

        String aktifPaket = TemaMotoru.sahnePaketi(a);
        String[][] paketSecenekleri = new String[TemaMotoru.SAHNE_PAKETLERI.length][2];
        for (int i = 0; i < TemaMotoru.SAHNE_PAKETLERI.length; i++) {
            paketSecenekleri[i][0] = TemaMotoru.SAHNE_PAKETLERI[i][0];
            paketSecenekleri[i][1] = TemaMotoru.SAHNE_PAKETLERI[i][1];
        }
        cipIzgarasiEkle(a, sahneBolumu, d, paketSecenekleri, aktifPaket, secilenKod -> {
            TemaMotoru.sahnePaketiSec(a, secilenKod);
            TemaMotoru.sabitArkaPlanSec(a, "");
            if (TemaMotoru.SAHNE_CIZIM.equals(TemaMotoru.sahneTercihi(a))
                    || TemaMotoru.SAHNE_DINAMIK_GOK.equals(TemaMotoru.sahneTercihi(a))
                    || TemaMotoru.SAHNE_DUZ_AMOLED.equals(TemaMotoru.sahneTercihi(a))) {
                TemaMotoru.sahneModuSec(a, TemaMotoru.SAHNE_CANLI_FOTO);
            }
            degisti.run();
        });

        TextView fotoEtiket = metinOlustur(a, "Arka Plan Galerisi (Dokunarak Sabitle)", 13, d.vurgu, true);
        fotoEtiket.setPadding(0, a.dp(12), 0, a.dp(6));
        sahneBolumu.addView(fotoEtiket);

        String aktifSabit = TemaMotoru.sabitArkaPlan(a);
        HorizontalScrollView galeriYatay = new HorizontalScrollView(a);
        galeriYatay.setHorizontalScrollBarEnabled(false);
        galeriYatay.setClipToPadding(false);
        LinearLayout galeriSira = new LinearLayout(a);
        galeriSira.setOrientation(LinearLayout.HORIZONTAL);
        for (int i = 0; i < TemaMotoru.OZEL_ARKAPLANLAR.length; i++) {
            final String[] row = TemaMotoru.OZEL_ARKAPLANLAR[i];
            final String kod = row[0];
            boolean secili = kod.equals(aktifSabit);
            String gorselAnahtar = kod.isEmpty() ? TemaMotoru.sahneAnahtariCoz(a, "vakit_5") : kod;
            Kutucuk ku = new Kutucuk(a, gorselAnahtar, row[1], row[2], d.heroBas);
            if (secili) ku.rozet("✓ Aktif");
            else if (kod.isEmpty()) ku.rozet("Otomatik");
            ku.setContentDescription("Arka plan " + row[1]);
            ku.tiklaninca(() -> {
                TemaMotoru.sabitArkaPlanSec(a, kod);
                if (!kod.isEmpty() && !TemaMotoru.SAHNE_CANLI_FOTO.equals(TemaMotoru.sahneTercihi(a))) {
                    TemaMotoru.sahneModuSec(a, TemaMotoru.SAHNE_CANLI_FOTO);
                }
                degisti.run();
            });
            LinearLayout.LayoutParams klp = new LinearLayout.LayoutParams(a.dp(136), a.dp(172));
            klp.setMargins(i == 0 ? 0 : a.dp(10), 0, 0, 0);
            galeriSira.addView(ku, klp);
        }
        galeriYatay.addView(galeriSira);
        sahneBolumu.addView(galeriYatay);

        TextView efektEtiket = metinOlustur(a, "Atmosfer Efektleri (Yıldız, Işık Hüzmesi & Kuşlar)", 13, d.vurgu, true);
        efektEtiket.setPadding(0, a.dp(12), 0, a.dp(4));
        sahneBolumu.addView(efektEtiket);
        cipIzgarasiEkle(a, sahneBolumu, d, new String[][]{
                {TemaMotoru.EFEKT_ZENGIN, "Zengin Efektler"},
                {TemaMotoru.EFEKT_SADE, "Sade Işıltı"},
                {TemaMotoru.EFEKT_KAPALI, "Kapalı"}
        }, TemaMotoru.efektYogunlugu(a), secilenKod -> {
            TemaMotoru.efektYogunluguSec(a, secilenKod);
            degisti.run();
        });

        TextView netlikEtiket = metinOlustur(a, "Arka Plan Netliği (Perde)", 13, d.vurgu, true);
        netlikEtiket.setPadding(0, a.dp(12), 0, a.dp(4));
        sahneBolumu.addView(netlikEtiket);
        cipIzgarasiEkle(a, sahneBolumu, d, new String[][]{
                {TemaMotoru.NETLIK_CANLI, "Canlı & Parlak"},
                {TemaMotoru.NETLIK_DENGELI, "Dengeli"},
                {TemaMotoru.NETLIK_OKUMA, "Okuma Odağı"}
        }, TemaMotoru.sahneNetlik(a), secilenKod -> {
            TemaMotoru.sahneNetlikSec(a, secilenKod);
            degisti.run();
        });

        ana.addView(sahneBolumu);

        // ============================================================ 6. TİPOGRAFİ, MUSHAF HATTI & ERİŞİLEBİLİRLİK
        LinearLayout yaziBolumu = studyoKarti(a, d);
        yaziBolumu.addView(kartIciBaslik(a, "Tipografi, Mushaf Hattı & Erişilebilirlik",
                "Metin büyüklüğü, Kur'ân-ı Kerîm hat karakteri ve okunabilirlik ayarları", d));

        TextView olcekEtiket = metinOlustur(a, "Yazı Ölçeği", 13, d.vurgu, true);
        olcekEtiket.setPadding(0, a.dp(4), 0, a.dp(6));
        yaziBolumu.addView(olcekEtiket);

        float mevcutOlcek = TemaMotoru.yaziOlcegi(a);
        float[] olcekDegerleri = {0.90f, 1.00f, 1.15f, 1.30f};
        String[] olcekAdlari = {"Küçük", "Standart", "Büyük", "Çok Büyük"};
        String aktifOlcekAnahtar = "1.00";
        String[][] olcekSecenekleri = new String[olcekDegerleri.length][2];
        for (int i = 0; i < olcekDegerleri.length; i++) {
            String anahtar = String.format(java.util.Locale.ROOT, "%.2f", olcekDegerleri[i]);
            olcekSecenekleri[i][0] = anahtar;
            olcekSecenekleri[i][1] = olcekAdlari[i];
            if (Math.abs(mevcutOlcek - olcekDegerleri[i]) < 0.04f) {
                aktifOlcekAnahtar = anahtar;
            }
        }
        cipIzgarasiEkle(a, yaziBolumu, d, olcekSecenekleri, aktifOlcekAnahtar, secilenKod -> {
            TemaMotoru.yaziOlcegiSec(a, Float.parseFloat(secilenKod));
            degisti.run();
        });

        TextView hatEtiket = metinOlustur(a, "Arapça Mushaf Yazı Tipi", 13, d.vurgu, true);
        hatEtiket.setPadding(0, a.dp(12), 0, a.dp(6));
        yaziBolumu.addView(hatEtiket);

        String aktifArapcaFont = TemaMotoru.arapcaYaziTipiDosyasi(a);
        cipIzgarasiEkle(a, yaziBolumu, d, TemaMotoru.ARAPCA_FONTLAR, aktifArapcaFont, secilenDosya -> {
            TemaMotoru.arapcaYaziTipiSec(a, secilenDosya);
            degisti.run();
        });

        // Canlı Besmele-i Şerîf hat önizleme kutusu
        LinearLayout besmeleKutu = new LinearLayout(a);
        besmeleKutu.setOrientation(LinearLayout.VERTICAL);
        besmeleKutu.setGravity(Gravity.CENTER);
        besmeleKutu.setPadding(a.dp(14), a.dp(12), a.dp(14), a.dp(12));
        GradientDrawable besmeleArka = new GradientDrawable();
        besmeleArka.setCornerRadius(a.dp(14));
        besmeleArka.setColor(d.acik ? 0x121E6B55 : 0x24000000);
        besmeleArka.setStroke(Math.max(1, a.dp(1)), (d.vurgu & 0x00FFFFFF) | 0x55000000);
        besmeleKutu.setBackground(besmeleArka);
        LinearLayout.LayoutParams blp = new LinearLayout.LayoutParams(-1, -2);
        blp.setMargins(0, a.dp(10), 0, a.dp(6));
        besmeleKutu.setLayoutParams(blp);

        TextView besmeleMetin = new TextView(a);
        besmeleMetin.setText(BESMELE);
        besmeleMetin.setTypeface(Varlik.kuranYazisi(a));
        besmeleMetin.setTextSize(TypedValue.COMPLEX_UNIT_SP, TemaMotoru.olcekliSp(a, 24));
        besmeleMetin.setTextColor(d.vurgu);
        besmeleMetin.setGravity(Gravity.CENTER);
        besmeleKutu.addView(besmeleMetin);

        TextView besmeleMeal = metinOlustur(a,
                "Rahmân ve Rahîm olan Allah'ın adıyla  ·  " + seciliArapcaFontAdi(aktifArapcaFont),
                TemaMotoru.olcekliSp(a, 12), d.soluk, false);
        besmeleMeal.setGravity(Gravity.CENTER);
        besmeleMeal.setPadding(0, a.dp(4), 0, 0);
        besmeleKutu.addView(besmeleMeal);
        yaziBolumu.addView(besmeleKutu);

        anahtarSatiriEkle(a, yaziBolumu, d,
                "Klasik Serif Başlıklar",
                "Başlıklarda editoryal kitap serifi (Lora) yazı karakterini kullanır",
                TemaMotoru.serifBaslik(a),
                acik -> {
                    TemaMotoru.serifBaslikSec(a, acik);
                    degisti.run();
                });

        anahtarSatiriEkle(a, yaziBolumu, d,
                "Yüksek Kontrast",
                "Kart opaklığını, kenarlık belirginliğini ve metin netliğini artırır",
                TemaMotoru.yuksekKontrast(a),
                acik -> {
                    TemaMotoru.yuksekKontrastSec(a, acik);
                    degisti.run();
                });

        ana.addView(yaziBolumu);

        // ============================================================ 7. NAMAZ VAKTİ HESAPLAMA METODU & ASR-I SÂNÎ
        LinearLayout metotBolumu = studyoKarti(a, d);
        metotBolumu.addView(kartIciBaslik(a, "Namaz Vakti Hesaplama Metodu & Fıkıh Ayarı",
                "Bulunduğunuz coğrafyaya uygun fecir/yatsı açıları ve ikindi gölge ölçüsü", d));

        HesapMotoru.Metot aktifMetot = HesapMotoru.aktifMetot(a);
        for (HesapMotoru.Metot m : HesapMotoru.METOTLAR) {
            boolean secili = m.kod.equals(aktifMetot.kod);
            metotBolumu.addView(metotSatiriOlustur(a, d, m, secili, () -> {
                HesapMotoru.metotSec(a, m.kod);
                degisti.run();
            }));
        }

        anahtarSatiriEkle(a, metotBolumu, d,
                "Hanefî Asr-ı Sânî (İkindi Gölgesi 2 Misli)",
                "Açık olduğunda ikindi vakti, cismin gölgesi boyunun iki katına ulaştığında girer",
                HesapMotoru.asriSani(a),
                acik -> {
                    HesapMotoru.asriSaniSec(a, acik);
                    degisti.run();
                });

        // Canlı 6 sütunlu bugünün hesaplanan vakitleri önizleme şeridi
        VakitTakvimi.Takvim takvim = VakitTakvimi.oku(a);
        HesapMotoru.GunVakitleri gv = HesapMotoru.gun(a, takvim, System.currentTimeMillis());

        TextView vakitBaslik = metinOlustur(a,
                "BUGÜNÜN HESAPLANAN VAKİTLERİ" + (takvim.yer != null ? "  ·  " + takvim.yer.toUpperCase(Metinler.TR) : ""),
                11, d.vurgu, true);
        vakitBaslik.setLetterSpacing(0.06f);
        vakitBaslik.setPadding(0, a.dp(10), 0, a.dp(6));
        metotBolumu.addView(vakitBaslik);

        LinearLayout altiliSatir = new LinearLayout(a);
        altiliSatir.setOrientation(LinearLayout.HORIZONTAL);
        altiliSatir.setPadding(a.dp(6), a.dp(10), a.dp(6), a.dp(10));
        GradientDrawable altiliArka = new GradientDrawable();
        altiliArka.setCornerRadius(a.dp(14));
        altiliArka.setColor(d.acik ? 0x121E6B55 : 0x26000000);
        altiliArka.setStroke(Math.max(1, a.dp(1)), (d.vurgu & 0x00FFFFFF) | 0x44000000);
        altiliSatir.setBackground(altiliArka);

        String[] vakitAdlari = {"İmsak", "Güneş", "Öğle", "İkindi", "Akşam", "Yatsı"};
        long[] vakitSaatleri = {gv.imsak, gv.gunes, gv.ogle, gv.ikindi, gv.aksam, gv.yatsi};
        for (int i = 0; i < 6; i++) {
            LinearLayout sutun = new LinearLayout(a);
            sutun.setOrientation(LinearLayout.VERTICAL);
            sutun.setGravity(Gravity.CENTER);

            boolean ikindiVurgusu = (i == 3 && HesapMotoru.asriSani(a));
            TextView vAd = metinOlustur(a, vakitAdlari[i], 11, ikindiVurgusu ? d.vurgu : d.soluk, ikindiVurgusu);
            vAd.setGravity(Gravity.CENTER);
            sutun.addView(vAd);

            TextView vSaat = metinOlustur(a, Metinler.saat(vakitSaatleri[i]), 13,
                    ikindiVurgusu ? d.vurgu : d.metin, true);
            vSaat.setGravity(Gravity.CENTER);
            vSaat.setPadding(0, a.dp(2), 0, 0);
            sutun.addView(vSaat);

            altiliSatir.addView(sutun, new LinearLayout.LayoutParams(0, -2, 1f));
        }
        metotBolumu.addView(altiliSatir);

        ana.addView(metotBolumu);
    }

    // ================================================================ 16 tema kartı üreticisi

    private static View temaKartiOlustur(DurumAktivitesi a, TemaMotoru.Tema t, boolean secili, Runnable degisti) {
        final float dp = a.getResources().getDisplayMetrics().density;
        LinearLayout kart = new LinearLayout(a);
        kart.setOrientation(LinearLayout.VERTICAL);
        kart.setPadding(a.dp(12), a.dp(10), a.dp(12), a.dp(10));
        kart.setClickable(true);
        kart.setContentDescription("Tema " + t.ad);
        kart.setBackground(new TemaNumuneArkaPlan(t, secili, dp));
        a.basmaEfekti(kart);
        kart.setOnClickListener(v -> {
            v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            TemaMotoru.temaSec(a, t.kod);
            degisti.run();
        });

        // Üst satır: 3 renk noktası (vurgu, ana, zemin) + seçiliyse altın "✓ Seçili" rozeti
        LinearLayout ust = new LinearLayout(a);
        ust.setGravity(Gravity.CENTER_VERTICAL);

        LinearLayout noktalar = new LinearLayout(a);
        noktalar.setGravity(Gravity.CENTER_VERTICAL);
        int[] uclu = {t.vurgu, t.ana, t.zemin};
        for (int i = 0; i < uclu.length; i++) {
            View n = renkNoktasi(a, uclu[i], 12, 0x80FFFFFF);
            LinearLayout.LayoutParams nlp = new LinearLayout.LayoutParams(a.dp(12), a.dp(12));
            if (i > 0) nlp.setMargins(a.dp(4), 0, 0, 0);
            noktalar.addView(n, nlp);
        }
        ust.addView(noktalar, new LinearLayout.LayoutParams(0, -2, 1f));

        if (secili) {
            TextView rozet = new TextView(a);
            rozet.setText("✓ Seçili");
            rozet.setTextSize(TypedValue.COMPLEX_UNIT_SP, 10.5f);
            rozet.setTextColor(t.acikTema ? Color.WHITE : t.onVurgu);
            rozet.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
            rozet.setPadding(a.dp(7), a.dp(2), a.dp(7), a.dp(2));
            GradientDrawable rg = new GradientDrawable();
            rg.setCornerRadius(a.dp(10));
            rg.setColor(t.vurgu);
            rozet.setBackground(rg);
            ust.addView(rozet);
        }
        kart.addView(ust);

        View esnek = new View(a);
        kart.addView(esnek, new LinearLayout.LayoutParams(1, 0, 1f));

        int yaziRenk = Color.WHITE;
        int altRenk = 0xDDFFFFFF;
        if (t.acikTema) {
            yaziRenk = 0xFF14211C;
            altRenk = 0xCC263A32;
        }

        TextView ad = new TextView(a);
        ad.setText(t.ad);
        ad.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13.5f);
        ad.setTextColor(yaziRenk);
        ad.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
        ad.setSingleLine(true);
        ad.setEllipsize(TextUtils.TruncateAt.END);
        if (!t.acikTema) ad.setShadowLayer(a.dp(4), 0, a.dp(1), 0x88000000);
        kart.addView(ad);

        TextView alt = new TextView(a);
        alt.setText(t.altBaslik);
        alt.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f);
        alt.setTextColor(altRenk);
        alt.setMaxLines(2);
        alt.setEllipsize(TextUtils.TruncateAt.END);
        alt.setLineSpacing(0, 1.08f);
        if (!t.acikTema) alt.setShadowLayer(a.dp(3), 0, a.dp(1), 0x77000000);
        kart.addView(alt);

        return kart;
    }

    /** Her temanın kendi heroBas -> heroSon -> zemin geçişini ve imza GeometrikDesen'ini çizen Drawable. */
    private static final class TemaNumuneArkaPlan extends Drawable {
        private final TemaMotoru.Tema tema;
        private final boolean secili;
        private final float dp;
        private final Paint boya = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Path kesim = new Path();
        private final RectF kutu = new RectF();

        TemaNumuneArkaPlan(TemaMotoru.Tema tema, boolean secili, float dp) {
            this.tema = tema;
            this.secili = secili;
            this.dp = dp;
        }

        @Override
        public void draw(Canvas canvas) {
            Rect b = getBounds();
            if (b.width() <= 0 || b.height() <= 0) return;
            kutu.set(b);
            float r = 18f * dp;

            int kayit = canvas.save();
            kesim.reset();
            kesim.addRoundRect(kutu, r, r, Path.Direction.CW);
            canvas.clipPath(kesim);

            int[] gecisRenkleri = tema.acikTema
                    ? new int[]{0xFFFAF8F3, 0xFFF2EEE4, tema.zemin}
                    : new int[]{tema.heroBas, tema.heroSon, tema.zemin};
            boya.setStyle(Paint.Style.FILL);
            boya.setShader(new LinearGradient(
                    b.left, b.top, b.right, b.bottom,
                    gecisRenkleri, new float[]{0f, 0.55f, 1f}, Shader.TileMode.CLAMP));
            canvas.drawRect(kutu, boya);
            boya.setShader(null);

            int desenKod = tema.varsayilanDesen;
            if (desenKod != GeometrikDesen.KAPALI) {
                canvas.save();
                canvas.translate(b.left, b.top);
                GeometrikDesen.ciz(canvas, b.width(), b.height(), dp * 0.72f,
                        desenKod, tema.vurgu, tema.acikTema ? 34 : 38);
                canvas.restore();
            }
            canvas.restoreToCount(kayit);

            // Kenarlık
            boya.setStyle(Paint.Style.STROKE);
            float kalinlik = secili ? 2.4f * dp : 1.0f * dp;
            boya.setStrokeWidth(kalinlik);
            boya.setColor(secili ? tema.vurgu : (tema.acikTema ? 0x331F5C4B : 0x38FFFFFF));
            RectF cerceve = new RectF(kutu);
            cerceve.inset(kalinlik * 0.5f, kalinlik * 0.5f);
            canvas.drawRoundRect(cerceve, r, r, boya);
        }

        @Override public void setAlpha(int alpha) { boya.setAlpha(alpha); }
        @Override public void setColorFilter(ColorFilter cf) { boya.setColorFilter(cf); }
        @Override @SuppressWarnings("deprecation") public int getOpacity() { return PixelFormat.TRANSLUCENT; }
    }

    // ================================================================ Canlı Önizleme Sahnesi (OnizlemeView)

    static final class OnizlemeView extends View {
        private final TemaMotoru.Durum d;
        private Bitmap arkaFoto;
        private final Paint boya = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint fotoBoya = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.FILTER_BITMAP_FLAG);
        private final Paint metinBoya = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Matrix matris = new Matrix();
        private final Path yol = new Path();
        private final RectF kutu = new RectF();

        OnizlemeView(Context c, TemaMotoru.Durum d) {
            super(c);
            this.d = d;
            if (TemaMotoru.SAHNE_CANLI_FOTO.equals(d.sahneModu)) {
                String gorsel = TemaMotoru.sahneAnahtariCoz(c, "vakit_5");
                this.arkaFoto = Gorseller.al(c, gorsel, TemaMotoru.dp(c, 360));
            }
            final float r = TemaMotoru.dp(c, 22);
            setOutlineProvider(new ViewOutlineProvider() {
                @Override
                public void getOutline(View view, Outline outline) {
                    outline.setRoundRect(0, 0, view.getWidth(), view.getHeight(), r);
                }
            });
            setClipToOutline(true);
        }

        @Override
        protected void onDraw(Canvas c) {
            int w = getWidth();
            int h = getHeight();
            if (w <= 0 || h <= 0) return;
            float dp = getResources().getDisplayMetrics().density;
            float disR = 22f * dp;

            // 1. Arka plan zemin + sahne moduna göre heroBas..heroSon gradyanı + aktif fotoğraf
            boya.setStyle(Paint.Style.FILL);
            if (TemaMotoru.SAHNE_DUZ_AMOLED.equals(d.sahneModu) && !d.acik) {
                boya.setShader(null);
                boya.setColor(d.zemin);
                c.drawRect(0, 0, w, h, boya);
            } else {
                int ustRenk = d.acik ? 0xFFFAF7F0 : d.heroBas;
                int ortaRenk = d.acik ? 0xFFF1ECE1 : d.heroSon;
                boya.setShader(new LinearGradient(0, 0, 0, h,
                        new int[]{ustRenk, ortaRenk, d.zemin},
                        new float[]{0f, 0.56f, 1f}, Shader.TileMode.CLAMP));
                c.drawRect(0, 0, w, h, boya);
                boya.setShader(null);

                if (arkaFoto != null) {
                    float olcek = Math.max(w / (float) arkaFoto.getWidth(), h / (float) arkaFoto.getHeight());
                    matris.reset();
                    matris.postScale(olcek, olcek);
                    matris.postTranslate((w - arkaFoto.getWidth() * olcek) * 0.5f, (h - arkaFoto.getHeight() * olcek) * 0.35f);
                    fotoBoya.setAlpha(d.acik ? 72 : 138);
                    c.drawBitmap(arkaFoto, matris, fotoBoya);
                }

                // Ufuk kubbe parıltısı
                boya.setShader(new RadialGradient(w * 0.76f, h * 0.34f, w * 0.42f,
                        (d.vurgu & 0x00FFFFFF) | (d.acik ? 0x22000000 : 0x36000000),
                        0x00000000, Shader.TileMode.CLAMP));
                c.drawRect(0, 0, w, h, boya);
                boya.setShader(null);
            }

            // 2. Geometrik tezhip deseni
            if (d.desen != GeometrikDesen.KAPALI) {
                GeometrikDesen.ciz(c, w, h, dp * 0.80f, d.desen, d.vurgu, d.acik ? 28 : 30);
            }

            // 3. Mini cami kubbesi, minare ve hilâl silüeti (düz AMOLED hariç belirgin, AMOLED'de zarif çizgi)
            cizCamiSilueti(c, w, h, dp);

            // 4. Üst bilgi satırı: aktif tema rozeti + sahne modu etiketi
            float rozetYukseklik = 24f * dp;
            String rozetMetni = "✦ " + d.tema.ad;
            metinBoya.setTypeface(TemaMotoru.baslikTipi(getContext()));
            metinBoya.setTextSize(11.5f * dp);
            float rozetGenislik = metinBoya.measureText(rozetMetni) + 20f * dp;

            kutu.set(14f * dp, 12f * dp, 14f * dp + rozetGenislik, 12f * dp + rozetYukseklik);
            boya.setStyle(Paint.Style.FILL);
            boya.setColor(d.acik ? 0x201E6B55 : 0x40000000);
            c.drawRoundRect(kutu, rozetYukseklik * 0.5f, rozetYukseklik * 0.5f, boya);
            boya.setStyle(Paint.Style.STROKE);
            boya.setStrokeWidth(1f * dp);
            boya.setColor((d.vurgu & 0x00FFFFFF) | 0x88000000);
            c.drawRoundRect(kutu, rozetYukseklik * 0.5f, rozetYukseklik * 0.5f, boya);

            metinBoya.setColor(d.vurgu);
            Paint.FontMetrics fm = metinBoya.getFontMetrics();
            float rozetBazY = kutu.centerY() - (fm.ascent + fm.descent) * 0.5f;
            c.drawText(rozetMetni, kutu.left + 10f * dp, rozetBazY, metinBoya);

            // 5. Örnek cam kart (kartBicimi yarıçapı & kenarlığı ile)
            float kartSol = 14f * dp;
            float kartSag = w - 14f * dp;
            float kartUst = 46f * dp;
            float kartAlt = h - 14f * dp;
            float kartR = d.yaricapDp() * dp * 0.85f;
            kutu.set(kartSol, kartUst, kartSag, kartAlt);

            boya.setStyle(Paint.Style.FILL);
            if (TemaMotoru.KART_MAT.equals(d.kartBicimi)) {
                boya.setShader(null);
                boya.setColor(d.acik ? 0xF2FFFFFF : TemaMotoru.karistir(d.camUst, d.zemin, 0.35f) | 0xEC000000);
            } else {
                boya.setShader(new LinearGradient(kartSol, kartUst, kartSag, kartAlt,
                        d. camUst, d.camAlt, Shader.TileMode.CLAMP));
            }
            c.drawRoundRect(kutu, kartR, kartR, boya);
            boya.setShader(null);

            boya.setStyle(Paint.Style.STROKE);
            if (TemaMotoru.KART_CERCEVELI.equals(d.kartBicimi)) {
                boya.setStrokeWidth(1.8f * dp);
                boya.setColor((d.vurgu & 0x00FFFFFF) | 0xAA000000);
            } else {
                boya.setStrokeWidth(1f * dp);
                boya.setColor(d.camKenar);
            }
            c.drawRoundRect(kutu, kartR, kartR, boya);

            // 6. Sol tarafta geri sayım halkası önizlemesi ("01:24:18")
            float halkaR = Math.min((kartAlt - kartUst) * 0.36f, 44f * dp);
            float halkaCx = kartSol + 18f * dp + halkaR;
            float halkaCy = (kartUst + kartAlt) * 0.5f;

            boya.setStyle(Paint.Style.STROKE);
            boya.setStrokeWidth(4.5f * dp);
            boya.setStrokeCap(Paint.Cap.ROUND);
            boya.setColor(d.acik ? 0x2214211C : 0x26FFFFFF);
            c.drawCircle(halkaCx, halkaCy, halkaR, boya);

            RectF yayKutu = new RectF(halkaCx - halkaR, halkaCy - halkaR, halkaCx + halkaR, halkaCy + halkaR);
            boya.setColor(d.vurgu);
            c.drawArc(yayKutu, -90f, 248f, false, boya);

            // Halka içi sayaç
            metinBoya.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
            metinBoya.setTextSize(12.5f * dp * Math.min(1.12f, d.yaziOlcegi));
            metinBoya.setColor(d.metin);
            String sayac = "01:24:18";
            float sw = metinBoya.measureText(sayac);
            fm = metinBoya.getFontMetrics();
            c.drawText(sayac, halkaCx - sw * 0.5f, halkaCy - (fm.ascent + fm.descent) * 0.5f - 5f * dp, metinBoya);

            metinBoya.setTypeface(Typeface.DEFAULT);
            metinBoya.setTextSize(9.5f * dp);
            metinBoya.setColor(d.soluk);
            String altEtiket = "Akşam'a";
            float aw = metinBoya.measureText(altEtiket);
            c.drawText(altEtiket, halkaCx - aw * 0.5f, halkaCy + 12f * dp, metinBoya);

            // 7. Sağ tarafta Arapça Besmele + örnek vakit/meal satırı
            float yaziSol = halkaCx + halkaR + 16f * dp;
            float yaziSag = kartSag - 14f * dp;
            float yaziMerkezX = (yaziSol + yaziSag) * 0.5f;

            if (yaziSag > yaziSol + 40f * dp) {
                metinBoya.setTypeface(Varlik.kuranYazisi(getContext()));
                float arapcaBoyut = 18.5f * dp * Math.min(1.18f, d.yaziOlcegi);
                metinBoya.setTextSize(arapcaBoyut);
                while (arapcaBoyut > 12f * dp && metinBoya.measureText(BESMELE) > (yaziSag - yaziSol)) {
                    arapcaBoyut -= 1f * dp;
                    metinBoya.setTextSize(arapcaBoyut);
                }
                metinBoya.setColor(d.vurgu);
                float bw = metinBoya.measureText(BESMELE);
                c.drawText(BESMELE, yaziMerkezX - bw * 0.5f, halkaCy - 10f * dp, metinBoya);

                metinBoya.setTypeface(TemaMotoru.baslikTipi(getContext()));
                metinBoya.setTextSize(12.5f * dp * Math.min(1.15f, d.yaziOlcegi));
                metinBoya.setColor(d.metin);
                String ornekBaslik = "Kalpler Allah'ı anmakla huzur bulur";
                CharSequence kisaltilmis = TextUtils.ellipsize(ornekBaslik,
                        new android.text.TextPaint(metinBoya), yaziSag - yaziSol, TextUtils.TruncateAt.END);
                String satir1 = kisaltilmis.toString();
                float s1w = metinBoya.measureText(satir1);
                c.drawText(satir1, yaziMerkezX - s1w * 0.5f, halkaCy + 11f * dp, metinBoya);

                metinBoya.setTypeface(Typeface.DEFAULT);
                metinBoya.setTextSize(10.5f * dp);
                metinBoya.setColor(d.ana);
                String kaynak = "Ra'd Sûresi · 13/28";
                float kw = metinBoya.measureText(kaynak);
                c.drawText(kaynak, yaziMerkezX - kw * 0.5f, halkaCy + 27f * dp, metinBoya);
            }

            // Dış zarif altın çerçeve
            boya.setStyle(Paint.Style.STROKE);
            boya.setStrokeWidth(1.2f * dp);
            boya.setColor((d.vurgu & 0x00FFFFFF) | 0x66000000);
            kutu.set(0.6f * dp, 0.6f * dp, w - 0.6f * dp, h - 0.6f * dp);
            c.drawRoundRect(kutu, disR, disR, boya);
        }

        private void cizCamiSilueti(Canvas c, int w, int h, float dp) {
            float tabanY = 54f * dp;
            float kubbeMerkezX = w * 0.80f;
            float kubbeR = 22f * dp;

            int siluetRenk = d.acik
                    ? ((d.ana & 0x00FFFFFF) | 0x22000000)
                    : (TemaMotoru.SAHNE_DUZ_AMOLED.equals(d.sahneModu)
                    ? ((d.vurgu & 0x00FFFFFF) | 0x1E000000)
                    : 0x36000000);

            boya.setStyle(Paint.Style.FILL);
            boya.setColor(siluetRenk);

            // Ana kubbe
            RectF kubbe = new RectF(kubbeMerkezX - kubbeR, tabanY - kubbeR, kubbeMerkezX + kubbeR, tabanY + kubbeR);
            c.drawArc(kubbe, 180f, 180f, true, boya);

            // Yan yarım kubbeler
            float yanR = kubbeR * 0.58f;
            c.drawArc(new RectF(kubbeMerkezX - kubbeR - yanR * 0.9f, tabanY - yanR,
                    kubbeMerkezX - kubbeR + yanR * 1.1f, tabanY + yanR), 180f, 180f, true, boya);
            c.drawArc(new RectF(kubbeMerkezX + kubbeR - yanR * 1.1f, tabanY - yanR,
                    kubbeMerkezX + kubbeR + yanR * 0.9f, tabanY + yanR), 180f, 180f, true, boya);

            // İnce minare ve külah
            float minareX = kubbeMerkezX + kubbeR + 14f * dp;
            c.drawRect(minareX - 2.2f * dp, tabanY - 34f * dp, minareX + 2.2f * dp, tabanY, boya);
            yol.reset();
            yol.moveTo(minareX - 2.6f * dp, tabanY - 34f * dp);
            yol.lineTo(minareX, tabanY - 43f * dp);
            yol.lineTo(minareX + 2.6f * dp, tabanY - 34f * dp);
            yol.close();
            c.drawPath(yol, boya);

            // Kubbe âlemi (hilâl)
            float hilalCx = kubbeMerkezX;
            float hilalCy = tabanY - kubbeR - 6f * dp;
            float hr = 4.2f * dp;
            yol.reset();
            yol.addCircle(hilalCx, hilalCy, hr, Path.Direction.CW);
            Path icHilal = new Path();
            icHilal.addCircle(hilalCx + hr * 0.42f, hilalCy - hr * 0.18f, hr * 0.82f, Path.Direction.CW);
            yol.op(icHilal, Path.Op.DIFFERENCE);
            boya.setColor((d.vurgu & 0x00FFFFFF) | 0xCC000000);
            c.drawPath(yol, boya);
        }
    }

    // ================================================================ ortak UI bileşenleri

    private interface SecimDinleyici {
        void secildi(String kod);
    }

    private static void cipIzgarasiEkle(DurumAktivitesi a, LinearLayout ebeveyn, TemaMotoru.Durum d,
                                        String[][] secenekler, String aktifKod, SecimDinleyici dinleyici) {
        for (int i = 0; i < secenekler.length; i += 2) {
            LinearLayout satir = new LinearLayout(a);
            satir.setOrientation(LinearLayout.HORIZONTAL);
            LinearLayout.LayoutParams slp = new LinearLayout.LayoutParams(-1, -2);
            slp.setMargins(0, i == 0 ? a.dp(4) : a.dp(8), 0, 0);
            satir.setLayoutParams(slp);

            final String kodSol = secenekler[i][0];
            View sol = cipOlustur(a, d, secenekler[i][1], kodSol.equals(aktifKod),
                    () -> dinleyici.secildi(kodSol));
            LinearLayout.LayoutParams lpSol = new LinearLayout.LayoutParams(0, -2, 1f);
            lpSol.setMargins(0, 0, a.dp(4), 0);
            satir.addView(sol, lpSol);

            if (i + 1 < secenekler.length) {
                final String kodSag = secenekler[i + 1][0];
                View sag = cipOlustur(a, d, secenekler[i + 1][1], kodSag.equals(aktifKod),
                        () -> dinleyici.secildi(kodSag));
                LinearLayout.LayoutParams lpSag = new LinearLayout.LayoutParams(0, -2, 1f);
                lpSag.setMargins(a.dp(4), 0, 0, 0);
                satir.addView(sag, lpSag);
            } else {
                View bos = new View(a);
                LinearLayout.LayoutParams lpBos = new LinearLayout.LayoutParams(0, 1, 1f);
                lpBos.setMargins(a.dp(4), 0, 0, 0);
                satir.addView(bos, lpBos);
            }
            ebeveyn.addView(satir);
        }
    }

    private static TextView cipOlustur(DurumAktivitesi a, TemaMotoru.Durum d, String etiket,
                                       boolean secili, Runnable tiklama) {
        TextView t = new TextView(a);
        t.setText(secili ? "✓  " + etiket : etiket);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, TemaMotoru.olcekliSp(a, 13));
        t.setTextColor(secili ? d.birincilDugmeYaziRengi() : d.metin);
        t.setTypeface(Typeface.create("sans-serif-medium", secili ? Typeface.BOLD : Typeface.NORMAL));
        t.setGravity(Gravity.CENTER);
        t.setMinHeight(a.dp(42));
        t.setPadding(a.dp(10), a.dp(9), a.dp(10), a.dp(9));
        t.setBackground(d.cipArkaPlani(a, secili, 14));
        t.setClickable(true);
        t.setContentDescription(etiket);
        a.basmaEfekti(t);
        if (tiklama != null) {
            t.setOnClickListener(v -> {
                v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
                tiklama.run();
            });
        }
        return t;
    }

    private static View metotSatiriOlustur(DurumAktivitesi a, TemaMotoru.Durum d,
                                           HesapMotoru.Metot m, boolean secili, Runnable secEylem) {
        LinearLayout satir = new LinearLayout(a);
        satir.setGravity(Gravity.CENTER_VERTICAL);
        satir.setPadding(a.dp(12), a.dp(10), a.dp(12), a.dp(10));
        GradientDrawable arka = new GradientDrawable();
        arka.setCornerRadius(a.dp(14));
        if (secili) {
            arka.setColor((d.vurgu & 0x00FFFFFF) | (d.acik ? 0x22000000 : 0x2E000000));
            arka.setStroke(Math.max(2, a.dp(2)), d.vurgu);
        } else {
            arka.setColor(d.acik ? 0x0F14211C : 0x16FFFFFF);
            arka.setStroke(Math.max(1, a.dp(1)), d.acik ? 0x2414211C : 0x24FFFFFF);
        }
        satir.setBackground(arka);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(0, a.dp(6), 0, 0);
        satir.setLayoutParams(lp);
        satir.setClickable(true);
        satir.setContentDescription("Hesaplama metodu " + m.ad);
        a.basmaEfekti(satir);
        satir.setOnClickListener(v -> {
            v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            secEylem.run();
        });

        TextView radyo = metinOlustur(a, secili ? "◉" : "◯", 17, secili ? d.vurgu : d.silik, true);
        radyo.setPadding(0, 0, a.dp(10), 0);
        satir.addView(radyo);

        LinearLayout metinler = new LinearLayout(a);
        metinler.setOrientation(LinearLayout.VERTICAL);
        metinler.addView(metinOlustur(a, m.ad, 14, secili ? d.vurgu : d.metin, true));
        metinler.addView(metinOlustur(a, m.aciklama, 12, d.soluk, false));
        satir.addView(metinler, new LinearLayout.LayoutParams(0, -2, 1f));

        return satir;
    }

    private interface AnahtarDegisim {
        void degisti(boolean acik);
    }

    private static void anahtarSatiriEkle(DurumAktivitesi a, LinearLayout ebeveyn, TemaMotoru.Durum d,
                                          String baslik, String aciklama, boolean acik, AnahtarDegisim dinleyici) {
        LinearLayout s = new LinearLayout(a);
        s.setGravity(Gravity.CENTER_VERTICAL);
        s.setPadding(0, a.dp(10), 0, a.dp(6));

        LinearLayout yazi = new LinearLayout(a);
        yazi.setOrientation(LinearLayout.VERTICAL);
        yazi.setPadding(0, 0, a.dp(10), 0);
        yazi.addView(metinOlustur(a, baslik, 14, d.metin, true));
        yazi.addView(metinOlustur(a, aciklama, 12, d.soluk, false));
        s.addView(yazi, new LinearLayout.LayoutParams(0, -2, 1f));

        final Switch sw = new Switch(a);
        sw.setChecked(acik);
        sw.setContentDescription(baslik);
        sw.setThumbTintList(ColorStateList.valueOf(acik ? d.vurgu : 0xFFE0E0E0));
        sw.setOnCheckedChangeListener((b, yeni) -> {
            b.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            sw.setThumbTintList(ColorStateList.valueOf(yeni ? d.vurgu : 0xFFE0E0E0));
            dinleyici.degisti(yeni);
        });
        s.addView(sw);
        ebeveyn.addView(s);
    }

    private static LinearLayout studyoKarti(DurumAktivitesi a, TemaMotoru.Durum d) {
        LinearLayout k = new LinearLayout(a);
        k.setOrientation(LinearLayout.VERTICAL);
        k.setPadding(a.dp(16), a.dp(15), a.dp(16), a.dp(15));
        k.setBackground(d.kartArkaPlani(a));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(0, a.dp(4), 0, a.dp(12));
        k.setLayoutParams(lp);
        return k;
    }

    private static TextView bolumBasligi(DurumAktivitesi a, String s, TemaMotoru.Durum d) {
        TextView t = a.metin(s, 12, d.acik ? DurumAktivitesi.ALTIN : d.vurgu, true);
        t.setLetterSpacing(0.08f);
        t.setPadding(a.dp(4), a.dp(8), a.dp(4), a.dp(6));
        return t;
    }

    private static View kartIciBaslik(DurumAktivitesi a, String baslik, String alt, TemaMotoru.Durum d) {
        LinearLayout l = new LinearLayout(a);
        l.setOrientation(LinearLayout.VERTICAL);
        l.setPadding(0, 0, 0, a.dp(8));

        TextView b = metinOlustur(a, baslik, 16, d.metin, true);
        b.setTypeface(TemaMotoru.baslikTipi(a), Typeface.BOLD);
        l.addView(b);

        if (alt != null && !alt.isEmpty()) {
            TextView ac = metinOlustur(a, alt, 12, d.soluk, false);
            ac.setPadding(0, a.dp(2), 0, 0);
            l.addView(ac);
        }
        return l;
    }

    private static TextView metinOlustur(DurumAktivitesi a, String metin, int bazSp, int renk, boolean kalin) {
        TextView t = new TextView(a);
        t.setText(metin);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, TemaMotoru.olcekliSp(a, bazSp));
        t.setTextColor(renk);
        t.setTypeface(kalin ? Typeface.create("sans-serif-medium", Typeface.NORMAL) : Typeface.DEFAULT);
        t.setLineSpacing(0, 1.14f);
        return t;
    }

    private static View renkNoktasi(DurumAktivitesi a, int renk, int capDp, int kenarRenk) {
        View v = new View(a);
        GradientDrawable g = new GradientDrawable();
        g.setShape(GradientDrawable.OVAL);
        g.setColor(renk | 0xFF000000);
        g.setStroke(Math.max(1, a.dp(1)), kenarRenk);
        g.setSize(a.dp(capDp), a.dp(capDp));
        v.setBackground(g);
        return v;
    }

    private static String seciliArapcaFontAdi(String dosya) {
        for (String[] f : TemaMotoru.ARAPCA_FONTLAR) {
            if (f[0].equals(dosya)) return f[1];
        }
        return TemaMotoru.ARAPCA_FONTLAR[0][1];
    }

    private static String kisaMetotAdi(HesapMotoru.Metot m) {
        if (m == null) return "Diyanet";
        if ("diyanet".equals(m.kod)) return "Diyanet";
        return m.ad;
    }
}
