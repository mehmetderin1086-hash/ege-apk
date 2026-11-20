package com.mehmetderin.secde_vakti.saglik;

import android.graphics.Canvas;
import android.graphics.ColorFilter;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.PixelFormat;
import android.graphics.Rect;
import android.graphics.RectF;
import android.graphics.drawable.Drawable;

/**
 * Saf Canvas tabanlı İslâmî geometrik ve geleneksel tezhip desenleri.
 * Hem kart/sahne arka planlarında Drawable olarak hem de yüksek çözünürlüklü
 * paylaşım kartlarında doğrudan statik çizim metoduyla kullanılır.
 */
public final class GeometrikDesen extends Drawable {

    public static final int KAPALI = 0;
    public static final int SELCUKLU_YILDIZI = 1;
    public static final int IZNIK_RUMI = 2;
    public static final int MIHRAP_KEMERI = 3;
    public static final int KISVE_KAFES = 4;
    public static final int KUBBE_HALKA = 5;

    public static final String[] ADLAR = {
            "Kapalı",
            "Selçuklu Yıldızı",
            "İznik Rûmî & Penç",
            "Osmanlı Mihrap Kemeri",
            "Kâbe Kisvesi Kafesi",
            "Kubbe Halkaları"
    };

    private final int desen;
    private final float dpBirim;
    private int renk;
    private int temelAlfa;
    private final Paint boya = new Paint(Paint.ANTI_ALIAS_FLAG);

    public GeometrikDesen(int desen, int renk, int alfa, float dpBirim) {
        this.desen = desen;
        this.renk = renk & 0x00FFFFFF;
        this.temelAlfa = Math.max(0, Math.min(255, alfa));
        this.dpBirim = Math.max(0.5f, dpBirim);
    }

    @Override
    public void draw(Canvas canvas) {
        if (desen == KAPALI || temelAlfa <= 0) return;
        Rect b = getBounds();
        if (b.width() <= 0 || b.height() <= 0) return;
        int kayit = canvas.save();
        canvas.translate(b.left, b.top);
        ciz(canvas, b.width(), b.height(), dpBirim, desen, renk, temelAlfa, boya);
        canvas.restoreToCount(kayit);
    }

    @Override
    public void setAlpha(int alpha) {
        this.temelAlfa = alpha;
        invalidateSelf();
    }

    @Override
    public void setColorFilter(ColorFilter colorFilter) {
        boya.setColorFilter(colorFilter);
        invalidateSelf();
    }

    @Override
    @SuppressWarnings("deprecation")
    public int getOpacity() {
        return PixelFormat.TRANSLUCENT;
    }

    public static void ciz(Canvas c, int w, int h, float dp, int desen, int renk, int alfa) {
        ciz(c, w, h, dp, desen, renk, alfa, new Paint(Paint.ANTI_ALIAS_FLAG));
    }

    public static void ciz(Canvas c, int w, int h, float dp, int desen, int renk, int alfa, Paint p) {
        if (desen == KAPALI || alfa <= 0 || w <= 0 || h <= 0) return;
        Paint.Style eskiStil = p.getStyle();
        int baz = (renk & 0x00FFFFFF) | (Math.min(255, alfa) << 24);
        p.setColor(baz);
        p.setStyle(Paint.Style.STROKE);
        p.setStrokeWidth(Math.max(1f, 0.9f * dp));
        p.setStrokeCap(Paint.Cap.ROUND);
        p.setStrokeJoin(Paint.Join.ROUND);

        switch (desen) {
            case SELCUKLU_YILDIZI:
                selcukluYildizi(c, w, h, dp, p, renk, alfa);
                break;
            case IZNIK_RUMI:
                iznikRumi(c, w, h, dp, p, renk, alfa);
                break;
            case MIHRAP_KEMERI:
                mihrapKemeri(c, w, h, dp, p, renk, alfa);
                break;
            case KISVE_KAFES:
                kisveKafes(c, w, h, dp, p, renk, alfa);
                break;
            case KUBBE_HALKA:
                kubbeHalka(c, w, h, dp, p, renk, alfa);
                break;
            default:
                break;
        }
        p.setStyle(eskiStil);
    }

    /** 54dp ızgarada (tek satırlarda yarım adım kaydırmalı) 8 köşeli Selçuklu yıldızı ve iç rozet. */
    private static void selcukluYildizi(Canvas c, int w, int h, float dp, Paint p, int renk, int alfa) {
        float adim = 54f * dp;
        float r = 20f * dp;
        Path kare = new Path();
        int satir = 0;
        for (float y = adim * 0.45f; y < h + adim; y += adim * 0.86f, satir++) {
            float kayma = (satir % 2 == 1) ? adim * 0.5f : 0f;
            for (float x = -adim * 0.5f + kayma; x < w + adim; x += adim) {
                sekizKoseliYildiz(kare, x, y, r);
                c.drawPath(kare, p);
                p.setAlpha(Math.max(4, alfa * 3 / 5));
                c.drawCircle(x, y, r * 0.34f, p);
                p.setAlpha(alfa);
            }
        }
    }

    private static void sekizKoseliYildiz(Path yol, float cx, float cy, float r) {
        yol.reset();
        float k = r * 0.7071f;
        yol.moveTo(cx - k, cy - k);
        yol.lineTo(cx + k, cy - k);
        yol.lineTo(cx + k, cy + k);
        yol.lineTo(cx - k, cy + k);
        yol.close();

        yol.moveTo(cx, cy - r);
        yol.lineTo(cx + r, cy);
        yol.lineTo(cx, cy + r);
        yol.lineTo(cx - r, cy);
        yol.close();
    }

    /** İznik çini üslubunda teğet kemer yayları ve merkezde 4 yapraklı penç çiçeği. */
    private static void iznikRumi(Canvas c, int w, int h, float dp, Paint p, int renk, int alfa) {
        float adim = 58f * dp;
        RectF kutu = new RectF();
        for (float y = 0; y < h + adim; y += adim) {
            for (float x = 0; x < w + adim; x += adim) {
                float r = adim * 0.5f;
                kutu.set(x - r, y - r, x + r, y + r);
                c.drawArc(kutu, 0, 90, false, p);
                c.drawArc(kutu, 180, 90, false, p);

                float mx = x + r * 0.5f;
                float my = y + r * 0.5f;
                float pr = 5.5f * dp;
                p.setAlpha(Math.max(4, alfa * 3 / 4));
                c.drawCircle(mx - pr, my, pr, p);
                c.drawCircle(mx + pr, my, pr, p);
                c.drawCircle(mx, my - pr, pr, p);
                c.drawCircle(mx, my + pr, pr, p);
                p.setStyle(Paint.Style.FILL);
                c.drawCircle(mx, my, 1.8f * dp, p);
                p.setStyle(Paint.Style.STROKE);
                p.setAlpha(alfa);
            }
        }
    }

    /** Osmanlı sivri mihrap kemeri, sütunçeler ve köşe şemseleri. */
    private static void mihrapKemeri(Canvas c, int w, int h, float dp, Paint p, int renk, int alfa) {
        float pay = Math.min(w, h) * 0.06f;
        float sol = pay, sag = w - pay;
        float ust = pay;
        float omuzY = Math.min(h * 0.42f, ust + (sag - sol) * 0.46f);
        float alt = h - pay;
        float ox = w * 0.5f;

        Path kemer = new Path();
        kemer.moveTo(sol, alt);
        kemer.lineTo(sol, omuzY);
        kemer.quadTo(sol, ust + (omuzY - ust) * 0.25f, ox, ust);
        kemer.quadTo(sag, ust + (omuzY - ust) * 0.25f, sag, omuzY);
        kemer.lineTo(sag, alt);
        c.drawPath(kemer, p);

        // İç ince kemer
        float ic = 6f * dp;
        if (sag - sol > ic * 6) {
            p.setAlpha(Math.max(4, alfa * 2 / 3));
            kemer.reset();
            kemer.moveTo(sol + ic, alt);
            kemer.lineTo(sol + ic, omuzY + ic * 0.4f);
            kemer.quadTo(sol + ic, ust + ic + (omuzY - ust) * 0.25f, ox, ust + ic * 1.1f);
            kemer.quadTo(sag - ic, ust + ic + (omuzY - ust) * 0.25f, sag - ic, omuzY + ic * 0.4f);
            kemer.lineTo(sag - ic, alt);
            c.drawPath(kemer, p);
        }

        // Köşe madalyonları
        float mr = Math.min(12f * dp, (sag - sol) * 0.08f);
        c.drawCircle(sol + mr * 1.4f, ust + mr * 1.4f, mr, p);
        c.drawCircle(sag - mr * 1.4f, ust + mr * 1.4f, mr, p);
        p.setAlpha(alfa);
    }

    /** Kâbe kisvesi esinli 45° baklava kafesi, çift şeritli zikzak ve düğüm bezemesi. */
    private static void kisveKafes(Canvas c, int w, int h, float dp, Paint p, int renk, int alfa) {
        float adim = 46f * dp;
        int maks = (int) Math.ceil((w + h) / adim) + 2;
        for (int i = -maks; i <= maks; i++) {
            float x0 = i * adim;
            c.drawLine(x0, 0, x0 + h, h, p);
            c.drawLine(x0, 0, x0 - h, h, p);
        }
        p.setStyle(Paint.Style.FILL);
        p.setColor(((renk & 0x00FFFFFF) | (Math.min(255, alfa + 10) << 24)));
        float nr = 1.9f * dp;
        for (float y = adim * 0.5f; y < h; y += adim * 0.5f) {
            boolean tek = Math.round(y / (adim * 0.5f)) % 2 == 1;
            for (float x = tek ? adim * 0.5f : 0; x < w; x += adim) {
                c.drawCircle(x, y, nr, p);
            }
        }
        p.setStyle(Paint.Style.STROKE);
        p.setColor(((renk & 0x00FFFFFF) | (Math.min(255, alfa) << 24)));
    }

    /** Mimar Sinan kubbe geometrisi esinli eşmerkezli dilimli halkalar. */
    private static void kubbeHalka(Canvas c, int w, int h, float dp, Paint p, int renk, int alfa) {
        float cx = w * 0.5f;
        float cy = h * 0.34f;
        float maksR = Math.max(w, h) * 0.72f;
        float adim = 38f * dp;
        Path yildiz = new Path();
        for (float r = adim; r <= maksR; r += adim) {
            c.drawCircle(cx, cy, r, p);
            if (r < adim * 3.2f) {
                sekizKoseliYildiz(yildiz, cx, cy, r * 0.92f);
                p.setAlpha(Math.max(4, alfa * 2 / 3));
                c.drawPath(yildiz, p);
                p.setAlpha(alfa);
            }
        }
    }
}
