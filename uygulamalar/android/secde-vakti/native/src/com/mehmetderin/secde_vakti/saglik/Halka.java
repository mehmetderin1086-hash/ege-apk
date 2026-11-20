package com.mehmetderin.secde_vakti.saglik;

import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.BlurMaskFilter;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.graphics.SweepGradient;
import android.view.View;
import android.view.animation.DecelerateInterpolator;

/**
 * Dairesel ilerleme halkası: önceki vakitten sıradaki vakte geçen sürenin oranı.
 *  - 60 radial kadran çentiği (ilerleyen kısım vurgulu)
 *  - Dış mekânsal ışık hâlesi ve acil vakit son 15 dk uyarısı
 *  - Uçta nabız gibi parlayan yıldız noktası
 */
public final class Halka extends View {

    private float oran;
    private float gorunen;
    private boolean acilMod;
    private final Paint iz = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint centik = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint yay = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint nokta = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint parilti = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final RectF kutu = new RectF();
    private int renk1 = 0xFFF0B35A, renk2 = 0xFFFFE6B0;
    private ValueAnimator giris;

    public Halka(Context c) {
        super(c);
        setLayerType(LAYER_TYPE_SOFTWARE, null); // BlurMaskFilter için
        iz.setStyle(Paint.Style.STROKE);
        iz.setColor(0x33FFFFFF);
        centik.setStyle(Paint.Style.STROKE);
        centik.setStrokeCap(Paint.Cap.ROUND);
        yay.setStyle(Paint.Style.STROKE);
        yay.setStrokeCap(Paint.Cap.ROUND);
        nokta.setColor(Color.WHITE);
        parilti.setColor(0xFFF0B35A);
    }

    public void renkler(int r1, int r2) {
        renk1 = r1;
        renk2 = r2;
        parilti.setColor(r1);
        invalidate();
    }

    public void uyariModu(boolean acil) {
        this.acilMod = acil;
        invalidate();
    }

    public void izRengi(int r) {
        iz.setColor(r);
        invalidate();
    }

    /** Oranı ayarlar (0..1); ilk çağrıda sıfırdan dolarak canlanır. */
    public void oran(float o, boolean canlandir) {
        oran = Math.max(0f, Math.min(1f, o));
        if (canlandir) {
            if (giris != null) giris.cancel();
            giris = ValueAnimator.ofFloat(0f, oran);
            giris.setDuration(1400);
            giris.setInterpolator(new DecelerateInterpolator(2.2f));
            giris.addUpdateListener(a -> {
                gorunen = (float) a.getAnimatedValue();
                invalidate();
            });
            giris.start();
        } else if (giris == null || !giris.isRunning()) {
            gorunen = oran;
            invalidate();
        }
    }

    @Override
    protected void onDraw(Canvas c) {
        float w = getWidth(), h = getHeight();
        float min = Math.min(w, h);
        float cx = w / 2f, cy = h / 2f;
        float kalinlik = min * 0.044f;
        float pay = kalinlik * 2.0f;
        kutu.set(pay, pay, w - pay, h - pay);
        float yariCap = kutu.width() / 2f;
        float aci = 360f * gorunen;
        long t = System.currentTimeMillis();
        float nabiz = 0.72f + 0.28f * (float) Math.sin(t / (acilMod ? 240.0 : 420.0));

        // 1. Dış ambient hâle + son dakika uyarısı
        parilti.setStyle(Paint.Style.STROKE);
        parilti.setStrokeWidth(kalinlik * (acilMod ? 1.8f : 1.15f));
        parilti.setMaskFilter(new BlurMaskFilter(kalinlik * 1.6f, BlurMaskFilter.Blur.NORMAL));
        parilti.setColor(renk1);
        parilti.setAlpha(Math.round((acilMod ? 130 : 58) * nabiz));
        c.drawCircle(cx, cy, yariCap, parilti);
        parilti.setStyle(Paint.Style.FILL);

        // 2. 60 radyal kadran çentiği
        int aktifCentik = Math.round(gorunen * 60f);
        for (int i = 0; i < 60; i++) {
            boolean buyuk = (i % 5 == 0);
            double radC = Math.toRadians(-90 + i * 6.0);
            float disR = yariCap - kalinlik * 0.85f;
            float icR = disR - kalinlik * (buyuk ? 0.55f : 0.30f);
            centik.setStrokeWidth(buyuk ? Math.max(2f, kalinlik * 0.17f) : Math.max(1f, kalinlik * 0.10f));
            if (i <= aktifCentik) {
                centik.setColor(renk1);
                centik.setAlpha(buyuk ? 185 : 105);
            } else {
                centik.setColor(iz.getColor());
                centik.setAlpha(buyuk ? 95 : 52);
            }
            c.drawLine(
                    cx + (float) Math.cos(radC) * icR, cy + (float) Math.sin(radC) * icR,
                    cx + (float) Math.cos(radC) * disR, cy + (float) Math.sin(radC) * disR, centik);
        }

        // 3. Arka plan halkası ve dolan ilerleme yayı
        iz.setStrokeWidth(kalinlik);
        c.drawArc(kutu, 0, 360, false, iz);

        yay.setStrokeWidth(kalinlik);
        SweepGradient g = new SweepGradient(cx, cy, new int[]{renk2, renk1, renk1}, new float[]{0f, 0.6f, 1f});
        android.graphics.Matrix m = new android.graphics.Matrix();
        m.setRotate(-90, cx, cy);
        g.setLocalMatrix(m);
        yay.setShader(g);
        if (aci > 0.5f) c.drawArc(kutu, -90, aci, false, yay);

        // 4. Uçtaki parlayan kuyruklu nokta
        double rad = Math.toRadians(-90 + aci);
        float x = (float) (cx + yariCap * Math.cos(rad));
        float y = (float) (cy + yariCap * Math.sin(rad));
        parilti.setColor(renk1);
        parilti.setMaskFilter(new BlurMaskFilter(kalinlik * 1.45f, BlurMaskFilter.Blur.NORMAL));
        parilti.setAlpha((int) (215 * nabiz));
        c.drawCircle(x, y, kalinlik * 1.32f, parilti);
        c.drawCircle(x, y, kalinlik * 0.58f, nokta);
        if (isShown()) postInvalidateDelayed(50);
    }
}
