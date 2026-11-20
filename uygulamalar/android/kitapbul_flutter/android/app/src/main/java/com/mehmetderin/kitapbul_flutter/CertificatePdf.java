package com.mehmetderin.kitapbul_flutter;

import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Typeface;
import android.graphics.pdf.PdfDocument;
import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import org.json.JSONObject;

/** Okuma şampiyonları için yatay A4 başarı sertifikası. */
final class CertificatePdf {
    private static final int W = 842;
    private static final int H = 595;

    private CertificatePdf() {}

    static byte[] generate(String json) throws Exception {
        if (json.getBytes(StandardCharsets.UTF_8).length > 16384) {
            throw new IllegalArgumentException("Sertifika verisi çok büyük");
        }
        JSONObject data = new JSONObject(json);
        String name = PdfSayfa.tekSatir(data.getString("name"));
        String klass = PdfSayfa.tekSatir(data.getString("className"));
        int count = data.getInt("books");
        if (name.isEmpty() || name.length() > 240 || klass.length() > 120 || count < 0) {
            throw new IllegalArgumentException("Sertifika bilgisi geçersiz");
        }

        PdfDocument doc = new PdfDocument();
        PdfDocument.Page page = null;
        try {
            page = doc.startPage(new PdfDocument.PageInfo.Builder(W, H, 1).create());
            Canvas c = page.getCanvas();
            Paint frame = new Paint(Paint.ANTI_ALIAS_FLAG);
            frame.setColor(Color.rgb(82, 72, 140));
            frame.setStyle(Paint.Style.STROKE);
            frame.setStrokeWidth(3f);
            Paint title = new Paint(Paint.ANTI_ALIAS_FLAG);
            title.setColor(Color.rgb(48, 39, 94));
            title.setTextSize(30f);
            title.setTextAlign(Paint.Align.CENTER);
            title.setTypeface(Typeface.create("sans-serif", Typeface.BOLD));
            Paint nameP = new Paint(title);
            nameP.setColor(Color.rgb(44, 54, 66));
            nameP.setTextSize(24f);
            Paint body = new Paint(title);
            body.setColor(Color.rgb(65, 75, 83));
            body.setTextSize(17f);
            body.setTypeface(Typeface.create("sans-serif", Typeface.NORMAL));

            c.drawColor(Color.WHITE);
            c.drawRoundRect(28f, 28f, W - 28f, H - 28f, 14f, 14f, frame);
            c.drawText("OKUMA BAŞARI SERTİFİKASI", W / 2f, 112f, title);
            c.drawText("Bu sertifika", W / 2f, 160f, body);
            float afterName = ortaliSatirlar(c, name, nameP, 205f, W - 140f);
            float afterClass = ortaliSatirlar(c, klass.isEmpty() ? "Sınıf belirtilmemiş" : klass, body, afterName + 12f, W - 140f);
            if (afterClass >= 425f) throw new IllegalArgumentException("Sertifika metni çok uzun");
            c.drawText(count + " kitap okuma başarısı için verilmiştir.", W / 2f, afterClass + 37f, body);
            c.drawText("Kitap Bul", W / 2f, 525f, body);
            doc.finishPage(page);
            page = null;
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            doc.writeTo(out);
            return out.toByteArray();
        } finally {
            if (page != null) doc.finishPage(page);
            doc.close();
        }
    }

    private static float ortaliSatirlar(Canvas c, String text, Paint paint, float firstY, float maxWidth) {
        String rest = text;
        float y = firstY;
        int lines = 0;
        while (!rest.isEmpty()) {
            if (++lines > 8) throw new IllegalArgumentException("Sertifika metni çok uzun");
            int count = PdfSayfa.kirilmaNoktasi(rest, paint, maxWidth);
            c.drawText(rest.substring(0, count), W / 2f, y, paint);
            rest = PdfSayfa.ltrim(rest.substring(count));
            y += paint.getTextSize() + 9f;
        }
        return y;
    }
}
