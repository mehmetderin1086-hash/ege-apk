package com.mehmetderin.kitapbul_flutter;

import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Typeface;
import java.nio.charset.StandardCharsets;
import org.json.JSONArray;
import org.json.JSONObject;

/** Envanter sayım tutanağı PDF'i. */
final class InventoryPdf {
    private InventoryPdf() {}

    static byte[] generate(String json) throws Exception {
        if (json.getBytes(StandardCharsets.UTF_8).length > 10 * 1024 * 1024) {
            throw new IllegalArgumentException("Sayım çok büyük");
        }
        JSONObject data = new JSONObject(json);
        JSONArray rows = data.getJSONArray("rows");
        JSONArray unknown = data.getJSONArray("unknown");
        if (rows.length() > 10000 || unknown.length() > 100000) {
            throw new IllegalArgumentException("Sayım çok büyük");
        }

        Paint body = new Paint(Paint.ANTI_ALIAS_FLAG);
        body.setColor(Color.rgb(38, 47, 52));
        body.setTextSize(10f);
        body.setTypeface(Typeface.create("sans-serif", Typeface.NORMAL));
        final Paint bold = new Paint(body);
        bold.setTextSize(13f);
        bold.setTypeface(Typeface.create("sans-serif", Typeface.BOLD));
        Paint small = new Paint(body);
        small.setTextSize(9f);
        small.setColor(Color.rgb(90, 100, 106));

        PdfSayfa pdf = new PdfSayfa(42f, small, 16f, 55f, (canvas, margin) -> {
            canvas.drawText("Envanter Sayım Tutanağı", margin, 48f, bold);
            return 74f;
        });
        try {
            pdf.yeniSayfa();
            pdf.satir("Sayım: " + data.getString("name"), bold, 0f);
            pdf.satir("Konum: " + data.optString("location", "Tümü"), body, 0f);
            pdf.satir("Görevli: " + data.getString("operator") + " · Başlangıç: " + data.getString("startedAt"), body, 0f);
            pdf.satir("Beklenen stok sayım başlangıcındaki kayıttır. ISBN ve elle sayılan nüshaların kimliği doğrulanmış değildir.", small, 0f);
            pdf.y += 10f;
            for (int i = 0; i < rows.length(); i++) {
                JSONObject row = rows.getJSONObject(i);
                pdf.gerekirseYeniSayfa(110f);
                pdf.satir((i + 1) + ". " + row.getString("title") + " · " + row.getString("author"), bold, 0f);
                pdf.satir("ISBN: " + row.getString("isbn"), body, 10f);
                pdf.satir("Beklenen: " + row.getInt("expected") + " · Sayılan: " + row.getInt("count")
                        + " · Fark: " + row.getInt("difference"), body, 10f);
                pdf.satir("Kimlikli: " + row.getInt("identified") + " · ISBN: " + row.getInt("isbnCount")
                        + " · Elle: " + row.getInt("manual"), body, 10f);
                pdf.y += 8f;
            }
            if (unknown.length() > 0) {
                pdf.satir("Tanınmayan barkodlar (" + unknown.length() + ")", bold, 0f);
                for (int i = 0; i < unknown.length(); i++) {
                    pdf.satir(unknown.getString(i), body, 10f);
                }
            }
            String imza = "Adı soyadı: ....................................................    İmza: ....................................................";
            pdf.y += 20f;
            pdf.satir("Sayım görevlisi / komisyon imzaları", bold, 0f);
            pdf.y += 30f;
            pdf.satir(imza, body, 0f);
            pdf.y += 25f;
            pdf.satir(imza, body, 0f);
            return pdf.bitir();
        } finally {
            pdf.kapat();
        }
    }
}
