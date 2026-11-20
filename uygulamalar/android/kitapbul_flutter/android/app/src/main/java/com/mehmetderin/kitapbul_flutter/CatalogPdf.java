package com.mehmetderin.kitapbul_flutter;

import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Typeface;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import org.json.JSONArray;
import org.json.JSONObject;

/** Katalog listesi PDF'i (Kitaplar > PDF olarak dışa aktar). */
final class CatalogPdf {
    private CatalogPdf() {}

    static byte[] generate(String json) throws Exception {
        if (json.getBytes(StandardCharsets.UTF_8).length > 10 * 1024 * 1024) {
            throw new IllegalArgumentException("Katalog çok büyük");
        }
        final JSONArray rows = new JSONArray(json);
        if (rows.length() > 10000) throw new IllegalArgumentException("Katalog çok büyük");

        Paint body = new Paint(Paint.ANTI_ALIAS_FLAG);
        body.setColor(Color.rgb(38, 47, 52));
        body.setTextSize(11f);
        body.setTypeface(Typeface.create("sans-serif", Typeface.NORMAL));
        final Paint bold = new Paint(body);
        bold.setTextSize(13f);
        bold.setTypeface(Typeface.create("sans-serif", Typeface.BOLD));
        final Paint small = new Paint(body);
        small.setTextSize(9f);
        small.setColor(Color.rgb(90, 100, 106));

        PdfSayfa pdf = new PdfSayfa(42f, small, 17f, 53f, (canvas, margin) -> {
            canvas.drawText("Kitap Listesi", margin, 48f, bold);
            canvas.drawText(rows.length() + " kitap", margin, 66f, small);
            return 96f;
        });
        try {
            pdf.yeniSayfa();
            String[][] alanlar = {
                {"Yayınevi: ", "publisher"}, {"ISBN: ", "isbn"},
                {"Kategori: ", "category"}, {"Raf: ", "shelf"},
            };
            for (int i = 0; i < rows.length(); i++) {
                JSONObject row = rows.getJSONObject(i);
                pdf.gerekirseYeniSayfa(100f);
                pdf.satir((i + 1) + ". " + row.optString("title"), bold, 0f);
                pdf.satir(row.optString("author"), body, 12f);
                List<String> details = new ArrayList<>();
                for (String[] alan : alanlar) {
                    String value = row.optString(alan[1]);
                    if (!value.trim().isEmpty()) details.add(alan[0] + value);
                }
                details.add("Adet: " + row.optInt("quantity"));
                details.add("Uygun: " + row.optInt("available"));
                pdf.satir(String.join(" · ", details), small, 12f);
                pdf.y += 12f;
            }
            return pdf.bitir();
        } finally {
            pdf.kapat();
        }
    }
}
