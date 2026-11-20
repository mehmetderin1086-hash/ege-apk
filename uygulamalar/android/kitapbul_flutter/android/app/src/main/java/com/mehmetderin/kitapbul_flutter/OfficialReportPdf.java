package com.mehmetderin.kitapbul_flutter;

import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.graphics.pdf.PdfDocument;
import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.Locale;
import org.json.JSONArray;
import org.json.JSONObject;

/**
 * Resmî Okul Kütüphanesi Dönem Faaliyet Raporu, Demirbaş Defteri ve Nöbet Çizelgesi
 * için kurumsal başlıklı, tablolu ve imza bloklu A4 PDF üreticisi.
 */
final class OfficialReportPdf {
    private static final Locale TR = Locale.forLanguageTag("tr-TR");
    private static final int W = 595;
    private static final int H = 842;
    private static final float M = 34f;
    private static final float CONTENT_W = W - 2 * M;

    private OfficialReportPdf() {}

    static byte[] generate(String json) throws Exception {
        if (json.getBytes(StandardCharsets.UTF_8).length > 25 * 1024 * 1024) {
            throw new IllegalArgumentException("Rapor verisi çok büyük");
        }
        JSONObject root = new JSONObject(json);
        final String schoolName = root.optString("schoolName", "Cumhuriyet Anadolu Lisesi");
        final String libraryName = root.optString("libraryName", "Cumhuriyet Kütüphanesi");
        final String reportTitle = root.optString("reportTitle", "KÜTÜPHANE KAYIT VE FAALİYET RAPORU");
        final String subtitle = root.optString("subtitle", "");
        final String footerNote = root.optString("footerNote", "");
        final String leftSignerTitle = root.optString("leftSignerTitle", "Kütüphane Sorumlusu");
        final String leftSignerName = root.optString("leftSignerName", "");
        final String rightSignerTitle = root.optString("rightSignerTitle", "Okul Müdürü");
        final String rightSignerName = root.optString("rightSignerName", "");

        JSONArray kpis = root.optJSONArray("kpis");
        JSONArray sections = root.optJSONArray("sections");

        Paint fill = new Paint(Paint.ANTI_ALIAS_FLAG);
        fill.setStyle(Paint.Style.FILL);

        Paint stroke = new Paint(Paint.ANTI_ALIAS_FLAG);
        stroke.setStyle(Paint.Style.STROKE);
        stroke.setStrokeWidth(0.8f);
        stroke.setColor(Color.rgb(203, 213, 225));

        Paint bold = new Paint(Paint.ANTI_ALIAS_FLAG);
        bold.setTypeface(Typeface.create("sans-serif", Typeface.BOLD));

        Paint regular = new Paint(Paint.ANTI_ALIAS_FLAG);
        regular.setTypeface(Typeface.create("sans-serif", Typeface.NORMAL));

        PdfDocument doc = new PdfDocument();
        int pageNo = 1;
        PdfDocument.Page page = doc.startPage(new PdfDocument.PageInfo.Builder(W, H, pageNo).create());
        Canvas canvas = page.getCanvas();
        float y = drawOfficialHeader(canvas, schoolName, libraryName, reportTitle, subtitle, true, fill, bold, regular);

        try {
            // KPI Summary Cards on first page
            if (kpis != null && kpis.length() > 0) {
                int count = Math.min(kpis.length(), 4);
                float gap = 8f;
                float boxW = (CONTENT_W - gap * (count - 1)) / count;
                float boxH = 44f;
                for (int i = 0; i < count; i++) {
                    JSONObject kpi = kpis.getJSONObject(i);
                    float bx = M + i * (boxW + gap);
                    RectF r = new RectF(bx, y, bx + boxW, y + boxH);
                    fill.setColor(Color.rgb(241, 245, 249));
                    canvas.drawRoundRect(r, 6f, 6f, fill);
                    canvas.drawRoundRect(r, 6f, 6f, stroke);

                    bold.setColor(Color.rgb(30, 58, 138));
                    bold.setTextSize(13.5f);
                    drawSingle(canvas, kpi.optString("value", "0"), bx + 10f, y + 20f, boxW - 20f, bold);

                    regular.setColor(Color.rgb(71, 85, 105));
                    regular.setTextSize(8.2f);
                    drawSingle(canvas, kpi.optString("label", ""), bx + 10f, y + 34f, boxW - 20f, regular);
                }
                y += boxH + 16f;
            }

            // Tabular Sections
            if (sections != null) {
                for (int s = 0; s < sections.length(); s++) {
                    JSONObject sec = sections.getJSONObject(s);
                    String heading = sec.optString("heading", "");
                    JSONArray headers = sec.getJSONArray("headers");
                    JSONArray weightsArr = sec.optJSONArray("weights");
                    JSONArray rows = sec.getJSONArray("rows");

                    int colCount = headers.length();
                    float[] colWidths = computeColWidths(colCount, weightsArr);

                    if (y > H - 110f) {
                        drawFooter(canvas, libraryName, pageNo, regular);
                        doc.finishPage(page);
                        pageNo++;
                        page = doc.startPage(new PdfDocument.PageInfo.Builder(W, H, pageNo).create());
                        canvas = page.getCanvas();
                        y = drawOfficialHeader(canvas, schoolName, libraryName, reportTitle, subtitle, false, fill, bold, regular);
                    }

                    if (!heading.isEmpty()) {
                        bold.setColor(Color.rgb(15, 23, 42));
                        bold.setTextSize(10.5f);
                        drawSingle(canvas, heading, M, y + 10f, CONTENT_W, bold);
                        y += 16f;
                    }

                    y = drawTableHeader(canvas, headers, colWidths, y, fill, bold);

                    for (int r = 0; r < rows.length(); r++) {
                        if (y > H - 56f) {
                            drawFooter(canvas, libraryName, pageNo, regular);
                            doc.finishPage(page);
                            pageNo++;
                            page = doc.startPage(new PdfDocument.PageInfo.Builder(W, H, pageNo).create());
                            canvas = page.getCanvas();
                            y = drawOfficialHeader(canvas, schoolName, libraryName, reportTitle, subtitle, false, fill, bold, regular);
                            y = drawTableHeader(canvas, headers, colWidths, y, fill, bold);
                        }
                        JSONArray row = rows.getJSONArray(r);
                        float rowH = 18.5f;
                        if (r % 2 == 1) {
                            fill.setColor(Color.rgb(248, 250, 252));
                            canvas.drawRect(M, y, M + CONTENT_W, y + rowH, fill);
                        }
                        fill.setColor(Color.rgb(226, 232, 240));
                        canvas.drawRect(M, y + rowH - 0.5f, M + CONTENT_W, y + rowH, fill);

                        regular.setColor(Color.rgb(30, 41, 59));
                        regular.setTextSize(8.2f);
                        float cx = M;
                        for (int c = 0; c < colCount; c++) {
                            String cellVal = c < row.length() ? row.optString(c, "") : "";
                            drawSingle(canvas, cellVal, cx + 5f, y + 12.5f, colWidths[c] - 10f, regular);
                            cx += colWidths[c];
                        }
                        y += rowH;
                    }
                    y += 16f;
                }
            }

            // Signature block
            if (y > H - 130f) {
                drawFooter(canvas, libraryName, pageNo, regular);
                doc.finishPage(page);
                pageNo++;
                page = doc.startPage(new PdfDocument.PageInfo.Builder(W, H, pageNo).create());
                canvas = page.getCanvas();
                y = drawOfficialHeader(canvas, schoolName, libraryName, reportTitle, subtitle, false, fill, bold, regular);
            }

            y += 10f;
            if (!footerNote.isEmpty()) {
                regular.setColor(Color.rgb(100, 116, 139));
                regular.setTextSize(8f);
                drawSingle(canvas, footerNote, M, y, CONTENT_W, regular);
                y += 22f;
            }

            float sigY = y + 8f;
            bold.setColor(Color.rgb(15, 23, 42));
            bold.setTextSize(9.5f);
            drawCentered(canvas, leftSignerTitle, M, sigY, 200f, bold);
            drawCentered(canvas, rightSignerTitle, W - M - 200f, sigY, 200f, bold);

            regular.setColor(Color.rgb(51, 65, 85));
            regular.setTextSize(9f);
            if (!leftSignerName.isEmpty()) {
                drawCentered(canvas, leftSignerName, M, sigY + 15f, 200f, regular);
            }
            if (!rightSignerName.isEmpty()) {
                drawCentered(canvas, rightSignerName, W - M - 200f, sigY + 15f, 200f, regular);
            }

            regular.setColor(Color.rgb(148, 163, 184));
            regular.setTextSize(8f);
            drawCentered(canvas, "İmza", M, sigY + 42f, 200f, regular);
            drawCentered(canvas, "İmza / Mühür", W - M - 200f, sigY + 42f, 200f, regular);

            drawFooter(canvas, libraryName, pageNo, regular);
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

    private static float drawOfficialHeader(
            Canvas canvas, String school, String library, String title, String subtitle,
            boolean fullHeader, Paint fill, Paint bold, Paint regular) {
        if (!fullHeader) {
            bold.setColor(Color.rgb(30, 58, 138));
            bold.setTextSize(9f);
            drawSingle(canvas, school.toUpperCase(TR) + " — " + title, M, 34f, CONTENT_W, bold);
            fill.setColor(Color.rgb(30, 58, 138));
            canvas.drawRect(M, 40f, M + CONTENT_W, 41.2f, fill);
            return 54f;
        }

        bold.setColor(Color.rgb(15, 23, 42));
        bold.setTextSize(9.5f);
        drawCentered(canvas, "T.C. MİLLÎ EĞİTİM BAKANLIĞI", M, 36f, CONTENT_W, bold);

        bold.setTextSize(12f);
        drawCentered(canvas, school.toUpperCase(TR) + " MÜDÜRLÜĞÜ", M, 51f, CONTENT_W, bold);

        bold.setColor(Color.rgb(30, 58, 138));
        bold.setTextSize(10.5f);
        drawCentered(canvas, library.toUpperCase(TR) + " — " + title.toUpperCase(TR), M, 66f, CONTENT_W, bold);

        if (!subtitle.isEmpty()) {
            regular.setColor(Color.rgb(71, 85, 105));
            regular.setTextSize(8.5f);
            drawCentered(canvas, subtitle, M, 79f, CONTENT_W, regular);
        }

        fill.setColor(Color.rgb(30, 58, 138));
        canvas.drawRect(M, 86f, M + CONTENT_W, 88f, fill);
        fill.setColor(Color.rgb(191, 219, 254));
        canvas.drawRect(M, 89.5f, M + CONTENT_W, 90.5f, fill);
        return 102f;
    }

    private static float drawTableHeader(
            Canvas canvas, JSONArray headers, float[] colWidths, float y, Paint fill, Paint bold) {
        float h = 21f;
        fill.setColor(Color.rgb(30, 58, 138));
        canvas.drawRoundRect(new RectF(M, y, M + CONTENT_W, y + h), 4f, 4f, fill);
        canvas.drawRect(M, y + 10f, M + CONTENT_W, y + h, fill);

        bold.setColor(Color.WHITE);
        bold.setTextSize(8.3f);
        float cx = M;
        for (int c = 0; c < headers.length(); c++) {
            drawSingle(canvas, headers.optString(c, ""), cx + 5f, y + 14f, colWidths[c] - 10f, bold);
            cx += colWidths[c];
        }
        return y + h;
    }

    private static void drawFooter(Canvas canvas, String library, int pageNo, Paint regular) {
        regular.setColor(Color.rgb(100, 116, 139));
        regular.setTextSize(8f);
        drawSingle(canvas, library + " · Kitap Bul Okul Otomasyonu", M, H - 18f, CONTENT_W - 80f, regular);
        String p = "Sayfa " + pageNo;
        float pw = regular.measureText(p);
        canvas.drawText(p, W - M - pw, H - 18f, regular);
    }

    private static float[] computeColWidths(int cols, JSONArray weights) {
        float[] w = new float[cols];
        float sum = 0f;
        for (int i = 0; i < cols; i++) {
            float v = weights != null && i < weights.length() ? (float) weights.optDouble(i, 1.0) : 1.0f;
            if (v <= 0.1f) v = 1.0f;
            w[i] = v;
            sum += v;
        }
        for (int i = 0; i < cols; i++) {
            w[i] = (w[i] / sum) * CONTENT_W;
        }
        return w;
    }

    private static String clip(String val, float max, Paint paint) {
        String clean = PdfSayfa.tekSatir(val == null ? "" : val);
        if (clean.isEmpty()) return "";
        int end = Math.min(paint.breakText(clean, true, max, null), clean.length());
        if (end < clean.length() && end > 0 && Character.isHighSurrogate(clean.charAt(end - 1))) end--;
        String shown = clean.substring(0, end);
        if (end < clean.length()) {
            while (!shown.isEmpty() && paint.measureText(shown + "…") > max) {
                shown = shown.substring(0, shown.length() - 1);
            }
            shown = shown + "…";
        }
        return shown;
    }

    private static void drawSingle(Canvas canvas, String val, float x, float y, float max, Paint paint) {
        String s = clip(val, max, paint);
        if (!s.isEmpty()) canvas.drawText(s, x, y, paint);
    }

    private static void drawCentered(Canvas canvas, String val, float x, float y, float max, Paint paint) {
        String s = clip(val, max, paint);
        if (s.isEmpty()) return;
        float tw = paint.measureText(s);
        canvas.drawText(s, x + Math.max(0f, (max - tw) / 2f), y, paint);
    }
}
