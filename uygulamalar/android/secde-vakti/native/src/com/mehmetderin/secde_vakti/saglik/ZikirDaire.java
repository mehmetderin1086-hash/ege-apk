package com.mehmetderin.secde_vakti.saglik;

import android.content.Context;
import android.graphics.BlurMaskFilter;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RadialGradient;
import android.graphics.RectF;
import android.graphics.Shader;
import android.graphics.SweepGradient;
import android.graphics.Typeface;
import android.os.SystemClock;
import android.view.HapticFeedbackConstants;
import android.view.MotionEvent;
import android.view.View;

import java.util.ArrayList;
import java.util.List;

/**
 * Zikirmatik dairesi: dokundukça sayar. Çevresinde tesbih taneleri döner (her sayımda bir tane
 * ilerler), ilerleme halkası dolar, her dokunuşta halka dalga yayılır; hedef dolunca altın patlama
 * ve uzun titreşim.
 */
public final class ZikirDaire extends View {

    public interface Dinleyici {
        void sayildi(int sayi, boolean hedefDoldu);
    }

    private int sayi, hedef = 33;
    private Dinleyici dinleyici;
    private final Paint boya = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint yazi = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final RectF kutu = new RectF();
    private final List<long[]> dalgalar = new ArrayList<>();
    private long patlama = -1;
    private float boncukAci, boncukHedef;

    public ZikirDaire(Context c) {
        super(c);
        setLayerType(LAYER_TYPE_SOFTWARE, null);
        yazi.setTextAlign(Paint.Align.CENTER);
        setClickable(true);
        setContentDescription("Zikir saymak için dokunun");
    }

    public void ayarla(int sayi, int hedef) {
        this.sayi = sayi;
        this.hedef = Math.max(1, hedef);
        boncukHedef = sayi * 12f;
        boncukAci = boncukHedef;
        invalidate();
    }

    public void dinleyici(Dinleyici d) {
        dinleyici = d;
    }

    public int sayi() {
        return sayi;
    }

    /** Bir sayım (dokunuş ya da test). */
    public void say() {
        sayi++;
        boolean doldu = sayi % hedef == 0;
        long t = SystemClock.uptimeMillis();
        dalgalar.add(new long[]{t});
        boncukHedef += 12f;
        if (doldu) {
            patlama = t;
            performHapticFeedback(HapticFeedbackConstants.LONG_PRESS);
        } else {
            performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP);
        }
        if (dinleyici != null) dinleyici.sayildi(sayi, doldu);
        invalidate();
    }

    private float basX, basY;

    /** Parmak kalkınca ve kaydırma yapılmadıysa sayar (sayfa kaydırırken yanlış sayım olmaz). */
    @Override
    public boolean onTouchEvent(MotionEvent e) {
        switch (e.getActionMasked()) {
            case MotionEvent.ACTION_DOWN:
                basX = e.getX();
                basY = e.getY();
                animate().scaleX(0.975f).scaleY(0.975f).setDuration(70).start();
                return true;
            case MotionEvent.ACTION_UP:
                animate().scaleX(1f).scaleY(1f).setDuration(120).start();
                float esik = android.view.ViewConfiguration.get(getContext()).getScaledTouchSlop() * 2f;
                if (Math.hypot(e.getX() - basX, e.getY() - basY) <= esik) {
                    performClick();
                    say();
                }
                return true;
            case MotionEvent.ACTION_CANCEL:
                animate().scaleX(1f).scaleY(1f).setDuration(120).start();
                return true;
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
        float w = getWidth(), h = getHeight();
        float cx = w / 2, cy = h / 2, R = Math.min(w, h) / 2f * 0.80f;
        long t = SystemClock.uptimeMillis();

        // Dokunuş dalgaları
        boya.setStyle(Paint.Style.STROKE);
        for (int i = dalgalar.size() - 1; i >= 0; i--) {
            float ilerleme = (t - dalgalar.get(i)[0]) / 700f;
            if (ilerleme >= 1) { dalgalar.remove(i); continue; }
            boya.setStrokeWidth(R * 0.04f * (1 - ilerleme));
            boya.setColor(Color.argb((int) (160 * (1 - ilerleme)), 240, 179, 90));
            c.drawCircle(cx, cy, R * (0.9f + 0.35f * ilerleme), boya);
        }

        // Hedef dolunca altın patlama + 16 ışın yıldız serpilmesi
        if (patlama > 0) {
            float p = (t - patlama) / 1100f;
            if (p < 1) {
                boya.setStyle(Paint.Style.FILL);
                boya.setShader(new RadialGradient(cx, cy, R * (1 + p * 0.6f),
                        new int[]{Color.argb((int) (200 * (1 - p)), 255, 214, 130), 0x00F0B35A}, null, Shader.TileMode.CLAMP));
                c.drawCircle(cx, cy, R * (1 + p * 0.6f), boya);
                boya.setShader(null);
                for (int i = 0; i < 16; i++) {
                    double a = Math.toRadians(i * 22.5 + p * 25.0);
                    float uR = R * (0.95f + p * 0.45f);
                    float sx = cx + (float) Math.cos(a) * uR;
                    float sy = cy + (float) Math.sin(a) * uR;
                    boya.setColor(Color.argb(Math.round(220 * (1f - p)), 255, 224, 144));
                    c.drawCircle(sx, sy, R * (0.028f * (1f - p * 0.5f)), boya);
                }
            } else patlama = -1;
        }

        // Gövde
        boya.setStyle(Paint.Style.FILL);
        boya.setShader(new RadialGradient(cx, cy - R * 0.3f, R * 1.2f, new int[]{0xE6262C58, 0xF00B0E22}, null, Shader.TileMode.CLAMP));
        c.drawCircle(cx, cy, R * 0.86f, boya);
        boya.setShader(null);

        // İlerleme halkası
        float oran = (sayi % hedef) / (float) hedef;
        if (sayi > 0 && sayi % hedef == 0) oran = 1f;
        kutu.set(cx - R * 0.95f, cy - R * 0.95f, cx + R * 0.95f, cy + R * 0.95f);
        boya.setStyle(Paint.Style.STROKE);
        boya.setStrokeCap(Paint.Cap.ROUND);
        boya.setStrokeWidth(R * 0.05f);
        boya.setColor(0x33FFFFFF);
        c.drawArc(kutu, 0, 360, false, boya);
        boya.setShader(new SweepGradient(cx, cy, new int[]{0xFFC07A1E, 0xFFF0B35A, 0xFFFFE0A0, 0xFFC07A1E}, null));
        c.save();
        c.rotate(-90, cx, cy);
        if (oran > 0) c.drawArc(kutu, 0, 360 * oran, false, boya);
        c.restore();
        boya.setShader(null);

        // Dönen tesbih taneleri (33 tane)
        boncukAci += (boncukHedef - boncukAci) * 0.2f;
        boya.setStyle(Paint.Style.FILL);
        for (int i = 0; i < 33; i++) {
            double a = Math.toRadians(i * (360.0 / 33) + boncukAci - 90);
            float bx = cx + (float) Math.cos(a) * R * 1.12f, by = cy + (float) Math.sin(a) * R * 1.12f;
            boolean ust = i == 0;
            boya.setShader(new RadialGradient(bx - R * 0.015f, by - R * 0.015f, R * 0.05f,
                    new int[]{ust ? 0xFFFFF1C9 : 0xFFF6C77A, ust ? 0xFFC07A1E : 0xFF8A4E12}, null, Shader.TileMode.CLAMP));
            c.drawCircle(bx, by, ust ? R * 0.05f : R * 0.04f, boya);
        }
        boya.setShader(null);

        // Sayı ve hedef
        yazi.setColor(Color.WHITE);
        yazi.setTypeface(Typeface.create("sans-serif-light", Typeface.NORMAL));
        yazi.setTextSize(R * 0.52f);
        yazi.setShadowLayer(R * 0.04f, 0, R * 0.01f, 0x80000000);
        c.drawText(String.valueOf(sayi), cx, cy + R * 0.16f, yazi);
        yazi.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        yazi.setTextSize(R * 0.11f);
        yazi.setColor(0xFFF0B35A);
        int tur = sayi / hedef;
        c.drawText((sayi % hedef) + " / " + hedef + (tur > 0 ? "  ·  " + tur + ". tur" : ""), cx, cy + R * 0.42f, yazi);
        yazi.setColor(0x99FFFFFF);
        yazi.setTextSize(R * 0.085f);
        c.drawText("dokunun", cx, cy - R * 0.42f, yazi);

        if (!dalgalar.isEmpty() || patlama > 0 || Math.abs(boncukHedef - boncukAci) > 0.1f) postInvalidateOnAnimation();
    }
}
