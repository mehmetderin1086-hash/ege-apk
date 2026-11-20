package com.mehmetderin.secde_vakti.saglik;

import android.app.AlertDialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.HapticFeedbackConstants;
import android.view.View;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.Date;
import java.util.List;
import java.util.Locale;

/**
 * Ramazan ve Oruç Modu:
 *  - Canlı İftar / Sahur geri sayım kartı (1 saniyelik akıcı sayaç ve oruç ilerleme çubuğu)
 *  - İftar ve Sahur (Niyet) Duâları (Arapça hat, Türkçe okunuş ve meal)
 *  - 30 Günlük İmsakiye alt sayfası (Diyanet + çevrimdışı astronomik hibrit, Cuma / Kadir Gecesi / Arefe vurgulu)
 */
public final class RamazanModu {

    public static final String ANAHTAR_HER_ZAMAN_GOSTER = "ramazan_karti_goster";
    public static final String ANAHTAR_SUNNET_HATIRLAT = "sunnet_oruc_hatirlat";

    public static final String IFTAR_DUASI_ARAPCA =
            "اللَّهُمَّ لَكَ صُمْتُ وَبِكَ آمَنْتُ وَعَلَيْكَ تَوَكَّلْتُ وَعَلَى رِزْقِكَ أَفْطَرْتُ";
    public static final String IFTAR_DUASI_OKUNUS =
            "Allâhümme leke sumtü ve bike âmentü ve aleyke tevekkeltü ve alâ rızkıke eftartü.";
    public static final String IFTAR_DUASI_MEAL =
            "Allah'ım! Senin rızân için oruç tuttum, sana inandım, sana güvendim ve senin verdiğin rızıkla orucumu açtım.";

    public static final String NEBEVI_IFTAR_ARAPCA =
            "ذَهَبَ الظَّمَأُ وَابْتَلَّتِ الْعُرُوقُ وَثَبَتَ الْأَجْرُ إِنْ شَاءَ اللَّهُ";
    public static final String NEBEVI_IFTAR_MEAL =
            "\"Zehebe'z-zameü vebtelleti'l-urûku ve sebete'l-ecru inşâallâh.\" — "
                    + "Susuzluk gitti, damarlar ıslandı ve inşallah mükâfat sabit oldu. (Ebû Dâvûd, Savm, 22)";

    public static final String SAHUR_NIYET_ARAPCA =
            "نَوَيْتُ أَنْ أَصُومَ صَوْمَ شَهْرِ رَمَضَانَ مِنَ الْفَجْرِ إِلَى الْمَغْرِبِ خَالِصًا لِلَّهِ تَعَالَى";
    public static final String SAHUR_NIYET_OKUNUS =
            "Neveytü en esûme savme şehri Ramazâne mine'l-fecri ile'l-mağribi hâlisan lillâhi Teâlâ.";
    public static final String SAHUR_NIYET_MEAL =
            "Niyet ettim Allah rızâsı için Ramazan ayının orucunu fecrin doğuşundan güneşin batışına kadar tutmaya. "
                    + "(Nâfile veya kazâ oruçlarında kalben hangi oruca niyet edildiğini geçirmek yeterlidir.)";

    private RamazanModu() {}

    /** Hicrî tarihte "Ramazan" geçip geçmediğini büyük/küçük harf duyarsız denetler. */
    public static boolean ramazanMi(VakitTakvimi.Takvim t) {
        if (t == null) return false;
        String h = t.hicri != null ? t.hicri : t.bugunHicri();
        return hicriRamazanMi(h);
    }

    private static boolean hicriRamazanMi(String hicri) {
        if (hicri == null || hicri.isEmpty()) return false;
        String tr = hicri.toLowerCase(Metinler.TR);
        String en = hicri.toLowerCase(Locale.ROOT);
        return tr.contains("ramazan") || en.contains("ramazan") || en.contains("ramadan");
    }

    /**
     * Ana ekranda İftar/Sahur kartının gösterilip gösterilmeyeceğini belirler:
     *  - Ramazan ayındaysak, VEYA
     *  - Kullanıcı "ramazan_karti_goster" tercihini açtıysa, VEYA
     *  - Pazartesi/Perşembe sünnet orucu hatırlatıcısı açık ve bugün Pazartesi/Perşembe ise true döner.
     */
    public static boolean anaEkrandaGoster(Context c, VakitTakvimi.Takvim t) {
        if (ramazanMi(t)) return true;
        if (Tercihler.sp(c).getBoolean(ANAHTAR_HER_ZAMAN_GOSTER, false)) return true;
        if (Tercihler.sp(c).getBoolean(ANAHTAR_SUNNET_HATIRLAT, false)) {
            int dow = Calendar.getInstance().get(Calendar.DAY_OF_WEEK);
            return dow == Calendar.MONDAY || dow == Calendar.THURSDAY;
        }
        return false;
    }

    public static boolean herZamanGoster(Context c) {
        return Tercihler.sp(c).getBoolean(ANAHTAR_HER_ZAMAN_GOSTER, false);
    }

    public static void herZamanGosterSec(Context c, boolean acik) {
        Tercihler.sp(c).edit().putBoolean(ANAHTAR_HER_ZAMAN_GOSTER, acik).apply();
    }

    public static boolean sunnetHatirlat(Context c) {
        return Tercihler.sp(c).getBoolean(ANAHTAR_SUNNET_HATIRLAT, false);
    }

    public static void sunnetHatirlatSec(Context c, boolean acik) {
        Tercihler.sp(c).edit().putBoolean(ANAHTAR_SUNNET_HATIRLAT, acik).apply();
    }

    // ================================================================ Vakitler Sekmesi Canlı Kartı

    /**
     * Vakitler sekmesi için canlı İftar / Sahur geri sayım kartı:
     *  - İmsak öncesi : Sahur bitimine (İmsak'a) kalan süre
     *  - İmsak–Akşam  : İftar'a kalan süre + görsel oruç ilerleme çubuğu
     *  - Akşam sonrası: Ertesi günün sahur (İmsak) vaktine kalan süre
     */
    public static View anaKart(final DurumAktivitesi a, final VakitTakvimi.Takvim t) {
        final TemaMotoru.Durum tm = TemaMotoru.aktif(a);
        final LinearLayout k = kart(a, tm);

        // Üst etiket + Vakit saatleri satırı
        LinearLayout ust = new LinearLayout(a);
        ust.setOrientation(LinearLayout.HORIZONTAL);
        ust.setGravity(Gravity.CENTER_VERTICAL);

        boolean ramazan = ramazanMi(t);
        int dow = Calendar.getInstance().get(Calendar.DAY_OF_WEEK);
        boolean sunnetGunu = (dow == Calendar.MONDAY || dow == Calendar.THURSDAY);
        String baslikEtiket = ramazan
                ? "🌙  RAMAZAN-I ŞERİF"
                : (sunnetGunu ? "🌿  SÜNNET ORUCU VAKİTLERİ" : "🌙  SAHUR VE İFTAR SAYACI");

        final TextView tvUstEtiket = metin(a, tm, baslikEtiket, 11, tm.vurgu, true);
        tvUstEtiket.setLetterSpacing(0.06f);
        ust.addView(tvUstEtiket, new LinearLayout.LayoutParams(0, -2, 1f));

        final TextView tvDurumRozet = metin(a, tm, "", 11, tm.iyi, true);
        tvDurumRozet.setShadowLayer(0, 0, 0, 0);
        tvDurumRozet.setPadding(a.dp(9), a.dp(3), a.dp(9), a.dp(3));
        GradientDrawable rBg = new GradientDrawable();
        rBg.setCornerRadius(a.dp(10));
        rBg.setColor((tm.vurgu & 0x00FFFFFF) | (tm.acik ? 0x1E000000 : 0x2A000000));
        rBg.setStroke(1, (tm.vurgu & 0x00FFFFFF) | 0x66000000);
        tvDurumRozet.setBackground(rBg);
        ust.addView(tvDurumRozet);
        k.addView(ust);

        a.bosluk(k, 6);

        // Ana geri sayım satırı
        LinearLayout sayacSatir = new LinearLayout(a);
        sayacSatir.setOrientation(LinearLayout.HORIZONTAL);
        sayacSatir.setGravity(Gravity.CENTER_VERTICAL);

        LinearLayout solSayac = new LinearLayout(a);
        solSayac.setOrientation(LinearLayout.VERTICAL);
        final TextView tvHedefAd = metin(a, tm, "", 13, tm.soluk, true);
        final TextView tvSayac = metin(a, tm, "00:00:00", 30, tm.metin, true);
        tvSayac.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        tvSayac.setLetterSpacing(0.03f);
        solSayac.addView(tvHedefAd);
        solSayac.addView(tvSayac);
        sayacSatir.addView(solSayac, new LinearLayout.LayoutParams(0, -2, 1f));

        // Sağda İmsak & İftar kutucuğu
        LinearLayout sagSaatler = new LinearLayout(a);
        sagSaatler.setOrientation(LinearLayout.VERTICAL);
        sagSaatler.setGravity(Gravity.END);
        sagSaatler.setPadding(a.dp(10), a.dp(6), a.dp(10), a.dp(6));
        GradientDrawable sBg = new GradientDrawable();
        sBg.setCornerRadius(a.dp(12));
        sBg.setColor(tm.acik ? 0x1014211C : 0x1AFFFFFF);
        sBg.setStroke(1, tm.acik ? 0x2214211C : 0x28FFFFFF);
        sagSaatler.setBackground(sBg);

        final TextView tvImsakSaat = metin(a, tm, "", 12, tm.soluk, true);
        final TextView tvIftarSaat = metin(a, tm, "", 13, tm.vurgu, true);
        sagSaatler.addView(tvImsakSaat);
        sagSaatler.addView(tvIftarSaat);
        sayacSatir.addView(sagSaatler);
        k.addView(sayacSatir);

        // İlerleme çubuğu (İmsak - İftar arası doluluk)
        a.bosluk(k, 8);
        final FrameLayout ilerlemeDis = new FrameLayout(a);
        GradientDrawable izBg = new GradientDrawable();
        izBg.setCornerRadius(a.dp(5));
        izBg.setColor(tm.acik ? 0x1814211C : 0x24FFFFFF);
        ilerlemeDis.setBackground(izBg);
        final View ilerlemeDolu = new View(a);
        GradientDrawable doluBg = new GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT,
                new int[]{tm.vurguKoyu, tm.vurgu});
        doluBg.setCornerRadius(a.dp(5));
        ilerlemeDolu.setBackground(doluBg);
        ilerlemeDis.addView(ilerlemeDolu, new FrameLayout.LayoutParams(0, a.dp(7)));
        k.addView(ilerlemeDis, new LinearLayout.LayoutParams(-1, a.dp(7)));

        // Eylem düğmeleri: [ İftar Duâsı ]  [ 30 Günlük İmsakiye › ]
        LinearLayout dugmeler = new LinearLayout(a);
        dugmeler.setOrientation(LinearLayout.HORIZONTAL);
        TextView duaBtn = temaDugmesi(a, tm, "🤲 İftar Duâsı", false,
                v -> iftarDuasiGoster(a));
        TextView imsakiyeBtn = temaDugmesi(a, tm, "30 Günlük İmsakiye ›", true,
                v -> a.guvenli("imsakiye", () -> imsakiyeAc(a, t)));
        dugmeler.addView(duaBtn, a.yarim(true));
        dugmeler.addView(imsakiyeBtn, a.yarim(false));
        k.addView(dugmeler);

        // Canlı güncelleyici (1 sn)
        final Handler handler = new Handler(Looper.getMainLooper());
        final Runnable guncelle = new Runnable() {
            @Override
            public void run() {
                long simdi = System.currentTimeMillis();
                HesapMotoru.GunVakitleri bugun = HesapMotoru.gun(a, t, simdi);
                HesapMotoru.GunVakitleri yarin = HesapMotoru.gun(a, t, komsuGunMs(simdi, 1));

                long hedefMs;
                float oran;
                if (simdi < bugun.imsak) {
                    hedefMs = bugun.imsak;
                    tvHedefAd.setText("Sahur bitimine (İmsak'a) kalan");
                    tvDurumRozet.setText("Sahur Vakti");
                    tvDurumRozet.setTextColor(tm.iyi);
                    tvImsakSaat.setText("İmsak  " + Metinler.saat(bugun.imsak));
                    tvIftarSaat.setText("İftar  " + Metinler.saat(bugun.aksam));
                    HesapMotoru.GunVakitleri dun = HesapMotoru.gun(a, t, komsuGunMs(simdi, -1));
                    long geceToplam = Math.max(1L, bugun.imsak - dun.aksam);
                    oran = Math.max(0f, Math.min(1f, (simdi - dun.aksam) / (float) geceToplam));
                } else if (simdi < bugun.aksam) {
                    hedefMs = bugun.aksam;
                    long orucToplam = Math.max(1L, bugun.aksam - bugun.imsak);
                    oran = Math.max(0f, Math.min(1f, (simdi - bugun.imsak) / (float) orucToplam));
                    int yuzde = Math.round(oran * 100f);
                    tvHedefAd.setText("İftar vaktine kalan süre");
                    tvDurumRozet.setText("%" + yuzde + " tamamlandı");
                    tvDurumRozet.setTextColor(tm.vurgu);
                    tvImsakSaat.setText("İmsak  " + Metinler.saat(bugun.imsak));
                    tvIftarSaat.setText("İftar  " + Metinler.saat(bugun.aksam));
                } else {
                    hedefMs = yarin.imsak;
                    tvHedefAd.setText("Hayırlı İftarlar · Yarınki Sahur'a kalan");
                    tvDurumRozet.setText("İftar Oldu ✓");
                    tvDurumRozet.setTextColor(tm.iyi);
                    tvImsakSaat.setText("Yarın İmsak  " + Metinler.saat(yarin.imsak));
                    tvIftarSaat.setText("Yarın İftar  " + Metinler.saat(yarin.aksam));
                    oran = 1f;
                }

                tvSayac.setText(Metinler.sayac(Math.max(0L, hedefMs - simdi)));
                int disGen = ilerlemeDis.getWidth();
                if (disGen > 0) {
                    FrameLayout.LayoutParams dlp = (FrameLayout.LayoutParams) ilerlemeDolu.getLayoutParams();
                    int yeniGen = Math.round(disGen * oran);
                    if (dlp.width != yeniGen) {
                        dlp.width = yeniGen;
                        ilerlemeDolu.setLayoutParams(dlp);
                    }
                } else {
                    final float sonOran = oran;
                    ilerlemeDis.post(() -> {
                        int g = ilerlemeDis.getWidth();
                        if (g > 0) {
                            FrameLayout.LayoutParams dlp = (FrameLayout.LayoutParams) ilerlemeDolu.getLayoutParams();
                            dlp.width = Math.round(g * sonOran);
                            ilerlemeDolu.setLayoutParams(dlp);
                        }
                    });
                }
                handler.postDelayed(this, 1000);
            }
        };

        guncelle.run();
        handler.removeCallbacks(guncelle);
        k.addOnAttachStateChangeListener(new View.OnAttachStateChangeListener() {
            @Override
            public void onViewAttachedToWindow(View v) {
                handler.removeCallbacks(guncelle);
                handler.post(guncelle);
            }

            @Override
            public void onViewDetachedFromWindow(View v) {
                handler.removeCallbacks(guncelle);
            }
        });
        return k;
    }

    /** İftar ve Sahur Niyet Duâsı penceresini açar. */
    public static void iftarDuasiGoster(final DurumAktivitesi a) {
        TemaMotoru.Durum tm = TemaMotoru.aktif(a);
        ScrollView sv = new ScrollView(a);
        LinearLayout icerik = new LinearLayout(a);
        icerik.setOrientation(LinearLayout.VERTICAL);
        icerik.setPadding(a.dp(20), a.dp(12), a.dp(20), a.dp(8));

        Typeface arapcaTip = Varlik.kuranYazisi(a);

        TextView ar1 = new TextView(a);
        ar1.setText(IFTAR_DUASI_ARAPCA);
        ar1.setTypeface(arapcaTip);
        ar1.setTextSize(23);
        ar1.setGravity(Gravity.CENTER);
        ar1.setLineSpacing(0, 1.35f);
        ar1.setPadding(0, a.dp(4), 0, a.dp(8));
        icerik.addView(ar1);

        TextView ok1 = new TextView(a);
        ok1.setText("Okunuşu: " + IFTAR_DUASI_OKUNUS);
        ok1.setTextSize(14);
        ok1.setTypeface(Typeface.create("sans-serif-medium", Typeface.ITALIC));
        ok1.setPadding(0, 0, 0, a.dp(6));
        icerik.addView(ok1);

        TextView ml1 = new TextView(a);
        ml1.setText("Anlamı: " + IFTAR_DUASI_MEAL);
        ml1.setTextSize(14);
        ml1.setPadding(0, 0, 0, a.dp(12));
        icerik.addView(ml1);

        View cizgi = new View(a);
        cizgi.setBackgroundColor(tm.acik ? 0x22000000 : 0x33FFFFFF);
        icerik.addView(cizgi, new LinearLayout.LayoutParams(-1, 1));

        TextView bas2 = new TextView(a);
        bas2.setText("\nPeygamber Efendimiz'in (s.a.v.) İftar Duâsı");
        bas2.setTextSize(14);
        bas2.setTypeface(Typeface.DEFAULT_BOLD);
        icerik.addView(bas2);

        TextView ar2 = new TextView(a);
        ar2.setText(NEBEVI_IFTAR_ARAPCA);
        ar2.setTypeface(arapcaTip);
        ar2.setTextSize(21);
        ar2.setGravity(Gravity.CENTER);
        ar2.setLineSpacing(0, 1.35f);
        ar2.setPadding(0, a.dp(6), 0, a.dp(6));
        icerik.addView(ar2);

        TextView ml2 = new TextView(a);
        ml2.setText(NEBEVI_IFTAR_MEAL);
        ml2.setTextSize(13);
        icerik.addView(ml2);

        sv.addView(icerik);

        new AlertDialog.Builder(a)
                .setTitle("İftar Duâsı")
                .setView(sv)
                .setPositiveButton("Kapat", null)
                .setNeutralButton("Kopyala", (d, w) -> {
                    ClipboardManager cm = (ClipboardManager) a.getSystemService(Context.CLIPBOARD_SERVICE);
                    if (cm != null) {
                        String metin = IFTAR_DUASI_ARAPCA + "\n\n" + IFTAR_DUASI_OKUNUS + "\n" + IFTAR_DUASI_MEAL;
                        cm.setPrimaryClip(ClipData.newPlainText("İftar Duâsı", metin));
                        Toast.makeText(a, "İftar duâsı panoya kopyalandı", Toast.LENGTH_SHORT).show();
                    }
                })
                .show();
    }

    // ================================================================ 30 Günlük İmsakiye Alt Sayfası

    /**
     * 30 Günlük İmsakiye ve Oruç Vakitleri alt sayfasını açar.
     */
    public static void imsakiyeAc(final DurumAktivitesi a, final VakitTakvimi.Takvim t) {
        final TemaMotoru.Durum tm = TemaMotoru.aktif(a);
        final VakitTakvimi.Takvim takvim = t != null ? t : VakitTakvimi.oku(a);
        final List<Vakit> kurulu = VakitDeposu.gelecek(a);

        LinearLayout s = a.sutun();

        boolean ramazan = ramazanMi(takvim);
        String yerAdi = (takvim.yer != null && !takvim.yer.isEmpty()) ? takvim.yer : "Konumunuz";
        String metotAdi = HesapMotoru.aktifMetot(a).ad;
        s.addView(metin(a, tm, yerAdi + "  ·  " + metotAdi, 13, tm.soluk, false));
        a.bosluk(s, 8);

        // Başlangıç gününü belirle (Ramazan içindeysek 1 Ramazan'dan, değilse bugünden)
        Calendar baslangicCal = imsakiyeBaslangicGunu(takvim, ramazan);
        int baslangicRamazanGunu = ramazan ? 1 : 0;

        // Tablo Üst Başlığı
        LinearLayout baslik = new LinearLayout(a);
        baslik.setGravity(Gravity.CENTER_VERTICAL);
        baslik.setPadding(a.dp(10), 0, a.dp(10), a.dp(6));
        baslik.addView(metin(a, tm, "Tarih", 11, tm.silik, true), new LinearLayout.LayoutParams(a.dp(82), -2));
        String[] sutunAdlari = {"İmsak", "Güneş", "Öğle", "İkindi", "İftar", "Yatsı"};
        for (int c = 0; c < sutunAdlari.length; c++) {
            boolean anaVakit = (c == 0 || c == 4);
            TextView x = metin(a, tm, sutunAdlari[c], 11, anaVakit ? tm.vurgu : tm.silik, true);
            x.setGravity(Gravity.CENTER);
            baslik.addView(x, new LinearLayout.LayoutParams(0, -2, 1f));
        }
        s.addView(baslik);

        // 30 Günlük Tablo Kartı ve Paylaşım Metni Üretimi
        LinearLayout tabloKart = kart(a, tm);
        tabloKart.setPadding(a.dp(6), a.dp(8), a.dp(6), a.dp(8));

        SimpleDateFormat gunAdBicim = new SimpleDateFormat("d MMM EEE", Metinler.TR);
        SimpleDateFormat paylasTarihBicim = new SimpleDateFormat("dd.MM EEE", Metinler.TR);
        StringBuilder paylasMetni = new StringBuilder();
        paylasMetni.append("🌙 SECDE VAKTİ · 30 GÜNLÜK İMSAKİYE\n");
        paylasMetni.append("📍 ").append(yerAdi).append(" (").append(metotAdi).append(")\n");
        paylasMetni.append("────────────────────────────────────\n");
        paylasMetni.append("Tarih        İmsak   Güneş   Öğle    İkindi  İftar   Yatsı\n");

        Calendar bugunCal = Calendar.getInstance();
        Calendar iterCal = (Calendar) baslangicCal.clone();
        boolean yaklasikVar = false;

        for (int i = 0; i < 30; i++) {
            long gunMs = iterCal.getTimeInMillis();
            HesapMotoru.GunVakitleri gv = HesapMotoru.gun(a, takvim, gunMs);
            if (gv.yaklasik) yaklasikVar = true;

            boolean bugunMu = ayniGun(iterCal, bugunCal);
            boolean cuma = iterCal.get(Calendar.DAY_OF_WEEK) == Calendar.FRIDAY;
            int ramazanGunNo = baslangicRamazanGunu > 0 ? (baslangicRamazanGunu + i) : ramazanGunuCikar(takvim.hicri(gunMs));
            String ozelEtiket = ozelGunEtiketi(takvim, kurulu, iterCal, ramazanGunNo);
            boolean kadirGecesi = ozelEtiket != null && ozelEtiket.contains("Kadir");
            boolean arefe = ozelEtiket != null && ozelEtiket.contains("Arefe");

            LinearLayout satirKapsayici = new LinearLayout(a);
            satirKapsayici.setOrientation(LinearLayout.VERTICAL);
            satirKapsayici.setPadding(a.dp(6), a.dp(7), a.dp(6), a.dp(7));

            if (bugunMu || kadirGecesi || arefe || cuma) {
                GradientDrawable sBg = new GradientDrawable();
                sBg.setCornerRadius(a.dp(11));
                if (bugunMu) {
                    sBg.setColor((tm.vurgu & 0x00FFFFFF) | (tm.acik ? 0x26000000 : 0x38000000));
                    sBg.setStroke(Math.max(1, a.dp(1)), tm.vurgu);
                } else if (kadirGecesi) {
                    sBg.setColor((tm.iyi & 0x00FFFFFF) | (tm.acik ? 0x22000000 : 0x30000000));
                    sBg.setStroke(Math.max(1, a.dp(1)), tm.iyi);
                } else if (arefe) {
                    sBg.setColor(0x28E89DBD);
                    sBg.setStroke(1, 0x88E89DBD);
                } else {
                    sBg.setColor((tm.vurgu & 0x00FFFFFF) | (tm.acik ? 0x0E000000 : 0x14000000));
                }
                satirKapsayici.setBackground(sBg);
            }

            LinearLayout r = new LinearLayout(a);
            r.setOrientation(LinearLayout.HORIZONTAL);
            r.setGravity(Gravity.CENTER_VERTICAL);

            // Sol tarih + Hicrî/Ramazan günü + ≈ işareti
            LinearLayout tarihKutusu = new LinearLayout(a);
            tarihKutusu.setOrientation(LinearLayout.VERTICAL);
            String tarihYazi = gunAdBicim.format(new Date(gunMs)) + (gv.yaklasik ? " ≈" : "");
            int tarihRenk = bugunMu ? tm.vurgu : (kadirGecesi ? tm.iyi : (cuma ? tm.vurgu : tm.metin));
            TextView tvTarih = metin(a, tm, tarihYazi, 11, tarihRenk, bugunMu || cuma || kadirGecesi);
            tvTarih.setShadowLayer(0, 0, 0, 0);
            tvTarih.setPadding(0, 0, 0, 0);
            tarihKutusu.addView(tvTarih);

            String altTarih = ramazanGunNo > 0 ? (ramazanGunNo + " Ramazan") : kisaHicri(takvim.hicri(gunMs));
            if (bugunMu) altTarih = (altTarih != null ? altTarih + " · Bugün" : "Bugün");
            if (altTarih != null && !altTarih.isEmpty()) {
                TextView tvAlt = metin(a, tm, altTarih, 9, bugunMu ? tm.vurgu : tm.silik, bugunMu);
                tvAlt.setShadowLayer(0, 0, 0, 0);
                tvAlt.setPadding(0, 0, 0, 0);
                tarihKutusu.addView(tvAlt);
            }
            r.addView(tarihKutusu, new LinearLayout.LayoutParams(a.dp(82), -2));

            long[] vakitAnlari = {gv.imsak, gv.gunes, gv.ogle, gv.ikindi, gv.aksam, gv.yatsi};
            StringBuilder paylasSatir = new StringBuilder();
            paylasSatir.append(String.format(Locale.ROOT, "%-12s ",
                    paylasTarihBicim.format(new Date(gunMs)) + (gv.yaklasik ? "≈" : "")));

            for (int c = 0; c < 6; c++) {
                String sStr = Metinler.saat(vakitAnlari[c]);
                boolean vurguSutun = (c == 0 || c == 4); // İmsak ve İftar
                int sRenk = vurguSutun ? (c == 4 ? tm.vurgu : tm.metin) : tm.soluk;
                if (bugunMu && vurguSutun) sRenk = tm.vurgu;
                TextView tvSaat = metin(a, tm, sStr, 12, sRenk, vurguSutun || bugunMu);
                tvSaat.setShadowLayer(0, 0, 0, 0);
                tvSaat.setGravity(Gravity.CENTER);
                tvSaat.setPadding(0, 0, 0, 0);
                r.addView(tvSaat, new LinearLayout.LayoutParams(0, -2, 1f));
                paylasSatir.append(String.format(Locale.ROOT, "%-7s ", sStr));
            }
            satirKapsayici.addView(r);

            if (ozelEtiket != null) {
                int etRenk = kadirGecesi ? tm.iyi : (arefe ? 0xFFE89DBD : tm.vurgu);
                TextView tvOzel = metin(a, tm, "✦ " + ozelEtiket, 11, etRenk, true);
                tvOzel.setShadowLayer(0, 0, 0, 0);
                tvOzel.setPadding(0, a.dp(2), 0, 0);
                satirKapsayici.addView(tvOzel);
                paylasSatir.append(" [").append(ozelEtiket).append("]");
            }

            LinearLayout.LayoutParams rlp = new LinearLayout.LayoutParams(-1, -2);
            if (i < 29) rlp.setMargins(0, 0, 0, a.dp(2));
            tabloKart.addView(satirKapsayici, rlp);

            paylasMetni.append(paylasSatir.toString().trim()).append('\n');
            iterCal.add(Calendar.DAY_OF_MONTH, 1);
        }
        if (yaklasikVar) {
            paylasMetni.append("────────────────────────────────────\n");
            paylasMetni.append("≈ işaretli satırlar konuma göre astronomik hesapla üretilmiştir.\n");
        }
        s.addView(tabloKart);

        // Dipnot
        s.addView(metin(a, tm, "≈ işaretli satırlar konumunuza göre astronomik hesapla üretilmiştir",
                12, tm.silik, false));
        s.addView(metin(a, tm, "Cumalar altın, Kadir Gecesi (27. Gece) zümrüt, Arefe pembe vurgulu gösterilir.",
                11, tm.silik, false));
        a.bosluk(s, 8);

        // Paylaş Düğmesi
        final String nihaiPaylasMetni = paylasMetni.toString();
        s.addView(temaDugmesi(a, tm, "📤  İmsakiyeyi Paylaş", true, v -> {
            try {
                Intent paylas = new Intent(Intent.ACTION_SEND);
                paylas.setType("text/plain");
                paylas.putExtra(Intent.EXTRA_SUBJECT, yerAdi + " 30 Günlük İmsakiye");
                paylas.putExtra(Intent.EXTRA_TEXT, nihaiPaylasMetni);
                a.startActivity(Intent.createChooser(paylas, "İmsakiyeyi paylaş"));
            } catch (Throwable ignored) {
            }
        }));

        // İftar ve Sahur (Niyet) Duâları Kartı
        s.addView(bolumBasligi(a, tm, "İftar ve Sahur (Niyet) Duâları"));
        LinearLayout duaKart = kart(a, tm);
        Typeface arapcaTip = Varlik.kuranYazisi(a);

        duaKart.addView(metin(a, tm, "İftar Duâsı", 16, tm.vurgu, true));
        TextView tvIftarAr = metin(a, tm, IFTAR_DUASI_ARAPCA, 22, tm.metin, false);
        tvIftarAr.setTypeface(arapcaTip);
        tvIftarAr.setGravity(Gravity.CENTER);
        tvIftarAr.setLineSpacing(0, 1.35f);
        tvIftarAr.setPadding(0, a.dp(6), 0, a.dp(6));
        duaKart.addView(tvIftarAr);
        duaKart.addView(metin(a, tm, IFTAR_DUASI_OKUNUS, 13, tm.metin, true));
        duaKart.addView(metin(a, tm, IFTAR_DUASI_MEAL, 13, tm.soluk, false));
        a.bosluk(duaKart, 6);
        duaKart.addView(metin(a, tm, NEBEVI_IFTAR_MEAL, 12, tm.silik, false));

        a.bosluk(duaKart, 10);
        View cizgi = new View(a);
        cizgi.setBackgroundColor(tm.acik ? 0x1A14211C : 0x22FFFFFF);
        duaKart.addView(cizgi, new LinearLayout.LayoutParams(-1, 1));
        a.bosluk(duaKart, 10);

        duaKart.addView(metin(a, tm, "Sahur (Oruç Niyeti) Duâsı", 16, tm.vurgu, true));
        TextView tvSahurAr = metin(a, tm, SAHUR_NIYET_ARAPCA, 21, tm.metin, false);
        tvSahurAr.setTypeface(arapcaTip);
        tvSahurAr.setGravity(Gravity.CENTER);
        tvSahurAr.setLineSpacing(0, 1.35f);
        tvSahurAr.setPadding(0, a.dp(6), 0, a.dp(6));
        duaKart.addView(tvSahurAr);
        duaKart.addView(metin(a, tm, SAHUR_NIYET_OKUNUS, 13, tm.metin, true));
        duaKart.addView(metin(a, tm, SAHUR_NIYET_MEAL, 13, tm.soluk, false));
        s.addView(duaKart);

        // Görünüm ve Hatırlatıcı Ayarları Kartı
        s.addView(bolumBasligi(a, tm, "Ana Ekran Kartı Tercihleri"));
        LinearLayout ayarKart = kart(a, tm);
        temaAnahtari(a, tm, ayarKart,
                "Ana ekranda Sahur/İftar kartını her zaman göster",
                "Ramazan ayı dışında da Vakitler ekranında canlı geri sayım kartı yer alır",
                herZamanGoster(a),
                acik -> herZamanGosterSec(a, acik));
        temaAnahtari(a, tm, ayarKart,
                "Pazartesi ve Perşembe günleri göster",
                "Sünnet orucu günlerinde ana ekranda sahur ve iftar sayacını otomatik gösterir",
                sunnetHatirlat(a),
                acik -> sunnetHatirlatSec(a, acik));
        s.addView(ayarKart);

        ScrollView sv = a.sayfa(s);
        sv.setPadding(0, 0, 0, 0);
        a.altSayfa("İmsakiye ve Oruç Vakitleri", sv, "kandil");
    }

    // ================================================================ Takvim ve Özel Gün Yardımcıları

    private static Calendar imsakiyeBaslangicGunu(VakitTakvimi.Takvim takvim, boolean ramazan) {
        Calendar cal = Calendar.getInstance();
        cal.set(Calendar.HOUR_OF_DAY, 12);
        cal.set(Calendar.MINUTE, 0);
        cal.set(Calendar.SECOND, 0);
        cal.set(Calendar.MILLISECOND, 0);
        if (!ramazan) return cal;

        String h = takvim.hicri != null ? takvim.hicri : takvim.bugunHicri();
        int rGun = ramazanGunuCikar(h);
        if (rGun > 1 && rGun <= 30) {
            cal.add(Calendar.DAY_OF_MONTH, -(rGun - 1));
        }
        return cal;
    }

    private static int ramazanGunuCikar(String hicri) {
        if (!hicriRamazanMi(hicri)) return 0;
        String t = hicri.trim();
        int bosluk = t.indexOf(' ');
        if (bosluk <= 0) return 0;
        try {
            int gun = Integer.parseInt(t.substring(0, bosluk).replaceAll("[^0-9]", ""));
            return (gun >= 1 && gun <= 30) ? gun : 0;
        } catch (NumberFormatException e) {
            return 0;
        }
    }

    private static String ozelGunEtiketi(VakitTakvimi.Takvim takvim, List<Vakit> kurulu,
                                         Calendar gun, int ramazanGunNo) {
        // 1) Kurulu mübarek gün bildirimlerinde Kadir / Arefe / Bayram var mı kontrol et
        if (kurulu != null) {
            for (Vakit v : kurulu) {
                if (!"holy".equals(v.tur)) continue;
                Calendar vc = Calendar.getInstance();
                vc.setTimeInMillis(v.zaman);
                if (ayniGun(gun, vc) && v.baslik != null && !v.baslik.isEmpty()) {
                    if (v.baslik.toLowerCase(Metinler.TR).contains("kadir")) {
                        return "Kadir Gecesi (27. Gece)";
                    }
                    return v.baslik;
                }
            }
        }

        // 2) Hicrî tarih / Ramazan gün numarasından Kadir Gecesi (26. gün akşamı = 27. Gece) ve Arefe tespiti
        if (ramazanGunNo == 26) {
            return "Kadir Gecesi (27. Gece)";
        }
        String h = takvim != null ? takvim.hicri(gun.getTimeInMillis()) : null;
        if (h != null) {
            String kucuk = h.toLowerCase(Metinler.TR).trim();
            if (kucuk.startsWith("9 zilhicce")) {
                return "Kurban Bayramı Arefesi";
            }
            // Ertesi gün 1 Şevval ise bugün Arefe'dir
            Calendar yarin = (Calendar) gun.clone();
            yarin.add(Calendar.DAY_OF_MONTH, 1);
            String yh = takvim.hicri(yarin.getTimeInMillis());
            if (yh != null && yh.toLowerCase(Metinler.TR).trim().startsWith("1 şevval")) {
                return "Ramazan Bayramı Arefesi";
            }
        }
        if (ramazanGunNo == 30) {
            return "Ramazan Arefesi";
        }
        return null;
    }

    private static boolean ayniGun(Calendar a, Calendar b) {
        return a.get(Calendar.YEAR) == b.get(Calendar.YEAR)
                && a.get(Calendar.DAY_OF_YEAR) == b.get(Calendar.DAY_OF_YEAR);
    }

    private static long komsuGunMs(long bazMs, int gunFarki) {
        Calendar cal = Calendar.getInstance();
        cal.setTimeInMillis(bazMs);
        cal.set(Calendar.HOUR_OF_DAY, 12);
        cal.set(Calendar.MINUTE, 0);
        cal.set(Calendar.SECOND, 0);
        cal.set(Calendar.MILLISECOND, 0);
        cal.add(Calendar.DAY_OF_MONTH, gunFarki);
        return cal.getTimeInMillis();
    }

    private static String kisaHicri(String h) {
        if (h == null || h.isEmpty()) return null;
        return h.replaceAll("\\s+\\d{4}\\s*$", "").trim();
    }

    // ================================================================ Görünüm Yardımcıları

    private static LinearLayout kart(DurumAktivitesi a, TemaMotoru.Durum tm) {
        LinearLayout k = a.cam();
        k.setBackground(tm.kartArkaPlani(a));
        return k;
    }

    private static TextView bolumBasligi(DurumAktivitesi a, TemaMotoru.Durum tm, String s) {
        TextView t = a.altBaslik(s);
        t.setTextColor(tm.vurgu);
        if (tm.acik) t.setShadowLayer(0, 0, 0, 0);
        return t;
    }

    private static TextView metin(DurumAktivitesi a, TemaMotoru.Durum tm, String s, int sp, int renk, boolean kalin) {
        TextView tv = a.metin(s, TemaMotoru.olcekliSp(a, sp), renk, kalin);
        if (tm.acik) tv.setShadowLayer(0, 0, 0, 0);
        return tv;
    }

    private static TextView temaDugmesi(DurumAktivitesi a, TemaMotoru.Durum tm, String yazi,
                                        boolean birincil, View.OnClickListener l) {
        TextView b = a.dugme(yazi, birincil, l);
        b.setTextColor(birincil ? tm.birincilDugmeYaziRengi() : tm.metin);
        b.setBackground(birincil ? tm.birincilDugme(a, 16) : tm.ikincilDugme(a, 16));
        if (birincil && tm.acik) b.setTextColor(Color.WHITE);
        return b;
    }

    private static void temaAnahtari(DurumAktivitesi a, TemaMotoru.Durum tm, LinearLayout k,
                                     String ad, String aciklama, boolean acik, DurumAktivitesi.Degisim d) {
        LinearLayout s = new LinearLayout(a);
        s.setGravity(Gravity.CENTER_VERTICAL);
        s.setPadding(0, a.dp(6), 0, a.dp(6));
        LinearLayout yazi = new LinearLayout(a);
        yazi.setOrientation(LinearLayout.VERTICAL);
        yazi.addView(metin(a, tm, ad, 15, tm.metin, true));
        yazi.addView(metin(a, tm, aciklama, 13, tm.soluk, false));
        s.addView(yazi, new LinearLayout.LayoutParams(0, -2, 1f));
        final Switch sw = new Switch(a);
        sw.setChecked(acik);
        sw.setContentDescription(ad);
        sw.setThumbTintList(android.content.res.ColorStateList.valueOf(acik ? tm.vurgu : 0xFFE0E0E0));
        sw.setOnCheckedChangeListener((b, v) -> {
            b.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            sw.setThumbTintList(android.content.res.ColorStateList.valueOf(v ? tm.vurgu : 0xFFE0E0E0));
            d.degisti(v);
        });
        s.addView(sw);
        k.addView(s);
    }
}
