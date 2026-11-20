package com.mehmetderin.secde_vakti.saglik;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.view.View;

/** Sekme simgeleri (kodla çizilir): vakit (hilal+yıldız), kıble (pusula), zikir (tesbih), takvim, menü. */
public final class Simge extends View {

    public static final int VAKIT = 0, KIBLE = 1, ZIKIR = 2, TAKVIM = 3, MENU = 4, KURAN = 5;

    private final int tur;
    private int renk = 0xCCFFFFFF;
    private final Paint boya = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Path yol = new Path();
    private final RectF r = new RectF();

    public Simge(Context c, int tur) {
        super(c);
        this.tur = tur;
        boya.setStrokeCap(Paint.Cap.ROUND);
        boya.setStrokeJoin(Paint.Join.ROUND);
    }

    public void renk(int r) {
        if (renk == r) return;
        renk = r;
        invalidate();
    }

    @Override
    protected void onDraw(Canvas c) {
        float w = getWidth(), h = getHeight(), s = Math.min(w, h);
        float cx = w / 2, cy = h / 2, u = s / 24f;
        boya.setColor(renk);
        boya.setStrokeWidth(1.8f * u);
        boya.setStyle(Paint.Style.STROKE);
        switch (tur) {
            case VAKIT: {
                // Hilal
                boya.setStyle(Paint.Style.FILL);
                yol.reset();
                yol.addCircle(cx - 1 * u, cy + 0.5f * u, 8 * u, Path.Direction.CW);
                Path kes = new Path();
                kes.addCircle(cx + 2.5f * u, cy - 1.5f * u, 7 * u, Path.Direction.CW);
                yol.op(kes, Path.Op.DIFFERENCE);
                c.drawPath(yol, boya);
                yildiz(c, cx + 6 * u, cy - 5 * u, 2.6f * u);
                break;
            }
            case KIBLE: {
                c.drawCircle(cx, cy, 9 * u, boya);
                boya.setStyle(Paint.Style.FILL);
                yol.reset();
                yol.moveTo(cx, cy - 7 * u);
                yol.lineTo(cx + 2.6f * u, cy);
                yol.lineTo(cx, cy + 7 * u);
                yol.lineTo(cx - 2.6f * u, cy);
                yol.close();
                c.drawPath(yol, boya);
                break;
            }
            case ZIKIR: {
                boya.setStyle(Paint.Style.FILL);
                int n = 9;
                for (int i = 0; i < n; i++) {
                    double a = Math.PI * 0.75 + i * (Math.PI * 1.5 / (n - 1));
                    c.drawCircle(cx + (float) Math.cos(a) * 7.5f * u, cy - 1.5f * u + (float) Math.sin(a) * 7.5f * u, 1.6f * u, boya);
                }
                // İmame ve püskül
                c.drawCircle(cx, cy + 6.8f * u, 1.9f * u, boya);
                boya.setStyle(Paint.Style.STROKE);
                c.drawLine(cx, cy + 8.5f * u, cx, cy + 11 * u, boya);
                break;
            }
            case TAKVIM: {
                r.set(cx - 9 * u, cy - 7 * u, cx + 9 * u, cy + 9 * u);
                c.drawRoundRect(r, 2.5f * u, 2.5f * u, boya);
                c.drawLine(cx - 9 * u, cy - 2 * u, cx + 9 * u, cy - 2 * u, boya);
                c.drawLine(cx - 4.5f * u, cy - 10 * u, cx - 4.5f * u, cy - 5 * u, boya);
                c.drawLine(cx + 4.5f * u, cy - 10 * u, cx + 4.5f * u, cy - 5 * u, boya);
                boya.setStyle(Paint.Style.FILL);
                for (int i = 0; i < 3; i++) for (int j = 0; j < 2; j++)
                    c.drawCircle(cx - 4.5f * u + i * 4.5f * u, cy + 2 * u + j * 4 * u, 1.1f * u, boya);
                break;
            }
            case KURAN: {
                // Açık kitap (rahle üstünde)
                yol.reset();
                yol.moveTo(cx, cy - 4 * u);
                yol.quadTo(cx - 5 * u, cy - 7.5f * u, cx - 10 * u, cy - 5.5f * u);
                yol.lineTo(cx - 10 * u, cy + 5.5f * u);
                yol.quadTo(cx - 5 * u, cy + 3.5f * u, cx, cy + 7 * u);
                yol.quadTo(cx + 5 * u, cy + 3.5f * u, cx + 10 * u, cy + 5.5f * u);
                yol.lineTo(cx + 10 * u, cy - 5.5f * u);
                yol.quadTo(cx + 5 * u, cy - 7.5f * u, cx, cy - 4 * u);
                yol.close();
                c.drawPath(yol, boya);
                c.drawLine(cx, cy - 4 * u, cx, cy + 7 * u, boya);
                c.drawLine(cx - 6 * u, cy + 10 * u, cx + 6 * u, cy + 7.5f * u, boya);
                c.drawLine(cx + 6 * u, cy + 10 * u, cx - 6 * u, cy + 7.5f * u, boya);
                break;
            }
            default: {
                boya.setStyle(Paint.Style.FILL);
                for (int i = 0; i < 2; i++) for (int j = 0; j < 2; j++) {
                    r.set(cx - 9 * u + i * 10 * u, cy - 9 * u + j * 10 * u, cx - 1 * u + i * 10 * u, cy - 1 * u + j * 10 * u);
                    c.drawRoundRect(r, 2.2f * u, 2.2f * u, boya);
                }
                break;
            }
        }
    }

    private void yildiz(Canvas c, float x, float y, float r) {
        Path p = new Path();
        for (int i = 0; i < 10; i++) {
            double a = -Math.PI / 2 + i * Math.PI / 5;
            float rr = i % 2 == 0 ? r : r * 0.45f;
            float px = x + (float) Math.cos(a) * rr, py = y + (float) Math.sin(a) * rr;
            if (i == 0) p.moveTo(px, py);
            else p.lineTo(px, py);
        }
        p.close();
        c.drawPath(p, boya);
    }
}
