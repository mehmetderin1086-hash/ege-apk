package com.mehmetderin.secde_vakti.saglik;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.DashPathEffect;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RadialGradient;
import android.graphics.RectF;
import android.graphics.Shader;
import android.graphics.Typeface;
import android.view.View;

import java.util.List;

/**
 * Güneş ve Hilâl Yörünge Arkı: günün İmsak -> Yatsı vakitlerini ufuk yayı üzerinde
 * görselleştirir; aktif anı parlayan Güneş veya Hilâl ile gösterir.
 */
public final class GokYorungeView extends View {

    private static final String[] KISA = {"İms", "Gün", "Öğl", "İkn", "Akş", "Yat"};

    private final long[] vakitler = new long[6];
    private final TemaMotoru.Durum tm;
    private long simdiMs = System.currentTimeMillis();
    private boolean hazir;

    private final Paint boya = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint yaziBoya = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Path yol = new Path();
    private final Path kesik = new Path();
    private final RectF yayKutu = new RectF();
    private final DashPathEffect tireEfekt;

    public GokYorungeView(Context c, TemaMotoru.Durum tm, List<VakitTakvimi.An> gunVakitleri) {
        super(c);
        this.tm = tm;
        float dp = getResources().getDisplayMetrics().density;
        tireEfekt = new DashPathEffect(new float[]{4f * dp, 4f * dp}, 0f);
        if (gunVakitleri != null && gunVakitleri.size() >= 6) {
            for (int i = 0; i < 6; i++) vakitler[i] = gunVakitleri.get(i).zaman;
            hazir = true;
        }
        yaziBoya.setTextAlign(Paint.Align.CENTER);
        setContentDescription("Güneş ve vakit yörüngesi");
    }

    public void guncelle(long anMs) {
        this.simdiMs = anMs;
        invalidate();
    }

    @Override
    protected void onDraw(Canvas c) {
        int w = getWidth(), h = getHeight();
        if (w <= 0 || h <= 0) return;
        float dp = getResources().getDisplayMetrics().density;

        if (!hazir) {
            yaziBoya.setColor(tm.soluk);
            yaziBoya.setTextSize(12f * dp);
            c.drawText("Vakit çizelgesi bekleniyor", w / 2f, h / 2f, yaziBoya);
            return;
        }

        float sol = 22f * dp;
        float sag = w - 22f * dp;
        float gen = sag - sol;
        float ufukY = h * 0.72f;
        float tepeY = 26f * dp;
        float rx = gen * 0.5f;
        float ry = ufukY - tepeY;
        float merkezX = (sol + sag) * 0.5f;

        long basMs = vakitler[0]; // İmsak
        long gunesMs = vakitler[1];
        long aksamMs = vakitler[4];
        long bitisMs = vakitler[5]; // Yatsı
        long toplamAralik = Math.max(1L, bitisMs - basMs);
        float genelOran = Math.max(0f, Math.min(1f, (simdiMs - basMs) / (float) toplamAralik));

        boolean gunduz = simdiMs >= gunesMs && simdiMs <= aksamMs;

        // 1. Sinüzoidal gök kubbe yayı ve dolgu (zaman yatayda eşit akar; etiketler çakışmaz)
        yol.reset();
        yol.moveTo(sol, ufukY);
        int adim = 48;
        for (int s = 0; s <= adim; s++) {
            float u = s / (float) adim;
            float px = sol + u * gen;
            float py = ufukY - (float) Math.sin(u * Math.PI) * ry;
            yol.lineTo(px, py);
        }
        yol.lineTo(sag, ufukY);
        yol.close();
        boya.setStyle(Paint.Style.FILL);
        boya.setShader(new LinearGradient(0, tepeY, 0, ufukY,
                renkAlfa(tm.vurgu, tm.acik ? 34 : 44), renkAlfa(tm.vurgu, 0), Shader.TileMode.CLAMP));
        c.drawPath(yol, boya);
        boya.setShader(null);

        // 2. Kesikli ufuk çizgisi & gelecek yay
        boya.setStyle(Paint.Style.STROKE);
        boya.setStrokeWidth(1.2f * dp);
        boya.setColor(tm.acik ? 0x3314211C : 0x33FFFFFF);
        boya.setPathEffect(tireEfekt);
        kesik.reset();
        kesik.moveTo(sol - 4f * dp, ufukY);
        kesik.lineTo(sag + 4f * dp, ufukY);
        c.drawPath(kesik, boya);

        boya.setStrokeWidth(1.8f * dp);
        boya.setColor(tm.acik ? 0x3314211C : 0x3DFFFFFF);
        yol.reset();
        for (int s = 0; s <= adim; s++) {
            float u = s / (float) adim;
            float px = sol + u * gen;
            float py = ufukY - (float) Math.sin(u * Math.PI) * ry;
            if (s == 0) yol.moveTo(px, py);
            else yol.lineTo(px, py);
        }
        c.drawPath(yol, boya);
        boya.setPathEffect(null);

        // 3. Tamamlanan parlak yörünge yayı
        if (genelOran > 0.01f) {
            boya.setStrokeWidth(2.6f * dp);
            boya.setStrokeCap(Paint.Cap.ROUND);
            boya.setShader(new LinearGradient(sol, ufukY, sag, ufukY,
                    new int[]{tm.ana, tm.vurgu, 0xFFFFE59A}, new float[]{0f, 0.55f, 1f}, Shader.TileMode.CLAMP));
            yol.reset();
            int doluAdim = Math.max(2, Math.round(adim * genelOran));
            for (int s = 0; s <= doluAdim; s++) {
                float u = (s / (float) doluAdim) * genelOran;
                float px = sol + u * gen;
                float py = ufukY - (float) Math.sin(u * Math.PI) * ry;
                if (s == 0) yol.moveTo(px, py);
                else yol.lineTo(px, py);
            }
            c.drawPath(yol, boya);
            boya.setShader(null);
        }

        // 4. Altı vakit işaretçileri ve çakışmasız etiket konumları
        float sonEtiketX = -1000f;
        float minAralik = 25f * dp;
        for (int i = 0; i < 6; i++) {
            float oran = Math.max(0f, Math.min(1f, (vakitler[i] - basMs) / (float) toplamAralik));
            float vx = sol + oran * gen;
            float vy = ufukY - (float) Math.sin(oran * Math.PI) * ry;
            boolean gecti = vakitler[i] <= simdiMs;

            boya.setStyle(Paint.Style.FILL);
            boya.setColor(gecti ? tm.vurgu : (tm.acik ? 0x6614211C : 0x66FFFFFF));
            c.drawCircle(vx, vy, (i == 1 || i == 4 ? 3.5f : 2.8f) * dp, boya);

            float ex = Math.max(vx, sonEtiketX + minAralik);
            if (ex > sag + 4f * dp) ex = sag + 4f * dp;
            sonEtiketX = ex;
            yaziBoya.setTextSize(9.5f * dp);
            yaziBoya.setTypeface(gecti ? Typeface.create("sans-serif-medium", Typeface.BOLD) : Typeface.DEFAULT);
            yaziBoya.setColor(gecti ? tm.vurgu : tm.silik);
            c.drawText(KISA[i], ex, ufukY + 14f * dp, yaziBoya);
        }

        // 5. Göksel küre (Güneş veya Hilâl)
        float ox = sol + genelOran * gen;
        float oy = ufukY - (float) Math.sin(genelOran * Math.PI) * ry;
        float tSin = 0.85f + 0.15f * (float) Math.sin(System.currentTimeMillis() / 600.0);
        int gokRenk = gunduz ? 0xFFFFD66B : 0xFFE6EDFF;

        boya.setStyle(Paint.Style.FILL);
        boya.setShader(new RadialGradient(ox, oy, 16f * dp * tSin,
                new int[]{renkAlfa(gokRenk, 165), renkAlfa(gokRenk, 0)}, null, Shader.TileMode.CLAMP));
        c.drawCircle(ox, oy, 16f * dp * tSin, boya);
        boya.setShader(null);

        boya.setColor(gokRenk);
        if (gunduz) {
            c.drawCircle(ox, oy, 6.2f * dp, boya);
        } else {
            yol.reset();
            yol.addCircle(ox, oy, 6.2f * dp, Path.Direction.CW);
            Path kes = new Path();
            kes.addCircle(ox + 2.5f * dp, oy - 1.3f * dp, 5.2f * dp, Path.Direction.CW);
            yol.op(kes, Path.Op.DIFFERENCE);
            c.drawPath(yol, boya);
        }

        // Üst köşe gündüz süresi bilgisi
        long gunduzMs = Math.max(0L, aksamMs - gunesMs);
        long saat = gunduzMs / 3_600_000L;
        long dk = (gunduzMs % 3_600_000L) / 60_000L;
        yaziBoya.setTextSize(10.5f * dp);
        yaziBoya.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        yaziBoya.setColor(tm.soluk);
        String durumYazi = (gunduz ? "☀ Gündüz " : "☽ Gece ") + " · " + saat + " sa " + dk + " dk gün ışığı";
        c.drawText(durumYazi, merkezX, 15f * dp, yaziBoya);
    }

    private static int renkAlfa(int renk, int a) {
        return (renk & 0x00FFFFFF) | (Math.max(0, Math.min(255, a)) << 24);
    }
}
