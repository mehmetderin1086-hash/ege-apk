package com.mehmetderin.kitapbul_flutter;

import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Typeface;
import java.nio.charset.StandardCharsets;
import org.json.JSONArray;
import org.json.JSONObject;

/** Ders kitabı dağıtım çizelgesi PDF'i (13 sütun). */
final class TextbookReportPdf {
    private TextbookReportPdf() {}

    static byte[] generate(String json) throws Exception {
        if (json.getBytes(StandardCharsets.UTF_8).length > 10 * 1024 * 1024) {
            throw new IllegalArgumentException("Çizelge çok büyük");
        }
        JSONObject data = new JSONObject(json);
        JSONArray headers = data.getJSONArray("headers");
        final JSONArray rows = data.getJSONArray("rows");
        JSONArray filters = data.getJSONArray("filters");
        if (headers.length() != 13 || rows.length() > 10000 || filters.length() > 10) {
            throw new IllegalArgumentException("Çizelge biçimi geçersiz");
        }

        Paint body = new Paint(Paint.ANTI_ALIAS_FLAG);
        body.setColor(Color.rgb(38, 47, 52));
        body.setTextSize(10f);
        body.setTypeface(Typeface.create("sans-serif", Typeface.NORMAL));
        final Paint bold = new Paint(body);
        bold.setTextSize(13f);
        bold.setTypeface(Typeface.create("sans-serif", Typeface.BOLD));
        final Paint small = new Paint(body);
        small.setTextSize(9f);
        small.setColor(Color.rgb(90, 100, 106));

        PdfSayfa pdf = new PdfSayfa(42f, small, 16f, 55f, (canvas, margin) -> {
            canvas.drawText("Ders Kitabı Çizelgesi", margin, 48f, bold);
            canvas.drawText(rows.length() + " kayıt", margin, 65f, small);
            return 91f;
        });
        try {
            pdf.yeniSayfa();
            for (int i = 0; i < filters.length(); i++) {
                pdf.satir(filters.getString(i), small, 0f);
            }
            pdf.y += 12f;
            for (int i = 0; i < rows.length(); i++) {
                JSONArray row = rows.getJSONArray(i);
                if (row.length() != headers.length()) {
                    throw new IllegalArgumentException("Satır sütun sayısı uyuşmuyor");
                }
                pdf.gerekirseYeniSayfa(100f);
                pdf.satir((i + 1) + ". " + row.getString(3) + " · " + row.getString(4), bold, 0f);
                for (int j = 0; j < headers.length(); j++) {
                    String value = row.getString(j);
                    if (!value.isEmpty()) pdf.satir(headers.getString(j) + ": " + value, body, 10f);
                }
                pdf.y += 12f;
            }
            return pdf.bitir();
        } finally {
            pdf.kapat();
        }
    }
}
