package com.mehmetderin.secde_vakti.saglik;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapShader;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.LinearGradient;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.graphics.RectF;
import android.graphics.Shader;
import android.graphics.Typeface;
import android.os.SystemClock;
import android.text.TextPaint;
import android.text.TextUtils;
import android.util.TypedValue;
import android.view.HapticFeedbackConstants;
import android.view.MotionEvent;
import android.view.View;
import android.view.animation.OvershootInterpolator;

/**
 * Resimli, renkli menü butonu: yuvarlak köşeli fotoğraf, fotoğraf yavaşça yakınlaşıp kayar,
 * alttan renkli geçiş, başlık ve alt yazı, basınca çöküp yaylanır, ışıltı süzülür.
 */
public final class Kutucuk extends View {

    private final String gorsel;
    private final String baslik;
    private final String alt;
    private final int renk;
    private String rozet;
    private Bitmap bitmap;
    private final Paint resim = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.FILTER_BITMAP_FLAG);
    private final Paint perde = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint kenar = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint isilti = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint rozetZemin = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final TextPaint baslikBoya = new TextPaint(Paint.ANTI_ALIAS_FLAG);
    private final TextPaint altBoya = new TextPaint(Paint.ANTI_ALIAS_FLAG);
    private final TextPaint rozetBoya = new TextPaint(Paint.ANTI_ALIAS_FLAG);
    private final Matrix matris = new Matrix();
    private final RectF kutu = new RectF();
    private final RectF rozetKutu = new RectF();
    private final long faz = (long) (Math.random() * 20000);
    private Runnable tik;

    public Kutucuk(Context c, String gorsel, String baslik, String alt, int renk) {
        super(c);
        this.gorsel = gorsel;
        this.baslik = baslik;
        this.alt = alt;
        this.renk = renk;
        baslikBoya.setColor(Color.WHITE);
        baslikBoya.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        baslikBoya.setShadowLayer(dp(4), 0, dp(1), 0xB3000000);
        altBoya.setColor(0xE8FFFFFF);
        altBoya.setShadowLayer(dp(3), 0, dp(1), 0xB3000000);
        rozetBoya.setColor(0xFFFFF3D4);
        rozetBoya.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
        kenar.setStyle(Paint.Style.STROKE);
        kenar.setStrokeWidth(dp(1.1f));
        kenar.setColor(0x52FFFFFF);
        setClickable(true);
        setFocusable(true);
        setContentDescription(baslik + (alt == null ? "" : ", " + alt));
    }

    public Kutucuk rozet(String metin) {
        this.rozet = metin;
        invalidate();
        return this;
    }

    public String baslik() {
        return baslik;
    }

    /** Tıklamada titreşim ve yaylanma; asıl işi dinleyici yapar. */
    public void tiklaninca(Runnable r) {
        tik = r;
        setOnClickListener(v -> {
            v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            if (tik != null) tik.run();
        });
    }

    @Override
    public boolean onTouchEvent(MotionEvent e) {
        int a = e.getActionMasked();
        if (a == MotionEvent.ACTION_DOWN) animate().scaleX(0.95f).scaleY(0.95f).setDuration(110).start();
        else if (a == MotionEvent.ACTION_UP || a == MotionEvent.ACTION_CANCEL)
            animate().scaleX(1f).scaleY(1f).setDuration(280).setInterpolator(new OvershootInterpolator(2.2f)).start();
        return super.onTouchEvent(e);
    }

    @Override
    protected void onSizeChanged(int w, int h, int ow, int oh) {
        super.onSizeChanged(w, h, ow, oh);
        if (bitmap == null) bitmap = Gorseller.al(getContext(), gorsel, Math.max(w, h));
        if (bitmap != null) {
            resim.setShader(new BitmapShader(bitmap, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP));
        }
        perde.setShader(new LinearGradient(0, h * 0.35f, 0, h,
                new int[]{0x00000000, (renk & 0x00FFFFFF) | 0x99000000, 0xE6000000}, new float[]{0f, 0.55f, 1f},
                Shader.TileMode.CLAMP));
        float olcu = Math.min(w, h);
        baslikBoya.setTextSize(Math.max(dp(14), Math.min(dp(19), olcu * 0.12f)));
        altBoya.setTextSize(Math.max(dp(11), Math.min(dp(13), olcu * 0.085f)));
        rozetBoya.setTextSize(Math.max(dp(10), Math.min(dp(11.5f), olcu * 0.075f)));
    }

    @Override
    protected void onDraw(Canvas c) {
        int w = getWidth(), h = getHeight();
        float r = dp(20);
        kutu.set(0, 0, w, h);
        long t = SystemClock.uptimeMillis() + faz;
        if (bitmap != null) {
            float taban = Math.max(w / (float) bitmap.getWidth(), h / (float) bitmap.getHeight());
            double a = (t % 24000L) / 24000.0 * 2 * Math.PI;
            float olcek = taban * (1.08f + 0.05f * (float) Math.sin(a));
            float bw = bitmap.getWidth() * olcek, bh = bitmap.getHeight() * olcek;
            matris.reset();
            matris.postScale(olcek, olcek);
            matris.postTranslate((w - bw) / 2f + (float) Math.cos(a) * (bw - w) * 0.3f,
                    (h - bh) / 2f + (float) Math.sin(a * 0.8) * (bh - h) * 0.3f);
            resim.getShader().setLocalMatrix(matris);
            c.drawRoundRect(kutu, r, r, resim);
        } else {
            Paint yedek = new Paint(Paint.ANTI_ALIAS_FLAG);
            yedek.setColor(renk);
            c.drawRoundRect(kutu, r, r, yedek);
        }
        c.drawRoundRect(kutu, r, r, perde);

        // Süzülen ışıltı (çapraz parlama), ~7 sn'de bir
        long d = t % 7000L;
        if (d < 1400) {
            float x = -w + (d / 1400f) * w * 2.2f;
            isilti.setShader(new LinearGradient(x, 0, x + w * 0.45f, h,
                    new int[]{0x00FFFFFF, 0x36FFFFFF, 0x00FFFFFF}, null, Shader.TileMode.CLAMP));
            c.drawRoundRect(kutu, r, r, isilti);
        }
        c.drawRoundRect(kutu, r, r, kenar);

        // Üst sağ durum rozeti (varsa)
        if (rozet != null && !rozet.isEmpty()) {
            float rw = rozetBoya.measureText(rozet) + dp(14);
            float rh = dp(20);
            float rm = dp(10);
            rozetKutu.set(w - rm - rw, rm, w - rm, rm + rh);
            rozetZemin.setStyle(Paint.Style.FILL);
            rozetZemin.setColor(0xA60B1512);
            c.drawRoundRect(rozetKutu, rh * 0.5f, rh * 0.5f, rozetZemin);
            rozetZemin.setStyle(Paint.Style.STROKE);
            rozetZemin.setStrokeWidth(dp(0.9f));
            rozetZemin.setColor(0x99F0B35A);
            c.drawRoundRect(rozetKutu, rh * 0.5f, rh * 0.5f, rozetZemin);
            Paint.FontMetrics fm = rozetBoya.getFontMetrics();
            float cy = rozetKutu.centerY() - (fm.ascent + fm.descent) * 0.5f;
            c.drawText(rozet, rozetKutu.left + dp(7), cy, rozetBoya);
        }

        float pay = dp(12);
        float y = h - pay;
        if (alt != null && !alt.isEmpty()) {
            CharSequence a = TextUtils.ellipsize(alt, altBoya, w - pay * 2, TextUtils.TruncateAt.END);
            c.drawText(a, 0, a.length(), pay, y, altBoya);
            y -= altBoya.getTextSize() * 1.25f;
        }
        CharSequence b = TextUtils.ellipsize(baslik, baslikBoya, w - pay * 2, TextUtils.TruncateAt.END);
        c.drawText(b, 0, b.length(), pay, y, baslikBoya);
        if (isShown()) postInvalidateDelayed(40);
    }

    private float dp(float v) {
        return TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, getResources().getDisplayMetrics());
    }
}
