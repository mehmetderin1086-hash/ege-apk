package com.mehmetderin.secde_vakti.saglik;

import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RadialGradient;
import android.graphics.RectF;
import android.graphics.Shader;
import android.graphics.Typeface;
import android.os.SystemClock;
import android.util.TypedValue;
import android.view.HapticFeedbackConstants;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewConfiguration;
import android.view.ViewParent;
import android.view.animation.OvershootInterpolator;

import java.util.Locale;

/**
 * 3B dokunsal tesbih boncuk görünümü ve 7 günlük zikir sütun grafiği.
 * Kıvrımlı ipek kaytan üzerinde gerçekçi ışık kırılımlı 7 tesbih tanesi,
 * 11 ve 33. tanelerde altın halkalı nişane / imâme ayracı, hem dokunma hem de
 * parmakla aşağı çekme etkileşimi sunar.
 */
public final class BoncukluZikirView extends View {

    public static final String[] MALZEMELER = {
            "Kehribar",
            "Zümrüt Yeşim",
            "Oltu Taşı",
            "İnci Sedef",
            "Firuze Çini"
    };

    /** Malzeme paletleri: {açık parıltı, gövde orta, koyu gölge, ip rengi, halka altını}. */
    private static final int[][] PALETLER = {
            // 0 · Kehribar (Damla bal kehribarı)
            {0xFFFFEEAA, 0xFFD98218, 0xFF542003, 0xFFD8B06A, 0xFFFFD97D},
            // 1 · Zümrüt Yeşim
            {0xFFA6F7D0, 0xFF198754, 0xFF062E1B, 0xFFC5DEC9, 0xFFEAC978},
            // 2 · Oltu Taşı (Erzurum oltusu)
            {0xFF7B8596, 0xFF212630, 0xFF050608, 0xFFB89B67, 0xFFE8C26E},
            // 3 · İnci Sedef
            {0xFFFFFFFF, 0xFFE6DDD0, 0xFF8C7F70, 0xFFDCCBB2, 0xFFD6A84E},
            // 4 · Firuze Çini (İznik firuzesi)
            {0xFFB5FAFF, 0xFF179FB0, 0xFF063C4A, 0xFFBAE4E8, 0xFFF2CC72},
    };

    public interface Dinleyici {
        void sayildi(int yeniSayi, boolean hedefDoldu);
    }

    private int sayi = 0;
    private int hedef = 33;
    private int malzeme = 0;
    private Dinleyici dinleyici;

    private float animOfset = 0f;
    private float suruklemeOfset = 0f;
    private ValueAnimator gecisAnim;
    private long altinParlamaBasi = -1L;

    private float basX, basY;
    private boolean surukleniyor = false;
    private boolean buDokunustaSayildi = false;

    private final Paint boya = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint ipBoya = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint yaziBoya = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Path ipYolu = new Path();
    private final RectF geciciKutu = new RectF();

    public BoncukluZikirView(Context c) {
        super(c);
        setClickable(true);
        setContentDescription("Tesbih boncuğu: saymak için dokunun veya aşağı çekin");
        ipBoya.setStyle(Paint.Style.STROKE);
        ipBoya.setStrokeCap(Paint.Cap.ROUND);
    }

    public void dinleyici(Dinleyici d) {
        this.dinleyici = d;
    }

    public void ayarla(int sayi, int hedef) {
        this.sayi = Math.max(0, sayi);
        this.hedef = Math.max(1, hedef);
        invalidate();
    }

    public void malzeme(int tur) {
        this.malzeme = Math.max(0, Math.min(MALZEMELER.length - 1, tur));
        invalidate();
    }

    public int malzeme() {
        return malzeme;
    }

    public int sayi() {
        return sayi;
    }

    public int hedef() {
        return hedef;
    }

    /** Bir boncuk ilerletir (dokunuş, aşağı çekme ya da programatik çağrı). */
    public void say() {
        boncukIlerlet(0f);
    }

    private void boncukIlerlet(float mevcutKayma) {
        sayi++;
        boolean hedefDoldu = (sayi % hedef == 0);
        boolean otuzUcDoldu = (sayi % 33 == 0);
        if (hedefDoldu || otuzUcDoldu) {
            if (hedefDoldu) altinParlamaBasi = SystemClock.uptimeMillis();
            performHapticFeedback(HapticFeedbackConstants.LONG_PRESS);
        } else {
            performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK);
        }
        suruklemeOfset = 0f;
        animasyonBaslat(mevcutKayma - 1f, 0f, 330L);
        if (dinleyici != null) {
            dinleyici.sayildi(sayi, hedefDoldu);
        }
        invalidate();
    }

    private void animasyonBaslat(float baslangic, float bitis, long sureMs) {
        if (gecisAnim != null) {
            gecisAnim.cancel();
        }
        animOfset = baslangic;
        gecisAnim = ValueAnimator.ofFloat(baslangic, bitis);
        gecisAnim.setDuration(sureMs);
        gecisAnim.setInterpolator(new OvershootInterpolator(1.55f));
        gecisAnim.addUpdateListener(a -> {
            animOfset = (Float) a.getAnimatedValue();
            invalidate();
        });
        gecisAnim.start();
    }

    @Override
    protected void onDetachedFromWindow() {
        if (gecisAnim != null) {
            gecisAnim.cancel();
            gecisAnim = null;
        }
        super.onDetachedFromWindow();
    }

    @Override
    protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
        int varsayilanBoy = dp(300);
        int w = resolveSize(varsayilanBoy, widthMeasureSpec);
        int h = resolveSize(varsayilanBoy, heightMeasureSpec);
        setMeasuredDimension(w, h);
    }

    @Override
    public boolean onTouchEvent(MotionEvent e) {
        int a = e.getActionMasked();
        float adimPx = Math.max(dp(36), getHeight() * 0.135f);
        float slop = ViewConfiguration.get(getContext()).getScaledTouchSlop();

        switch (a) {
            case MotionEvent.ACTION_DOWN: {
                basX = e.getX();
                basY = e.getY();
                surukleniyor = false;
                buDokunustaSayildi = false;
                suruklemeOfset = 0f;
                ViewParent p = getParent();
                if (p != null) p.requestDisallowInterceptTouchEvent(true);
                return true;
            }
            case MotionEvent.ACTION_MOVE: {
                if (buDokunustaSayildi) return true;
                float dx = e.getX() - basX;
                float dy = e.getY() - basY;
                if (!surukleniyor && Math.hypot(dx, dy) > slop) {
                    surukleniyor = true;
                }
                if (surukleniyor) {
                    float ham = dy / adimPx;
                    suruklemeOfset = Math.max(-0.22f, Math.min(0.95f, ham));
                    if (suruklemeOfset >= 0.66f) {
                        buDokunustaSayildi = true;
                        performClick();
                        boncukIlerlet(suruklemeOfset);
                    } else {
                        invalidate();
                    }
                }
                return true;
            }
            case MotionEvent.ACTION_UP: {
                if (!buDokunustaSayildi) {
                    float dx = e.getX() - basX;
                    float dy = e.getY() - basY;
                    boolean dokunus = Math.hypot(dx, dy) <= slop * 2.2f;
                    boolean kisaCekme = dy >= dp(14) && Math.abs(dx) <= Math.abs(dy) * 1.3f;
                    if (dokunus || kisaCekme) {
                        buDokunustaSayildi = true;
                        performClick();
                        boncukIlerlet(Math.max(0f, suruklemeOfset));
                    } else if (Math.abs(suruklemeOfset) > 0.01f) {
                        float kalan = suruklemeOfset;
                        suruklemeOfset = 0f;
                        animasyonBaslat(kalan, 0f, 220L);
                    }
                }
                surukleniyor = false;
                return true;
            }
            case MotionEvent.ACTION_CANCEL: {
                if (Math.abs(suruklemeOfset) > 0.01f) {
                    float kalan = suruklemeOfset;
                    suruklemeOfset = 0f;
                    animasyonBaslat(kalan, 0f, 200L);
                }
                surukleniyor = false;
                return true;
            }
            default:
                return true;
        }
    }

    @Override
    public boolean performClick() {
        return super.performClick();
    }

    @Override
    protected void onDraw(Canvas c) {
        int w = getWidth();
        int h = getHeight();
        if (w <= 0 || h <= 0) return;

        TemaMotoru.Durum tm = TemaMotoru.aktif(getContext());
        int[] palet = PALETLER[malzeme];
        long simdi = SystemClock.uptimeMillis();

        float ipMerkezX = w * 0.35f;
        float salinimX = Math.min(w * 0.068f, dp(22));
        float ustY = h * 0.05f;
        float altY = h * 0.95f;
        float bazR = Math.min(w * 0.105f, (altY - ustY) / 13.4f);

        // Hedef dolduğunda altın kutlama hâlesi
        if (altinParlamaBasi > 0L) {
            float p = (simdi - altinParlamaBasi) / 1000f;
            if (p < 1f) {
                float rH = Math.min(w, h) * (0.32f + p * 0.36f);
                boya.setStyle(Paint.Style.FILL);
                boya.setShader(new RadialGradient(ipMerkezX, h * 0.5f, rH,
                        new int[]{Color.argb((int) (185 * (1f - p)), 255, 218, 128), Color.TRANSPARENT},
                        null, Shader.TileMode.CLAMP));
                c.drawCircle(ipMerkezX, h * 0.5f, rH, boya);
                boya.setShader(null);
                postInvalidateOnAnimation();
            } else {
                altinParlamaBasi = -1L;
            }
        }

        // 1 · Kıvrımlı ipek kaytan (S-eğrisi)
        ipYolu.reset();
        int parcaSayisi = 36;
        for (int i = 0; i <= parcaSayisi; i++) {
            float t = i / (float) parcaSayisi;
            float px = ipX(t, ipMerkezX, salinimX);
            float py = ustY + t * (altY - ustY);
            if (i == 0) ipYolu.moveTo(px, py);
            else ipYolu.lineTo(px, py);
        }
        // İp gölgesi
        ipBoya.setStrokeWidth(Math.max(dp(5), bazR * 0.24f));
        ipBoya.setColor(0x55000000);
        c.save();
        c.translate(dp(2), dp(3));
        c.drawPath(ipYolu, ipBoya);
        c.restore();

        // İp ana dokusu
        ipBoya.setStrokeWidth(Math.max(dp(3.5f), bazR * 0.17f));
        ipBoya.setColor(palet[3]);
        c.drawPath(ipYolu, ipBoya);

        // İp ipek sırt parıltısı
        ipBoya.setStrokeWidth(Math.max(dp(1.2f), bazR * 0.06f));
        ipBoya.setColor(0x88FFFFFF);
        c.drawPath(ipYolu, ipBoya);

        // 2 · 7 görünür boncuk (uçlarda yumuşak giriş-çıkış için -4..+4 aralığı)
        float toplamKayma = animOfset + suruklemeOfset;
        // Önce uçtakileri, en son merkezdeki aktif taneyi çiz (derinlik sıralaması)
        int[] sira = {-4, 4, -3, 3, -2, 2, -1, 1, 0};
        for (int k : sira) {
            float u = k + toplamKayma;
            if (u < -3.85f || u > 3.85f) continue;

            float t = (u + 3.5f) / 7.0f;
            float bx = ipX(t, ipMerkezX, salinimX);
            float by = ustY + t * (altY - ustY);
            float aciDerece = ipTegetAci(t, ipMerkezX, salinimX, altY - ustY);

            // Uçlarda saydamlaşma ve hafif perspektif ölçeği
            float kenarMesafe = Math.abs(u);
            float alfaOran = kenarMesafe <= 3.05f ? 1f : Math.max(0f, 1f - (kenarMesafe - 3.05f) / 0.80f);
            float perspektif = 1.06f - 0.045f * Math.min(3.5f, kenarMesafe);
            float r = bazR * perspektif;

            int boncukNo = sayi - k;
            int mod33 = ((boncukNo % 33) + 33) % 33;
            boolean imame = (mod33 == 0);
            boolean nisane = !imame && (mod33 == 11 || mod33 == 22);

            boncukCiz(c, bx, by, r, aciDerece, palet, imame, nisane, alfaOran, k == 0);
        }

        // 3 · Sağ tarafta net sayaç ve malzeme rozeti
        sayacRozetiCiz(c, w, h, tm, palet);
    }

    private static float ipX(float t, float merkezX, float salinimX) {
        return merkezX + (float) Math.sin((t - 0.5f) * Math.PI * 1.45f) * salinimX;
    }

    private static float ipTegetAci(float t, float merkezX, float salinimX, float boyY) {
        float dt = 0.01f;
        float dx = ipX(t + dt, merkezX, salinimX) - ipX(t - dt, merkezX, salinimX);
        float dy = 2f * dt * boyY;
        return (float) Math.toDegrees(Math.atan2(dx, dy));
    }

    private void boncukCiz(Canvas c, float bx, float by, float r, float ipAci,
                           int[] palet, boolean imame, boolean nisane, float alfaOran, boolean merkez) {
        int alfa = Math.max(0, Math.min(255, Math.round(255 * alfaOran)));
        if (alfa <= 4) return;

        int acikRenk = alfaUygula(palet[0], alfa);
        int ortaRenk = alfaUygula(palet[1], alfa);
        int koyuRenk = alfaUygula(palet[2], alfa);
        int altinRenk = alfaUygula(palet[4], alfa);
        int koyuAltin = alfaUygula(0xFF8C5B12, alfa);

        c.save();
        c.translate(bx, by);
        c.rotate(-ipAci);

        float rx = imame ? r * 0.94f : nisane ? r * 0.88f : r;
        float ry = imame ? r * 1.36f : nisane ? r * 1.18f : r;

        // Alt düşen gölge
        boya.setStyle(Paint.Style.FILL);
        float golgeR = Math.max(rx, ry) * 1.18f;
        boya.setShader(new RadialGradient(r * 0.18f, ry * 0.34f, golgeR,
                new int[]{Color.argb(Math.round(125 * alfaOran), 0, 0, 0), Color.TRANSPARENT},
                new float[]{0.25f, 1f}, Shader.TileMode.CLAMP));
        geciciKutu.set(-rx * 1.05f + r * 0.16f, -ry * 0.95f + ry * 0.30f,
                rx * 1.25f + r * 0.16f, ry * 1.25f + ry * 0.30f);
        c.drawOval(geciciKutu, boya);
        boya.setShader(null);

        // Merkez boncuk için zarif vurgu hâlesi
        if (merkez) {
            boya.setShader(new RadialGradient(0, 0, Math.max(rx, ry) * 1.45f,
                    new int[]{alfaUygula(palet[4], Math.round(62 * alfaOran)), Color.TRANSPARENT},
                    null, Shader.TileMode.CLAMP));
            c.drawCircle(0, 0, Math.max(rx, ry) * 1.45f, boya);
            boya.setShader(null);
        }

        // 3 duraklı eksen dışı RadialGradient ile gerçekçi 3B küre / nişane gövdesi
        float isikX = -rx * 0.34f;
        float isikY = -ry * 0.34f;
        float gradR = Math.max(rx, ry) * 1.42f;
        boya.setShader(new RadialGradient(isikX, isikY, gradR,
                new int[]{acikRenk, ortaRenk, koyuRenk},
                new float[]{0.04f, 0.52f, 1.0f},
                Shader.TileMode.CLAMP));
        geciciKutu.set(-rx, -ry, rx, ry);
        c.drawOval(geciciKutu, boya);
        boya.setShader(null);

        // Alt kenar geri yansıma (rim light)
        boya.setStyle(Paint.Style.STROKE);
        boya.setStrokeWidth(Math.max(1f, r * 0.055f));
        boya.setColor(Color.argb(Math.round(52 * alfaOran),
                Color.red(palet[0]), Color.green(palet[0]), Color.blue(palet[0])));
        geciciKutu.set(-rx * 0.90f, -ry * 0.90f, rx * 0.90f, ry * 0.90f);
        c.drawArc(geciciKutu, 25f, 115f, false, boya);

        // 11. ve 33. boncuklar için işlemeli altın nişane / imâme halkaları
        if (imame || nisane) {
            boya.setStyle(Paint.Style.STROKE);
            boya.setStrokeWidth(Math.max(dp(2), r * (imame ? 0.13f : 0.10f)));
            boya.setShader(new LinearGradient(-rx, 0, rx, 0,
                    new int[]{koyuAltin, altinRenk, alfaUygula(0xFFFFF6D6, alfa), altinRenk, koyuAltin},
                    null, Shader.TileMode.CLAMP));
            // Orta altın kuşak
            c.drawLine(-rx * 0.95f, 0f, rx * 0.95f, 0f, boya);
            if (imame) {
                // İmâme çift sırma bilezik + merkez mücevher
                boya.setStrokeWidth(Math.max(dp(1.3f), r * 0.075f));
                c.drawLine(-rx * 0.80f, -ry * 0.36f, rx * 0.80f, -ry * 0.36f, boya);
                c.drawLine(-rx * 0.80f, ry * 0.36f, rx * 0.80f, ry * 0.36f, boya);
                boya.setShader(null);
                boya.setStyle(Paint.Style.FILL);
                boya.setColor(alfaUygula(0xFFFFF3C4, alfa));
                c.drawCircle(0f, 0f, r * 0.16f, boya);
                boya.setStyle(Paint.Style.STROKE);
                boya.setStrokeWidth(Math.max(1f, r * 0.06f));
                boya.setColor(altinRenk);
                c.drawOval(new RectF(-rx, -ry, rx, ry), boya);
            } else {
                boya.setShader(null);
                boya.setStyle(Paint.Style.STROKE);
                boya.setStrokeWidth(Math.max(1f, r * 0.05f));
                boya.setColor(altinRenk);
                c.drawOval(new RectF(-rx, -ry, rx, ry), boya);
            }
            boya.setShader(null);
        }

        // İp delikleri (üst ve alt kutuplarda altın yüksüklü delik detayı)
        boya.setStyle(Paint.Style.FILL);
        float delikRx = rx * 0.20f;
        float delikRy = rx * 0.09f;
        for (float kutup : new float[]{-ry * 0.93f, ry * 0.93f}) {
            boya.setColor(altinRenk);
            geciciKutu.set(-delikRx * 1.38f, kutup - delikRy * 1.38f, delikRx * 1.38f, kutup + delikRy * 1.38f);
            c.drawOval(geciciKutu, boya);

            boya.setColor(Color.argb(Math.round(215 * alfaOran), 12, 8, 4));
            geciciKutu.set(-delikRx, kutup - delikRy, delikRx, kutup + delikRy);
            c.drawOval(geciciKutu, boya);
        }

        // Sol-üst parlak speküler ışık yansıması (glint)
        c.save();
        c.translate(-rx * 0.33f, -ry * 0.36f);
        c.rotate(-28f);
        boya.setStyle(Paint.Style.FILL);
        boya.setColor(Color.argb(Math.round(168 * alfaOran), 255, 255, 255));
        geciciKutu.set(-rx * 0.24f, -ry * 0.12f, rx * 0.24f, ry * 0.12f);
        c.drawOval(geciciKutu, boya);
        boya.setColor(Color.argb(Math.round(230 * alfaOran), 255, 255, 255));
        c.drawCircle(-rx * 0.06f, -ry * 0.02f, rx * 0.07f, boya);
        c.restore();

        c.restore();
    }

    private void sayacRozetiCiz(Canvas c, int w, int h, TemaMotoru.Durum tm, int[] palet) {
        float sol = w * 0.56f;
        float sag = w - dp(10);
        if (sag - sol < dp(96)) {
            sol = Math.max(w * 0.50f, sag - dp(112));
        }
        float merkezX = (sol + sag) * 0.5f;
        float ust = h * 0.20f;
        float alt = h * 0.80f;
        float rKart = dp(20);

        // Yarı saydam cam kart
        geciciKutu.set(sol, ust, sag, alt);
        boya.setStyle(Paint.Style.FILL);
        boya.setColor(tm.acik ? 0xE6FFFFFF : 0xB80E1424);
        c.drawRoundRect(geciciKutu, rKart, rKart, boya);

        boya.setStyle(Paint.Style.STROKE);
        boya.setStrokeWidth(Math.max(1f, dp(1)));
        boya.setColor(tm.acik ? 0x3314211C : 0x40FFFFFF);
        c.drawRoundRect(geciciKutu, rKart, rKart, boya);

        // Üst malzeme etiketi
        yaziBoya.setTextAlign(Paint.Align.CENTER);
        yaziBoya.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        yaziBoya.setTextSize(sp(11.5f));
        yaziBoya.setColor(tm.acik ? tm.ana : palet[4]);
        c.drawText(MALZEMELER[malzeme], merkezX, ust + dp(24), yaziBoya);

        // Büyük sayaç
        yaziBoya.setTypeface(Typeface.create("sans-serif-light", Typeface.BOLD));
        String sayiMetni = String.valueOf(sayi);
        float sayiSp = sayi >= 10000 ? 28f : sayi >= 1000 ? 33f : 38f;
        yaziBoya.setTextSize(sp(sayiSp));
        yaziBoya.setColor(tm.metin);
        c.drawText(sayiMetni, merkezX, (ust + alt) * 0.5f + dp(4), yaziBoya);

        // sayi / hedef satırı
        int mod = sayi % hedef;
        int gosterilen = (sayi > 0 && mod == 0) ? hedef : mod;
        yaziBoya.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        yaziBoya.setTextSize(sp(13.5f));
        yaziBoya.setColor(tm.vurgu);
        c.drawText(sayi + " / " + hedef, merkezX, (ust + alt) * 0.5f + dp(26), yaziBoya);

        // Mini ilerleme çubuğu
        float cubukSol = sol + dp(14);
        float cubukSag = sag - dp(14);
        float cubukY = alt - dp(34);
        float cubukYuk = dp(6);
        geciciKutu.set(cubukSol, cubukY, cubukSag, cubukY + cubukYuk);
        boya.setStyle(Paint.Style.FILL);
        boya.setColor(tm.acik ? 0x2214211C : 0x28FFFFFF);
        c.drawRoundRect(geciciKutu, cubukYuk, cubukYuk, boya);

        float oran = gosterilen / (float) hedef;
        if (oran > 0f) {
            geciciKutu.set(cubukSol, cubukY, cubukSol + (cubukSag - cubukSol) * Math.min(1f, oran), cubukY + cubukYuk);
            boya.setShader(new LinearGradient(cubukSol, cubukY, cubukSag, cubukY,
                    new int[]{tm.vurgu, tm.ana}, null, Shader.TileMode.CLAMP));
            c.drawRoundRect(geciciKutu, cubukYuk, cubukYuk, boya);
            boya.setShader(null);
        }

        // Alt ipucu / devir bilgisi
        int devir = sayi / hedef;
        yaziBoya.setTypeface(Typeface.DEFAULT);
        yaziBoya.setTextSize(sp(10.5f));
        yaziBoya.setColor(tm.silik);
        String altMetin = devir > 0 ? (devir + ". devir  ·  Aşağı çek") : "Aşağı çek / dokun";
        c.drawText(altMetin, merkezX, alt - dp(12), yaziBoya);
    }

    private static int alfaUygula(int renk, int alfa) {
        int mevcut = Color.alpha(renk);
        int yeni = (mevcut * alfa) / 255;
        return (renk & 0x00FFFFFF) | (Math.max(0, Math.min(255, yeni)) << 24);
    }

    private int dp(float v) {
        return Math.round(TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, getResources().getDisplayMetrics()));
    }

    private float sp(float v) {
        return TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, v, getResources().getDisplayMetrics());
    }

    // ========================================================================
    // 7 Günlük Zikir Sütun Grafiği
    // ========================================================================

    /** Son 7 günün zikir sayılarını aktif tema renkleriyle yuvarlatılmış sütun grafik olarak çizer. */
    public static final class ZikirGrafikView extends View {

        private int[] degerler = new int[7];
        private String[] etiketler = {"", "", "", "", "", "", "Bugün"};
        private final Paint boya = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint yazi = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final RectF kutu = new RectF();

        public ZikirGrafikView(Context c) {
            super(c);
            yazi.setTextAlign(Paint.Align.CENTER);
        }

        public ZikirGrafikView(Context c, int[] degerler, String[] etiketler) {
            this(c);
            veri(degerler, etiketler);
        }

        public void veri(int[] degerler, String[] etiketler) {
            if (degerler != null) {
                this.degerler = new int[7];
                for (int i = 0; i < Math.min(7, degerler.length); i++) {
                    this.degerler[i] = Math.max(0, degerler[i]);
                }
            }
            if (etiketler != null) {
                this.etiketler = new String[7];
                for (int i = 0; i < 7; i++) {
                    this.etiketler[i] = i < etiketler.length && etiketler[i] != null ? etiketler[i] : "";
                }
            }
            invalidate();
        }

        public void ayarla(int[] degerler, String[] etiketler) {
            veri(degerler, etiketler);
        }

        @Override
        protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
            int varsayilanYuk = Math.round(TypedValue.applyDimension(
                    TypedValue.COMPLEX_UNIT_DIP, 152, getResources().getDisplayMetrics()));
            int w = resolveSize(varsayilanYuk * 2, widthMeasureSpec);
            int h = resolveSize(varsayilanYuk, heightMeasureSpec);
            setMeasuredDimension(w, h);
        }

        @Override
        protected void onDraw(Canvas c) {
            int w = getWidth();
            int h = getHeight();
            if (w <= 0 || h <= 0) return;

            TemaMotoru.Durum tm = TemaMotoru.aktif(getContext());
            float yogunluk = getResources().getDisplayMetrics().density;
            float olcekSp = getResources().getDisplayMetrics().scaledDensity;

            float ustBosluk = 24f * yogunluk;
            float altBosluk = 26f * yogunluk;
            float tabanY = h - altBosluk;
            float maksYuk = Math.max(20f * yogunluk, tabanY - ustBosluk);

            int tepe = 0;
            for (int d : degerler) if (d > tepe) tepe = d;
            if (tepe <= 0) tepe = 33;

            // İnce taban ve orta kılavuz çizgileri
            boya.setStyle(Paint.Style.STROKE);
            boya.setStrokeWidth(Math.max(1f, yogunluk * 0.8f));
            boya.setColor(tm.acik ? 0x1E14211C : 0x22FFFFFF);
            c.drawLine(8f * yogunluk, tabanY, w - 8f * yogunluk, tabanY, boya);
            c.drawLine(8f * yogunluk, ustBosluk + maksYuk * 0.5f, w - 8f * yogunluk, ustBosluk + maksYuk * 0.5f, boya);

            float hucreGen = w / 7f;
            float sutunGen = Math.min(hucreGen * 0.50f, 26f * yogunluk);
            float yaricap = sutunGen * 0.45f;

            for (int i = 0; i < 7; i++) {
                float cx = hucreGen * (i + 0.5f);
                int deger = i < degerler.length ? degerler[i] : 0;
                boolean bugun = (i == 6);

                // Arka plan sütun yuvası
                boya.setStyle(Paint.Style.FILL);
                boya.setShader(null);
                boya.setColor(tm.acik ? 0x1214211C : 0x16FFFFFF);
                kutu.set(cx - sutunGen * 0.5f, ustBosluk, cx + sutunGen * 0.5f, tabanY);
                c.drawRoundRect(kutu, yaricap, yaricap, boya);

                if (deger > 0) {
                    float oran = Math.min(1f, deger / (float) tepe);
                    float sutunYuk = Math.max(sutunGen * 0.65f, maksYuk * oran);
                    float ustY = tabanY - sutunYuk;
                    kutu.set(cx - sutunGen * 0.5f, ustY, cx + sutunGen * 0.5f, tabanY);

                    int ustRenk = bugun ? tm.vurgu : TemaMotoru.karistir(tm.vurgu, tm.ana, 0.25f);
                    int altRenk = bugun ? TemaMotoru.karistir(tm.ana, tm.vurguKoyu, 0.35f) : tm.ana;
                    boya.setShader(new LinearGradient(cx, ustY, cx, tabanY, ustRenk, altRenk, Shader.TileMode.CLAMP));
                    c.drawRoundRect(kutu, yaricap, yaricap, boya);
                    boya.setShader(null);

                    // Sıfırdan büyük sütunların üstünde sayı etiketi
                    yazi.setTypeface(Typeface.create("sans-serif-medium", bugun ? Typeface.BOLD : Typeface.NORMAL));
                    yazi.setTextSize(10.5f * olcekSp);
                    yazi.setColor(bugun ? tm.vurgu : tm.metin);
                    c.drawText(degerBicimle(deger), cx, Math.max(12f * yogunluk, ustY - 5f * yogunluk), yazi);
                } else {
                    // Sıfır günler için zarif nokta izi
                    boya.setColor(tm.acik ? 0x2E14211C : 0x33FFFFFF);
                    kutu.set(cx - sutunGen * 0.5f, tabanY - 4f * yogunluk, cx + sutunGen * 0.5f, tabanY);
                    c.drawRoundRect(kutu, yaricap, yaricap, boya);
                }

                // Gün etiketi
                String etiket = i < etiketler.length ? etiketler[i] : "";
                yazi.setTypeface(Typeface.create("sans-serif-medium", bugun ? Typeface.BOLD : Typeface.NORMAL));
                yazi.setTextSize(11f * olcekSp);
                yazi.setColor(bugun ? tm.vurgu : tm.soluk);
                c.drawText(etiket, cx, tabanY + 17f * yogunluk, yazi);
            }
        }

        private static String degerBicimle(int v) {
            if (v >= 10000) {
                return String.format(new Locale("tr", "TR"), "%.1fB", v / 1000f);
            }
            return String.format(new Locale("tr", "TR"), "%,d", v);
        }
    }
}
