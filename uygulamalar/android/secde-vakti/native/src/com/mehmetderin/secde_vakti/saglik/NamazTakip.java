package com.mehmetderin.secde_vakti.saglik;

import android.app.AlertDialog;
import android.content.Context;
import android.content.SharedPreferences;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.HapticFeedbackConstants;
import android.view.MotionEvent;
import android.view.View;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.Date;
import java.util.Locale;
import java.util.Map;

/**
 * Günlük 5 Vakit Namaz Takibi, Cezalandırmayan Seri, Özel Hâl (Mazeret) Modu ve 12 Haftalık Isı Haritası:
 *  - Depolama: "secde_namaz_takip" SharedPreferences
 *  - Vakitler: 0=Sabah, 1=Öğle, 2=İkindi, 3=Akşam, 4=Yatsı
 *  - Durumlar: 0=BEKLIYOR, 1=EDA, 2=CEMAAT, 3=KAZA, 4=MAZERET
 */
public final class NamazTakip {

    public static final String DOSYA = "secde_namaz_takip";

    public static final int BEKLIYOR = 0;
    public static final int EDA = 1;
    public static final int CEMAAT = 2;
    public static final int KAZA = 3;
    public static final int MAZERET = 4;

    public static final String[] VAKIT_ADLARI = {"Sabah", "Öğle", "İkindi", "Akşam", "Yatsı"};

    private static final String ANAHTAR_MAZERET = "mazeret_modu";
    private static final String ANAHTAR_REKOR = "en_uzun_seri";
    private static final int MOR_MAZERET = 0xFFB39DDB;

    private NamazTakip() {}

    static SharedPreferences sp(Context c) {
        return c.getSharedPreferences(DOSYA, Context.MODE_PRIVATE);
    }

    public static String bugunKey() {
        return gunKey(System.currentTimeMillis());
    }

    public static String gunKey(long ms) {
        Calendar cal = Calendar.getInstance();
        cal.setTimeInMillis(ms);
        return String.format(Locale.ROOT, "%04d-%02d-%02d",
                cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1, cal.get(Calendar.DAY_OF_MONTH));
    }

    private static String gunDizisi(Context c, String gunKey) {
        String ham = sp(c).getString("g_" + gunKey, "00000");
        if (ham == null || ham.length() != 5) return "00000";
        return ham;
    }

    public static int durum(Context c, String gunKey, int vakitIdx) {
        if (vakitIdx < 0 || vakitIdx >= 5 || gunKey == null) return BEKLIYOR;
        String d = gunDizisi(c, gunKey);
        char ch = d.charAt(vakitIdx);
        int v = ch - '0';
        return (v >= BEKLIYOR && v <= MAZERET) ? v : BEKLIYOR;
    }

    public static void durumSec(Context c, String gunKey, int vakitIdx, int yeniDurum) {
        if (vakitIdx < 0 || vakitIdx >= 5 || gunKey == null) return;
        int d = Math.max(BEKLIYOR, Math.min(MAZERET, yeniDurum));
        char[] arr = gunDizisi(c, gunKey).toCharArray();
        arr[vakitIdx] = (char) ('0' + d);
        sp(c).edit().putString("g_" + gunKey, new String(arr)).apply();
        // Rekor seriyi güncel tut
        seri(c);
    }

    public static boolean mazeretModu(Context c) {
        return sp(c).getBoolean(ANAHTAR_MAZERET, false);
    }

    /**
     * Özel Hâl / Mazeret Modu (Seri Dondurma):
     * Açıldığında bugünün henüz işaretlenmemiş vakitlerini MAZERET olarak işaretler ve seriyi korur.
     * Kapatıldığında bugünün MAZERET olan vakitlerini tekrar BEKLIYOR durumuna döndürür.
     */
    public static void mazeretModuSec(Context c, boolean acik) {
        SharedPreferences.Editor ed = sp(c).edit().putBoolean(ANAHTAR_MAZERET, acik);
        String bugun = bugunKey();
        char[] arr = gunDizisi(c, bugun).toCharArray();
        for (int i = 0; i < 5; i++) {
            int cur = arr[i] - '0';
            if (acik && cur == BEKLIYOR) {
                arr[i] = (char) ('0' + MAZERET);
            } else if (!acik && cur == MAZERET) {
                arr[i] = (char) ('0' + BEKLIYOR);
            }
        }
        ed.putString("g_" + bugun, new String(arr)).apply();
    }

    /** Bugün edâ (vaktinde veya cemaatle) edilen vakit sayısı (0..5). */
    public static int bugunTamamlanan(Context c) {
        String d = gunDizisi(c, bugunKey());
        int say = 0;
        for (int i = 0; i < 5; i++) {
            int v = d.charAt(i) - '0';
            if (v == EDA || v == CEMAAT) say++;
        }
        return say;
    }

    /**
     * Cezalandırmayan seri (Pillars & Sekine yaklaşımı):
     *  - Gün içinde henüz 5/5 tamamlanmamışsa seriyi sıfırlamaz, dünden geriye sayar.
     *  - Bugün 5/5 tamamlanmışsa bugünü de seriye dâhil eder.
     *  - Tamamı MAZERET olan özel hâl günleri zinciri kırmaz, seriyi dondurarak korur.
     */
    public static int seri(Context c) {
        if (mazeretModu(c)) {
            // Mazeret modu açıkken bugünün boş kalan yuvalarını otomatik koruma altında tut
            String bKey = bugunKey();
            String bd = gunDizisi(c, bKey);
            if ("00000".equals(bd)) {
                sp(c).edit().putString("g_" + bKey, "44444").apply();
            }
        }

        Calendar cal = ogleTakvimi();
        int toplam = 0;

        // Önce bugünü kontrol et
        String bDizisi = gunDizisi(c, takvimKey(cal));
        int bEda = edaSayisi(bDizisi);
        int bMaz = mazeretSayisi(bDizisi);
        if (bEda + bMaz == 5) {
            if (bEda > 0) toplam++;
        }

        // Dünden geriye doğru kesintisiz zinciri tara
        for (int i = 1; i <= 3650; i++) {
            cal.add(Calendar.DAY_OF_MONTH, -1);
            String d = gunDizisi(c, takvimKey(cal));
            int eda = edaSayisi(d);
            int maz = mazeretSayisi(d);
            if (eda + maz == 5) {
                if (eda > 0) toplam++;
            } else {
                break;
            }
        }

        int kayitliRekor = sp(c).getInt(ANAHTAR_REKOR, 0);
        if (toplam > kayitliRekor) {
            sp(c).edit().putInt(ANAHTAR_REKOR, toplam).apply();
        }
        return toplam;
    }

    /** Kaydedilmiş tüm geçmişi tarayarak en uzun seriyi döndürür. */
    public static int enUzunSeri(Context c) {
        int aktifSeri = seri(c);
        int enUzun = Math.max(aktifSeri, sp(c).getInt(ANAHTAR_REKOR, 0));

        String enEskiKey = null;
        for (Map.Entry<String, ?> e : sp(c).getAll().entrySet()) {
            String k = e.getKey();
            if (k != null && k.startsWith("g_") && k.length() == 12) {
                String tarih = k.substring(2);
                if (enEskiKey == null || tarih.compareTo(enEskiKey) < 0) {
                    enEskiKey = tarih;
                }
            }
        }
        if (enEskiKey == null) return enUzun;

        Calendar bas = anahtardanTakvim(enEskiKey);
        Calendar bit = ogleTakvimi();
        if (bas == null) return enUzun;

        int zincir = 0;
        String bugun = takvimKey(bit);
        int guvenlik = 0;
        while (!bas.after(bit) && guvenlik++ < 4000) {
            String k = takvimKey(bas);
            String d = gunDizisi(c, k);
            int eda = edaSayisi(d);
            int maz = mazeretSayisi(d);
            if (eda + maz == 5) {
                if (eda > 0) {
                    zincir++;
                    if (zincir > enUzun) enUzun = zincir;
                }
            } else if (!bugun.equals(k)) {
                zincir = 0;
            }
            bas.add(Calendar.DAY_OF_MONTH, 1);
        }

        if (enUzun > sp(c).getInt(ANAHTAR_REKOR, 0)) {
            sp(c).edit().putInt(ANAHTAR_REKOR, enUzun).apply();
        }
        return enUzun;
    }

    private static int edaSayisi(String d) {
        int n = 0;
        for (int i = 0; i < 5 && i < d.length(); i++) {
            int v = d.charAt(i) - '0';
            if (v == EDA || v == CEMAAT) n++;
        }
        return n;
    }

    private static int cemaatSayisi(String d) {
        int n = 0;
        for (int i = 0; i < 5 && i < d.length(); i++) {
            if (d.charAt(i) - '0' == CEMAAT) n++;
        }
        return n;
    }

    private static int mazeretSayisi(String d) {
        int n = 0;
        for (int i = 0; i < 5 && i < d.length(); i++) {
            if (d.charAt(i) - '0' == MAZERET) n++;
        }
        return n;
    }

    // ================================================================ Vakitler Sekmesi Ana Kartı

    /**
     * Vakitler sekmesi için kompakt, etkileşimli 5 vakit edâ çubuğu kartı.
     */
    public static View anaKart(final DurumAktivitesi a) {
        final TemaMotoru.Durum tm = TemaMotoru.aktif(a);
        final LinearLayout disKart = kart(a, tm);
        final Runnable[] yenile = new Runnable[1];
        yenile[0] = () -> {
            disKart.removeAllViews();
            anaKartDoldur(a, tm, disKart, yenile[0]);
        };
        yenile[0].run();
        return disKart;
    }

    private static void anaKartDoldur(final DurumAktivitesi a, final TemaMotoru.Durum tm,
                                      final LinearLayout k, final Runnable yenile) {
        String bugun = bugunKey();
        if (mazeretModu(a) && "00000".equals(gunDizisi(a, bugun))) {
            mazeretModuSec(a, true);
        }

        // Üst başlık satırı
        LinearLayout ust = new LinearLayout(a);
        ust.setOrientation(LinearLayout.HORIZONTAL);
        ust.setGravity(Gravity.CENTER_VERTICAL);

        TextView baslik = metin(a, tm, "GÜNLÜK NAMAZ TAKİBİ", 11, tm.vurgu, true);
        baslik.setLetterSpacing(0.06f);
        ust.addView(baslik, new LinearLayout.LayoutParams(0, -2, 1f));

        int aktifSeri = seri(a);
        boolean mazeret = mazeretModu(a);
        String rozetYazi;
        int rozetRenk;
        if (mazeret) {
            rozetYazi = "✦ Özel Hâl · Seri Korunuyor";
            rozetRenk = MOR_MAZERET;
        } else if (aktifSeri > 0) {
            rozetYazi = "🔥 " + aktifSeri + " gün seri";
            rozetRenk = tm.vurgu;
        } else {
            rozetYazi = "Bugün " + bugunTamamlanan(a) + "/5";
            rozetRenk = tm.iyi;
        }

        TextView seriHap = metin(a, tm, rozetYazi, 11, rozetRenk, true);
        seriHap.setShadowLayer(0, 0, 0, 0);
        seriHap.setPadding(a.dp(8), a.dp(3), a.dp(8), a.dp(3));
        GradientDrawable hapBg = new GradientDrawable();
        hapBg.setCornerRadius(a.dp(10));
        hapBg.setColor((rozetRenk & 0x00FFFFFF) | (tm.acik ? 0x1C000000 : 0x28000000));
        hapBg.setStroke(1, (rozetRenk & 0x00FFFFFF) | 0x66000000);
        seriHap.setBackground(hapBg);
        ust.addView(seriHap);

        TextView istDugme = metin(a, tm, "İstatistik ›", 12, tm.vurgu, true);
        istDugme.setPadding(a.dp(10), a.dp(4), a.dp(2), a.dp(4));
        istDugme.setClickable(true);
        istDugme.setOnClickListener(v -> {
            v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            a.guvenli("namaz_takip", () -> sayfaAc(a));
        });
        ust.addView(istDugme);
        k.addView(ust);

        a.bosluk(k, 8);

        // 5 eşit yatay hap
        k.addView(besVakitSatiri(a, tm, bugun, yenile));
    }

    private static View besVakitSatiri(final DurumAktivitesi a, final TemaMotoru.Durum tm,
                                       final String gunKey, final Runnable yenile) {
        LinearLayout sira = new LinearLayout(a);
        sira.setOrientation(LinearLayout.HORIZONTAL);

        for (int i = 0; i < 5; i++) {
            final int idx = i;
            final int d = durum(a, gunKey, idx);

            LinearLayout hucre = new LinearLayout(a);
            hucre.setOrientation(LinearLayout.VERTICAL);
            hucre.setGravity(Gravity.CENTER);
            hucre.setPadding(a.dp(2), a.dp(9), a.dp(2), a.dp(9));

            int vurguRengi = durumRengi(tm, d);
            GradientDrawable bg = new GradientDrawable();
            bg.setCornerRadius(a.dp(14));
            if (d == BEKLIYOR) {
                bg.setColor(tm.acik ? 0x1014211C : 0x1AFFFFFF);
                bg.setStroke(1, tm.acik ? 0x2E14211C : 0x33FFFFFF);
            } else {
                bg.setColor((vurguRengi & 0x00FFFFFF) | (tm.acik ? 0x22000000 : 0x33000000));
                bg.setStroke(Math.max(1, a.dp(1)), (vurguRengi & 0x00FFFFFF) | 0xAA000000);
            }
            hucre.setBackground(bg);

            TextView tvSimge = metin(a, tm, durumSimgesi(d), 15,
                    d == BEKLIYOR ? tm.silik : vurguRengi, true);
            tvSimge.setShadowLayer(0, 0, 0, 0);
            tvSimge.setGravity(Gravity.CENTER);
            tvSimge.setPadding(0, 0, 0, a.dp(2));
            hucre.addView(tvSimge);

            TextView tvAd = metin(a, tm, VAKIT_ADLARI[idx], 12,
                    d == BEKLIYOR ? tm.metin : vurguRengi, true);
            tvAd.setShadowLayer(0, 0, 0, 0);
            tvAd.setGravity(Gravity.CENTER);
            tvAd.setPadding(0, 0, 0, 0);
            hucre.addView(tvAd);

            TextView tvAlt = metin(a, tm, durumKisaAdi(d), 10,
                    d == BEKLIYOR ? tm.silik : tm.soluk, false);
            tvAlt.setShadowLayer(0, 0, 0, 0);
            tvAlt.setGravity(Gravity.CENTER);
            tvAlt.setPadding(0, a.dp(1), 0, 0);
            hucre.addView(tvAlt);

            hucre.setClickable(true);
            hucre.setLongClickable(true);
            a.basmaEfekti(hucre);

            hucre.setOnClickListener(v -> {
                v.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK);
                int yeni = sonrakiDurum(d, mazeretModu(a));
                durumSec(a, gunKey, idx, yeni);
                yenile.run();
            });

            hucre.setOnLongClickListener(v -> {
                v.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS);
                uzunBasmaMenusu(a, gunKey, idx, yenile);
                return true;
            });

            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, -2, 1f);
            if (i > 0) lp.setMargins(a.dp(5), 0, 0, 0);
            sira.addView(hucre, lp);
        }
        return sira;
    }

    private static int sonrakiDurum(int mevcut, boolean mazeretAcik) {
        if (mazeretAcik) {
            switch (mevcut) {
                case BEKLIYOR: return MAZERET;
                case MAZERET: return EDA;
                case EDA: return CEMAAT;
                case CEMAAT: return KAZA;
                default: return BEKLIYOR;
            }
        }
        switch (mevcut) {
            case BEKLIYOR: return EDA;
            case EDA: return CEMAAT;
            case CEMAAT: return KAZA;
            default: return BEKLIYOR;
        }
    }

    private static void uzunBasmaMenusu(final DurumAktivitesi a, final String gunKey,
                                        final int vakitIdx, final Runnable yenile) {
        final String[] secenekler = {
                "✓  Vaktinde Edâ",
                "✦✦  Cemaatle Edâ",
                "↺  Kazâya Kaldı (+1 Kazâ Borcu Ekle)",
                "✦  Özel Hâl / Muaf",
                "○  Temizle"
        };
        new AlertDialog.Builder(a)
                .setTitle(VAKIT_ADLARI[vakitIdx] + " Namazı")
                .setItems(secenekler, (d, secim) -> {
                    switch (secim) {
                        case 0:
                            durumSec(a, gunKey, vakitIdx, EDA);
                            break;
                        case 1:
                            durumSec(a, gunKey, vakitIdx, CEMAAT);
                            break;
                        case 2:
                            durumSec(a, gunKey, vakitIdx, KAZA);
                            KazaTakip.artir(a, vakitIdx, 1);
                            Toast.makeText(a, VAKIT_ADLARI[vakitIdx] + " kazâ defterine +1 eklendi",
                                    Toast.LENGTH_SHORT).show();
                            break;
                        case 3:
                            durumSec(a, gunKey, vakitIdx, MAZERET);
                            break;
                        case 4:
                            durumSec(a, gunKey, vakitIdx, BEKLIYOR);
                            break;
                    }
                    yenile.run();
                })
                .setNegativeButton("Vazgeç", null)
                .show();
    }

    private static String durumSimgesi(int d) {
        switch (d) {
            case EDA: return "✓";
            case CEMAAT: return "✦✦";
            case KAZA: return "↺";
            case MAZERET: return "✦";
            default: return "○";
        }
    }

    private static String durumKisaAdi(int d) {
        switch (d) {
            case EDA: return "Edâ";
            case CEMAAT: return "Cemaat";
            case KAZA: return "Kazâ";
            case MAZERET: return "Muaf";
            default: return "Bekliyor";
        }
    }

    private static int durumRengi(TemaMotoru.Durum tm, int d) {
        switch (d) {
            case EDA: return tm.iyi;
            case CEMAAT: return tm.vurgu;
            case KAZA: return tm.kotu;
            case MAZERET: return MOR_MAZERET;
            default: return tm.silik;
        }
    }

    // ================================================================ Tam Alt Sayfa & Isı Haritası

    /**
     * Namaz Takibi ve 12 Haftalık Isı Haritası alt sayfasını açar.
     */
    public static void sayfaAc(final DurumAktivitesi a) {
        final LinearLayout kokSutun = a.sutun();
        final ScrollView sv = a.sayfa(kokSutun);
        sv.setPadding(0, 0, 0, 0);

        final int[] seciliGecmisGun = {0}; // 0=Bugün, 1=Dün, .. 6=6 gün önce
        final Runnable[] ciz = new Runnable[1];
        ciz[0] = () -> {
            final int kaymaY = sv.getScrollY();
            kokSutun.removeAllViews();
            sayfaIcerigiDoldur(a, kokSutun, seciliGecmisGun, ciz[0]);
            sv.post(() -> sv.scrollTo(0, kaymaY));
        };
        ciz[0].run();

        a.altSayfa("Namaz Takibi ve Isı Haritası", sv, "mihrap");
    }

    private static void sayfaIcerigiDoldur(final DurumAktivitesi a, final LinearLayout s,
                                           final int[] seciliGunOffset, final Runnable yenile) {
        final TemaMotoru.Durum tm = TemaMotoru.aktif(a);

        // Son 30 gün istatistikleri hesapla
        int son30Eda = 0;
        int son30GecerliYuva = 0;
        int son30Cemaat = 0;
        Calendar cal = ogleTakvimi();
        for (int g = 0; g < 30; g++) {
            String d = gunDizisi(a, takvimKey(cal));
            int eda = edaSayisi(d);
            int cem = cemaatSayisi(d);
            int maz = mazeretSayisi(d);
            son30Eda += eda;
            son30Cemaat += cem;
            son30GecerliYuva += (5 - maz);
            cal.add(Calendar.DAY_OF_MONTH, -1);
        }
        int oranYuzde = son30GecerliYuva > 0 ? Math.round((son30Eda * 100f) / son30GecerliYuva) : 100;
        int aktifSeri = seri(a);
        int rekorSeri = enUzunSeri(a);

        // 1) Özet İstatistik Kartı (2x2 kutular)
        LinearLayout ozetKart = kart(a, tm);
        if (mazeretModu(a)) {
            TextView bilgi = metin(a, tm, "✦ Özel Hâl Modu Aktif · Seriniz dondurularak korunuyor", 12, MOR_MAZERET, true);
            bilgi.setPadding(0, 0, 0, a.dp(8));
            ozetKart.addView(bilgi);
        }

        LinearLayout ustSatir = new LinearLayout(a);
        ustSatir.setOrientation(LinearLayout.HORIZONTAL);
        ustSatir.addView(istatistikKutusu(a, tm, aktifSeri + " gün", "Aktif Seri", tm.vurgu),
                new LinearLayout.LayoutParams(0, -2, 1f));
        View ara1 = new View(a);
        ustSatir.addView(ara1, new LinearLayout.LayoutParams(a.dp(8), 1));
        ustSatir.addView(istatistikKutusu(a, tm, rekorSeri + " gün", "En Uzun Seri", tm.iyi),
                new LinearLayout.LayoutParams(0, -2, 1f));
        ozetKart.addView(ustSatir);

        a.bosluk(ozetKart, 8);

        LinearLayout altSatir = new LinearLayout(a);
        altSatir.setOrientation(LinearLayout.HORIZONTAL);
        altSatir.addView(istatistikKutusu(a, tm, "%" + oranYuzde, "Son 30 Gün Edâ", tm.ana),
                new LinearLayout.LayoutParams(0, -2, 1f));
        View ara2 = new View(a);
        altSatir.addView(ara2, new LinearLayout.LayoutParams(a.dp(8), 1));
        altSatir.addView(istatistikKutusu(a, tm, son30Cemaat + " vakit", "30 Gün Cemaat", tm.vurgu),
                new LinearLayout.LayoutParams(0, -2, 1f));
        ozetKart.addView(altSatir);
        s.addView(ozetKart);

        // 2) 12 Haftalık Isı Haritası Kartı
        s.addView(bolumBasligi(a, tm, "Son 12 Hafta · 84 Günlük Isı Haritası"));
        LinearLayout haritaKart = kart(a, tm);
        IsiHaritasiView harita = new IsiHaritasiView(a);
        haritaKart.addView(harita, new LinearLayout.LayoutParams(-1, a.dp(178)));
        a.bosluk(haritaKart, 8);

        // Lejant satırı
        LinearLayout lejant = new LinearLayout(a);
        lejant.setOrientation(LinearLayout.HORIZONTAL);
        lejant.setGravity(Gravity.CENTER_VERTICAL);
        lejant.addView(metin(a, tm, "Az", 11, tm.silik, false));
        for (int kademe = 0; kademe <= 5; kademe++) {
            View kutu = new View(a);
            GradientDrawable kBg = new GradientDrawable();
            kBg.setCornerRadius(a.dp(3));
            kBg.setColor(isiRengi(tm, kademe));
            if (kademe == 0) kBg.setStroke(1, tm.acik ? 0x2614211C : 0x26FFFFFF);
            kutu.setBackground(kBg);
            LinearLayout.LayoutParams klp = new LinearLayout.LayoutParams(a.dp(12), a.dp(12));
            klp.setMargins(a.dp(4), 0, kademe == 5 ? a.dp(4) : 0, 0);
            lejant.addView(kutu, klp);
        }
        lejant.addView(metin(a, tm, "5/5", 11, tm.silik, false));
        TextView ekLejant = metin(a, tm, "  ·  ● Cemaat   ▢ Özel Hâl", 11, tm.soluk, false);
        lejant.addView(ekLejant);
        haritaKart.addView(lejant);
        haritaKart.addView(metin(a, tm, "Bir güne dokunarak o günün vakit özetini görebilirsiniz.", 11, tm.silik, false));
        s.addView(haritaKart);

        // 3) Son 7 Gün Düzenleyici
        s.addView(bolumBasligi(a, tm, "Son 7 Gün Kaydı · Geçmişi Düzenle"));
        LinearLayout gecmisKart = kart(a, tm);

        HorizontalScrollView gunKaydir = new HorizontalScrollView(a);
        gunKaydir.setHorizontalScrollBarEnabled(false);
        gunKaydir.setOverScrollMode(View.OVER_SCROLL_NEVER);
        LinearLayout gunCipler = new LinearLayout(a);
        gunCipler.setOrientation(LinearLayout.HORIZONTAL);

        SimpleDateFormat kisaTarih = new SimpleDateFormat("d MMM EEE", Metinler.TR);
        Calendar gCal = ogleTakvimi();
        String seciliTarihKey = bugunKey();
        String seciliTarihAd = "Bugün";

        for (int g = 0; g < 7; g++) {
            final int ofset = g;
            long ms = gCal.getTimeInMillis();
            String key = takvimKey(gCal);
            String etiket = g == 0 ? "Bugün" : (g == 1 ? "Dün" : kisaTarih.format(new Date(ms)));
            int gunEda = edaSayisi(gunDizisi(a, key));
            boolean secili = (seciliGunOffset[0] == g);
            if (secili) {
                seciliTarihKey = key;
                seciliTarihAd = g == 0 ? "Bugün (" + kisaTarih.format(new Date(ms)) + ")"
                        : (g == 1 ? "Dün (" + kisaTarih.format(new Date(ms)) + ")"
                        : Metinler.tarih(ms));
            }

            TextView cip = metin(a, tm, etiket + " · " + gunEda + "/5", 12,
                    secili ? tm.birincilDugmeYaziRengi() : tm.metin, true);
            cip.setShadowLayer(0, 0, 0, 0);
            cip.setPadding(a.dp(12), a.dp(7), a.dp(12), a.dp(7));
            cip.setBackground(tm.cipArkaPlani(a, secili, 14));
            cip.setClickable(true);
            cip.setOnClickListener(v -> {
                v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
                seciliGunOffset[0] = ofset;
                yenile.run();
            });
            LinearLayout.LayoutParams clp = new LinearLayout.LayoutParams(-2, -2);
            clp.setMargins(0, 0, a.dp(6), 0);
            gunCipler.addView(cip, clp);

            gCal.add(Calendar.DAY_OF_MONTH, -1);
        }
        gunKaydir.addView(gunCipler);
        gecmisKart.addView(gunKaydir);

        a.bosluk(gecmisKart, 10);
        gecmisKart.addView(metin(a, tm, seciliTarihAd, 14, tm.vurgu, true));
        gecmisKart.addView(metin(a, tm, "Dokunarak durumu değiştirin; kazâ veya cemaat seçenekleri için basılı tutun.",
                12, tm.silik, false));
        a.bosluk(gecmisKart, 8);
        gecmisKart.addView(besVakitSatiri(a, tm, seciliTarihKey, yenile));

        final String hedefKey = seciliTarihKey;
        TextView tumunuEda = temaDugmesi(a, tm, "Seçili Günün 5 Vaktini Edâ İşaretle", false, v -> {
            for (int i = 0; i < 5; i++) {
                if (durum(a, hedefKey, i) == BEKLIYOR) {
                    durumSec(a, hedefKey, i, EDA);
                }
            }
            yenile.run();
        });
        gecmisKart.addView(tumunuEda);
        s.addView(gecmisKart);

        // 4) Özel Hâl / Mazeret Modu Kartı
        s.addView(bolumBasligi(a, tm, "Şefkatli Takip · Özel Hâl Modu"));
        LinearLayout mazeretKart = kart(a, tm);
        temaAnahtari(a, tm, mazeretKart,
                "Özel Hâl / Mazeret Modu",
                "Hanımlara özel hâl, yolculuk veya hastalık durumunda seriniz bozulmadan korunur.",
                mazeretModu(a),
                acik -> {
                    mazeretModuSec(a, acik);
                    yenile.run();
                });
        s.addView(mazeretKart);

        // 5) Kazâ Defterine Geçiş Düğmesi
        s.addView(temaDugmesi(a, tm, "Kazâ ve Oruç Defterini Aç ›", true,
                v -> a.guvenli("kaza_defteri", () -> KazaTakip.sayfaAc(a))));
    }

    private static View istatistikKutusu(DurumAktivitesi a, TemaMotoru.Durum tm,
                                         String deger, String etiket, int vurguRenk) {
        LinearLayout kutu = new LinearLayout(a);
        kutu.setOrientation(LinearLayout.VERTICAL);
        kutu.setPadding(a.dp(12), a.dp(10), a.dp(12), a.dp(10));
        GradientDrawable bg = new GradientDrawable();
        bg.setCornerRadius(a.dp(14));
        bg.setColor(tm.acik ? 0x1014211C : 0x18FFFFFF);
        bg.setStroke(1, tm.acik ? 0x2214211C : 0x26FFFFFF);
        kutu.setBackground(bg);

        TextView tvDeger = metin(a, tm, deger, 21, vurguRenk, true);
        kutu.addView(tvDeger);
        TextView tvEtiket = metin(a, tm, etiket, 12, tm.soluk, false);
        kutu.addView(tvEtiket);
        return kutu;
    }

    static int isiRengi(TemaMotoru.Durum tm, int edaSayisi) {
        int bos = tm.acik ? 0x1814211C : 0x1FFFFFFF;
        if (edaSayisi <= 0) return bos;
        int hedef = tm.iyi;
        float oran;
        switch (edaSayisi) {
            case 1: oran = 0.24f; break;
            case 2: oran = 0.42f; break;
            case 3: oran = 0.60f; break;
            case 4: oran = 0.80f; break;
            default: oran = 1.0f; break;
        }
        return TemaMotoru.karistir(bos, hedef, oran);
    }

    // ================================================================ Pure Canvas 12x7 Isı Haritası

    /**
     * 12 sütun × 7 satır (84 gün) yuvarlatılmış karelerden oluşan saf Canvas ısı haritası:
     *  - 0..5 tamamlanma yoğunluğu (aktif temanın zümrüt/iyi paletinde)
     *  - Cemaatle kılınan günler için altın nokta
     *  - Özel hâl (mazeret) günleri için yumuşak mor çerçeve
     */
    public static final class IsiHaritasiView extends View {

        private static final int SUTUN = 12;
        private static final int SATIR = 7;
        private static final int TOPLAM_GUN = SUTUN * SATIR; // 84

        private final Paint hucreBoya = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint kenarBoya = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint yaziBoya = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final RectF kutu = new RectF();

        private final long[] gunMs = new long[TOPLAM_GUN];
        private final int[] edalar = new int[TOPLAM_GUN];
        private final boolean[] cemaatVar = new boolean[TOPLAM_GUN];
        private final boolean[] mazeretVar = new boolean[TOPLAM_GUN];
        private final String[] ayBasliklari = new String[SUTUN];
        private final String[] satirGunAdlari = new String[SATIR];

        private float solPay, ustPay, hucreBoy, aralik;

        public IsiHaritasiView(Context context) {
            super(context);
            kenarBoya.setStyle(Paint.Style.STROKE);
            yaziBoya.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
            verileriYukle();
        }

        public void verileriYukle() {
            Context c = getContext();
            Calendar cal = ogleTakvimi();
            cal.add(Calendar.DAY_OF_MONTH, -(TOPLAM_GUN - 1));

            SimpleDateFormat ayBicim = new SimpleDateFormat("MMM", Metinler.TR);
            SimpleDateFormat gunBicim = new SimpleDateFormat("EEE", Metinler.TR);
            int oncekiAy = -1;

            for (int i = 0; i < TOPLAM_GUN; i++) {
                long ms = cal.getTimeInMillis();
                gunMs[i] = ms;
                String d = gunDizisi(c, takvimKey(cal));
                edalar[i] = edaSayisi(d);
                cemaatVar[i] = cemaatSayisi(d) > 0;
                mazeretVar[i] = mazeretSayisi(d) > 0;

                if (i < SATIR) {
                    satirGunAdlari[i] = gunBicim.format(new Date(ms));
                }
                int sutun = i / SATIR;
                if (i % SATIR == 0) {
                    int ay = cal.get(Calendar.MONTH);
                    if (ay != oncekiAy) {
                        ayBasliklari[sutun] = ayBicim.format(new Date(ms));
                        oncekiAy = ay;
                    } else {
                        ayBasliklari[sutun] = null;
                    }
                }
                cal.add(Calendar.DAY_OF_MONTH, 1);
            }
            invalidate();
        }

        @Override
        protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            Context c = getContext();
            TemaMotoru.Durum tm = TemaMotoru.aktif(c);
            float dp = c.getResources().getDisplayMetrics().density;

            int w = getWidth();
            int h = getHeight();
            if (w <= 0 || h <= 0) return;

            solPay = 34f * dp;
            ustPay = 20f * dp;
            aralik = 4f * dp;

            float kullanilabilirGen = w - solPay - 4f * dp;
            float kullanilabilirYuk = h - ustPay - 4f * dp;
            float genHucre = (kullanilabilirGen - (SUTUN - 1) * aralik) / SUTUN;
            float yukHucre = (kullanilabilirYuk - (SATIR - 1) * aralik) / SATIR;
            hucreBoy = Math.max(8f * dp, Math.min(genHucre, yukHucre));

            // Yatayda ortala
            float toplamIzgaraGen = SUTUN * hucreBoy + (SUTUN - 1) * aralik;
            float basX = solPay + Math.max(0f, (kullanilabilirGen - toplamIzgaraGen) * 0.5f);
            solPay = basX;

            yaziBoya.setTextSize(TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, 10,
                    c.getResources().getDisplayMetrics()));
            yaziBoya.setColor(tm.silik);

            // Üst ay etiketleri
            float sonEtiketSag = -100f;
            for (int col = 0; col < SUTUN; col++) {
                String ay = ayBasliklari[col];
                if (ay != null) {
                    float cx = basX + col * (hucreBoy + aralik);
                    if (cx > sonEtiketSag + 6f * dp) {
                        canvas.drawText(ay, cx, ustPay - 6f * dp, yaziBoya);
                        sonEtiketSag = cx + yaziBoya.measureText(ay);
                    }
                }
            }

            // Sol gün etiketleri (0, 2, 4, 6 satırları)
            for (int row = 0; row < SATIR; row += 2) {
                String gAd = satirGunAdlari[row];
                if (gAd != null) {
                    float cy = ustPay + row * (hucreBoy + aralik) + hucreBoy * 0.76f;
                    canvas.drawText(gAd, 0f, cy, yaziBoya);
                }
            }

            float kose = 4.5f * dp;
            for (int col = 0; col < SUTUN; col++) {
                for (int row = 0; row < SATIR; row++) {
                    int idx = col * SATIR + row;
                    float sol = basX + col * (hucreBoy + aralik);
                    float ust = ustPay + row * (hucreBoy + aralik);
                    kutu.set(sol, ust, sol + hucreBoy, ust + hucreBoy);

                    hucreBoya.setStyle(Paint.Style.FILL);
                    hucreBoya.setColor(isiRengi(tm, edalar[idx]));
                    canvas.drawRoundRect(kutu, kose, kose, hucreBoya);

                    // Özel hâl mor çerçeve veya bugün vurgusu
                    if (mazeretVar[idx]) {
                        kenarBoya.setStrokeWidth(1.5f * dp);
                        kenarBoya.setColor(MOR_MAZERET);
                        canvas.drawRoundRect(kutu, kose, kose, kenarBoya);
                    } else if (idx == TOPLAM_GUN - 1) {
                        kenarBoya.setStrokeWidth(1.4f * dp);
                        kenarBoya.setColor(tm.vurgu);
                        canvas.drawRoundRect(kutu, kose, kose, kenarBoya);
                    } else if (edalar[idx] == 0) {
                        kenarBoya.setStrokeWidth(Math.max(1f, 0.7f * dp));
                        kenarBoya.setColor(tm.acik ? 0x2014211C : 0x20FFFFFF);
                        canvas.drawRoundRect(kutu, kose, kose, kenarBoya);
                    }

                    // Cemaat altın noktası
                    if (cemaatVar[idx]) {
                        hucreBoya.setColor(tm.vurgu);
                        float r = Math.max(2f * dp, hucreBoy * 0.16f);
                        canvas.drawCircle(sol + hucreBoy - r - 1.6f * dp, ust + r + 1.6f * dp, r, hucreBoya);
                    }
                }
            }
        }

        @Override
        public boolean onTouchEvent(MotionEvent event) {
            if (event.getAction() == MotionEvent.ACTION_UP && hucreBoy > 0) {
                float x = event.getX();
                float y = event.getY();
                int col = (int) Math.floor((x - solPay) / (hucreBoy + aralik));
                int row = (int) Math.floor((y - ustPay) / (hucreBoy + aralik));
                if (col >= 0 && col < SUTUN && row >= 0 && row < SATIR) {
                    int idx = col * SATIR + row;
                    performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK);
                    Context c = getContext();
                    String d = gunDizisi(c, gunKey(gunMs[idx]));
                    int eda = edaSayisi(d);
                    int cem = cemaatSayisi(d);
                    int maz = mazeretSayisi(d);
                    StringBuilder ozet = new StringBuilder(Metinler.tarih(gunMs[idx]));
                    ozet.append(" · ").append(eda).append("/5 Edâ");
                    if (cem > 0) ozet.append(" (").append(cem).append(" Cemaat)");
                    if (maz > 0) ozet.append(" · ").append(maz).append(" Özel Hâl");
                    Toast.makeText(c, ozet.toString(), Toast.LENGTH_SHORT).show();
                    return true;
                }
            }
            return true;
        }
    }

    // ================================================================ Yardımcılar

    private static Calendar ogleTakvimi() {
        Calendar cal = Calendar.getInstance();
        cal.set(Calendar.HOUR_OF_DAY, 12);
        cal.set(Calendar.MINUTE, 0);
        cal.set(Calendar.SECOND, 0);
        cal.set(Calendar.MILLISECOND, 0);
        return cal;
    }

    private static String takvimKey(Calendar cal) {
        return String.format(Locale.ROOT, "%04d-%02d-%02d",
                cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1, cal.get(Calendar.DAY_OF_MONTH));
    }

    private static Calendar anahtardanTakvim(String key) {
        try {
            String[] p = key.split("-");
            if (p.length != 3) return null;
            Calendar cal = ogleTakvimi();
            cal.set(Integer.parseInt(p[0]), Integer.parseInt(p[1]) - 1, Integer.parseInt(p[2]));
            return cal;
        } catch (Throwable t) {
            return null;
        }
    }

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
