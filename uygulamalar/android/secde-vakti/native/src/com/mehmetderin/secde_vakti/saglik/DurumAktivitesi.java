package com.mehmetderin.secde_vakti.saglik;

import android.animation.ArgbEvaluator;
import android.animation.ValueAnimator;
import android.app.Activity;
import android.app.AlertDialog;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.TextUtils;
import android.util.TypedValue;
import android.view.GestureDetector;
import android.view.Gravity;
import android.view.HapticFeedbackConstants;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowManager;
import android.view.animation.DecelerateInterpolator;
import android.view.animation.OvershootInterpolator;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Collections;
import java.util.Date;
import java.util.List;
import java.util.Locale;

/**
 * Secde ana menüsü. Uygulama açılışında (ayarla kapatılabilir), uzun basma kısayolundan,
 * Hızlı Ayarlar kutucuğundan ve bildirimlerden açılır.
 *
 * Tam ekran canlı arka plan (Sahne: cami fotoğrafları, Ken Burns, yıldız/zerre efektleri) üzerinde
 * beş sekme:
 *   0 Vakitler — halka içinde geri sayım, günün vakitleri, resimli hızlı erişim, günün ayeti,
 *                yaklaşan mübarek gün, bildirim durumu, hızlı anahtarlar
 *   1 Kıble    — sensörle dönen pusula, Kâbe yönü ve uzaklığı, hizalanınca ışık + titreşim
 *   2 Zikir    — zikirmatik: 8 zikir, hedef, namaz tesbihatı (33·33·33), günlük/toplam sayım
 *   3 Takvim   — 31 günlük vakit tablosu, hicrî tarih, cuma ve mübarek günler
 *   4 Menü     — uygulamanın bölümlerine resimli butonlar, ayarlar, test, teşhis
 * Sekme geçişleri: kayma + saydamlık, arka plan geçişi, kayan altın gösterge, kaydırma ile geçiş,
 * dokunsal geri bildirim. İçerik sırayla süzülerek gelir. XML kaynağı yoktur.
 */
public final class DurumAktivitesi extends Activity {

    static final String EK_TEST = "test";
    static final String EK_SAYAC = "sayac_degistir";
    static final String EK_SEKME = "sekme";
    static final String EK_YENIDEN_KUR = "yeniden_kur";
    /** Uygulama açılışında ana menü olarak gösterildi. */
    static final String EK_ANA = "ana_menu";
    static final String EK_DOGRUDAN = "secde_dogrudan";
    private static final String SON_SEKME = "son_sekme";
    private static final String AYRINTI_ACIK = "ayrinti_acik";
    static final String ANA_ACTIVITY = "com.mehmetderin.secde_vakti.MainActivity";

    private static final int SEKME_SAYISI = 5;
    private static final String[] SEKME_ADI = {"Vakitler", "Kur'an", "Kıble", "Zikir", "Menü"};
    private static final int[] SEKME_SIMGE = {Simge.VAKIT, Simge.KURAN, Simge.KIBLE, Simge.ZIKIR, Simge.MENU};
    static final int S_VAKIT = 0, S_KURAN = 1, S_KIBLE = 2, S_ZIKIR = 3, S_MENU = 4;

    // Cam paleti: arka plan her zaman koyulaştırılmış fotoğraf olduğu için açık renk metin
    static final int BEYAZ = Color.WHITE;
    static final int SOLUK = 0xCCFFFFFF;
    static final int SILIK = 0x99FFFFFF;
    static final int ALTIN = 0xFFF0B35A;
    static final int KOYU = 0xFF1A1206;
    static final int IYI = 0xFF7FD1A8;
    static final int KOTU = 0xFFFF8A80;
    static final int UYARI = 0xFFFFC66D;
    private static final int CAM_KENAR = 0x33FFFFFF;

    private Sahne sahne;
    private FrameLayout kok;
    private LinearLayout dikey;
    final ArrayList<View> altYigin = new ArrayList<>();
    final ArrayList<String> altArka = new ArrayList<>();
    KuranArayuz kuranArayuz;
    private FrameLayout sayfaKabi;
    private final ScrollView[] sayfalar = new ScrollView[SEKME_SAYISI];
    private final LinearLayout[] sekmeHucre = new LinearLayout[SEKME_SAYISI];
    private final TextView[] sekmeYazi = new TextView[SEKME_SAYISI];
    private final Simge[] sekmeSimge = new Simge[SEKME_SAYISI];
    private View gosterge;
    private FrameLayout sekmeHap;
    private LinearLayout sekmeCubugu;
    private int sekme = 0;
    int ustBosluk, altBosluk;
    private boolean anaMenu;
    private GestureDetector kaydirma;

    private TextView sayacMetni;
    private Halka halka;
    private GokYorungeView gokYorunge;
    private long siradakiZaman, oncekiZaman;
    private int sonDakika = -1;
    private Pusula pusula;
    private TextView kibleDurum;
    private ZikirDaire zikirDaire;
    private final List<ValueAnimator> nabizlar = new ArrayList<>();
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Runnable tik = new Runnable() {
        @Override
        public void run() {
            sayaciGuncelle();
            handler.postDelayed(this, 1000);
        }
    };

    // ================================================================ yaşam döngüsü

    @Override
    protected void onCreate(Bundle b) {
        setTheme(android.R.style.Theme_DeviceDefault_NoActionBar);
        super.onCreate(b);
        setTitle("Secde Vakti");
        Window w = getWindow();
        w.setStatusBarColor(Color.TRANSPARENT);
        w.setNavigationBarColor(Color.TRANSPARENT);
        w.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS);
        if (Build.VERSION.SDK_INT >= 30) {
            w.setDecorFitsSystemWindows(false);
        } else {
            w.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION);
        }
        if (Build.VERSION.SDK_INT >= 29) w.setNavigationBarContrastEnforced(false);

        kuranArayuz = new KuranArayuz(this);
        kok = new FrameLayout(this);
        kok.setBackgroundColor(0xFF070914);
        sahne = new Sahne(this);
        kok.addView(sahne, new FrameLayout.LayoutParams(-1, -1));

        dikey = new LinearLayout(this);
        dikey.setOrientation(LinearLayout.VERTICAL);
        sayfaKabi = new FrameLayout(this);
        dikey.addView(sayfaKabi, new LinearLayout.LayoutParams(-1, 0, 1f));
        sekmeCubugunuKur();
        dikey.addView(sekmeCubugu);
        kok.addView(dikey, new FrameLayout.LayoutParams(-1, -1));
        setContentView(kok);

        ustBosluk = dp(36);
        kok.setOnApplyWindowInsetsListener((v, ins) -> {
            int ust, alt;
            if (Build.VERSION.SDK_INT >= 30) {
                android.graphics.Insets i = ins.getInsets(android.view.WindowInsets.Type.systemBars());
                ust = i.top;
                alt = i.bottom;
            } else {
                ust = ins.getSystemWindowInsetTop();
                alt = ins.getSystemWindowInsetBottom();
            }
            ustBosluk = ust + dp(12);
            sekmeCubugu.setPadding(dp(10), dp(6), dp(10), alt + dp(8));
            for (ScrollView s : sayfalar) if (s != null) s.setPadding(0, ustBosluk, 0, 0);
            for (View a : altYigin) a.setPadding(0, ustBosluk - dp(6), 0, alt);
            altBosluk = alt;
            return ins;
        });

        kaydirma = new GestureDetector(this, new GestureDetector.SimpleOnGestureListener() {
            @Override
            public boolean onFling(MotionEvent e1, MotionEvent e2, float vx, float vy) {
                if (e1 == null || e2 == null) return false;
                float dx = e2.getX() - e1.getX(), dy = e2.getY() - e1.getY();
                if (Math.abs(dx) > dp(90) && Math.abs(dx) > Math.abs(dy) * 1.8f && Math.abs(vx) > 700) {
                    sekmeyeGec(sekme + (dx < 0 ? 1 : -1));
                    return true;
                }
                return false;
            }
        });

        if (Build.VERSION.SDK_INT >= 33) {
            try {
                getOnBackInvokedDispatcher().registerOnBackInvokedCallback(
                        android.window.OnBackInvokedDispatcher.PRIORITY_DEFAULT,
                        this::geriTusuIsle);
            } catch (Throwable ignored) {
            }
        }

        anaMenu = getIntent() == null
                || getIntent().getBooleanExtra(EK_ANA, false)
                || Intent.ACTION_MAIN.equals(getIntent().getAction());
        sekme = Math.max(0, Math.min(SEKME_SAYISI - 1, Tercihler.sp(this).getInt(SON_SEKME, 0)));
        if (anaMenu) sekme = 0;
        isle(getIntent());

        dikey.setAlpha(0f);
        dikey.setTranslationY(dp(28));
        dikey.animate().alpha(1f).translationY(0).setDuration(650).setStartDelay(120)
                .setInterpolator(new DecelerateInterpolator(2f)).start();
    }

    Sahne sahneRef() {
        return sahne;
    }

    @Override
    public boolean dispatchTouchEvent(MotionEvent ev) {
        if (ev != null && ev.getActionMasked() == MotionEvent.ACTION_DOWN && sahne != null) {
            sahne.dokunusEfekti(ev.getX(), ev.getY());
        }
        if (kaydirma != null && sekme != S_KIBLE && altYigin.isEmpty()) kaydirma.onTouchEvent(ev);
        return super.dispatchTouchEvent(ev);
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        isle(intent);
    }

    private void isle(Intent i) {
        if (i == null) return;
        if (i.getBooleanExtra(EK_YENIDEN_KUR, false)) {
            i.removeExtra(EK_YENIDEN_KUR);
            KonumVeTakvim.otomatikTazele(this);
            KonumVeTakvim.bildirimleriYenile(this, true);
            VakitSayaci.guncelle(this);
            Toast.makeText(this, "Vakit takvimi ve bildirimler yenilendi", Toast.LENGTH_SHORT).show();
            if (sayfalar[0] != null) hepsiniCiz();
        }
        if (i.getBooleanExtra(EK_TEST, false)) {
            i.removeExtra(EK_TEST);
            BildirimKontrol.testPlanla(this);
        }
        if (i.getBooleanExtra(EK_SAYAC, false)) {
            i.removeExtra(EK_SAYAC);
            boolean yeni = !Tercihler.sayacAcik(this);
            Tercihler.sayacAcik(this, yeni);
            VakitSayaci.guncelle(this);
            Toast.makeText(this, yeni ? "Vakit sayacı açıldı" : "Vakit sayacı kapatıldı", Toast.LENGTH_SHORT).show();
        }
        if (i.hasExtra(EK_SEKME)) {
            int s = i.getIntExtra(EK_SEKME, 0);
            i.removeExtra(EK_SEKME);
            if (sayfalar[0] == null) sekme = Math.max(0, Math.min(SEKME_SAYISI - 1, s));
            else sekmeyeGec(s);
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        sahne.canli(true);
        try {
            hepsiniCiz();
        } catch (Throwable t) {
            sayfaKabi.removeAllViews();
            TextView hata = metin("Ekran çizilemedi: " + t, 14, KOTU, false);
            hata.setPadding(dp(20), dp(80), dp(20), 0);
            sayfaKabi.addView(hata);
        }
        handler.removeCallbacks(tik);
        handler.post(tik);
        kuranArayuz.devam();
        BildirimKontrol.kontrolEt(this);
    }

    @Override
    protected void onPause() {
        super.onPause();
        sahne.canli(false);
        handler.removeCallbacks(tik);
        nabizlariDurdur();
        kuranArayuz.durakla();
    }

    @Override
    @SuppressWarnings("deprecation")
    public void onBackPressed() {
        geriTusuIsle();
    }

    void geriTusuIsle() {
        if (!altYigin.isEmpty()) {
            altSayfaKapat();
            return;
        }
        if (sekme != 0) {
            sekmeyeGec(0);
            return;
        }
        moveTaskToBack(true);
    }

    @Override
    public void finish() {
        super.finish();
        overridePendingTransition(android.R.anim.fade_in, android.R.anim.fade_out);
    }

    // ================================================================ sekme çubuğu

    private void sekmeCubugunuKur() {
        sekmeCubugu = new LinearLayout(this);
        sekmeCubugu.setOrientation(LinearLayout.VERTICAL);
        sekmeCubugu.setPadding(dp(10), dp(6), dp(10), dp(14));

        FrameLayout hap = new FrameLayout(this);
        sekmeHap = hap;
        hap.setPadding(dp(4), dp(4), dp(4), dp(4));

        gosterge = new View(this);
        hap.addView(gosterge, new FrameLayout.LayoutParams(0, dp(56)));
        sekmeCubuguStiliUygula();

        LinearLayout satir = new LinearLayout(this);
        satir.setOrientation(LinearLayout.HORIZONTAL);
        for (int i = 0; i < SEKME_SAYISI; i++) {
            LinearLayout hucre = new LinearLayout(this);
            hucre.setOrientation(LinearLayout.VERTICAL);
            hucre.setGravity(Gravity.CENTER);
            Simge s = new Simge(this, SEKME_SIMGE[i]);
            hucre.addView(s, new LinearLayout.LayoutParams(dp(24), dp(24)));
            TextView t = metin(SEKME_ADI[i], 11, SOLUK, true);
            t.setGravity(Gravity.CENTER);
            t.setShadowLayer(0, 0, 0, 0);
            t.setPadding(0, dp(1), 0, 0);
            hucre.addView(t, new LinearLayout.LayoutParams(-2, -2));
            final int n = i;
            hucre.setOnClickListener(v -> sekmeyeGec(n));
            hucre.setContentDescription(SEKME_ADI[i] + " sekmesi");
            sekmeHucre[i] = hucre;
            sekmeYazi[i] = t;
            sekmeSimge[i] = s;
            satir.addView(hucre, new LinearLayout.LayoutParams(0, dp(56), 1f));
        }
        hap.addView(satir, new FrameLayout.LayoutParams(-1, dp(56)));
        hap.addOnLayoutChangeListener((v, l, t, r, bb, ol, ot, or, ob) -> gostergeyiYerlestir(false));
        sekmeCubugu.addView(hap, new LinearLayout.LayoutParams(-1, -2));
    }

    private void sekmeCubuguStiliUygula() {
        TemaMotoru.Durum tm = TemaMotoru.aktif(this);
        if (kok != null) kok.setBackgroundColor(tm.zemin);
        if (sahne != null) sahne.invalidate();
        if (sekmeHap != null) {
            GradientDrawable arka = new GradientDrawable();
            arka.setColor(tm.acik ? 0xEBFFFFFF : 0xB80A0D20);
            arka.setStroke(1, tm.camKenar);
            arka.setCornerRadius(dp(30));
            sekmeHap.setBackground(arka);
        }
        if (gosterge != null) {
            gosterge.setBackground(tm.birincilDugme(this, 24));
        }
        try {
            if (Build.VERSION.SDK_INT >= 30 && getWindow() != null && getWindow().getInsetsController() != null) {
                int maske = android.view.WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS
                        | android.view.WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS;
                getWindow().getInsetsController().setSystemBarsAppearance(tm.acik ? maske : 0, maske);
            }
        } catch (Throwable ignored) {
        }
    }

    private void gostergeyiYerlestir(boolean canli) {
        View hucre = sekmeHucre[sekme];
        if (hucre == null || hucre.getWidth() == 0) return;
        TemaMotoru.Durum tm = TemaMotoru.aktif(this);
        ViewGroup.LayoutParams lp = gosterge.getLayoutParams();
        if (lp.width != hucre.getWidth()) {
            lp.width = hucre.getWidth();
            gosterge.setLayoutParams(lp);
        }
        float hedef = hucre.getLeft();
        if (canli) {
            gosterge.animate().translationX(hedef).setDuration(420).setInterpolator(new OvershootInterpolator(1.1f)).start();
        } else {
            gosterge.setTranslationX(hedef);
        }
        for (int i = 0; i < SEKME_SAYISI; i++) {
            final int hedefRenk = i == sekme ? tm.birincilDugmeYaziRengi() : tm.soluk;
            final TextView t = sekmeYazi[i];
            final Simge s = sekmeSimge[i];
            float olcek = i == sekme ? 1.08f : 1f;
            if (canli) {
                ValueAnimator a = ValueAnimator.ofObject(new ArgbEvaluator(), t.getCurrentTextColor(), hedefRenk);
                a.setDuration(300);
                a.addUpdateListener(x -> {
                    int r = (int) x.getAnimatedValue();
                    t.setTextColor(r);
                    s.renk(r);
                });
                a.start();
                sekmeHucre[i].animate().scaleX(olcek).scaleY(olcek).setDuration(300).start();
                if (i == sekme) {
                    s.animate().rotationBy(360).setDuration(600).setInterpolator(new DecelerateInterpolator(2f)).start();
                }
            } else {
                t.setTextColor(hedefRenk);
                s.renk(hedefRenk);
                sekmeHucre[i].setScaleX(olcek);
                sekmeHucre[i].setScaleY(olcek);
            }
        }
    }

    void sekmeyeGec(int yeni) {
        if (yeni < 0 || yeni >= SEKME_SAYISI || yeni == sekme || sayfalar[yeni] == null) return;
        final int eski = sekme;
        sekme = yeni;
        Tercihler.sp(this).edit().putInt(SON_SEKME, yeni).apply();
        sekmeCubugu.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK);
        gostergeyiYerlestir(true);
        arkaPlaniSec();

        final ScrollView cikan = sayfalar[eski];
        final ScrollView giren = sayfalar[yeni];
        float yon = yeni > eski ? 1f : -1f;
        float mesafe = dp(70);
        cikan.animate().cancel();
        cikan.animate().alpha(0f).translationX(-yon * mesafe).setDuration(220)
                .withEndAction(() -> {
                    cikan.setVisibility(View.GONE);
                    cikan.setTranslationX(0);
                }).start();
        giren.animate().cancel();
        giren.setVisibility(View.VISIBLE);
        giren.setAlpha(0f);
        giren.setTranslationX(yon * mesafe);
        giren.animate().alpha(1f).translationX(0).setStartDelay(90).setDuration(380)
                .setInterpolator(new DecelerateInterpolator(2f)).start();
        sirayla((ViewGroup) giren.getChildAt(0), 120);
    }

    int sekme() {
        return sekme;
    }

    private void arkaPlaniSec() {
        if (!altYigin.isEmpty()) {
            sahne.goster(altArka.get(altArka.size() - 1));
            return;
        }
        switch (sekme) {
            case S_KURAN: sahne.goster("kuran_bg"); break;
            case S_KIBLE: sahne.goster("kible_bg"); break;
            case S_ZIKIR: sahne.goster("zikir_bg"); break;
            case S_MENU: sahne.goster("mihrap"); break;
            default: {
                VakitTakvimi.An s = VakitTakvimi.oku(this).simdiki();
                sahne.vakit(Sahne.vakitNo(s == null ? "isha" : s.namaz));
            }
        }
    }

    private void hepsiniCiz() {
        nabizlariDurdur();
        sekmeCubuguStiliUygula();
        sayfaKabi.removeAllViews();
        VakitTakvimi.Takvim takvim = VakitTakvimi.oku(this);
        List<Vakit> kurulu = VakitDeposu.gelecek(this);
        sayfalar[0] = sayfa(vakitlerSayfasi(takvim, kurulu));
        sayfalar[S_KURAN] = sayfa(kuranArayuz.sekme());
        sayfalar[S_KIBLE] = sayfa(kibleSayfasi(takvim));
        sayfalar[S_ZIKIR] = sayfa(zikirSayfasi());
        sayfalar[S_MENU] = sayfa(menuSayfasi(kurulu));
        for (int i = 0; i < SEKME_SAYISI; i++) {
            sayfalar[i].setVisibility(i == sekme ? View.VISIBLE : View.GONE);
            sayfaKabi.addView(sayfalar[i], new FrameLayout.LayoutParams(-1, -1));
        }
        arkaPlaniSec();
        gostergeyiYerlestir(false);
        sirayla((ViewGroup) sayfalar[sekme].getChildAt(0), 200);
    }

    ScrollView sayfa(LinearLayout icerik) {
        ScrollView s = new ScrollView(this);
        s.setVerticalScrollBarEnabled(false);
        s.setOverScrollMode(View.OVER_SCROLL_NEVER);
        s.setClipToPadding(false);
        s.setPadding(0, ustBosluk, 0, 0);
        if (Build.VERSION.SDK_INT >= 23) {
            s.setOnScrollChangeListener((v, x, y, ox, oy) -> {
                if (sahne != null) sahne.kaydirmaOfseti(y);
            });
        }
        s.addView(icerik);
        return s;
    }

    LinearLayout sutun() {
        LinearLayout l = new LinearLayout(this);
        l.setOrientation(LinearLayout.VERTICAL);
        l.setPadding(dp(18), 0, dp(18), dp(24));
        return l;
    }

    void sirayla(ViewGroup g, long gecikme) {
        if (g == null) return;
        for (int i = 0; i < g.getChildCount(); i++) {
            View v = g.getChildAt(i);
            v.setAlpha(0f);
            v.setTranslationY(dp(22));
            v.animate().alpha(1f).translationY(0).setStartDelay(gecikme + i * 60L).setDuration(460)
                    .setInterpolator(new DecelerateInterpolator(2f)).start();
        }
    }

    private void nabizlariDurdur() {
        for (ValueAnimator a : nabizlar) a.cancel();
        nabizlar.clear();
    }

    void sayfaBasligi(LinearLayout s, String baslik, String alt) {
        TextView b = metin(baslik, 28, BEYAZ, true);
        b.setTypeface(TemaMotoru.baslikTipi(this), Typeface.BOLD);
        s.addView(b);
        if (alt != null) s.addView(metin(alt, 14, SOLUK, false));
        bosluk(s, 14);
    }

    // ================================================================ alt sayfalar

    /**
     * Sekmelerin üstünde, sağdan kayarak açılan alt sayfa: üstte "‹" ve başlık, altta içerik.
     * Geri tuşu ya da "‹" kapatır; arka plan sahnesi bu sayfanınkine geçer.
     */
    void altSayfa(String baslik, View icerik, String arka, View... sagEylem) {
        LinearLayout sayfa = new LinearLayout(this);
        sayfa.setOrientation(LinearLayout.VERTICAL);
        sayfa.setClickable(true);
        sayfa.setPadding(0, ustBosluk - dp(6), 0, altBosluk);
        LinearLayout ust = new LinearLayout(this);
        ust.setGravity(Gravity.CENTER_VERTICAL);
        ust.setPadding(dp(8), 0, dp(12), dp(6));
        TextView geri = metin("‹", 34, BEYAZ, false);
        geri.setPadding(dp(10), 0, dp(14), dp(4));
        geri.setContentDescription("Geri");
        geri.setOnClickListener(v -> {
            v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            altSayfaKapat();
        });
        ust.addView(geri);
        TextView b = metin(baslik, 22, BEYAZ, true);
        b.setTypeface(TemaMotoru.baslikTipi(this), Typeface.BOLD);
        b.setSingleLine(true);
        b.setEllipsize(android.text.TextUtils.TruncateAt.END);
        ust.addView(b, new LinearLayout.LayoutParams(0, -2, 1f));
        for (View v : sagEylem) ust.addView(v);
        sayfa.addView(ust);
        sayfa.addView(icerik, new LinearLayout.LayoutParams(-1, 0, 1f));

        final View onceki = altYigin.isEmpty() ? dikey : altYigin.get(altYigin.size() - 1);
        altYigin.add(sayfa);
        altArka.add(arka);
        kok.addView(sayfa, new FrameLayout.LayoutParams(-1, -1));
        sahne.goster(arka);
        int gen = Math.max(kok.getWidth(), dp(360));
        sayfa.setTranslationX(gen);
        sayfa.animate().translationX(0).setDuration(380).setInterpolator(new DecelerateInterpolator(2.2f)).start();
        onceki.animate().alpha(0f).translationX(-dp(60)).setDuration(300)
                .withEndAction(() -> onceki.setVisibility(View.INVISIBLE)).start();
        if (icerik instanceof ViewGroup && !(icerik instanceof android.widget.AdapterView)) {
            View ic = icerik instanceof ScrollView ? ((ScrollView) icerik).getChildAt(0) : icerik;
            if (ic instanceof ViewGroup) sirayla((ViewGroup) ic, 180);
        }
    }

    void altSayfaKapat() {
        if (altYigin.isEmpty()) return;
        final View ust = altYigin.remove(altYigin.size() - 1);
        altArka.remove(altArka.size() - 1);
        final View alt = altYigin.isEmpty() ? dikey : altYigin.get(altYigin.size() - 1);
        alt.setVisibility(View.VISIBLE);
        alt.animate().cancel();
        alt.animate().alpha(1f).translationX(0).setDuration(320).setInterpolator(new DecelerateInterpolator(2f)).start();
        ust.animate().translationX(kok.getWidth()).setDuration(300).withEndAction(() -> kok.removeView(ust)).start();
        arkaPlaniSec();
        kuranArayuz.altSayfaKapandi(ust);
    }

    int altSayfaSayisi() {
        return altYigin.size();
    }

    /** Uygulamayı denetle: veri, yazı tipi, ses, ağ, servis, son hata; kopyalanabilir rapor. */
    void denetimAc() {
        final LinearLayout s = sutun();
        s.addView(metin("Uygulamanın bölümlerinin telefonunda çalışıp çalışmadığını denetler. Sonucu kopyalayıp "
                + "Claude'a yapıştırabilirsiniz.", 14, SOLUK, false));
        bosluk(s, 8);
        final LinearLayout k = cam();
        final TextView bekle = metin("Denetleniyor… (internet denetimi birkaç saniye sürebilir)", 15, BEYAZ, true);
        k.addView(bekle);
        s.addView(k);
        final LinearLayout eylem = new LinearLayout(this);
        s.addView(eylem);
        ScrollView sv = sayfa(s);
        sv.setPadding(0, 0, 0, 0);
        altSayfa("Uygulamayı denetle", sv, "mihrap");
        new Thread(() -> {
            final List<Denetim.Sonuc> l;
            final String rapor;
            try {
                l = Denetim.calistir(this);
                rapor = Denetim.rapor(this, l) + "\n" + rapor(VakitDeposu.gelecek(this));
            } catch (Throwable t) {
                // Denetimdeki beklenmedik bir hata arka plan iş parçacığında uygulamayı çökertmesin
                Hata.kaydet(this, "Denetim", t);
                runOnUiThread(() -> {
                    if (isFinishing() || isDestroyed()) return;
                    bekle.setText("Denetim tamamlanamadı: " + t);
                    bekle.setTextColor(KOTU);
                });
                return;
            }
            if (isFinishing() || isDestroyed()) return;
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed()) return;
                k.removeAllViews();
                int sorun = 0;
                for (Denetim.Sonuc x : l) {
                    if (x.seviye < 0) sorun++;
                    String ayrinti = x.ayrinti.length() > 600 ? x.ayrinti.substring(0, 600) + "…" : x.ayrinti;
                    satir(k, x.seviye, x.ad, ayrinti, null, null);
                }
                k.addView(metin(sorun == 0 ? "Sorun bulunmadı." : sorun + " sorun bulundu.", 15, sorun == 0 ? IYI : KOTU, true), 0);
                eylem.addView(dugme("Raporu kopyala", true, v -> {
                    android.content.ClipboardManager cm = (android.content.ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
                    if (cm != null) cm.setPrimaryClip(android.content.ClipData.newPlainText("Secde Vakti denetim", rapor));
                    Toast.makeText(this, "Rapor kopyalandı; Claude'a yapıştırın", Toast.LENGTH_LONG).show();
                }), yarim(true));
                eylem.addView(dugme("Paylaş", false, v -> {
                    try {
                        startActivity(Intent.createChooser(new Intent(Intent.ACTION_SEND).setType("text/plain")
                                .putExtra(Intent.EXTRA_TEXT, rapor), "Raporu paylaş"));
                    } catch (Throwable ignored) {
                    }
                }), yarim(false));
                if (Hata.son(this) != null) {
                    s.addView(dugme("Hata kaydını sil", false, v -> {
                        Hata.temizle(this);
                        Toast.makeText(this, "Hata kaydı silindi", Toast.LENGTH_SHORT).show();
                    }));
                }
            });
        }, "secde-denetim").start();
    }

    void takvimAc() {
        guvenli("takvim", this::takvimAcIc);
    }

    private void takvimAcIc() {
        ScrollView s = sayfa(takvimSayfasi(VakitTakvimi.oku(this), VakitDeposu.gelecek(this)));
        s.setPadding(0, 0, 0, 0);
        altSayfa("Takvim", s, "kandil");
    }

    /** Bir bölümü açarken hata olursa uygulama kapanmaz: hata kaydedilir, kullanıcıya söylenir. */
    void guvenli(String yer, Runnable r) {
        try {
            r.run();
        } catch (Throwable t) {
            Hata.kaydet(this, yer, t);
            Toast.makeText(this, "Açılamadı: " + t.getClass().getSimpleName()
                    + ". Menü › Uygulamayı denetle ile raporu alın.", Toast.LENGTH_LONG).show();
        }
    }

    /** Menü ve hızlı erişim butonlarının hedefleri. */
    void bolumAc(String ad) {
        guvenli("bolumAc " + ad, () -> bolumAcIc(ad));
    }

    private void bolumAcIc(String ad) {
        switch (ad) {
            case "kuran": sekmeyeGec(S_KURAN); break;
            case "kible": sekmeyeGec(S_KIBLE); break;
            case "zikir": sekmeyeGec(S_ZIKIR); break;
            case "takvim": takvimAc(); break;
            case "elifba": kuranArayuz.elifBaAc(); break;
            case "dualar": kuranArayuz.dualarAc(); break;
            case "esma": kuranArayuz.esmaAc(); break;
            case "meal": kuranArayuz.sesliMealAc(); break;
            case "imler": kuranArayuz.yerImleriAc(); break;
            case "denetim": denetimAc(); break;
            case "tema": TemaGalerisi.sayfaAc(this, this::hepsiniCiz); break;
            case "huzur": HuzurModu.sayfaAc(this); break;
            case "paylas": PaylasimKarti.sayfaAc(this, VakitTakvimi.oku(this)); break;
            case "kerahet": Kerahet.sayfaAc(this, VakitTakvimi.oku(this)); break;
            case "namaz_takip": NamazTakip.sayfaAc(this); break;
            case "kaza": KazaTakip.sayfaAc(this, false); break;
            case "oruc": KazaTakip.sayfaAc(this, true); break;
            case "imsakiye": RamazanModu.imsakiyeAc(this, VakitTakvimi.oku(this)); break;
            case "tesbihat": TesbihatRehberi.sayfaAc(this); break;
            case "hatim": HatimTakip.sayfaAc(this); break;
            case "ezan_studyo": EzanStudyo.sayfaAc(this); break;
            case "camiler": CamilerSayfasi.sayfaAc(this, VakitTakvimi.oku(this)); break;
            case "hicri": HicriTakvim.sayfaAc(this, VakitTakvimi.oku(this)); break;
            case "konum": KonumVeTakvim.sayfaAc(this, this::hepsiniCiz); break;
            case "manevi": {
                final VakitTakvimi.Takvim tk = VakitTakvimi.oku(this);
                ManeviPaket.sayfaAc(this, tk, (ar, tr, kay) ->
                        PaylasimKarti.ozelMetinleAc(this, tk, PaylasimKarti.SABLON_HADIS_DUA, ar, tr, kay));
                break;
            }
            default: sekmeyeGec(S_VAKIT); break;
        }
    }

    // ================================================================ 0 · Vakitler

    private TextView ustEylemHapi(TemaMotoru.Durum tm, String yazi, String aciklama, Runnable eylem) {
        TextView h = metin(yazi, 11, tm.vurgu, true);
        h.setShadowLayer(0, 0, 0, 0);
        h.setPadding(dp(9), dp(6), dp(9), dp(6));
        h.setBackground(tm.ikincilDugme(this, 16));
        h.setContentDescription(aciklama);
        h.setClickable(true);
        basmaEfekti(h);
        h.setOnClickListener(v -> {
            v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            eylem.run();
        });
        return h;
    }

    private LinearLayout vakitlerSayfasi(final VakitTakvimi.Takvim t, List<Vakit> kurulu) {
        final TemaMotoru.Durum tm = TemaMotoru.aktif(this);
        LinearLayout s = sutun();
        long simdiMs = System.currentTimeMillis();
        String hicriMetin = t.hicri != null ? t.hicri : t.bugunHicri();
        if (hicriMetin == null) {
            Calendar hc = Calendar.getInstance();
            int[] hd = HicriTakvim.miladidenHicriye(hc.get(Calendar.YEAR), hc.get(Calendar.MONTH) + 1, hc.get(Calendar.DAY_OF_MONTH));
            hicriMetin = hd[2] + " " + HicriTakvim.hicriAyAdi(hd[1]) + " " + hd[0];
        }
        String alt = Metinler.tarih(simdiMs) + "  ·  " + hicriMetin;

        LinearLayout ustSatir = new LinearLayout(this);
        ustSatir.setGravity(Gravity.CENTER_VERTICAL);
        TextView yerBaslik = metin((t.yer != null ? t.yer : "Secde Vakti") + " ▾", 24, BEYAZ, true);
        yerBaslik.setTypeface(TemaMotoru.baslikTipi(this), Typeface.BOLD);
        yerBaslik.setSingleLine(true);
        yerBaslik.setEllipsize(TextUtils.TruncateAt.END);
        yerBaslik.setContentDescription("Konum ve şehir seçimi");
        yerBaslik.setClickable(true);
        basmaEfekti(yerBaslik);
        yerBaslik.setOnClickListener(v -> {
            v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            bolumAc("konum");
        });
        ustSatir.addView(yerBaslik, new LinearLayout.LayoutParams(0, -2, 1f));

        LinearLayout sagHizli = new LinearLayout(this);
        sagHizli.setGravity(Gravity.CENTER_VERTICAL);
        TextView huzurHap = ustEylemHapi(tm, "☽ Huzur", "Huzur ve Tefekkür Modu", () -> bolumAc("huzur"));
        TextView temaHap = ustEylemHapi(tm, "🎨 Tema", "Tema Stüdyosu", () -> bolumAc("tema"));
        TextView kartHap = ustEylemHapi(tm, "✦ Kart", "Paylaşım Kartı", () -> bolumAc("paylas"));
        LinearLayout.LayoutParams hlp = new LinearLayout.LayoutParams(-2, -2);
        hlp.setMargins(0, 0, dp(4), 0);
        LinearLayout.LayoutParams klp = new LinearLayout.LayoutParams(-2, -2);
        klp.setMargins(dp(4), 0, 0, 0);
        sagHizli.addView(huzurHap, hlp);
        sagHizli.addView(temaHap);
        sagHizli.addView(kartHap, klp);
        ustSatir.addView(sagHizli);
        s.addView(ustSatir);

        TextView tarihAlt = metin(alt, 13, SOLUK, false);
        tarihAlt.setOnClickListener(v -> bolumAc("hicri"));
        s.addView(tarihAlt);
        bosluk(s, 10);

        HesapMotoru.Metot aktifMetot = HesapMotoru.aktifMetot(this);
        boolean asriSani = HesapMotoru.asriSani(this);
        boolean ozelHesap = !"diyanet".equals(aktifMetot.kod) || asriSani;

        List<VakitTakvimi.An> bugun;
        VakitTakvimi.An siradaki = null;
        VakitTakvimi.An simdiki = null;
        if (ozelHesap && (!t.bugun().isEmpty() || !Double.isNaN(t.enlem))) {
            bugun = HesapMotoru.gun(this, t, simdiMs).liste();
            List<VakitTakvimi.An> dun = HesapMotoru.gun(this, t, simdiMs - 86_400_000L).liste();
            List<VakitTakvimi.An> yarin = HesapMotoru.gun(this, t, simdiMs + 86_400_000L).liste();
            List<VakitTakvimi.An> pencere = new ArrayList<>(18);
            pencere.addAll(dun);
            pencere.addAll(bugun);
            pencere.addAll(yarin);
            for (VakitTakvimi.An an : pencere) {
                if (an.zaman <= simdiMs) simdiki = an;
                else if (siradaki == null) { siradaki = an; break; }
            }
        } else {
            bugun = t.bugun();
            siradaki = t.sonraki();
            simdiki = t.simdiki();
        }

        String ad = null;
        siradakiZaman = 0;
        if (siradaki != null) {
            ad = siradaki.ad();
            siradakiZaman = siradaki.zaman;
        } else {
            for (Vakit v : kurulu) if (v.vakitBildirimi()) { ad = v.kisaAd(); siradakiZaman = v.zaman; break; }
        }
        oncekiZaman = simdiki != null ? simdiki.zaman : siradakiZaman - 6 * 3600_000L;

        FrameLayout halkaKabi = new FrameLayout(this);
        halka = new Halka(this);
        Kerahet.Pencere aktifKerahet = (!bugun.isEmpty() || !Double.isNaN(t.enlem)) ? Kerahet.aktifKerahet(this, t) : null;
        if (aktifKerahet != null) {
            halka.renkler(tm.uyari, 0xFFFFE4A8);
        } else {
            halka.renkler(tm.vurgu, TemaMotoru.karistir(tm.vurgu, Color.WHITE, 0.42f));
        }
        halka.izRengi(tm.acik ? 0x2414211C : 0x33FFFFFF);
        int boy = dp(262);
        halkaKabi.addView(halka, new FrameLayout.LayoutParams(boy, boy, Gravity.CENTER));
        LinearLayout orta = new LinearLayout(this);
        orta.setOrientation(LinearLayout.VERTICAL);
        orta.setGravity(Gravity.CENTER);
        sayacMetni = null;
        if (siradakiZaman == 0) {
            orta.addView(ortala(metin("Vakit bilgisi yok", 20, BEYAZ, true)));
            orta.addView(ortala(metin("Uygulamayı açınca yüklenir", 13, SOLUK, false)));
        } else {
            orta.addView(ortala(metin("SIRADAKİ", 12, ALTIN, true)));
            orta.addView(ortala(metin(ad, 30, BEYAZ, true)));
            sayacMetni = ortala(metin("", 38, BEYAZ, false));
            sayacMetni.setTypeface(Typeface.create("sans-serif-light", Typeface.NORMAL));
            sayacMetni.setFontFeatureSettings("tnum");
            sayacMetni.setLetterSpacing(0.03f);
            orta.addView(sayacMetni);
            TextView hedefSaat = ortala(metin(Metinler.saat(siradakiZaman), 15, SOLUK, true));
            hedefSaat.setFontFeatureSettings("tnum");
            orta.addView(hedefSaat);
        }
        halkaKabi.addView(orta, new FrameLayout.LayoutParams(-2, -2, Gravity.CENTER));
        s.addView(halkaKabi, new LinearLayout.LayoutParams(-1, boy));
        if (siradakiZaman > 0) {
            halka.oran(oran(), true);
            halka.setScaleX(0.85f);
            halka.setScaleY(0.85f);
            halka.animate().scaleX(1f).scaleY(1f).setDuration(900).setInterpolator(new OvershootInterpolator(1.4f)).start();
        }
        sayaciGuncelle();
        bosluk(s, 10);

        gokYorunge = null;
        if (!bugun.isEmpty()) {
            s.addView(Kerahet.ozetSerit(this, t));
            bosluk(s, 10);

            if (bugun.size() >= 6) {
                LinearLayout yorungeKart = cam();
                yorungeKart.setPadding(dp(12), dp(10), dp(12), dp(10));
                gokYorunge = new GokYorungeView(this, tm, bugun);
                yorungeKart.addView(gokYorunge, new LinearLayout.LayoutParams(-1, dp(96)));
                s.addView(yorungeKart);
            }
        } else if (!Double.isNaN(t.enlem)) {
            s.addView(Kerahet.ozetSerit(this, t));
            bosluk(s, 10);
        }

        if (RamazanModu.anaEkrandaGoster(this, t)) {
            s.addView(RamazanModu.anaKart(this, t));
        }

        if (!bugun.isEmpty()) {
            LinearLayout k = cam();
            if (ozelHesap) {
                TextView metotBilgi = metin("✦ " + aktifMetot.ad + (asriSani ? " · Asr-ı Sânî (Hanefî)" : ""), 11, ALTIN, true);
                metotBilgi.setPadding(dp(14), 0, dp(14), dp(6));
                metotBilgi.setOnClickListener(v -> bolumAc("tema"));
                k.addView(metotBilgi);
            }
            long simdi = System.currentTimeMillis();
            for (VakitTakvimi.An a : bugun) {
                boolean etkin = simdiki != null && simdiki.zaman == a.zaman;
                boolean gecti = a.zaman <= simdi && !etkin;
                LinearLayout r = new LinearLayout(this);
                r.setGravity(Gravity.CENTER_VERTICAL);
                r.setPadding(dp(14), dp(12), dp(14), dp(12));
                int renk = etkin ? KOYU : gecti ? SILIK : BEYAZ;
                r.addView(metin(a.ad(), 17, renk, etkin), new LinearLayout.LayoutParams(0, -2, 1f));
                if (etkin) {
                    TextView rozet = metin("şimdi", 12, KOYU, true);
                    rozet.setShadowLayer(0, 0, 0, 0);
                    rozet.setPadding(0, 0, dp(10), 0);
                    r.addView(rozet);
                }
                TextView saatTv = metin(Metinler.saat(a.zaman), 17, renk, true);
                saatTv.setFontFeatureSettings("tnum");
                r.addView(saatTv);
                if (etkin) nabiz(r);
                k.addView(r);
            }
            s.addView(k);
        }

        s.addView(NamazTakip.anaKart(this));
        s.addView(anaEkranHizliCetele(tm));

        // Resimli hızlı erişim
        int namazTam = NamazTakip.bugunTamamlanan(this);
        int hatimCuz = HatimTakip.tamamlananCuzSayisi(this);
        int zikirGun = new Zikir(this).gunluk();

        s.addView(altBaslik("Hızlı erişim"));
        HorizontalScrollView yatay = new HorizontalScrollView(this);
        yatay.setHorizontalScrollBarEnabled(false);
        yatay.setOverScrollMode(View.OVER_SCROLL_NEVER);
        yatay.setClipToPadding(false);
        LinearLayout sira = new LinearLayout(this);
        sira.setOrientation(LinearLayout.HORIZONTAL);
        sira.addView(kutucuk("k_huzur", "Huzur & Tefekkür", "Nefes hâlesi · gece", 0xFF15385A, () -> bolumAc("huzur")).rozet("Yeni"), kutucukDuzeni(150, 150, true));
        sira.addView(kutucuk("mihrap", "Tema Stüdyosu", "16 tema · arka planlar", 0xFF1B5A45, () -> bolumAc("tema")), kutucukDuzeni(150, 150, false));
        sira.addView(kutucuk("k_namaz_takip", "Namaz Takibi", "Seri · ısı haritası", 0xFF285C48, () -> bolumAc("namaz_takip")).rozet(namazTam + "/5"), kutucukDuzeni(150, 150, false));
        sira.addView(kutucuk("k_kuran", "Kur'an-ı Kerim", "Meal · tilavet", 0xFF6A3A12, () -> sekmeyeGec(S_KURAN)), kutucukDuzeni(150, 150, false));
        sira.addView(kutucuk("k_kabe", "Kıble", "Pusula", 0xFF7A4A10, () -> sekmeyeGec(S_KIBLE)), kutucukDuzeni(150, 150, false));
        sira.addView(kutucuk("k_tesbih", "Zikirmatik", "3D tesbih · sayaç", 0xFF1E5A3A, () -> sekmeyeGec(S_ZIKIR)).rozet(zikirGun > 0 ? String.valueOf(zikirGun) : null), kutucukDuzeni(150, 150, false));
        sira.addView(kutucuk("k_hatim", "Hatim Takibi", "30 cüz · sesli meal", 0xFF1E5A4A, () -> bolumAc("hatim")).rozet(hatimCuz + "/30"), kutucukDuzeni(150, 150, false));
        sira.addView(kutucuk("k_iftar", "Kazâ & Oruç", "Borç · oruç defteri", 0xFF6A3A12, () -> bolumAc("kaza")), kutucukDuzeni(150, 150, false));
        sira.addView(kutucuk("k_ramazan", "İmsakiye", "30 gün · iftar", 0xFF78521D, () -> bolumAc("imsakiye")), kutucukDuzeni(150, 150, false));
        sira.addView(kutucuk("k_cami_radar", "Camiler", "Radar · cuma", 0xFF164C7E, () -> bolumAc("camiler")), kutucukDuzeni(150, 150, false));
        sira.addView(kutucuk("k_tesbihat", "Tesbihat", "5 vakit · sesli", 0xFF1E5A3A, () -> bolumAc("tesbihat")), kutucukDuzeni(150, 150, false));
        sira.addView(kutucuk("k_ezan", "Ezan & Sûre", "Çevrimdışı ses", 0xFF445933, () -> bolumAc("ezan_studyo")), kutucukDuzeni(150, 150, false));
        sira.addView(kutucuk("k_kerahet", "Kerâhet & Nâfile", "İşrâk · teheccüd", 0xFF5A4218, () -> bolumAc("kerahet")), kutucukDuzeni(150, 150, false));
        sira.addView(kutucuk("k_hilal", "Takvim", "Aylık vakitler", 0xFF3A2A6A, this::takvimAc), kutucukDuzeni(150, 150, false));
        sira.addView(kutucuk("elifba_bg", "Elif-Ba", "Harfler · test", 0xFF1A4A7A, kuranArayuz::elifBaAc), kutucukDuzeni(150, 150, false));
        sira.addView(kutucuk("k_dua", "Dualar", "Günlük dualar", 0xFF8A3A3A, kuranArayuz::dualarAc), kutucukDuzeni(150, 150, false));
        sira.addView(kutucuk("k_cini", "Kart Paylaş", "Sosyal kartlar", 0xFF72304D, () -> bolumAc("paylas")), kutucukDuzeni(150, 150, false));
        yatay.addView(sira);
        s.addView(yatay, new LinearLayout.LayoutParams(-1, -2));
        bosluk(s, 12);

        // Vakte özel manevî paket kartı
        s.addView(ManeviPaket.vakitPaketiKarti(this, t, (ar, tr, kay) ->
                PaylasimKarti.ozelMetinleAc(this, t, PaylasimKarti.SABLON_HADIS_DUA, ar, tr, kay)));

        // Günün ayeti ve yaklaşan mübarek gün (uygulamanın kurduğu bildirimlerden)
        final Vakit ayet = ilk(kurulu, "verse");
        if (ayet != null && !ayet.metin.isEmpty()) {
            LinearLayout k = cam();
            LinearLayout ust = new LinearLayout(this);
            ust.setGravity(Gravity.CENTER_VERTICAL);
            ust.addView(metin("GÜNÜN AYETİ", 12, ALTIN, true), new LinearLayout.LayoutParams(0, -2, 1f));
            ust.addView(metin("Kart Paylaş ›", 12, ALTIN, true));
            k.addView(ust);
            k.addView(metin(ayet.metin, 16, BEYAZ, false));
            k.setClickable(true);
            basmaEfekti(k);
            k.setOnClickListener(v -> PaylasimKarti.ozelMetinleAc(this, t, PaylasimKarti.SABLON_AYET,
                    null, ayet.metin, "Günün Âyeti"));
            s.addView(k);
        }
        Vakit mubarek = ilk(kurulu, "holy");
        if (mubarek != null) {
            LinearLayout k = cam();
            k.setOrientation(LinearLayout.HORIZONTAL);
            k.setGravity(Gravity.CENTER_VERTICAL);
            LinearLayout y = new LinearLayout(this);
            y.setOrientation(LinearLayout.VERTICAL);
            y.addView(metin("YAKLAŞAN MÜBAREK GÜN", 12, ALTIN, true));
            y.addView(metin(mubarek.baslik.isEmpty() ? "Mübarek gün" : mubarek.baslik, 16, BEYAZ, true));
            y.addView(metin(Metinler.gunVeSaat(mubarek.zaman) + "  ·  Tüm Dini Günler ›", 13, SOLUK, false));
            k.addView(y, new LinearLayout.LayoutParams(0, -2, 1f));
            long gun = Math.max(0, (mubarek.zaman - System.currentTimeMillis()) / 86_400_000L);
            TextView kalan = metin(gun == 0 ? "bugün" : gun + " gün", 18, ALTIN, true);
            k.addView(kalan);
            k.setClickable(true);
            basmaEfekti(k);
            k.setOnClickListener(v -> HicriTakvim.sayfaAc(this, t));
            s.addView(k);
        }

        s.addView(durumHapi(kurulu));

        LinearLayout k = cam();
        anahtar(k, "Vakit sayacı", "Bildirim alanında geri sayım", Tercihler.sayacAcik(this), acik -> {
            Tercihler.sayacAcik(this, acik);
            VakitSayaci.guncelle(this);
        });
        anahtar(k, "Vakitte titreşime al", SessizMod.sure(this) + " dk · Güneş hariç", SessizMod.acik(this),
                acik -> SessizMod.ayarla(this, acik, SessizMod.sure(this)));
        anahtar(k, "Sahur ve İftar sayacı", "Ana ekranda iftar ve sahur geri sayım kartını her zaman göster",
                RamazanModu.herZamanGoster(this), acik -> {
                    RamazanModu.herZamanGosterSec(this, acik);
                    hepsiniCiz();
                });
        s.addView(k);
        s.addView(dugme("Uygulamanın tüm bölümleri", true, v -> uygulamayiAc(false)));
        return s;
    }

    private static Vakit ilk(List<Vakit> l, String tur) {
        for (Vakit v : l) if (tur.equals(v.tur)) return v;
        return null;
    }

    private void nabiz(View r) {
        final GradientDrawable g = TemaMotoru.aktif(this).birincilDugme(this, 14);
        r.setBackground(g);
        ValueAnimator a = ValueAnimator.ofFloat(0.82f, 1f);
        a.setDuration(1400);
        a.setRepeatMode(ValueAnimator.REVERSE);
        a.setRepeatCount(ValueAnimator.INFINITE);
        a.addUpdateListener(x -> {
            float f = (float) x.getAnimatedValue();
            g.setAlpha((int) (255 * f));
            r.setScaleX(0.985f + 0.015f * f);
            r.setScaleY(0.985f + 0.015f * f);
        });
        a.start();
        nabizlar.add(a);
    }

    private float oran() {
        long toplam = siradakiZaman - oncekiZaman;
        if (toplam <= 0) return 0f;
        return (System.currentTimeMillis() - oncekiZaman) / (float) toplam;
    }

    private LinearLayout anaEkranHizliCetele(final TemaMotoru.Durum tm) {
        final LinearLayout kart = cam();
        final String gunKey = NamazTakip.bugunKey();

        LinearLayout ust = new LinearLayout(this);
        ust.setGravity(Gravity.CENTER_VERTICAL);
        final TextView ozetBaslik = metin("", 12, ALTIN, true);
        ust.addView(ozetBaslik, new LinearLayout.LayoutParams(0, -2, 1f));
        TextView detayLink = metin("Takip ›", 12, ALTIN, true);
        detayLink.setOnClickListener(v -> bolumAc("namaz_takip"));
        ust.addView(detayLink);
        kart.addView(ust);
        bosluk(kart, 6);

        final LinearLayout ceteleSatiri = new LinearLayout(this);
        ceteleSatiri.setOrientation(LinearLayout.HORIZONTAL);
        final TextView[] haplar = new TextView[5];
        final Runnable yenile = () -> {
            int eda = NamazTakip.bugunTamamlanan(this);
            int zikir = new Zikir(this).gunluk();
            int cuz = HatimTakip.tamamlananCuzSayisi(this);
            ozetBaslik.setText("GÜNÜN İBADET ÖZETİ  ·  " + eda + "/5 Namaz  ·  " + zikir + " Zikir  ·  " + cuz + "/30 Cüz");
            for (int i = 0; i < 5; i++) {
                int st = NamazTakip.durum(this, gunKey, i);
                boolean kilindi = st == NamazTakip.EDA || st == NamazTakip.CEMAAT || st == NamazTakip.MAZERET;
                boolean cemaat = st == NamazTakip.CEMAAT;
                haplar[i].setText((kilindi ? (cemaat ? "★ " : "✓ ") : "") + NamazTakip.VAKIT_ADLARI[i]);
                haplar[i].setTextColor(kilindi ? tm.birincilDugmeYaziRengi() : tm.metin);
                haplar[i].setBackground(tm.cipArkaPlani(this, kilindi, 12));
                haplar[i].setTypeface(Typeface.create("sans-serif-medium", kilindi ? Typeface.BOLD : Typeface.NORMAL));
            }
        };

        for (int i = 0; i < 5; i++) {
            final int idx = i;
            TextView tv = new TextView(this);
            tv.setGravity(Gravity.CENTER);
            tv.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11.5f);
            tv.setSingleLine(true);
            tv.setPadding(dp(2), dp(8), dp(2), dp(8));
            tv.setClickable(true);
            tv.setContentDescription("Hızlı işaretle " + NamazTakip.VAKIT_ADLARI[i]);
            basmaEfekti(tv);
            tv.setOnClickListener(v -> {
                v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
                int cur = NamazTakip.durum(this, gunKey, idx);
                int sonraki = (cur == NamazTakip.BEKLIYOR) ? NamazTakip.EDA
                        : (cur == NamazTakip.EDA ? NamazTakip.CEMAAT : NamazTakip.BEKLIYOR);
                NamazTakip.durumSec(this, gunKey, idx, sonraki);
                yenile.run();
            });
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, -2, 1f);
            if (i > 0) lp.setMargins(dp(5), 0, 0, 0);
            ceteleSatiri.addView(tv, lp);
            haplar[i] = tv;
        }
        yenile.run();
        kart.addView(ceteleSatiri);
        return kart;
    }

    private void sayaciGuncelle() {
        if (sayacMetni == null || siradakiZaman == 0) return;
        long simdiMs = System.currentTimeMillis();
        long kalan = siradakiZaman - simdiMs;
        if (gokYorunge != null) gokYorunge.guncelle(simdiMs);
        if (kalan <= 0) {
            sayacMetni.setText("Vakit girdi");
            siradakiZaman = 0;
            sayfaKabi.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS);
            handler.postDelayed(this::hepsiniCiz, 2500);
            return;
        }
        sayacMetni.setText(Metinler.sayac(kalan));
        if (halka != null) {
            halka.oran(oran(), false);
            halka.uyariModu(kalan <= 15 * 60_000L);
        }
        int dakika = (int) (kalan / 60000);
        if (sonDakika != -1 && dakika != sonDakika) {
            final TextView m = sayacMetni;
            m.animate().scaleX(1.06f).scaleY(1.06f).setDuration(140).withEndAction(() ->
                    m.animate().scaleX(1f).scaleY(1f).setDuration(260).start()).start();
        }
        sonDakika = dakika;
    }

    private View durumHapi(List<Vakit> kurulu) {
        List<BildirimKontrol.Sorun> sorunlar = BildirimKontrol.sorunlariBul(this, true);
        String bekci = Bekci.teshis(this, kurulu);
        boolean iyi = sorunlar.isEmpty() && bekci == null;
        LinearLayout h = cam();
        h.setOrientation(LinearLayout.HORIZONTAL);
        h.setGravity(Gravity.CENTER_VERTICAL);
        TextView isaret = metin(iyi ? "✓" : "!", 20, iyi ? IYI : KOTU, true);
        isaret.setGravity(Gravity.CENTER);
        h.addView(isaret, new LinearLayout.LayoutParams(dp(30), -2));
        String yazi;
        if (!sorunlar.isEmpty()) yazi = sorunlar.size() == 1 ? sorunlar.get(0).baslik : sorunlar.size() + " sorun: bildirimler gelmeyebilir";
        else if (bekci != null) yazi = "Bildirimler yenilenmeli";
        else {
            int vakit = VakitDeposu.say(kurulu, "main");
            long son = VakitDeposu.sonVakitZamani(kurulu);
            yazi = "Bildirimler çalışıyor · " + vakit + " vakit" + (son > 0 ? " · " + Metinler.yonelme(Metinler.gunAy(son)) + " kadar" : "");
        }
        h.addView(metin(yazi, 14, iyi ? SOLUK : KOTU, true), new LinearLayout.LayoutParams(0, -2, 1f));
        h.addView(metin(iyi ? "›" : "Düzelt ›", 15, ALTIN, true));
        h.setClickable(true);
        basmaEfekti(h);
        h.setOnClickListener(v -> {
            v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            if (!sorunlar.isEmpty()) BildirimKontrol.duzelt(this, sorunlar.get(0));
            else if (bekci != null) uygulamayiAc(true);
            else sekmeyeGec(S_MENU);
        });
        return h;
    }

    // ================================================================ 1 · Kıble

    private LinearLayout kibleSayfasi(VakitTakvimi.Takvim t) {
        LinearLayout s = sutun();
        boolean konum = !Double.isNaN(t.enlem) && !Double.isNaN(t.boylam);
        sayfaBasligi(s, "Kıble", konum && t.yer != null ? t.yer : "Kâbe yönü");

        pusula = new Pusula(this);
        int boy = dp(310);
        FrameLayout kap = new FrameLayout(this);
        kap.addView(pusula, new FrameLayout.LayoutParams(boy, boy, Gravity.CENTER));
        s.addView(kap, new LinearLayout.LayoutParams(-1, boy));
        bosluk(s, 8);

        LinearLayout k = cam();
        if (konum) {
            final double yon = Kible.yon(t.enlem, t.boylam);
            double km = Kible.uzaklikKm(t.enlem, t.boylam);
            pusula.kible(yon);
            k.addView(ortala(metin(String.format(Locale.ROOT, "%.0f°", yon), 40, ALTIN, true)));
            k.addView(ortala(metin(Kible.yonAdi(yon) + " · kuzeyden saat yönünde", 14, SOLUK, false)));
            k.addView(ortala(metin("Kâbe'ye " + String.format(new Locale("tr", "TR"), "%,d", Math.round(km)) + " km", 15, BEYAZ, true)));
            String ks = t.kibleSaati();
            if (ks != null) {
                k.addView(ortala(metin("Bugün kıble saati " + ks + " · güneş tam kıble yönünde", 13, SOLUK, false)));
            }
            kibleDurum = ortala(metin("", 16, BEYAZ, true));
            kibleDurum.setPadding(0, dp(8), 0, 0);
            k.addView(kibleDurum);
            pusula.dinleyici((hizali, telefon) -> kibleDurumuYaz(yon, telefon, hizali));
            kibleDurumuYaz(yon, 0, false);
        } else {
            k.addView(metin("Konum bilinmiyor", 18, BEYAZ, true));
            k.addView(metin("Secde Vakti'de konumunuzu seçince kıble yönü burada görünür.", 14, SOLUK, false));
            k.addView(dugme("Uygulamada konum seç", true, v -> uygulamayiAc(false)));
        }
        s.addView(k);

        LinearLayout kibleEylemler = new LinearLayout(this);
        kibleEylemler.setOrientation(LinearLayout.VERTICAL);
        kibleEylemler.addView(dugme("Yakındaki Camiler ve Konum Radarı ›", true, v -> {
            getSharedPreferences("secde_camiler", MODE_PRIVATE).edit().putInt("son_mod", 0).apply();
            CamilerSayfasi.sayfaAc(this, t);
        }));
        kibleEylemler.addView(dugme("Cuma Sünnetleri ve Bayram Rehberi ›", false, v -> {
            getSharedPreferences("secde_camiler", MODE_PRIVATE).edit().putInt("son_mod", 1).apply();
            CamilerSayfasi.sayfaAc(this, t);
        }));
        s.addView(kibleEylemler);
        bosluk(s, 12);

        LinearLayout ipucu = cam();
        ipucu.addView(metin("Doğru ölçüm için", 15, BEYAZ, true));
        ipucu.addView(metin("• Telefonu yere paralel, düz tutun\n• Metal eşyalardan, mıknatıslardan uzak durun\n"
                + "• Sapma varsa telefonu havada 8 çizerek pusulayı ayarlayın\n• Telefonun üst ucu altın işarete gelince ışık yanar ve titreşir", 13, SOLUK, false));
        s.addView(ipucu);
        return s;
    }

    private void kibleDurumuYaz(double kible, double telefon, boolean hizali) {
        if (kibleDurum == null) return;
        TemaMotoru.Durum tm = TemaMotoru.aktif(this);
        if (pusula != null && !pusula.sensorVar()) {
            kibleDurum.setText("Pusula sensörü bulunamadı. Kıble, kuzeyden " + Math.round(kible) + "°.");
            kibleDurum.setTextColor(tm.uyari);
            return;
        }
        if (hizali) {
            kibleDurum.setText("✓ Kıble yönündesiniz");
            kibleDurum.setTextColor(tm.iyi);
        } else {
            double f = Kible.fark(kible, telefon);
            kibleDurum.setText((f > 0 ? "Sağa " : "Sola ") + Math.round(Math.abs(f)) + "° dönün");
            kibleDurum.setTextColor(tm.metin);
        }
    }

    // ================================================================ 2 · Zikir

    private LinearLayout zikirSayfasi() {
        final Zikir z = new Zikir(this);
        final TemaMotoru.Durum tm = TemaMotoru.aktif(this);
        LinearLayout s = sutun();
        sayfaBasligi(s, "Zikirmatik", "Bugün " + binlik(z.gunluk()) + "  ·  Toplam " + binlik(z.toplam()));
        final TextView ustBilgi = (TextView) s.getChildAt(1);

        // Zikir seçimi (yatay çipler: yerleşik + özel + "+ Özel Zikir")
        HorizontalScrollView yatay = new HorizontalScrollView(this);
        yatay.setHorizontalScrollBarEnabled(false);
        yatay.setOverScrollMode(View.OVER_SCROLL_NEVER);
        final LinearLayout cipler = new LinearLayout(this);
        yatay.addView(cipler);
        s.addView(yatay, new LinearLayout.LayoutParams(-1, -2));
        bosluk(s, 10);

        final TextView arapca = ortala(metin("", 30, BEYAZ, false));
        arapca.setTypeface(Varlik.kuranYazisi(this));
        final TextView adi = ortala(metin("", 17, ALTIN, true));
        final TextView anlam = ortala(metin("", 13, SOLUK, false));
        LinearLayout baslikKart = cam();
        baslikKart.addView(arapca);
        baslikKart.addView(adi);
        baslikKart.addView(anlam);
        s.addView(baslikKart);

        // Görünüm Modu Seçici: [ Dairesel Kadran | 3D Tesbih Boncuğu ]
        LinearLayout modCubuk = new LinearLayout(this);
        modCubuk.setOrientation(LinearLayout.HORIZONTAL);
        modCubuk.setPadding(dp(4), dp(4), dp(4), dp(4));
        GradientDrawable modArka = new GradientDrawable();
        modArka.setCornerRadius(dp(18));
        modArka.setColor(tm.acik ? 0x1414211C : 0x22FFFFFF);
        modArka.setStroke(1, tm.acik ? 0x2614211C : 0x33FFFFFF);
        modCubuk.setBackground(modArka);
        LinearLayout.LayoutParams modLp = new LinearLayout.LayoutParams(-1, -2);
        modLp.setMargins(0, 0, 0, dp(8));
        modCubuk.setLayoutParams(modLp);

        final TextView kadranSec = metin("Dairesel Kadran", 13, BEYAZ, true);
        kadranSec.setGravity(Gravity.CENTER);
        kadranSec.setShadowLayer(0, 0, 0, 0);
        kadranSec.setPadding(dp(10), dp(8), dp(10), dp(8));
        final TextView boncukSec = metin("3D Tesbih Boncuğu", 13, BEYAZ, true);
        boncukSec.setGravity(Gravity.CENTER);
        boncukSec.setShadowLayer(0, 0, 0, 0);
        boncukSec.setPadding(dp(10), dp(8), dp(10), dp(8));
        modCubuk.addView(kadranSec, new LinearLayout.LayoutParams(0, -2, 1f));
        modCubuk.addView(boncukSec, new LinearLayout.LayoutParams(0, -2, 1f));
        s.addView(modCubuk);

        // 5 Boncuk Malzemesi Çubuğu (3D Tesbih modunda görünür)
        final HorizontalScrollView malzemeYatay = new HorizontalScrollView(this);
        malzemeYatay.setHorizontalScrollBarEnabled(false);
        malzemeYatay.setOverScrollMode(View.OVER_SCROLL_NEVER);
        final LinearLayout malzemeSatir = new LinearLayout(this);
        malzemeSatir.setPadding(0, 0, 0, dp(6));
        malzemeYatay.addView(malzemeSatir);
        s.addView(malzemeYatay, new LinearLayout.LayoutParams(-1, -2));

        zikirDaire = new ZikirDaire(this);
        final BoncukluZikirView boncukGorunum = new BoncukluZikirView(this);
        boncukGorunum.malzeme(z.boncukMalzeme());
        int boy = dp(312);
        FrameLayout kap = new FrameLayout(this);
        kap.addView(zikirDaire, new FrameLayout.LayoutParams(dp(300), dp(300), Gravity.CENTER));
        kap.addView(boncukGorunum, new FrameLayout.LayoutParams(-1, boy, Gravity.CENTER));
        s.addView(kap, new LinearLayout.LayoutParams(-1, boy));

        final BoncukluZikirView.ZikirGrafikView grafik =
                new BoncukluZikirView.ZikirGrafikView(this, z.sonYediGun(), z.sonYediGunEtiket());

        final Runnable[] sec = new Runnable[1];
        final Runnable[] modYenile = new Runnable[1];
        final TextView[] hedefDugme = new TextView[1];

        modYenile[0] = () -> {
            boolean boncuk = z.boncukModu();
            zikirDaire.setVisibility(boncuk ? View.GONE : View.VISIBLE);
            boncukGorunum.setVisibility(boncuk ? View.VISIBLE : View.GONE);
            malzemeYatay.setVisibility(boncuk ? View.VISIBLE : View.GONE);

            kadranSec.setTextColor(!boncuk ? tm.birincilDugmeYaziRengi() : tm.soluk);
            kadranSec.setBackground(!boncuk ? tm.birincilDugme(this, 14) : null);
            boncukSec.setTextColor(boncuk ? tm.birincilDugmeYaziRengi() : tm.soluk);
            boncukSec.setBackground(boncuk ? tm.birincilDugme(this, 14) : null);

            malzemeSatir.removeAllViews();
            int secMalz = z.boncukMalzeme();
            for (int m = 0; m < BoncukluZikirView.MALZEMELER.length; m++) {
                final int mIdx = m;
                boolean mSec = m == secMalz;
                TextView mc = metin(BoncukluZikirView.MALZEMELER[m], 12,
                        mSec ? tm.birincilDugmeYaziRengi() : tm.metin, true);
                mc.setShadowLayer(0, 0, 0, 0);
                mc.setPadding(dp(12), dp(6), dp(12), dp(6));
                mc.setBackground(tm.cipArkaPlani(this, mSec, 15));
                LinearLayout.LayoutParams mlp = new LinearLayout.LayoutParams(-2, -2);
                mlp.setMargins(0, 0, dp(6), 0);
                mc.setOnClickListener(v -> {
                    v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
                    z.boncukMalzeme(mIdx);
                    boncukGorunum.malzeme(mIdx);
                    modYenile[0].run();
                });
                malzemeSatir.addView(mc, mlp);
            }
        };

        kadranSec.setOnClickListener(v -> {
            if (z.boncukModu()) {
                v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
                z.boncukModu(false);
                modYenile[0].run();
            }
        });
        boncukSec.setOnClickListener(v -> {
            if (!z.boncukModu()) {
                v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
                z.boncukModu(true);
                modYenile[0].run();
            }
        });

        sec[0] = () -> {
            List<Zikir.Tanim> tum = z.tumTanimlar();
            int i = z.secili();
            Zikir.Tanim d = z.tanim(i);
            arapca.setText(d.arapca);
            arapca.setVisibility(d.arapca == null || d.arapca.isEmpty() ? View.GONE : View.VISIBLE);
            adi.setText(d.ad);
            anlam.setText(d.anlam);
            zikirDaire.ayarla(z.sayi(i), z.hedef(i));
            boncukGorunum.ayarla(z.sayi(i), z.hedef(i));
            if (hedefDugme[0] != null) hedefDugme[0].setText("Hedef: " + z.hedef(i));
            cipler.removeAllViews();
            for (int c = 0; c < tum.size(); c++) {
                final int n = c;
                final Zikir.Tanim tanim = tum.get(c);
                boolean secili = c == i;
                TextView ci = metin(tanim.ad, 14, secili ? tm.birincilDugmeYaziRengi() : tm.metin, true);
                ci.setShadowLayer(0, 0, 0, 0);
                ci.setPadding(dp(14), dp(8), dp(14), dp(8));
                ci.setBackground(tm.cipArkaPlani(this, secili, 18));
                LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-2, -2);
                lp.setMargins(0, 0, dp(8), 0);
                ci.setOnClickListener(v -> {
                    v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
                    z.sec(n);
                    sec[0].run();
                });
                if (tanim.ozel) {
                    ci.setOnLongClickListener(v -> {
                        new AlertDialog.Builder(this)
                                .setTitle("Özel zikir silinsin mi?")
                                .setMessage("\"" + tanim.ad + "\" listeden kaldırılacak.")
                                .setPositiveButton("Sil", (dg, w) -> {
                                    z.ozelSil(n);
                                    sec[0].run();
                                })
                                .setNegativeButton("Vazgeç", null)
                                .show();
                        return true;
                    });
                }
                cipler.addView(ci, lp);
            }
            TextView ekleCip = metin("+ Özel Zikir", 13, tm.vurgu, true);
            ekleCip.setShadowLayer(0, 0, 0, 0);
            ekleCip.setPadding(dp(14), dp(8), dp(14), dp(8));
            ekleCip.setBackground(tm.ikincilDugme(this, 18));
            ekleCip.setOnClickListener(v -> ozelZikirEkleDiyalog(z, sec[0]));
            cipler.addView(ekleCip, new LinearLayout.LayoutParams(-2, -2));

            arapca.setAlpha(0f);
            arapca.setTranslationY(dp(10));
            arapca.animate().alpha(1f).translationY(0).setDuration(350).start();
        };

        final ZikirDaire.Dinleyici sayimIsleyici = (sayi, doldu) -> {
            int i = z.secili();
            int yeniSayi = z.artir(i);
            zikirDaire.ayarla(yeniSayi, z.hedef(i));
            boncukGorunum.ayarla(yeniSayi, z.hedef(i));
            ustBilgi.setText("Bugün " + binlik(z.gunluk()) + "  ·  Toplam " + binlik(z.toplam()));
            grafik.veri(z.sonYediGun(), z.sonYediGunEtiket());
            if (doldu && z.tesbihat() && i < 2) {
                // Namaz tesbihatı: 33 Sübhânallah → 33 Elhamdülillah → 33 Allâhu ekber
                handler.postDelayed(() -> {
                    z.sec(i + 1);
                    z.sifirla(i + 1);
                    sec[0].run();
                    Toast.makeText(this, z.tanim(i + 1).ad + "'a geçildi", Toast.LENGTH_SHORT).show();
                }, 650);
            } else if (doldu) {
                Toast.makeText(this, "Hedef tamam: " + z.tanim(i).ad + " · " + z.hedef(i), Toast.LENGTH_SHORT).show();
            }
        };
        zikirDaire.dinleyici(sayimIsleyici);
        boncukGorunum.dinleyici(sayimIsleyici::sayildi);

        LinearLayout ikili = new LinearLayout(this);
        TextView sifir = dugme("Sıfırla", false, v -> new AlertDialog.Builder(this)
                .setTitle("Sayaç sıfırlansın mı?")
                .setMessage(z.tanim(z.secili()).ad + " sayısı 0 olacak.")
                .setPositiveButton("Sıfırla", (d, w) -> {
                    z.sifirla(z.secili());
                    sec[0].run();
                })
                .setNegativeButton("Vazgeç", null)
                .show());
        TextView hedef = dugme("Hedef", false, v -> {
            final int[] h = Zikir.HEDEFLER;
            String[] ad = new String[h.length];
            int secili = -1;
            for (int i = 0; i < h.length; i++) {
                ad[i] = String.valueOf(h[i]);
                if (h[i] == z.hedef(z.secili())) secili = i;
            }
            new AlertDialog.Builder(this).setTitle("Hedef sayı")
                    .setSingleChoiceItems(ad, secili, (d, w) -> {
                        z.hedef(z.secili(), h[w]);
                        sec[0].run();
                        d.dismiss();
                    }).setNegativeButton("Vazgeç", null).show();
        });
        hedefDugme[0] = hedef;
        ikili.addView(sifir, yarim(true));
        ikili.addView(hedef, yarim(false));
        s.addView(ikili);

        s.addView(dugme("5 Vakit Rehberli Namaz Tesbihatı ›", true, v -> TesbihatRehberi.sayfaAc(this)));
        bosluk(s, 10);

        LinearLayout ayar = cam();
        anahtar(ayar, "Namaz tesbihatı", "33 Sübhânallah · 33 Elhamdülillah · 33 Allâhu ekber, sırayla otomatik geçer",
                z.tesbihat(), z::tesbihat);
        s.addView(ayar);

        LinearLayout grafikKart = cam();
        grafikKart.addView(metin("SON 7 GÜNLÜK ZİKİR İSTATİSTİĞİ", 11, ALTIN, true));
        grafikKart.addView(grafik, new LinearLayout.LayoutParams(-1, dp(156)));
        s.addView(grafikKart);

        modYenile[0].run();
        sec[0].run();
        return s;
    }

    private void ozelZikirEkleDiyalog(final Zikir z, final Runnable yenile) {
        LinearLayout form = new LinearLayout(this);
        form.setOrientation(LinearLayout.VERTICAL);
        form.setPadding(dp(20), dp(12), dp(20), dp(4));

        final EditText eAd = new EditText(this);
        eAd.setHint("Zikir adı (ör. Yâ Şâfî)");
        form.addView(eAd);

        final EditText eArapca = new EditText(this);
        eArapca.setHint("Arapça yazılışı (isteğe bağlı)");
        form.addView(eArapca);

        final EditText eAnlam = new EditText(this);
        eAnlam.setHint("Anlamı (isteğe bağlı)");
        form.addView(eAnlam);

        final EditText eHedef = new EditText(this);
        eHedef.setHint("Hedef sayı (ör. 100)");
        eHedef.setInputType(android.text.InputType.TYPE_CLASS_NUMBER);
        eHedef.setText("100");
        form.addView(eHedef);

        new AlertDialog.Builder(this)
                .setTitle("Özel Zikir Ekle")
                .setView(form)
                .setPositiveButton("Ekle", (d, w) -> {
                    String ad = eAd.getText().toString().trim();
                    if (ad.isEmpty()) return;
                    int hdf = 100;
                    try { hdf = Integer.parseInt(eHedef.getText().toString().trim()); } catch (Throwable ignored) {}
                    z.ozelEkle(ad, eArapca.getText().toString(), eAnlam.getText().toString(), hdf);
                    yenile.run();
                })
                .setNegativeButton("Vazgeç", null)
                .show();
    }

    private static String binlik(long n) {
        return String.format(new Locale("tr", "TR"), "%,d", n);
    }

    // ================================================================ 3 · Takvim

    private LinearLayout takvimSayfasi(final VakitTakvimi.Takvim t, List<Vakit> kurulu) {
        TemaMotoru.Durum tm = TemaMotoru.aktif(this);
        LinearLayout s = sutun();
        s.addView(metin(t.yer != null ? t.yer : "Önümüzdeki günler", 14, SOLUK, false));

        LinearLayout ustDugmeler = new LinearLayout(this);
        ustDugmeler.addView(dugme("30 Günlük İmsakiye ›", true, v -> RamazanModu.imsakiyeAc(this, t)), yarim(true));
        ustDugmeler.addView(dugme("Hicrî & Kandiller ›", false, v -> HicriTakvim.sayfaAc(this, t)), yarim(false));
        s.addView(ustDugmeler);
        bosluk(s, 10);

        if (t.bos()) {
            LinearLayout k = cam();
            k.addView(metin("Vakit bilgisi yok. Uygulamayı açınca yüklenir.", 15, SOLUK, false));
            s.addView(k);
            return s;
        }
        LinearLayout baslik = new LinearLayout(this);
        baslik.setPadding(dp(14), 0, dp(14), dp(6));
        baslik.addView(metin("", 12, SILIK, true), new LinearLayout.LayoutParams(dp(78), -2));
        for (String k : VakitTakvimi.SIRA) {
            TextView x = metin(kisalt(Metinler.namazAdi(k)), 11, SILIK, true);
            x.setGravity(Gravity.CENTER);
            baslik.addView(x, new LinearLayout.LayoutParams(0, -2, 1f));
        }
        s.addView(baslik);

        Calendar gun = Calendar.getInstance();
        gun.set(Calendar.HOUR_OF_DAY, 12);
        SimpleDateFormat gunAd = new SimpleDateFormat("d MMM EEE", Metinler.TR);
        LinearLayout k = cam();
        k.setPadding(dp(6), dp(6), dp(6), dp(6));
        for (int i = 0; i < 31; i++) {
            List<VakitTakvimi.An> l = t.gun(gun.getTimeInMillis());
            if (!l.isEmpty()) {
                boolean bugun = i == 0;
                boolean cuma = gun.get(Calendar.DAY_OF_WEEK) == Calendar.FRIDAY;
                String mubarek = mubarekGun(kurulu, gun);
                LinearLayout satir = new LinearLayout(this);
                satir.setOrientation(LinearLayout.VERTICAL);
                satir.setPadding(dp(8), dp(8), dp(8), dp(8));
                if (bugun || mubarek != null) {
                    GradientDrawable g = new GradientDrawable();
                    int vurguArka = (tm.vurgu & 0x00FFFFFF) | (tm.acik ? 0x22000000 : 0x40000000);
                    int vurguKenar = (tm.vurgu & 0x00FFFFFF) | 0x80000000;
                    g.setColor(bugun ? vurguArka : (tm.acik ? 0x1FB4507A : 0x2EB4507A));
                    g.setStroke(1, bugun ? vurguKenar : 0x80E89DBD);
                    g.setCornerRadius(dp(12));
                    satir.setBackground(g);
                }
                LinearLayout r = new LinearLayout(this);
                r.setGravity(Gravity.CENTER_VERTICAL);
                LinearLayout tarih = new LinearLayout(this);
                tarih.setOrientation(LinearLayout.VERTICAL);
                tarih.addView(metin(gunAd.format(new Date(gun.getTimeInMillis())), 12,
                        bugun ? ALTIN : (cuma ? (tm.acik ? tm.ana : 0xFFFFD88A) : SOLUK), bugun || cuma));
                String h = t.hicri(gun.getTimeInMillis());
                if (h != null) {
                    TextView hx = metin(kisaHicri(h), 10, SILIK, false);
                    hx.setMaxLines(2);
                    tarih.addView(hx);
                }
                r.addView(tarih, new LinearLayout.LayoutParams(dp(78), -2));
                for (String anahtar : VakitTakvimi.SIRA) {
                    String saat = "–";
                    for (VakitTakvimi.An a : l) if (anahtar.equals(a.namaz)) { saat = Metinler.saat(a.zaman); break; }
                    TextView x = metin(saat, 13, bugun ? BEYAZ : SOLUK, bugun);
                    x.setFontFeatureSettings("tnum");
                    x.setGravity(Gravity.CENTER);
                    r.addView(x, new LinearLayout.LayoutParams(0, -2, 1f));
                }
                satir.addView(r);
                if (mubarek != null) satir.addView(metin("✦ " + mubarek, 12, tm.acik ? 0xFF9C2E62 : 0xFFE89DBD, true));
                k.addView(satir);
            }
            gun.add(Calendar.DAY_OF_MONTH, 1);
        }
        s.addView(k);
        s.addView(metin("Cumalar altın, mübarek günler pembe işaretli.", 12, SILIK, false));
        return s;
    }

    private static String mubarekGun(List<Vakit> kurulu, Calendar gun) {
        for (Vakit v : kurulu) {
            if (!"holy".equals(v.tur)) continue;
            Calendar c = Calendar.getInstance();
            c.setTimeInMillis(v.zaman);
            if (c.get(Calendar.YEAR) == gun.get(Calendar.YEAR) && c.get(Calendar.DAY_OF_YEAR) == gun.get(Calendar.DAY_OF_YEAR)) {
                return v.baslik.isEmpty() ? "Mübarek gün" : v.baslik;
            }
        }
        return null;
    }

    /** "21 Cemâziyelevvel 1448" → "21 Cemâziyelevvel" (yıl takvimde gereksiz). */
    private static String kisaHicri(String h) {
        return h.replaceAll("\\s+\\d{4}\\s*$", "").trim();
    }

    private static String kisalt(String ad) {
        if (ad == null) return "";
        return ad.length() > 6 ? ad.substring(0, 5) + "." : ad;
    }

    // ================================================================ 4 · Menü

    private LinearLayout menuSayfasi(List<Vakit> kurulu) {
        LinearLayout s = sutun();
        sayfaBasligi(s, "Menü", "Secde Vakti'nin bütün bölümleri");

        s.addView(TemaGalerisi.ozetKart(this, () -> bolumAc("tema")));

        // Resimli bölüm butonları (2 sütun)
        int namazTam = NamazTakip.bugunTamamlanan(this);
        int hatimCuz = HatimTakip.tamamlananCuzSayisi(this);
        int zikirGun = new Zikir(this).gunluk();

        String[][] bolum = {
                {"mihrap", "Tema Stüdyosu", "16 tema · manzaralar", "tema"},
                {"k_huzur", "Huzur & Tefekkür", "Nefes hâlesi · gece", "huzur"},
                {"k_namaz_takip", "Namaz Takibi", "Seri · ısı haritası", "namaz_takip"},
                {"k_iftar", "Kazâ ve Oruç", "Borç · oruç defteri", "kaza"},
                {"k_ramazan", "İmsakiye & Ramazan", "30 gün · iftar sayacı", "imsakiye"},
                {"k_kuran", "Kur'an-ı Kerim", "Meal · tilavet", "kuran"},
                {"k_hatim", "Hatim Takibi", "30 cüz · sesli meal", "hatim"},
                {"k_tesbihat", "Namaz Tesbihatı", "5 vakit · 8 adım", "tesbihat"},
                {"k_ezan", "Ezan & Sûreler", "Çevrimdışı ezber", "ezan_studyo"},
                {"k_cami_radar", "Yakındaki Camiler", "Radar · cuma rehberi", "camiler"},
                {"k_hilal", "Hicrî & Kandiller", "Dönüştürücü · 12 gün", "hicri"},
                {"k_dua", "Manevî Paket", "Âyet · hadîs · ezkâr", "manevi"},
                {"k_cini", "Paylaşım Kartı", "Sosyal medya kartı", "paylas"},
                {"elifba_bg", "Elif-Ba", "Harfler · test", "elifba"},
                {"k_dua", "Dualar", "Günlük dualar", "dualar"},
                {"k_cini", "Esmâü'l-Hüsnâ", "99 isim", "esma"},
                {"k_iftar", "Sesli meal", "10 okuyucu", "meal"},
                {"k_hilal", "Takvim", "Aylık vakitler", "takvim"},
                {"k_kabe", "Kıble", "Pusula", "kible"},
                {"k_tesbih", "Zikirmatik", "3D tesbih · sayaç", "zikir"},
                {"k_kerahet", "Kerâhet & Nâfile", "İşrâk · kuşluk · teheccüd", "kerahet"},
                {"kandil", "Oruç Defteri", "Kaza · nâfile takibi", "oruc"},
                {"k_kubbe", "Konum & Şehir", "81 il · GPS · takvim", "konum"},
                {"kuran_bg", "Yer imleri", "Kaydedilen ayetler", "imler"},
        };
        int[] renk = {
                0xFF1B5A45, 0xFF15385A, 0xFF285C48, 0xFF6A3A12,
                0xFF78521D, 0xFF6A3A12, 0xFF1E5A4A, 0xFF1E5A3A,
                0xFF445933, 0xFF164C7E, 0xFF3A2A6A, 0xFF8A3A3A,
                0xFF72304D, 0xFF3A2A6A, 0xFF8A3A3A, 0xFF1A4A7A,
                0xFF7A4A10, 0xFF3A2A6A, 0xFF7A4A10, 0xFF1E5A3A,
                0xFF5A4218, 0xFF78521D, 0xFF2A3A7A, 0xFF6A3A12
        };
        for (int i = 0; i < bolum.length; i += 2) {
            LinearLayout r = new LinearLayout(this);
            for (int j = 0; j < 2 && i + j < bolum.length; j++) {
                final String[] b = bolum[i + j];
                Kutucuk ku = kutucuk(b[0], b[1], b[2], renk[i + j], () -> bolumAc(b[3]));
                if ("namaz_takip".equals(b[3])) ku.rozet(namazTam + "/5");
                else if ("hatim".equals(b[3])) ku.rozet(hatimCuz + "/30");
                else if ("zikir".equals(b[3]) && zikirGun > 0) ku.rozet(String.valueOf(zikirGun));
                else if ("huzur".equals(b[3])) ku.rozet("Yeni");
                LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, dp(132), 1f);
                lp.setMargins(j == 0 ? 0 : dp(6), 0, j == 0 ? dp(6) : 0, dp(12));
                r.addView(ku, lp);
            }
            s.addView(r);
        }

        s.addView(dugme("Uygulamayı denetle", true, v -> bolumAc("denetim")));
        bosluk(s, 6);
        s.addView(altBaslik("Konum ve Görünüm"));
        LinearLayout g = cam();
        VakitTakvimi.Takvim aktifTakvim = VakitTakvimi.oku(this);
        g.addView(metin("📍 Aktif şehir: " + (aktifTakvim.yer != null ? aktifTakvim.yer : "İstanbul"), 15, BEYAZ, true));
        g.addView(metin("81 il listesinden veya GPS ile konumunuzu seçip 35 günlük vakit takvimini güncelleyebilirsiniz.", 13, SOLUK, false));
        g.addView(dugme("Konum & Şehir Değiştir", false, v -> bolumAc("konum")));
        s.addView(g);

        s.addView(altBaslik("Bildirimler"));
        izinlerKarti(s);
        kurulumKarti(s, kurulu);

        LinearLayout k = cam();
        baslik(k, "Seçenekler");
        anahtar(k, "Vakit sayacı", "Bildirim alanında sıradaki vakte geri sayım", Tercihler.sayacAcik(this), acik -> {
            Tercihler.sayacAcik(this, acik);
            VakitSayaci.guncelle(this);
        });
        anahtar(k, "Vakitte titreşime al", "Vakit girince telefon titreşimde kalır (Güneş hariç)", SessizMod.acik(this),
                acik -> SessizMod.ayarla(this, acik, SessizMod.sure(this)));
        TextView sure = metin("Titreşim süresi: " + SessizMod.sure(this) + " dk  ›", 14, ALTIN, true);
        sure.setPadding(0, dp(4), 0, dp(8));
        sure.setOnClickListener(v -> sureSec());
        k.addView(sure);
        anahtar(k, "Bildirim bekçisi", "Vakit bildirimleri biterse uyarır", Tercihler.bekciAcik(this), acik -> {
            Tercihler.bekciAcik(this, acik);
            if (acik) { Bekci.planla(this); Bekci.kontrol(this); }
            else Kanallar.nm(this).cancel(Kanallar.BILDIRIM_BEKCI);
        });
        anahtar(k, "Pil uyarısı", "Pil optimizasyonu açıkken açılışta hatırlat",
                !Tercihler.sp(this).getBoolean(BildirimKontrol.ANAHTAR_PIL_SORMA, false), acik ->
                        Tercihler.sp(this).edit().putBoolean(BildirimKontrol.ANAHTAR_PIL_SORMA, !acik).apply());
        s.addView(k);

        k = cam();
        baslik(k, "Test");
        long gelen = Tercihler.sp(this).getLong("son_test_basarili_ms", 0);
        long kurulan = Tercihler.sp(this).getLong("son_test_kurulan_ms", 0);
        boolean gelmedi = kurulan > 0 && gelen < kurulan && System.currentTimeMillis() - kurulan > 3 * 60_000L;
        k.addView(metin(gelmedi ? "Son zamanlanmış test gelmedi (" + Metinler.gunVeSaat(kurulan) + "). Pil ve otomatik başlatma ayarlarına bakın."
                : gelen > 0 ? "Son başarılı test: " + Metinler.gunVeSaat(gelen)
                : "1 dk sonra test, telefon kilitliyken bildirimin gelip gelmediğini dener.", 13, gelmedi ? UYARI : SOLUK, false));
        LinearLayout ikili = new LinearLayout(this);
        ikili.addView(dugme("1 dk sonra", true, v -> BildirimKontrol.testPlanla(this)), yarim(true));
        ikili.addView(dugme("Anında", false, v -> {
            TestAlarmAlici.goster(this, false);
            Toast.makeText(this, "Test bildirimi gönderildi", Toast.LENGTH_SHORT).show();
        }), yarim(false));
        k.addView(ikili);
        s.addView(k);

        final boolean acik = Tercihler.sp(this).getBoolean(AYRINTI_ACIK, false);
        TextView ac = metin((acik ? "▾  " : "▸  ") + "Ayrıntılar ve destek", 15, ALTIN, true);
        ac.setPadding(dp(4), dp(8), dp(4), dp(10));
        ac.setOnClickListener(v -> {
            Tercihler.sp(this).edit().putBoolean(AYRINTI_ACIK, !acik).apply();
            final int y = sayfalar[4].getScrollY();
            hepsiniCiz();
            sayfalar[4].post(() -> sayfalar[4].scrollTo(0, y));
        });
        s.addView(ac);
        if (acik) {
            listeKarti(s, kurulu);
            destekKarti(s, kurulu);
        }
        return s;
    }

    private void izinlerKarti(LinearLayout s) {
        LinearLayout k = cam();
        baslik(k, "Sistem ayarları");
        NotificationManager nm = Kanallar.nm(this);
        boolean izin = nm == null || nm.areNotificationsEnabled();
        satir(k, izin ? 1 : -1, "Bildirim izni", izin ? "Açık" : "Kapalı: hiçbir bildirim gelmez",
                izin ? null : "Aç", () -> BildirimKontrol.duzelt(this,
                        new BildirimKontrol.Sorun(BildirimKontrol.SORUN_IZIN, "", "", null)));
        String kapali = null, kapaliId = null;
        if (nm != null && Build.VERSION.SDK_INT >= 26) {
            try {
                for (NotificationChannel ch : nm.getNotificationChannels()) {
                    String id = ch.getId();
                    if ((id.startsWith("sekine_alarm_") || id.equals("sekine_channel_default"))
                            && ch.getImportance() == NotificationManager.IMPORTANCE_NONE) {
                        kapali = String.valueOf(ch.getName());
                        kapaliId = id;
                        break;
                    }
                }
            } catch (Throwable ignored) {
            }
        }
        final String kId = kapaliId;
        satir(k, kapali == null ? 1 : -1, "Ezan kanalları", kapali == null ? "Açık" : "\"" + kapali + "\" kapalı",
                kapali == null ? "Ayarlar" : "Aç", () -> {
                    if (kId != null) BildirimKontrol.duzelt(this, new BildirimKontrol.Sorun(BildirimKontrol.SORUN_KANAL, "", "", kId));
                    else BildirimKontrol.ilkAcilaniBaslat(this, Collections.singletonList(BildirimKontrol.bildirimAyarlari(this)));
                });
        if (Build.VERSION.SDK_INT >= 31) {
            android.app.AlarmManager am = (android.app.AlarmManager) getSystemService(ALARM_SERVICE);
            boolean tam = am == null || am.canScheduleExactAlarms();
            satir(k, tam ? 1 : -1, "Alarmlar ve hatırlatıcılar", tam ? "İzin var" : "Kapalı: bildirim gecikebilir",
                    tam ? null : "Aç", () -> BildirimKontrol.duzelt(this,
                            new BildirimKontrol.Sorun(BildirimKontrol.SORUN_TAM_ALARM, "", "", null)));
        }
        if (Build.VERSION.SDK_INT >= 28) {
            android.app.ActivityManager acm = (android.app.ActivityManager) getSystemService(ACTIVITY_SERVICE);
            boolean kisitli = acm != null && acm.isBackgroundRestricted();
            satir(k, kisitli ? -1 : 1, "Arka plan kullanımı", kisitli ? "\"Kısıtlanmış\": alarmlar durur" : "Serbest",
                    kisitli ? "Aç" : null, () -> BildirimKontrol.ilkAcilaniBaslat(this,
                            Collections.singletonList(BildirimKontrol.uygulamaAyrintilari(this))));
        }
        boolean pil = BildirimKontrol.pilMuaf(this);
        satir(k, pil ? 1 : 0, "Pil optimizasyonu", pil ? "Kapalı (önerilen)" : "Açık: kilitliyken gecikebilir",
                pil ? null : "Kapat", () -> BildirimKontrol.duzelt(this,
                        new BildirimKontrol.Sorun(BildirimKontrol.SORUN_PIL, "", "", null)));
        if (BildirimKontrol.tamEkranAyariVar()) {
            boolean te = BildirimKontrol.tamEkranNotu(this) == null;
            satir(k, te ? 1 : 0, "Tam ekran ezan", te ? "İzin var" : "Kapalı: ezan normal bildirim olarak gelir",
                    te ? null : "Aç", () -> BildirimKontrol.tamEkranAyariniAc(this));
        }
        String uretici = BildirimKontrol.ureticiNotu();
        if (uretici != null) {
            k.addView(metin(uretici, 13, SOLUK, false));
            k.addView(dugme("Otomatik başlatma ayarı", false, v -> BildirimKontrol.ureticiAyariniAc(this)));
        }
        s.addView(k);
    }

    private void kurulumKarti(LinearLayout s, List<Vakit> kurulu) {
        LinearLayout k = cam();
        baslik(k, "Kurulu bildirimler");
        int vakit = VakitDeposu.say(kurulu, "main");
        long son = VakitDeposu.sonVakitZamani(kurulu);
        if (vakit == 0) k.addView(metin("Kurulu vakit bildirimi yok.", 15, KOTU, true));
        else {
            k.addView(metin(vakit + " vakit bildirimi", 15, BEYAZ, true));
            if (son > 0) {
                long gun = Math.max(0, (son - System.currentTimeMillis()) / 86_400_000L);
                k.addView(metin(Metinler.tarih(son) + " tarihine kadar (" + gun + " gün)", 13, SOLUK, false));
            }
        }
        StringBuilder diger = new StringBuilder();
        ekle(diger, kurulu, "pre", "vakit öncesi");
        ekle(diger, kurulu, "sahur", "sahur");
        ekle(diger, kurulu, "iftar", "iftar");
        ekle(diger, kurulu, "friday", "cuma");
        ekle(diger, kurulu, "holy", "mübarek gün");
        ekle(diger, kurulu, "verse", "günün ayeti");
        if (diger.length() > 0) k.addView(metin("Ayrıca: " + diger, 13, SOLUK, false));
        long kurulum = Tercihler.sonKurulum(this);
        if (kurulum > 0) k.addView(metin("Son kurulum: " + Metinler.gunVeSaat(kurulum), 13, SOLUK, false));
        String bekci = Bekci.teshis(this, kurulu);
        if (bekci != null) k.addView(metin("⚠ " + bekci, 13, UYARI, true));
        k.addView(dugme("Bildirimleri yeniden kur", bekci != null, v -> uygulamayiAc(true)));
        s.addView(k);
    }

    private static void ekle(StringBuilder sb, List<Vakit> l, String tur, String ad) {
        int n = VakitDeposu.say(l, tur);
        if (n == 0) return;
        if (sb.length() > 0) sb.append(", ");
        sb.append(n).append(' ').append(ad);
    }

    private void listeKarti(LinearLayout s, List<Vakit> kurulu) {
        LinearLayout k = cam();
        baslik(k, "Yaklaşan bildirimler");
        if (kurulu.isEmpty()) k.addView(metin("Liste boş.", 13, SOLUK, false));
        int sinir = Math.min(kurulu.size(), 20);
        for (int i = 0; i < sinir; i++) {
            Vakit v = kurulu.get(i);
            LinearLayout r = new LinearLayout(this);
            r.setPadding(0, dp(5), 0, dp(5));
            r.addView(metin(Metinler.gunVeSaat(v.zaman), 13, SOLUK, false), new LinearLayout.LayoutParams(dp(130), -2));
            r.addView(metin(v.kisaAd(), 13, v.vakitBildirimi() ? BEYAZ : SOLUK, v.vakitBildirimi()), new LinearLayout.LayoutParams(0, -2, 1f));
            k.addView(r);
        }
        if (kurulu.size() > sinir) k.addView(metin("… ve " + (kurulu.size() - sinir) + " bildirim daha", 13, SILIK, false));
        s.addView(k);
    }

    private void destekKarti(LinearLayout s, List<Vakit> kurulu) {
        LinearLayout k = cam();
        baslik(k, "Destek");
        k.addView(metin(Build.MANUFACTURER + " " + Build.MODEL + " · Android " + Build.VERSION.RELEASE
                + " · Secde Vakti " + surum(), 13, SOLUK, false));
        LinearLayout ikili = new LinearLayout(this);
        ikili.addView(dugme("Raporu kopyala", false, v -> {
            ClipboardManager cm = (ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
            if (cm != null) {
                cm.setPrimaryClip(ClipData.newPlainText("Secde Vakti teşhis", rapor(kurulu)));
                Toast.makeText(this, "Rapor kopyalandı", Toast.LENGTH_SHORT).show();
            }
        }), yarim(true));
        ikili.addView(dugme("Paylaş", false, v -> {
            try {
                startActivity(Intent.createChooser(new Intent(Intent.ACTION_SEND).setType("text/plain")
                        .putExtra(Intent.EXTRA_SUBJECT, "Secde Vakti bildirim teşhisi")
                        .putExtra(Intent.EXTRA_TEXT, rapor(kurulu)), "Raporu paylaş"));
            } catch (Throwable ignored) {
            }
        }), yarim(false));
        k.addView(ikili);
        k.addView(dugme("Bildirim ayarlarını aç", false, v -> BildirimKontrol.ilkAcilaniBaslat(this,
                Collections.singletonList(BildirimKontrol.bildirimAyarlari(this)))));
        s.addView(k);
    }

    String rapor(List<Vakit> kurulu) {
        StringBuilder r = new StringBuilder("Secde Vakti bildirim teşhisi\n");
        r.append("Sürüm: ").append(surum()).append('\n');
        r.append("Cihaz: ").append(Build.MANUFACTURER).append(' ').append(Build.MODEL)
                .append(", Android ").append(Build.VERSION.RELEASE).append(" (API ").append(Build.VERSION.SDK_INT).append(")\n");
        r.append("Zaman: ").append(Metinler.gunVeSaat(System.currentTimeMillis())).append(' ')
                .append(java.util.TimeZone.getDefault().getID()).append('\n');
        VakitTakvimi.Takvim t = VakitTakvimi.oku(this);
        r.append("Takvim: ").append(t.vakitler.size()).append(" vakit, yer=").append(t.yer)
                .append(", bitiş=").append(t.bitis() > 0 ? Metinler.gunVeSaat(t.bitis()) : "-").append('\n');
        if (!Double.isNaN(t.enlem)) {
            r.append(String.format(Locale.ROOT, "Kıble: %.1f°, %.0f km%n", Kible.yon(t.enlem, t.boylam), Kible.uzaklikKm(t.enlem, t.boylam)));
        }
        r.append("Kurulum tamam: ").append(BildirimKontrol.kurulumTamam(this)).append('\n');
        List<BildirimKontrol.Sorun> sorunlar = BildirimKontrol.sorunlariBul(this, false);
        r.append("Sorunlar: ").append(sorunlar.isEmpty() ? "yok" : "").append('\n');
        for (BildirimKontrol.Sorun x : sorunlar) r.append("  - ").append(x.baslik).append('\n');
        r.append("Tam ekran: ").append(BildirimKontrol.tamEkranNotu(this) == null ? "izinli/uygulanmaz" : "kapalı").append('\n');
        r.append("Kurulu: ").append(kurulu.size()).append(" bildirim, ").append(VakitDeposu.say(kurulu, "main")).append(" vakit\n");
        long son = VakitDeposu.sonVakitZamani(kurulu);
        if (son > 0) r.append("Son vakit bildirimi: ").append(Metinler.gunVeSaat(son)).append('\n');
        long kur = Tercihler.sonKurulum(this);
        r.append("Son kurulum: ").append(kur > 0 ? Metinler.gunVeSaat(kur) : "bilinmiyor").append('\n');
        long bk = Tercihler.sp(this).getLong(Tercihler.SON_BEKCI_KONTROL, 0);
        r.append("Son bekçi denetimi: ").append(bk > 0 ? Metinler.gunVeSaat(bk) : "yok").append('\n');
        long tk = Tercihler.sp(this).getLong("son_test_kurulan_ms", 0);
        long tb = Tercihler.sp(this).getLong("son_test_basarili_ms", 0);
        r.append("Test: kurulan ").append(tk > 0 ? Metinler.gunVeSaat(tk) : "-")
                .append(", gelen ").append(tb > 0 ? Metinler.gunVeSaat(tb) : "-").append('\n');
        r.append("Sayaç: ").append(Tercihler.sayacAcik(this)).append(", titreşim: ").append(SessizMod.acik(this))
                .append(" (").append(SessizMod.sure(this)).append(" dk), açılış menüsü: ").append(Tercihler.acilisMenu(this)).append('\n');
        NotificationManager nm = Kanallar.nm(this);
        if (nm != null && Build.VERSION.SDK_INT >= 26) {
            try {
                r.append("Kanallar:\n");
                for (NotificationChannel ch : nm.getNotificationChannels()) {
                    r.append("  ").append(ch.getId()).append(" önem=").append(ch.getImportance()).append('\n');
                }
            } catch (Throwable ignored) {
            }
        }
        r.append("İlk 10:\n");
        for (int i = 0; i < Math.min(10, kurulu.size()); i++) {
            Vakit v = kurulu.get(i);
            r.append("  ").append(Metinler.gunVeSaat(v.zaman)).append(' ').append(v.tur)
                    .append(v.namaz == null ? "" : "/" + v.namaz).append(' ').append(v.kanal).append('\n');
        }
        return r.toString();
    }

    private void sureSec() {
        final int[] s = SessizMod.SURELER;
        String[] ad = new String[s.length];
        int secili = 0;
        for (int i = 0; i < s.length; i++) {
            ad[i] = s[i] + " dakika";
            if (s[i] == SessizMod.sure(this)) secili = i;
        }
        new AlertDialog.Builder(this)
                .setTitle("Titreşim süresi")
                .setSingleChoiceItems(ad, secili, (d, w) -> {
                    SessizMod.ayarla(this, SessizMod.acik(this), s[w]);
                    d.dismiss();
                    hepsiniCiz();
                })
                .setNegativeButton("Vazgeç", null)
                .show();
    }

    /**
     * Eski 1.0.0 ekranına düşmeden vakit takvimi ve bildirimleri yerel motordan doğrudan yeniler.
     */
    void uygulamayiAc(boolean yenidenKur) {
        try {
            KonumVeTakvim.otomatikTazele(this);
            KonumVeTakvim.bildirimleriYenile(this, true);
            VakitSayaci.guncelle(this);
            SessizMod.planla(this);
            if (yenidenKur) {
                Toast.makeText(this, "Vakit takvimi ve bildirimler yeniden kuruldu", Toast.LENGTH_SHORT).show();
            }
            hepsiniCiz();
        } catch (Throwable ignored) {
        }
    }

    // ================================================================ görünüm yardımcıları

    int dp(int v) {
        return Math.round(TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, getResources().getDisplayMetrics()));
    }

    int temaRengi(TemaMotoru.Durum tm, int renk) {
        if (renk == BEYAZ) return tm.metin;
        if (renk == SOLUK) return tm.soluk;
        if (renk == SILIK) return tm.silik;
        if (renk == ALTIN) return tm.vurgu;
        if (renk == KOYU) return tm.birincilDugmeYaziRengi();
        if (renk == IYI) return tm.iyi;
        if (renk == KOTU) return tm.kotu;
        if (renk == UYARI) return tm.uyari;
        return renk;
    }

    TextView metin(String s, int sp, int renk, boolean kalin) {
        TemaMotoru.Durum tm = TemaMotoru.aktif(this);
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp * tm.yaziOlcegi);
        t.setTextColor(temaRengi(tm, renk));
        t.setTypeface(kalin ? Typeface.create("sans-serif-medium", Typeface.NORMAL) : Typeface.DEFAULT);
        t.setLineSpacing(0, 1.12f);
        t.setPadding(0, dp(2), 0, dp(2));
        if (tm.acik) t.setShadowLayer(0, 0, 0, 0);
        else t.setShadowLayer(dp(6), 0, dp(1), 0x66000000);
        return t;
    }

    TextView ortala(TextView t) {
        t.setGravity(Gravity.CENTER);
        return t;
    }

    TextView altBaslik(String s) {
        TextView t = metin(s.toUpperCase(Metinler.TR), 12, ALTIN, true);
        t.setLetterSpacing(0.08f);
        t.setPadding(dp(4), dp(10), 0, dp(8));
        return t;
    }

    void baslik(LinearLayout k, String s) {
        TextView t = metin(s, 16, BEYAZ, true);
        t.setTypeface(TemaMotoru.baslikTipi(this), Typeface.BOLD);
        t.setPadding(0, 0, 0, dp(8));
        k.addView(t);
    }

    Kutucuk kutucuk(String gorsel, String baslik, String alt, int renk, Runnable r) {
        Kutucuk k = new Kutucuk(this, gorsel, baslik, alt, renk);
        k.tiklaninca(r);
        return k;
    }

    LinearLayout.LayoutParams kutucukDuzeni(int g, int y, boolean ilk) {
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(dp(g), dp(y));
        lp.setMargins(ilk ? 0 : dp(10), 0, 0, 0);
        return lp;
    }

    LinearLayout cam() {
        TemaMotoru.Durum tm = TemaMotoru.aktif(this);
        boolean kompakt = TemaMotoru.KART_KOMPAKT.equals(tm.kartBicimi);
        LinearLayout k = new LinearLayout(this);
        k.setOrientation(LinearLayout.VERTICAL);
        k.setPadding(dp(kompakt ? 13 : 16), dp(kompakt ? 10 : 14), dp(kompakt ? 13 : 16), dp(kompakt ? 10 : 14));
        k.setBackground(tm.kartArkaPlani(this));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(0, 0, 0, dp(kompakt ? 9 : 12));
        k.setLayoutParams(lp);
        return k;
    }

    void basmaEfekti(View v) {
        v.setOnTouchListener((x, e) -> {
            int a = e.getActionMasked();
            if (a == MotionEvent.ACTION_DOWN) x.animate().scaleX(0.97f).scaleY(0.97f).setDuration(110).start();
            else if (a == MotionEvent.ACTION_UP || a == MotionEvent.ACTION_CANCEL)
                x.animate().scaleX(1f).scaleY(1f).setDuration(260).setInterpolator(new OvershootInterpolator(2f)).start();
            return false;
        });
    }

    TextView dugme(String s, boolean birincil, View.OnClickListener l) {
        TemaMotoru.Durum tm = TemaMotoru.aktif(this);
        TextView b = metin(s, 15, birincil ? tm.birincilDugmeYaziRengi() : tm.metin, true);
        b.setShadowLayer(0, 0, 0, 0);
        b.setGravity(Gravity.CENTER);
        b.setMinHeight(dp(48));
        b.setBackground(birincil ? tm.birincilDugme(this, 16) : tm.ikincilDugme(this, 16));
        b.setClickable(true);
        basmaEfekti(b);
        b.setOnClickListener(v -> {
            v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            l.onClick(v);
        });
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(0, dp(10), 0, 0);
        b.setLayoutParams(lp);
        return b;
    }

    LinearLayout.LayoutParams yarim(boolean sol) {
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, -2, 1f);
        lp.setMargins(sol ? 0 : dp(5), dp(10), sol ? dp(5) : 0, 0);
        return lp;
    }

    void bosluk(LinearLayout p, int d) {
        View v = new View(this);
        v.setLayoutParams(new LinearLayout.LayoutParams(1, dp(d)));
        p.addView(v);
    }

    private void satir(LinearLayout k, int seviye, String ad, String durum, String eylem, Runnable r) {
        LinearLayout s = new LinearLayout(this);
        s.setGravity(Gravity.CENTER_VERTICAL);
        s.setPadding(0, dp(6), 0, dp(6));
        int renk = seviye > 0 ? IYI : seviye == 0 ? UYARI : KOTU;
        TextView isaret = metin(seviye > 0 ? "✓" : seviye == 0 ? "!" : "✗", 17, renk, true);
        isaret.setGravity(Gravity.CENTER);
        s.addView(isaret, new LinearLayout.LayoutParams(dp(28), -2));
        LinearLayout yazi = new LinearLayout(this);
        yazi.setOrientation(LinearLayout.VERTICAL);
        yazi.addView(metin(ad, 15, BEYAZ, true));
        yazi.addView(metin(durum, 13, seviye > 0 ? SOLUK : renk, false));
        s.addView(yazi, new LinearLayout.LayoutParams(0, -2, 1f));
        if (eylem != null && r != null) {
            TextView e = metin(eylem, 14, ALTIN, true);
            e.setPadding(dp(12), dp(8), dp(4), dp(8));
            e.setOnClickListener(v -> r.run());
            s.addView(e);
        }
        k.addView(s);
    }

    interface Degisim { void degisti(boolean acik); }

    void anahtar(LinearLayout k, String ad, String aciklama, boolean acik, Degisim d) {
        final TemaMotoru.Durum tm = TemaMotoru.aktif(this);
        final int acikRenk = tm.acik ? tm.ana : tm.vurgu;
        LinearLayout s = new LinearLayout(this);
        s.setGravity(Gravity.CENTER_VERTICAL);
        s.setPadding(0, dp(8), 0, dp(8));
        LinearLayout yazi = new LinearLayout(this);
        yazi.setOrientation(LinearLayout.VERTICAL);
        yazi.addView(metin(ad, 15, BEYAZ, true));
        yazi.addView(metin(aciklama, 13, SOLUK, false));
        s.addView(yazi, new LinearLayout.LayoutParams(0, -2, 1f));
        final Switch sw = new Switch(this);
        sw.setChecked(acik);
        sw.setContentDescription(ad);
        sw.setThumbTintList(android.content.res.ColorStateList.valueOf(acik ? acikRenk : 0xFFE0E0E0));
        sw.setOnCheckedChangeListener((b, v) -> {
            b.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            sw.setThumbTintList(android.content.res.ColorStateList.valueOf(v ? acikRenk : 0xFFE0E0E0));
            d.degisti(v);
        });
        s.addView(sw);
        k.addView(s);
    }

    private String surum() {
        try {
            PackageInfo pi = getPackageManager().getPackageInfo(getPackageName(), 0);
            return pi.versionName;
        } catch (Throwable t) {
            return "?";
        }
    }
}
