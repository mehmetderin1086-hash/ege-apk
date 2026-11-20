package com.mehmetderin.secde_vakti.saglik;

import android.app.AlertDialog;
import android.content.Context;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.text.Editable;
import android.text.InputType;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.HapticFeedbackConstants;
import android.view.View;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.Date;
import java.util.Locale;
import java.util.Map;

/**
 * 6 Vakit Kazâ Namazı Defteri, Kazâ Borcu Hesaplama Sihirbazı ve Oruç Takvimi:
 *  - Depolama: "secde_kaza_oruc" SharedPreferences
 *  - Vakitler: 0=Sabah, 1=Öğle, 2=İkindi, 3=Akşam, 4=Yatsı, 5=Vitir
 *  - Oruç Türleri: 1=Ramazan, 2=Kazâ Orucu, 3=Şevval (6 Gün), 4=Pazartesi/Perşembe Sünneti, 5=Eyyâm-ı Bîz (13-14-15)
 */
public final class KazaTakip {

    public static final String DOSYA = "secde_kaza_oruc";

    public static final String[] VAKIT_ADLARI = {"Sabah", "Öğle", "İkindi", "Akşam", "Yatsı", "Vitir"};

    public static final int ORUC_YOK = 0;
    public static final int ORUC_RAMAZAN = 1;
    public static final int ORUC_KAZA = 2;
    public static final int ORUC_SEVVAL = 3;
    public static final int ORUC_SUNNET = 4;
    public static final int ORUC_EYYAMI_BIZ = 5;

    public static final String[] ORUC_ADLARI = {
            "Yok",
            "Ramazan Orucu",
            "Kazâ Orucu",
            "Şevval (6 Gün)",
            "Pzt / Per Sünneti",
            "Eyyâm-ı Bîz (13-15)"
    };

    public static final String[] ORUC_KISA_ADLAR = {
            "Yok", "Ramazan", "Kazâ", "Şevval", "Sünnet", "Eyyâm-ı Bîz"
    };

    private static final int[] HEDEFLER = {1, 2, 5, 10};
    private static final String ANAHTAR_HEDEF = "gunluk_kaza_hedef";
    private static final String ANAHTAR_KAZA_ORUC = "kaza_oruc_borcu";
    private static final String ANAHTAR_SECILI_ORUC_TURU = "secili_oruc_turu";

    private KazaTakip() {}

    static SharedPreferences sp(Context c) {
        return c.getSharedPreferences(DOSYA, Context.MODE_PRIVATE);
    }

    // ================================================================ 6 Vakit Kazâ Namazı Veri API

    public static int borc(Context c, int vakitIdx) {
        if (vakitIdx < 0 || vakitIdx >= 6) return 0;
        return Math.max(0, sp(c).getInt("borc_" + vakitIdx, 0));
    }

    public static void borcAyarla(Context c, int vakitIdx, int deger) {
        if (vakitIdx < 0 || vakitIdx >= 6) return;
        sp(c).edit().putInt("borc_" + vakitIdx, Math.max(0, deger)).apply();
    }

    public static void artir(Context c, int vakitIdx, int fark) {
        if (vakitIdx < 0 || vakitIdx >= 6 || fark == 0) return;
        int mevcut = borc(c, vakitIdx);
        int yeni = Math.max(0, mevcut + fark);
        SharedPreferences.Editor ed = sp(c).edit().putInt("borc_" + vakitIdx, yeni);
        if (fark < 0 && mevcut > yeni) {
            int dusulen = mevcut - yeni;
            String kKey = "kilinan_" + bugunKey();
            int bugunKilinan = Math.max(0, sp(c).getInt(kKey, 0)) + dusulen;
            ed.putInt(kKey, bugunKilinan);
        }
        ed.apply();
    }

    public static int toplamBorc(Context c) {
        int top = 0;
        for (int i = 0; i < 6; i++) {
            top += borc(c, i);
        }
        return top;
    }

    public static int bugunKilinanKaza(Context c) {
        return Math.max(0, sp(c).getInt("kilinan_" + bugunKey(), 0));
    }

    public static int gunlukHedef(Context c) {
        int h = sp(c).getInt(ANAHTAR_HEDEF, 5);
        return h > 0 ? h : 5;
    }

    public static void gunlukHedefSec(Context c, int hedef) {
        sp(c).edit().putInt(ANAHTAR_HEDEF, Math.max(1, hedef)).apply();
    }

    // ================================================================ Oruç Defteri Veri API

    public static int orucTuru(Context c, String gunKey) {
        if (gunKey == null) return ORUC_YOK;
        int v = sp(c).getInt("oruc_" + gunKey, ORUC_YOK);
        return (v >= ORUC_YOK && v <= ORUC_EYYAMI_BIZ) ? v : ORUC_YOK;
    }

    public static void orucIsaretle(Context c, String gunKey, int tur) {
        if (gunKey == null) return;
        int temizTur = (tur >= ORUC_YOK && tur <= ORUC_EYYAMI_BIZ) ? tur : ORUC_YOK;
        int eski = orucTuru(c, gunKey);
        SharedPreferences.Editor ed = sp(c).edit();
        if (temizTur == ORUC_YOK) {
            ed.remove("oruc_" + gunKey);
        } else {
            ed.putInt("oruc_" + gunKey, temizTur);
        }
        // Kazâ orucu işaretlendiyse borçtan otomatik düş, kaldırıldıysa iade et
        int mevcutBorc = kazaOrucuBorcu(c);
        if (eski != ORUC_KAZA && temizTur == ORUC_KAZA && mevcutBorc > 0) {
            ed.putInt(ANAHTAR_KAZA_ORUC, mevcutBorc - 1);
        } else if (eski == ORUC_KAZA && temizTur != ORUC_KAZA) {
            ed.putInt(ANAHTAR_KAZA_ORUC, mevcutBorc + 1);
        }
        ed.apply();
    }

    public static int kazaOrucuBorcu(Context c) {
        return Math.max(0, sp(c).getInt(ANAHTAR_KAZA_ORUC, 0));
    }

    public static void kazaOrucuBorcuAyarla(Context c, int deger) {
        sp(c).edit().putInt(ANAHTAR_KAZA_ORUC, Math.max(0, deger)).apply();
    }

    public static void kazaOrucuArtir(Context c, int fark) {
        kazaOrucuBorcuAyarla(c, Math.max(0, kazaOrucuBorcu(c) + fark));
    }

    /** İçinde bulunulan milâdî yılda tutulan Şevval (tür = 3) oruçlarının sayısını döndürür. */
    public static int sevvalSayisi(Context c) {
        int yil = Calendar.getInstance().get(Calendar.YEAR);
        String onEk = "oruc_" + yil + "-";
        int sayac = 0;
        for (Map.Entry<String, ?> e : sp(c).getAll().entrySet()) {
            String k = e.getKey();
            if (k != null && k.startsWith(onEk) && e.getValue() instanceof Integer) {
                if (((Integer) e.getValue()) == ORUC_SEVVAL) {
                    sayac++;
                }
            }
        }
        return sayac;
    }

    private static String bugunKey() {
        Calendar cal = Calendar.getInstance();
        return String.format(Locale.ROOT, "%04d-%02d-%02d",
                cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1, cal.get(Calendar.DAY_OF_MONTH));
    }

    // ================================================================ Tam Alt Sayfa Arayüzü

    public static void sayfaAc(final DurumAktivitesi a) {
        sayfaAc(a, false);
    }

    public static void sayfaAc(final DurumAktivitesi a, boolean baslangicOrucSekmesi) {
        final LinearLayout kokSutun = a.sutun();
        final ScrollView sv = a.sayfa(kokSutun);
        sv.setPadding(0, 0, 0, 0);

        final boolean[] orucSekmesi = {baslangicOrucSekmesi};
        Calendar simdi = Calendar.getInstance();
        final int[] gosterilenYilAy = {simdi.get(Calendar.YEAR), simdi.get(Calendar.MONTH)};

        final Runnable[] ciz = new Runnable[1];
        ciz[0] = () -> {
            final int kaymaY = sv.getScrollY();
            kokSutun.removeAllViews();
            sayfaDoldur(a, kokSutun, orucSekmesi, gosterilenYilAy, ciz[0]);
            sv.post(() -> sv.scrollTo(0, kaymaY));
        };
        ciz[0].run();

        a.altSayfa("Kazâ ve Oruç Defteri", sv, "mihrap");
    }

    private static void sayfaDoldur(final DurumAktivitesi a, final LinearLayout s,
                                    final boolean[] orucSekmesi, final int[] gosterilenYilAy,
                                    final Runnable yenile) {
        final TemaMotoru.Durum tm = TemaMotoru.aktif(a);

        // Üst Sekme Seçici: [ Kazâ Namazları | Oruç Defteri ]
        LinearLayout sekmeCubuk = new LinearLayout(a);
        sekmeCubuk.setOrientation(LinearLayout.HORIZONTAL);
        sekmeCubuk.setPadding(a.dp(4), a.dp(4), a.dp(4), a.dp(4));
        GradientDrawable cubukBg = new GradientDrawable();
        cubukBg.setCornerRadius(a.dp(18));
        cubukBg.setColor(tm.acik ? 0x1414211C : 0x22FFFFFF);
        cubukBg.setStroke(1, tm.acik ? 0x2614211C : 0x33FFFFFF);
        sekmeCubuk.setBackground(cubukBg);

        sekmeCubuk.addView(sekmeCipi(a, tm, "Kazâ Namazları", !orucSekmesi[0], () -> {
            if (orucSekmesi[0]) {
                orucSekmesi[0] = false;
                yenile.run();
            }
        }), new LinearLayout.LayoutParams(0, -2, 1f));

        sekmeCubuk.addView(sekmeCipi(a, tm, "Oruç Defteri", orucSekmesi[0], () -> {
            if (!orucSekmesi[0]) {
                orucSekmesi[0] = true;
                yenile.run();
            }
        }), new LinearLayout.LayoutParams(0, -2, 1f));

        LinearLayout.LayoutParams slp = new LinearLayout.LayoutParams(-1, -2);
        slp.setMargins(0, 0, 0, a.dp(14));
        s.addView(sekmeCubuk, slp);

        if (!orucSekmesi[0]) {
            kazaNamazlariSekmesi(a, tm, s, yenile);
        } else {
            orucDefteriSekmesi(a, tm, s, gosterilenYilAy, yenile);
        }
    }

    private static View sekmeCipi(DurumAktivitesi a, TemaMotoru.Durum tm, String ad,
                                  boolean secili, Runnable tik) {
        TextView tv = metin(a, tm, ad, 14, secili ? tm.birincilDugmeYaziRengi() : tm.soluk, true);
        tv.setShadowLayer(0, 0, 0, 0);
        tv.setGravity(Gravity.CENTER);
        tv.setPadding(a.dp(10), a.dp(10), a.dp(10), a.dp(10));
        if (secili) {
            tv.setBackground(tm.birincilDugme(a, 14));
        }
        tv.setClickable(true);
        tv.setOnClickListener(v -> {
            v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            tik.run();
        });
        return tv;
    }

    // ================================================================ Sekme 1: Kazâ Namazları

    private static void kazaNamazlariSekmesi(final DurumAktivitesi a, final TemaMotoru.Durum tm,
                                             final LinearLayout s, final Runnable yenile) {
        int toplam = toplamBorc(a);
        int bugunKilinan = bugunKilinanKaza(a);
        int hedef = gunlukHedef(a);

        // 1) Özet Kartı + Günlük Hedef + Tahmini Bitiş + (-1 Gün) Hızlı Düşüm
        LinearLayout ozetKart = kart(a, tm);

        LinearLayout ust = new LinearLayout(a);
        ust.setOrientation(LinearLayout.HORIZONTAL);
        ust.setGravity(Gravity.CENTER_VERTICAL);

        LinearLayout sol = new LinearLayout(a);
        sol.setOrientation(LinearLayout.VERTICAL);
        sol.addView(metin(a, tm, "TOPLAM KALAN KAZÂ BORCU", 11, tm.vurgu, true));
        sol.addView(metin(a, tm, binlik(toplam) + " vakit", 28, tm.metin, true));
        ust.addView(sol, new LinearLayout.LayoutParams(0, -2, 1f));

        TextView bugunRozet = metin(a, tm, "Bugün: " + bugunKilinan + " kılındı", 12, tm.iyi, true);
        bugunRozet.setShadowLayer(0, 0, 0, 0);
        bugunRozet.setPadding(a.dp(10), a.dp(5), a.dp(10), a.dp(5));
        GradientDrawable brBg = new GradientDrawable();
        brBg.setCornerRadius(a.dp(12));
        brBg.setColor((tm.iyi & 0x00FFFFFF) | (tm.acik ? 0x1E000000 : 0x2A000000));
        brBg.setStroke(1, (tm.iyi & 0x00FFFFFF) | 0x66000000);
        bugunRozet.setBackground(brBg);
        ust.addView(bugunRozet);
        ozetKart.addView(ust);

        a.bosluk(ozetKart, 10);

        // Günlük hedef seçici
        ozetKart.addView(metin(a, tm, "Günlük Kazâ Hedefi", 12, tm.soluk, true));
        LinearLayout hedefSatir = new LinearLayout(a);
        hedefSatir.setOrientation(LinearLayout.HORIZONTAL);
        hedefSatir.setPadding(0, a.dp(4), 0, a.dp(8));
        for (int i = 0; i < HEDEFLER.length; i++) {
            final int hDeger = HEDEFLER[i];
            boolean secili = (hDeger == hedef);
            TextView hc = metin(a, tm, "Günde " + hDeger, 12,
                    secili ? tm.birincilDugmeYaziRengi() : tm.metin, true);
            hc.setShadowLayer(0, 0, 0, 0);
            hc.setGravity(Gravity.CENTER);
            hc.setPadding(a.dp(8), a.dp(7), a.dp(8), a.dp(7));
            hc.setBackground(tm.cipArkaPlani(a, secili, 12));
            hc.setClickable(true);
            hc.setOnClickListener(v -> {
                v.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK);
                gunlukHedefSec(a, hDeger);
                yenile.run();
            });
            LinearLayout.LayoutParams hlp = new LinearLayout.LayoutParams(0, -2, 1f);
            if (i > 0) hlp.setMargins(a.dp(6), 0, 0, 0);
            hedefSatir.addView(hc, hlp);
        }
        ozetKart.addView(hedefSatir);

        // Tahmini bitiş tarihi
        if (toplam == 0) {
            ozetKart.addView(metin(a, tm, "✓ Elhamdülillah, kayıtlı kazâ namazı borcunuz bulunmuyor.",
                    13, tm.iyi, true));
        } else {
            int gerekenGun = (int) Math.ceil(toplam / (double) hedef);
            Calendar bitisCal = Calendar.getInstance();
            bitisCal.add(Calendar.DAY_OF_YEAR, gerekenGun);
            String bitisTarih = new SimpleDateFormat("d MMMM yyyy", Metinler.TR).format(bitisCal.getTime());
            ozetKart.addView(metin(a, tm, "📅 Günde " + hedef + " kazâ ile tahmini bitiş: "
                    + bitisTarih + " (" + binlik(gerekenGun) + " gün)", 13, tm.soluk, false));
        }

        // Hızlı düğme: Tümünden 1 Günlük Düş (-1 Gün)
        TextView birGunDus = temaDugmesi(a, tm, "Tümünden 1 Günlük Düş (-1 Gün)", true, v -> {
            int dusulen = 0;
            for (int i = 0; i < 6; i++) {
                if (borc(a, i) > 0) {
                    artir(a, i, -1);
                    dusulen++;
                }
            }
            if (dusulen > 0) {
                Toast.makeText(a, "Allah kabul etsin · 1 günlük (" + dusulen + " vakit) kazâ düşüldü",
                        Toast.LENGTH_SHORT).show();
                yenile.run();
            } else {
                Toast.makeText(a, "Düşülecek kazâ borcu bulunmuyor", Toast.LENGTH_SHORT).show();
            }
        });
        ozetKart.addView(birGunDus);
        s.addView(ozetKart);

        // 2) 6 Vakit Kazâ Cetveli
        s.addView(bolumBasligi(a, tm, "6 Vakit Kazâ Çizelgesi"));
        LinearLayout listeKart = kart(a, tm);
        listeKart.addView(metin(a, tm, "Sayıya dokunarak doğrudan adet girebilirsiniz.", 11, tm.silik, false));
        a.bosluk(listeKart, 4);

        for (int i = 0; i < 6; i++) {
            final int idx = i;
            final int adet = borc(a, idx);

            LinearLayout satir = new LinearLayout(a);
            satir.setOrientation(LinearLayout.HORIZONTAL);
            satir.setGravity(Gravity.CENTER_VERTICAL);
            satir.setPadding(0, a.dp(8), 0, a.dp(8));

            LinearLayout solBilgi = new LinearLayout(a);
            solBilgi.setOrientation(LinearLayout.VERTICAL);
            solBilgi.addView(metin(a, tm, VAKIT_ADLARI[idx], 15, tm.metin, true));
            if (idx == 5) {
                solBilgi.addView(metin(a, tm, "Hanefî'de vâcip", 10, tm.silik, false));
            }
            satir.addView(solBilgi, new LinearLayout.LayoutParams(0, -2, 1f));

            // [-5] düğmesi
            satir.addView(kucukIslemDugmesi(a, tm, "-5", false, () -> {
                artir(a, idx, -5);
                yenile.run();
            }));

            // [-1 Kıldım] düğmesi
            View eksiBir = kucukIslemDugmesi(a, tm, "-1 Kıldım", true, () -> {
                artir(a, idx, -1);
                yenile.run();
            });
            LinearLayout.LayoutParams elp = new LinearLayout.LayoutParams(-2, -2);
            elp.setMargins(a.dp(5), 0, a.dp(6), 0);
            satir.addView(eksiBir, elp);

            // Adet (dokununca elle düzenleme)
            TextView tvSayi = metin(a, tm, binlik(adet), 16, adet == 0 ? tm.iyi : tm.vurgu, true);
            tvSayi.setGravity(Gravity.CENTER);
            tvSayi.setMinWidth(a.dp(52));
            tvSayi.setPadding(a.dp(6), a.dp(4), a.dp(6), a.dp(4));
            tvSayi.setClickable(true);
            tvSayi.setOnClickListener(v -> tekilBorcDuzenleDialog(a, VAKIT_ADLARI[idx] + " Kazâ Borcu", adet,
                    yeniDeger -> {
                        borcAyarla(a, idx, yeniDeger);
                        yenile.run();
                    }));
            satir.addView(tvSayi);

            // [+1] düğmesi
            View artiBir = kucukIslemDugmesi(a, tm, "+1", false, () -> {
                artir(a, idx, 1);
                yenile.run();
            });
            LinearLayout.LayoutParams alp = new LinearLayout.LayoutParams(-2, -2);
            alp.setMargins(a.dp(6), 0, 0, 0);
            satir.addView(artiBir, alp);

            listeKart.addView(satir);
            if (i < 5) {
                View cizgi = new View(a);
                cizgi.setBackgroundColor(tm.acik ? 0x1614211C : 0x1AFFFFFF);
                listeKart.addView(cizgi, new LinearLayout.LayoutParams(-1, 1));
            }
        }
        s.addView(listeKart);

        // 3) Kazâ Borcu Hesaplama Sihirbazı Düğmesi
        TextView sihirbazBtn = temaDugmesi(a, tm, "🧮  Kazâ Borcu Hesaplama Sihirbazı", false,
                v -> hesapSihirbaziAc(a, tm, yenile));
        s.addView(sihirbazBtn);
    }

    private static View kucukIslemDugmesi(DurumAktivitesi a, TemaMotoru.Durum tm,
                                          String etiket, boolean vurgulu, Runnable tik) {
        TextView b = metin(a, tm, etiket, 12,
                vurgulu ? tm.birincilDugmeYaziRengi() : tm.metin, true);
        b.setShadowLayer(0, 0, 0, 0);
        b.setGravity(Gravity.CENTER);
        b.setPadding(a.dp(9), a.dp(6), a.dp(9), a.dp(6));
        b.setBackground(vurgulu ? tm.birincilDugme(a, 10) : tm.ikincilDugme(a, 10));
        b.setClickable(true);
        a.basmaEfekti(b);
        b.setOnClickListener(v -> {
            v.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK);
            tik.run();
        });
        return b;
    }

    private interface SayiSonuc {
        void secildi(int deger);
    }

    private static void tekilBorcDuzenleDialog(final DurumAktivitesi a, String baslik,
                                               int mevcut, final SayiSonuc sonuc) {
        LinearLayout kap = new LinearLayout(a);
        kap.setOrientation(LinearLayout.VERTICAL);
        kap.setPadding(a.dp(20), a.dp(12), a.dp(20), a.dp(4));

        final EditText et = new EditText(a);
        et.setInputType(InputType.TYPE_CLASS_NUMBER);
        et.setText(String.valueOf(mevcut));
        et.setSelectAllOnFocus(true);
        kap.addView(et, new LinearLayout.LayoutParams(-1, -2));

        new AlertDialog.Builder(a)
                .setTitle(baslik)
                .setView(kap)
                .setPositiveButton("Kaydet", (d, w) -> {
                    int yeni = tamSayiOku(et.getText().toString(), mevcut);
                    sonuc.secildi(Math.max(0, yeni));
                })
                .setNegativeButton("Vazgeç", null)
                .show();
    }

    /**
     * Kazâ Borcu Hesaplama Sihirbazı (AlertDialog):
     * Formül: (yil*365 + ay*30) * ((30 - muafiyet) / 30.0)
     */
    private static void hesapSihirbaziAc(final DurumAktivitesi a, final TemaMotoru.Durum tm,
                                         final Runnable yenile) {
        LinearLayout form = new LinearLayout(a);
        form.setOrientation(LinearLayout.VERTICAL);
        form.setPadding(a.dp(20), a.dp(12), a.dp(20), a.dp(6));

        TextView aciklama = new TextView(a);
        aciklama.setText("Bülûğ çağından itibaren namaz kılınamayan tahmini süreyi girin. "
                + "Hanımlar özel hâl günlerini aylık muafiyet (0–15 gün) olarak düşebilir.");
        aciklama.setTextSize(13);
        aciklama.setPadding(0, 0, 0, a.dp(10));
        form.addView(aciklama);

        final EditText etYil = sihirbazGirdisi(a, form, "Yıl sayısı", "Örn: 2", "0");
        final EditText etAy = sihirbazGirdisi(a, form, "Ek ay sayısı", "Örn: 6", "0");
        final EditText etMuaf = sihirbazGirdisi(a, form, "Aylık muafiyet günü (0–15, isteğe bağlı)",
                "Hanımlar için özel hâl (yoksa 0)", "0");

        final TextView onizleme = new TextView(a);
        onizleme.setTextSize(14);
        onizleme.setPadding(0, a.dp(10), 0, a.dp(4));
        onizleme.setTextColor(tm.acik ? 0xFF1E6B55 : 0xFFE5C16C);
        form.addView(onizleme);

        final int[] hesaplananVakitBasi = {0};
        final Runnable hesaplaGuncelle = () -> {
            int yil = Math.max(0, tamSayiOku(etYil.getText().toString(), 0));
            int ay = Math.max(0, tamSayiOku(etAy.getText().toString(), 0));
            int muaf = Math.max(0, Math.min(15, tamSayiOku(etMuaf.getText().toString(), 0)));
            int vakitBasi = (int) Math.round((yil * 365 + ay * 30) * ((30 - muaf) / 30.0));
            hesaplananVakitBasi[0] = vakitBasi;
            onizleme.setText("Hesaplanan: Her vakit için " + binlik(vakitBasi)
                    + " kazâ\n(6 vakit toplamı: " + binlik(vakitBasi * 6L) + " vakit)");
        };
        TextWatcher izleyici = new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int st, int c, int af) {}
            @Override public void onTextChanged(CharSequence s, int st, int b, int c) {}
            @Override public void afterTextChanged(Editable s) { hesaplaGuncelle.run(); }
        };
        etYil.addTextChangedListener(izleyici);
        etAy.addTextChangedListener(izleyici);
        etMuaf.addTextChangedListener(izleyici);
        hesaplaGuncelle.run();

        new AlertDialog.Builder(a)
                .setTitle("Kazâ Borcu Hesaplama Sihirbazı")
                .setView(form)
                .setPositiveButton("Mevcut Borca Ekle", (d, w) -> {
                    int eklenecek = hesaplananVakitBasi[0];
                    if (eklenecek <= 0) {
                        Toast.makeText(a, "Lütfen yıl veya ay sayısı girin", Toast.LENGTH_SHORT).show();
                        return;
                    }
                    for (int i = 0; i < 6; i++) {
                        borcAyarla(a, i, borc(a, i) + eklenecek);
                    }
                    Toast.makeText(a, "Her vakte +" + binlik(eklenecek) + " kazâ borcu eklendi",
                            Toast.LENGTH_SHORT).show();
                    yenile.run();
                })
                .setNeutralButton("Borcu Bununla Ayarla", (d, w) -> {
                    int yeni = hesaplananVakitBasi[0];
                    for (int i = 0; i < 6; i++) {
                        borcAyarla(a, i, yeni);
                    }
                    Toast.makeText(a, "Kazâ defteri her vakit için " + binlik(yeni) + " olarak ayarlandı",
                            Toast.LENGTH_SHORT).show();
                    yenile.run();
                })
                .setNegativeButton("Vazgeç", null)
                .show();
    }

    private static EditText sihirbazGirdisi(Context c, LinearLayout ebeveyn, String etiket,
                                            String ipucu, String varsayilan) {
        TextView tv = new TextView(c);
        tv.setText(etiket);
        tv.setTextSize(12);
        tv.setPadding(0, TemaMotoru.dp(c, 6), 0, 0);
        ebeveyn.addView(tv);

        EditText et = new EditText(c);
        et.setInputType(InputType.TYPE_CLASS_NUMBER);
        et.setHint(ipucu);
        et.setText(varsayilan);
        et.setSelectAllOnFocus(true);
        ebeveyn.addView(et, new LinearLayout.LayoutParams(-1, -2));
        return et;
    }

    // ================================================================ Sekme 2: Oruç Defteri

    private static void orucDefteriSekmesi(final DurumAktivitesi a, final TemaMotoru.Durum tm,
                                           final LinearLayout s, final int[] gosterilenYilAy,
                                           final Runnable yenile) {
        final String bugun = bugunKey();
        final int bugunOruc = orucTuru(a, bugun);
        final int varsayilanTur = Math.max(ORUC_RAMAZAN,
                Math.min(ORUC_EYYAMI_BIZ, sp(a).getInt(ANAHTAR_SECILI_ORUC_TURU,
                        RamazanModu.ramazanMi(VakitTakvimi.oku(a)) ? ORUC_RAMAZAN : ORUC_SUNNET)));

        // 1) Bugünün Orucu Hızlı Kartı
        LinearLayout bugunKart = kart(a, tm);
        bugunKart.addView(metin(a, tm, "BUGÜNÜN ORUCU · " + Metinler.tarih(System.currentTimeMillis()).toUpperCase(Metinler.TR),
                11, tm.vurgu, true));
        a.bosluk(bugunKart, 6);

        // Oruç Türü Çipleri
        HorizontalScrollView turKaydir = new HorizontalScrollView(a);
        turKaydir.setHorizontalScrollBarEnabled(false);
        turKaydir.setOverScrollMode(View.OVER_SCROLL_NEVER);
        LinearLayout turSatir = new LinearLayout(a);
        turSatir.setOrientation(LinearLayout.HORIZONTAL);
        int aktifSeciliTur = bugunOruc != ORUC_YOK ? bugunOruc : varsayilanTur;

        for (int t = ORUC_RAMAZAN; t <= ORUC_EYYAMI_BIZ; t++) {
            final int turKod = t;
            boolean secili = (aktifSeciliTur == turKod);
            TextView cip = metin(a, tm, ORUC_KISA_ADLAR[turKod], 12,
                    secili ? tm.birincilDugmeYaziRengi() : tm.metin, true);
            cip.setShadowLayer(0, 0, 0, 0);
            cip.setPadding(a.dp(12), a.dp(7), a.dp(12), a.dp(7));
            cip.setBackground(tm.cipArkaPlani(a, secili, 13));
            cip.setClickable(true);
            cip.setOnClickListener(v -> {
                v.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK);
                sp(a).edit().putInt(ANAHTAR_SECILI_ORUC_TURU, turKod).apply();
                if (bugunOruc != ORUC_YOK) {
                    orucIsaretle(a, bugun, turKod);
                }
                yenile.run();
            });
            LinearLayout.LayoutParams clp = new LinearLayout.LayoutParams(-2, -2);
            clp.setMargins(0, 0, a.dp(6), 0);
            turSatir.addView(cip, clp);
        }
        turKaydir.addView(turSatir);
        bugunKart.addView(turKaydir);

        String dugmeMetni = bugunOruc != ORUC_YOK
                ? "✓ Bugün Oruçluyum (" + ORUC_ADLARI[bugunOruc] + ") · Kaldırmak İçin Dokun"
                : "Bugün Oruçluyum ✓ (" + ORUC_KISA_ADLAR[aktifSeciliTur] + " İşaretle)";
        TextView orucluyumBtn = temaDugmesi(a, tm, dugmeMetni, bugunOruc == ORUC_YOK, v -> {
            if (bugunOruc != ORUC_YOK) {
                orucIsaretle(a, bugun, ORUC_YOK);
            } else {
                orucIsaretle(a, bugun, aktifSeciliTur);
                Toast.makeText(a, "Allah kabul etsin · " + ORUC_ADLARI[aktifSeciliTur] + " kaydedildi",
                        Toast.LENGTH_SHORT).show();
            }
            yenile.run();
        });
        if (bugunOruc != ORUC_YOK) {
            GradientDrawable yesil = new GradientDrawable();
            yesil.setCornerRadius(a.dp(16));
            yesil.setColor((tm.iyi & 0x00FFFFFF) | (tm.acik ? 0x24000000 : 0x36000000));
            yesil.setStroke(Math.max(1, a.dp(1)), tm.iyi);
            orucluyumBtn.setBackground(yesil);
            orucluyumBtn.setTextColor(tm.iyi);
        }
        bugunKart.addView(orucluyumBtn);
        s.addView(bugunKart);

        // 2) Kazâ Orucu Borcu ve Şevval 6 Gün İlerlemesi
        LinearLayout borcKart = kart(a, tm);
        LinearLayout kazaSatir = new LinearLayout(a);
        kazaSatir.setOrientation(LinearLayout.HORIZONTAL);
        kazaSatir.setGravity(Gravity.CENTER_VERTICAL);

        final int orucBorc = kazaOrucuBorcu(a);
        LinearLayout kazaSol = new LinearLayout(a);
        kazaSol.setOrientation(LinearLayout.VERTICAL);
        kazaSol.addView(metin(a, tm, "Kazâ Orucu Borcu", 15, tm.metin, true));
        kazaSol.addView(metin(a, tm, "Sayıya dokunarak doğrudan düzenleyebilirsiniz", 11, tm.silik, false));
        kazaSatir.addView(kazaSol, new LinearLayout.LayoutParams(0, -2, 1f));

        kazaSatir.addView(kucukIslemDugmesi(a, tm, "-1", true, () -> {
            kazaOrucuArtir(a, -1);
            yenile.run();
        }));

        TextView tvOBorc = metin(a, tm, orucBorc + " gün", 16, orucBorc == 0 ? tm.iyi : tm.vurgu, true);
        tvOBorc.setGravity(Gravity.CENTER);
        tvOBorc.setPadding(a.dp(10), a.dp(4), a.dp(10), a.dp(4));
        tvOBorc.setClickable(true);
        tvOBorc.setOnClickListener(v -> tekilBorcDuzenleDialog(a, "Kazâ Orucu Borcu (Gün)", orucBorc, yeni -> {
            kazaOrucuBorcuAyarla(a, yeni);
            yenile.run();
        }));
        kazaSatir.addView(tvOBorc);

        kazaSatir.addView(kucukIslemDugmesi(a, tm, "+1", false, () -> {
            kazaOrucuArtir(a, 1);
            yenile.run();
        }));
        borcKart.addView(kazaSatir);

        a.bosluk(borcKart, 12);
        View ayirici = new View(a);
        ayirici.setBackgroundColor(tm.acik ? 0x1614211C : 0x1AFFFFFF);
        borcKart.addView(ayirici, new LinearLayout.LayoutParams(-1, 1));
        a.bosluk(borcKart, 10);

        // Şevval 6 Gün İlerleme Çubuğu
        int sevval = sevvalSayisi(a);
        int sevvalHedef = 6;
        LinearLayout sevvalUst = new LinearLayout(a);
        sevvalUst.setOrientation(LinearLayout.HORIZONTAL);
        sevvalUst.setGravity(Gravity.CENTER_VERTICAL);
        sevvalUst.addView(metin(a, tm, "Şevval Ayı 6 Gün Sünnet Orucu", 14, tm.metin, true),
                new LinearLayout.LayoutParams(0, -2, 1f));
        sevvalUst.addView(metin(a, tm, Math.min(sevval, sevvalHedef) + " / 6 gün", 14,
                sevval >= sevvalHedef ? tm.iyi : tm.vurgu, true));
        borcKart.addView(sevvalUst);

        a.bosluk(borcKart, 6);
        FrameLayout ilerlemeDis = new FrameLayout(a);
        GradientDrawable izBg = new GradientDrawable();
        izBg.setCornerRadius(a.dp(6));
        izBg.setColor(tm.acik ? 0x1814211C : 0x24FFFFFF);
        ilerlemeDis.setBackground(izBg);

        LinearLayout ilerlemeSatir = new LinearLayout(a);
        ilerlemeSatir.setOrientation(LinearLayout.HORIZONTAL);
        float doluluk = Math.min(1f, sevval / 6f);
        if (doluluk > 0f) {
            View dolu = new View(a);
            GradientDrawable doluBg = new GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT,
                    new int[]{tm.vurguKoyu, sevval >= 6 ? tm.iyi : tm.vurgu});
            doluBg.setCornerRadius(a.dp(6));
            dolu.setBackground(doluBg);
            ilerlemeSatir.addView(dolu, new LinearLayout.LayoutParams(0, a.dp(10), doluluk));
        }
        if (doluluk < 1f) {
            ilerlemeSatir.addView(new View(a), new LinearLayout.LayoutParams(0, a.dp(10), 1f - doluluk));
        }
        ilerlemeDis.addView(ilerlemeSatir, new FrameLayout.LayoutParams(-1, a.dp(10)));
        borcKart.addView(ilerlemeDis);
        a.bosluk(borcKart, 4);
        borcKart.addView(metin(a, tm, sevval >= 6
                ? "✓ Bu yılki 6 gün Şevval orucunu tamamladınız, Allah kabul etsin!"
                : "\"Ramazan orucunu tutup ardından Şevval'den altı gün oruç tutan bütün yılı oruçlu geçirmiş gibi olur.\" (Müslim)",
                12, sevval >= 6 ? tm.iyi : tm.soluk, false));
        s.addView(borcKart);

        // 3) Yaklaşan Pazartesi/Perşembe ve Eyyâm-ı Bîz Hatırlatıcısı
        s.addView(bolumBasligi(a, tm, "Sünnet Orucu Günleri"));
        LinearLayout sunnetKart = kart(a, tm);
        sunnetKart.addView(metin(a, tm, "📅 Yaklaşan Pazartesi / Perşembe: " + yaklasanPztPerMetni(),
                13, tm.metin, true));
        String eyyamBilgi = yaklasanEyyamiBizMetni(a);
        sunnetKart.addView(metin(a, tm, "🌕 Eyyâm-ı Bîz (Hicrî 13, 14, 15. günler): " + eyyamBilgi,
                13, tm.soluk, false));
        s.addView(sunnetKart);

        // 4) Etkileşimli Aylık Oruç Takvimi
        s.addView(bolumBasligi(a, tm, "Aylık Oruç Takvimi"));
        s.addView(aylikTakvimKarti(a, tm, gosterilenYilAy, yenile));
    }

    private static View aylikTakvimKarti(final DurumAktivitesi a, final TemaMotoru.Durum tm,
                                         final int[] gosterilenYilAy, final Runnable yenile) {
        LinearLayout takvimKart = kart(a, tm);

        Calendar ayBasi = Calendar.getInstance();
        ayBasi.set(gosterilenYilAy[0], gosterilenYilAy[1], 1, 12, 0, 0);
        ayBasi.set(Calendar.MILLISECOND, 0);

        String ayBaslik = new SimpleDateFormat("MMMM yyyy", Metinler.TR).format(ayBasi.getTime());

        // Üst Ay Gezgini: ‹ Ay Yıl ›
        LinearLayout ust = new LinearLayout(a);
        ust.setOrientation(LinearLayout.HORIZONTAL);
        ust.setGravity(Gravity.CENTER_VERTICAL);

        TextView geri = metin(a, tm, "‹ Önceki", 13, tm.vurgu, true);
        geri.setPadding(a.dp(6), a.dp(6), a.dp(10), a.dp(6));
        geri.setClickable(true);
        geri.setOnClickListener(v -> {
            Calendar c = Calendar.getInstance();
            c.set(gosterilenYilAy[0], gosterilenYilAy[1], 1);
            c.add(Calendar.MONTH, -1);
            gosterilenYilAy[0] = c.get(Calendar.YEAR);
            gosterilenYilAy[1] = c.get(Calendar.MONTH);
            yenile.run();
        });
        ust.addView(geri);

        TextView tvAy = metin(a, tm, ayBaslik, 16, tm.metin, true);
        tvAy.setGravity(Gravity.CENTER);
        ust.addView(tvAy, new LinearLayout.LayoutParams(0, -2, 1f));

        TextView ileri = metin(a, tm, "Sonraki ›", 13, tm.vurgu, true);
        ileri.setPadding(a.dp(10), a.dp(6), a.dp(6), a.dp(6));
        ileri.setClickable(true);
        ileri.setOnClickListener(v -> {
            Calendar c = Calendar.getInstance();
            c.set(gosterilenYilAy[0], gosterilenYilAy[1], 1);
            c.add(Calendar.MONTH, 1);
            gosterilenYilAy[0] = c.get(Calendar.YEAR);
            gosterilenYilAy[1] = c.get(Calendar.MONTH);
            yenile.run();
        });
        ust.addView(ileri);
        takvimKart.addView(ust);
        a.bosluk(takvimKart, 6);

        // Gün başlıkları (Pzt..Paz)
        String[] gunBas = {"Pzt", "Sal", "Çar", "Per", "Cum", "Cmt", "Paz"};
        LinearLayout baslikSatir = new LinearLayout(a);
        baslikSatir.setOrientation(LinearLayout.HORIZONTAL);
        for (String gb : gunBas) {
            TextView x = metin(a, tm, gb, 11, ("Pzt".equals(gb) || "Per".equals(gb)) ? tm.vurgu : tm.silik, true);
            x.setGravity(Gravity.CENTER);
            baslikSatir.addView(x, new LinearLayout.LayoutParams(0, -2, 1f));
        }
        takvimKart.addView(baslikSatir);
        a.bosluk(takvimKart, 4);

        int gunSayisi = ayBasi.getActualMaximum(Calendar.DAY_OF_MONTH);
        int ilkHaftaGunu = (ayBasi.get(Calendar.DAY_OF_WEEK) + 5) % 7; // Pzt=0 .. Paz=6
        String bugunStr = bugunKey();

        int toplamHucre = ((ilkHaftaGunu + gunSayisi + 6) / 7) * 7;
        LinearLayout haftaSatir = null;

        for (int i = 0; i < toplamHucre; i++) {
            if (i % 7 == 0) {
                haftaSatir = new LinearLayout(a);
                haftaSatir.setOrientation(LinearLayout.HORIZONTAL);
                LinearLayout.LayoutParams hlp = new LinearLayout.LayoutParams(-1, -2);
                hlp.setMargins(0, a.dp(2), 0, a.dp(2));
                takvimKart.addView(haftaSatir, hlp);
            }
            int gunNo = i - ilkHaftaGunu + 1;
            if (gunNo < 1 || gunNo > gunSayisi) {
                haftaSatir.addView(new View(a), new LinearLayout.LayoutParams(0, a.dp(40), 1f));
                continue;
            }

            final String gKey = String.format(Locale.ROOT, "%04d-%02d-%02d",
                    gosterilenYilAy[0], gosterilenYilAy[1] + 1, gunNo);
            final int tur = orucTuru(a, gKey);
            boolean bugunMu = bugunStr.equals(gKey);
            int dow = i % 7;
            boolean sunnetGunu = (dow == 0 || dow == 3); // Pazartesi veya Perşembe

            LinearLayout hucre = new LinearLayout(a);
            hucre.setOrientation(LinearLayout.VERTICAL);
            hucre.setGravity(Gravity.CENTER);
            hucre.setPadding(0, a.dp(5), 0, a.dp(5));

            GradientDrawable hBg = new GradientDrawable();
            hBg.setCornerRadius(a.dp(10));
            if (tur != ORUC_YOK) {
                int renk = orucRengi(tm, tur);
                hBg.setColor((renk & 0x00FFFFFF) | (tm.acik ? 0x26000000 : 0x38000000));
                hBg.setStroke(Math.max(1, a.dp(bugunMu ? 2 : 1)), renk);
            } else if (bugunMu) {
                hBg.setColor(tm.acik ? 0x1214211C : 0x1AFFFFFF);
                hBg.setStroke(Math.max(1, a.dp(1)), tm.vurgu);
            } else if (sunnetGunu) {
                hBg.setColor(tm.acik ? 0x0814211C : 0x0EFFFFFF);
            }
            hucre.setBackground(hBg);

            int yaziRenk = tur != ORUC_YOK ? orucRengi(tm, tur)
                    : (bugunMu ? tm.vurgu : (sunnetGunu ? tm.metin : tm.soluk));
            TextView tvNo = metin(a, tm, String.valueOf(gunNo), 13, yaziRenk, tur != ORUC_YOK || bugunMu);
            tvNo.setShadowLayer(0, 0, 0, 0);
            tvNo.setGravity(Gravity.CENTER);
            tvNo.setPadding(0, 0, 0, 0);
            hucre.addView(tvNo);

            String altIsaret = tur != ORUC_YOK ? orucHarfi(tur) : (sunnetGunu ? "·" : "");
            TextView tvAlt = metin(a, tm, altIsaret, 9, tur != ORUC_YOK ? orucRengi(tm, tur) : tm.silik, true);
            tvAlt.setShadowLayer(0, 0, 0, 0);
            tvAlt.setGravity(Gravity.CENTER);
            tvAlt.setPadding(0, 0, 0, 0);
            hucre.addView(tvAlt);

            final int secilenGunNo = gunNo;
            hucre.setClickable(true);
            hucre.setOnClickListener(v -> {
                v.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK);
                orucGunSecimMenusu(a, secilenGunNo + " " + ayBaslik, gKey, yenile);
            });

            LinearLayout.LayoutParams clp = new LinearLayout.LayoutParams(0, a.dp(42), 1f);
            clp.setMargins(a.dp(2), 0, a.dp(2), 0);
            haftaSatir.addView(hucre, clp);
        }

        a.bosluk(takvimKart, 8);
        takvimKart.addView(metin(a, tm,
                "R: Ramazan · K: Kazâ · Ş: Şevval · S: Sünnet · B: Eyyâm-ı Bîz (Güne dokunarak işaretleyin)",
                11, tm.silik, false));
        return takvimKart;
    }

    private static void orucGunSecimMenusu(final DurumAktivitesi a, String baslik,
                                           final String gunKey, final Runnable yenile) {
        final String[] secenekler = {
                "🌙  Ramazan Orucu",
                "↺  Kazâ Orucu",
                "✦  Şevval Orucu (6 Gün)",
                "🌿  Pazartesi / Perşembe Sünneti",
                "🌕  Eyyâm-ı Bîz (13-14-15)",
                "○  İşareti Temizle"
        };
        new AlertDialog.Builder(a)
                .setTitle(baslik)
                .setItems(secenekler, (d, secim) -> {
                    int yeniTur = (secim >= 0 && secim <= 4) ? (secim + 1) : ORUC_YOK;
                    orucIsaretle(a, gunKey, yeniTur);
                    yenile.run();
                })
                .setNegativeButton("Vazgeç", null)
                .show();
    }

    private static int orucRengi(TemaMotoru.Durum tm, int tur) {
        switch (tur) {
            case ORUC_RAMAZAN: return tm.vurgu;
            case ORUC_KAZA: return tm.uyari;
            case ORUC_SEVVAL: return tm.iyi;
            case ORUC_SUNNET: return tm.ana;
            case ORUC_EYYAMI_BIZ: return tm.acik ? 0xFF5E35B1 : 0xFFB39DDB;
            default: return tm.silik;
        }
    }

    private static String orucHarfi(int tur) {
        switch (tur) {
            case ORUC_RAMAZAN: return "R";
            case ORUC_KAZA: return "K";
            case ORUC_SEVVAL: return "Ş";
            case ORUC_SUNNET: return "S";
            case ORUC_EYYAMI_BIZ: return "B";
            default: return "";
        }
    }

    private static String yaklasanPztPerMetni() {
        Calendar c = Calendar.getInstance();
        SimpleDateFormat bicim = new SimpleDateFormat("d MMM EEEE", Metinler.TR);
        String ilk = null;
        String ikinci = null;
        for (int i = 0; i < 8; i++) {
            int dow = c.get(Calendar.DAY_OF_WEEK);
            if (dow == Calendar.MONDAY || dow == Calendar.THURSDAY) {
                String etiket = (i == 0 ? "Bugün (" + bicim.format(c.getTime()) + ")" : bicim.format(c.getTime()));
                if (ilk == null) ilk = etiket;
                else { ikinci = etiket; break; }
            }
            c.add(Calendar.DAY_OF_MONTH, 1);
        }
        return ilk + (ikinci != null ? "  ·  " + ikinci : "");
    }

    private static String yaklasanEyyamiBizMetni(Context context) {
        VakitTakvimi.Takvim t = VakitTakvimi.oku(context);
        Calendar cal = Calendar.getInstance();
        cal.set(Calendar.HOUR_OF_DAY, 12);
        SimpleDateFormat bicim = new SimpleDateFormat("d MMMM", Metinler.TR);
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < 31; i++) {
            String h = t.hicri(cal.getTimeInMillis());
            if (h != null) {
                String temiz = h.trim();
                if (temiz.startsWith("13 ") || temiz.startsWith("14 ") || temiz.startsWith("15 ")) {
                    if (sb.length() > 0) sb.append(", ");
                    sb.append(bicim.format(cal.getTime()));
                }
            }
            cal.add(Calendar.DAY_OF_MONTH, 1);
        }
        if (sb.length() > 0) return sb.toString();
        return "Her hicrî ayın 13, 14 ve 15. dolunay günleri müstehaptır.";
    }

    // ================================================================ Yardımcılar

    private static int tamSayiOku(String s, int varsayilan) {
        if (s == null) return varsayilan;
        String t = s.trim();
        if (t.isEmpty()) return 0;
        try {
            return Integer.parseInt(t);
        } catch (NumberFormatException e) {
            return varsayilan;
        }
    }

    private static String binlik(long n) {
        return String.format(Metinler.TR, "%,d", n);
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
        if (birincil && tm.acik) b.setTextColor(Color.WHITE);
        return b;
    }
}
