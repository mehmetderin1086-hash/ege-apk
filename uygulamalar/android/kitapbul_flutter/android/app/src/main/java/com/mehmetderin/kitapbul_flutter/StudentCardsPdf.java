package com.mehmetderin.kitapbul_flutter;

import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Typeface;
import android.graphics.pdf.PdfDocument;
import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import org.json.JSONArray;
import org.json.JSONObject;

/** A4 sayfa başına 10 (2×5) öğrenci kütüphane kartı; Code128 barkod çubukları Dart'ta hesaplanır. */
final class StudentCardsPdf {
    private static final int W = 595;
    private static final int H = 842;
    private static final float KENAR = 30f;

    private StudentCardsPdf() {}

    static byte[] generate(String json) throws Exception {
        if (json.getBytes(StandardCharsets.UTF_8).length > 10 * 1024 * 1024) {
            throw new IllegalArgumentException("Kart listesi çok büyük");
        }
        JSONArray cards = new JSONArray(json);
        if (cards.length() < 1 || cards.length() > 10000) {
            throw new IllegalArgumentException("Kart listesi boş veya çok büyük");
        }
        float cw = (W - 2 * KENAR) / 2f;
        float ch = (H - 2 * KENAR) / 5f;

        Paint border = new Paint(Paint.ANTI_ALIAS_FLAG);
        border.setColor(Color.rgb(120, 130, 135));
        border.setStyle(Paint.Style.STROKE);
        border.setStrokeWidth(0.8f);
        Paint bar = new Paint();
        bar.setColor(Color.BLACK);
        bar.setAntiAlias(false);
        Paint label = new Paint(Paint.ANTI_ALIAS_FLAG);
        label.setColor(Color.rgb(35, 45, 50));
        label.setTextSize(8f);
        label.setTypeface(Typeface.create("sans-serif", Typeface.BOLD));
        Paint nameP = new Paint(label);
        nameP.setTextSize(12f);
        Paint detail = new Paint(label);
        detail.setTextSize(9f);
        detail.setTypeface(Typeface.create("sans-serif", Typeface.NORMAL));

        PdfDocument doc = new PdfDocument();
        PdfDocument.Page page = null;
        try {
            for (int index = 0; index < cards.length(); index++) {
                if (index % 10 == 0) {
                    page = doc.startPage(new PdfDocument.PageInfo.Builder(W, H, index / 10 + 1).create());
                }
                Canvas canvas = page.getCanvas();
                JSONObject card = cards.getJSONObject(index);
                float x = (index % 2) * cw + KENAR + 8f;
                float y = ((index % 10) / 2) * ch + KENAR + 8f;
                float w = cw - 16f;
                float h = ch - 16f;
                canvas.drawRect(x, y, x + w, y + h, border);
                metin(canvas, "KÜTÜPHANE KARTI", x + 10f, y + 16f, w - 20f, label);
                metin(canvas, card.getString("name"), x + 10f, y + 36f, w - 20f, nameP);
                metin(canvas, card.getString("className"), x + 10f, y + 51f, w - 20f, detail);
                String number = card.getString("number");
                if (!number.isEmpty()) metin(canvas, "No: " + number, x + 10f, y + 64f, w - 20f, detail);

                JSONArray bars = card.getJSONArray("bars");
                if (bars.length() < 1 || bars.length() > 1024) throw new IllegalArgumentException("Barkod geçersiz");
                float left = x + 18f;
                float barWidth = w - 36f;
                for (int i = 0; i < bars.length(); i++) {
                    JSONArray item = bars.getJSONArray(i);
                    if (item.length() != 2) throw new IllegalArgumentException("Barkod geçersiz");
                    double position = item.getDouble(0);
                    double unit = item.getDouble(1);
                    if (Double.isNaN(position) || Double.isInfinite(position) || Double.isNaN(unit)
                            || Double.isInfinite(unit) || position < 0 || unit <= 0 || position + unit > 1.000001) {
                        throw new IllegalArgumentException("Barkod geçersiz");
                    }
                    canvas.drawRect(left + (float) (barWidth * position), y + h - 43f,
                            left + (float) (barWidth * (position + unit)), y + h - 10f, bar);
                }
                if (index % 10 == 9 || index == cards.length() - 1) {
                    doc.finishPage(page);
                    page = null;
                }
            }
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            doc.writeTo(out);
            return out.toByteArray();
        } finally {
            if (page != null) doc.finishPage(page);
            doc.close();
        }
    }

    /** Tek satır; sığmazsa üç noktayla kısaltır. */
    private static void metin(Canvas canvas, String value, float x, float y, float max, Paint paint) {
        String clean = PdfSayfa.tekSatir(value);
        if (clean.isEmpty()) return;
        int end = Math.min(paint.breakText(clean, true, max, null), clean.length());
        if (end < clean.length() && end > 0 && Character.isHighSurrogate(clean.charAt(end - 1))) end--;
        String shown = clean.substring(0, end);
        if (end < clean.length()) {
            while (!shown.isEmpty() && paint.measureText(shown + "…") > max) {
                shown = shown.substring(0, shown.length() - 1);
            }
            shown = shown + "…";
        }
        canvas.drawText(shown, x, y, paint);
    }
}
