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
 * A4 kitap sırt etiketi (3×8), barkodlu demirbaş etiketi (3×7) ve
 * QR kodlu büyük kitap kimlik kartı (2×5) vektörel PDF üreticisi.
 */
final class SpineLabelsPdf {
    private static final Locale TR = Locale.forLanguageTag("tr-TR");
    private static final int W = 595;
    private static final int H = 842;
    private static final float MARGIN_X = 22f;
    private static final float MARGIN_Y = 24f;

    private SpineLabelsPdf() {}

    static byte[] generate(String json) throws Exception {
        if (json.getBytes(StandardCharsets.UTF_8).length > 25 * 1024 * 1024) {
            throw new IllegalArgumentException("Etiket verisi çok büyük");
        }
        JSONObject root = new JSONObject(json);
        String template = root.optString("template", "standard");
        String school = root.optString("schoolName", "Cumhuriyet Anadolu Lisesi");
        String library = root.optString("libraryName", "Cumhuriyet Kütüphanesi");
        JSONArray items = root.getJSONArray("items");
        if (items.length() < 1 || items.length() > 10000) {
            throw new IllegalArgumentException("Etiket listesi boş veya sınırı aşıyor");
        }

        final int cols;
        final int rows;
        if ("spine".equals(template)) {
            cols = 3;
            rows = 8;
        } else if ("qrCard".equals(template)) {
            cols = 2;
            rows = 5;
        } else {
            cols = 3;
            rows = 7;
        }
        final int perPage = cols * rows;
        final float cellW = (W - 2 * MARGIN_X) / cols;
        final float cellH = (H - 2 * MARGIN_Y) / rows;

        Paint cutBorder = new Paint(Paint.ANTI_ALIAS_FLAG);
        cutBorder.setStyle(Paint.Style.STROKE);
        cutBorder.setStrokeWidth(0.65f);
        cutBorder.setColor(Color.rgb(180, 190, 200));

        Paint fillPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        fillPaint.setStyle(Paint.Style.FILL);

        Paint barPaint = new Paint();
        barPaint.setColor(Color.BLACK);
        barPaint.setAntiAlias(false);

        Paint boldPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        boldPaint.setTypeface(Typeface.create("sans-serif", Typeface.BOLD));

        Paint regularPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        regularPaint.setTypeface(Typeface.create("sans-serif", Typeface.NORMAL));

        PdfDocument doc = new PdfDocument();
        PdfDocument.Page page = null;
        try {
            for (int index = 0; index < items.length(); index++) {
                if (index % perPage == 0) {
                    page = doc.startPage(
                            new PdfDocument.PageInfo.Builder(W, H, index / perPage + 1).create());
                }
                Canvas canvas = page.getCanvas();
                JSONObject item = items.getJSONObject(index);
                int slot = index % perPage;
                int col = slot % cols;
                int row = slot / cols;

                float x = MARGIN_X + col * cellW + 4f;
                float y = MARGIN_Y + row * cellH + 4f;
                float w = cellW - 8f;
                float h = cellH - 8f;

                int accent = parseHexColor(item.optString("color", "#4F46E5"));
                RectF cardRect = new RectF(x, y, x + w, y + h);
                canvas.drawRoundRect(cardRect, 5f, 5f, cutBorder);

                if ("spine".equals(template)) {
                    drawSpineLabel(canvas, item, x, y, w, h, accent, fillPaint, boldPaint, regularPaint);
                } else if ("qrCard".equals(template)) {
                    drawQrCard(canvas, item, school, library, x, y, w, h, accent,
                            fillPaint, barPaint, boldPaint, regularPaint);
                } else {
                    drawStandardLabel(canvas, item, library, x, y, w, h, accent,
                            fillPaint, barPaint, boldPaint, regularPaint);
                }

                if (slot == perPage - 1 || index == items.length() - 1) {
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

    private static void drawSpineLabel(
            Canvas canvas, JSONObject item, float x, float y, float w, float h,
            int accent, Paint fill, Paint bold, Paint regular) {
        // Top colored band
        fill.setColor(accent);
        canvas.drawRoundRect(new RectF(x + 1f, y + 1f, x + w - 1f, y + 20f), 4f, 4f, fill);
        canvas.drawRect(x + 1f, y + 10f, x + w - 1f, y + 20f, fill);

        bold.setColor(Color.WHITE);
        bold.setTextSize(8.5f);
        String shelf = item.optString("shelf", "GENEL");
        drawCenteredSingleLine(canvas, shelf, x + 4f, y + 14f, w - 8f, bold);

        // Call number lines (e.g. TAR / İNA)
        bold.setColor(Color.rgb(20, 25, 35));
        bold.setTextSize(15f);
        drawCenteredSingleLine(canvas, item.optString("callTop", "GEN"), x + 6f, y + 41f, w - 12f, bold);

        bold.setColor(accent);
        bold.setTextSize(14f);
        drawCenteredSingleLine(canvas, item.optString("callBottom", "---"), x + 6f, y + 58f, w - 12f, bold);

        // Subtle divider
        fill.setColor(Color.rgb(226, 232, 240));
        canvas.drawRect(x + 10f, y + h - 24f, x + w - 10f, y + h - 23.2f, fill);

        regular.setColor(Color.rgb(55, 65, 81));
        regular.setTextSize(8.2f);
        String acc = item.optString("accession", "");
        if (acc.isEmpty()) acc = item.optString("barcodeText", "");
        drawCenteredSingleLine(canvas, acc, x + 6f, y + h - 10f, w - 12f, regular);
    }

    private static void drawStandardLabel(
            Canvas canvas, JSONObject item, String library, float x, float y, float w, float h,
            int accent, Paint fill, Paint barPaint, Paint bold, Paint regular) {
        // Left vertical accent stripe
        fill.setColor(accent);
        canvas.drawRect(x + 1.5f, y + 2f, x + 7f, y + h - 2f, fill);

        float left = x + 12f;
        float maxW = w - 18f;

        bold.setColor(accent);
        bold.setTextSize(7.2f);
        drawSingleLine(canvas, library.toUpperCase(TR), left, y + 12f, maxW, bold);

        String callTop = item.optString("callTop", "");
        String callBottom = item.optString("callBottom", "");
        String shelf = item.optString("shelf", "");
        String callLine = callTop + (callBottom.isEmpty() ? "" : " / " + callBottom)
                + (shelf.isEmpty() ? "" : "  ·  " + shelf);
        bold.setColor(Color.rgb(17, 24, 39));
        bold.setTextSize(9.5f);
        drawSingleLine(canvas, callLine, left, y + 24f, maxW, bold);

        regular.setColor(Color.rgb(31, 41, 55));
        regular.setTextSize(8.2f);
        drawSingleLine(canvas, item.optString("title", ""), left, y + 35.5f, maxW, regular);

        regular.setColor(Color.rgb(100, 116, 139));
        regular.setTextSize(7.4f);
        drawSingleLine(canvas, item.optString("author", ""), left, y + 45.5f, maxW, regular);

        JSONArray bars = item.optJSONArray("bars");
        if (bars != null && bars.length() > 0) {
            drawBars(canvas, bars, left + 2f, y + h - 41f, maxW - 4f, 25f, barPaint);
        }

        bold.setColor(Color.rgb(30, 41, 59));
        bold.setTextSize(7.8f);
        String codeText = item.optString("accession", "");
        if (codeText.isEmpty()) codeText = item.optString("barcodeText", "");
        drawCenteredSingleLine(canvas, codeText, left, y + h - 6.5f, maxW, bold);
    }

    private static void drawQrCard(
            Canvas canvas, JSONObject item, String school, String library,
            float x, float y, float w, float h,
            int accent, Paint fill, Paint barPaint, Paint bold, Paint regular) {
        // Header banner
        fill.setColor(accent);
        canvas.drawRoundRect(new RectF(x + 1f, y + 1f, x + w - 1f, y + 22f), 4f, 4f, fill);
        canvas.drawRect(x + 1f, y + 12f, x + w - 1f, y + 22f, fill);

        bold.setColor(Color.WHITE);
        bold.setTextSize(7.6f);
        String header = school + " · " + library;
        drawSingleLine(canvas, header.toUpperCase(TR), x + 8f, y + 14.5f, w - 16f, bold);

        float qrSize = 68f;
        float qrX = x + w - qrSize - 10f;
        float qrY = y + 30f;

        float left = x + 9f;
        float textW = qrX - left - 8f;

        // Call badge + shelf
        String badge = item.optString("callTop", "GEN") + " / " + item.optString("callBottom", "---");
        String shelf = item.optString("shelf", "");
        bold.setColor(accent);
        bold.setTextSize(9.5f);
        drawSingleLine(canvas, badge + (shelf.isEmpty() ? "" : " · " + shelf), left, y + 36f, textW, bold);

        // Title & Author
        bold.setColor(Color.rgb(15, 23, 42));
        bold.setTextSize(9.8f);
        drawSingleLine(canvas, item.optString("title", ""), left, y + 50f, textW, bold);

        regular.setColor(Color.rgb(71, 85, 105));
        regular.setTextSize(8.2f);
        drawSingleLine(canvas, item.optString("author", ""), left, y + 62f, textW, regular);

        String cat = item.optString("category", "");
        if (!cat.isEmpty()) {
            regular.setColor(Color.rgb(100, 116, 139));
            regular.setTextSize(7.5f);
            drawSingleLine(canvas, "Tür: " + cat, left, y + 73f, textW, regular);
        }

        // Barcode on bottom-left
        JSONArray bars = item.optJSONArray("bars");
        if (bars != null && bars.length() > 0) {
            drawBars(canvas, bars, left, y + h - 42f, textW, 24f, barPaint);
        }
        bold.setColor(Color.rgb(30, 41, 59));
        bold.setTextSize(7.8f);
        String codeText = item.optString("accession", "");
        if (codeText.isEmpty()) codeText = item.optString("barcodeText", "");
        drawSingleLine(canvas, codeText, left, y + h - 8f, textW, bold);

        // QR Matrix on right
        JSONArray qrRows = item.optJSONArray("qr");
        if (qrRows != null && qrRows.length() > 0) {
            drawQrMatrix(canvas, qrRows, qrX, qrY, qrSize, barPaint);
            regular.setColor(Color.rgb(71, 85, 105));
            regular.setTextSize(6.8f);
            drawCenteredSingleLine(canvas, "QR KİTAP KARTI", qrX, qrY + qrSize + 10f, qrSize, regular);
        }
    }

    private static void drawBars(
            Canvas canvas, JSONArray bars, float left, float top, float width, float height, Paint barPaint) {
        int len = Math.min(bars.length(), 1024);
        for (int i = 0; i < len; i++) {
            JSONArray seg = bars.optJSONArray(i);
            if (seg == null || seg.length() != 2) continue;
            double pos = seg.optDouble(0, -1);
            double unit = seg.optDouble(1, -1);
            if (pos < 0 || unit <= 0 || pos + unit > 1.0001) continue;
            canvas.drawRect(
                    left + (float) (width * pos),
                    top,
                    left + (float) (width * (pos + unit)),
                    top + height,
                    barPaint);
        }
    }

    private static void drawQrMatrix(
            Canvas canvas, JSONArray qrRows, float left, float top, float size, Paint darkPaint) {
        int modules = qrRows.length();
        if (modules < 10 || modules > 177) return;
        float cell = size / modules;
        for (int r = 0; r < modules; r++) {
            String row = qrRows.optString(r, "");
            int cols = Math.min(row.length(), modules);
            float ry = top + r * cell;
            for (int c = 0; c < cols; c++) {
                if (row.charAt(c) == '1') {
                    float rx = left + c * cell;
                    canvas.drawRect(rx, ry, rx + cell + 0.15f, ry + cell + 0.15f, darkPaint);
                }
            }
        }
    }

    private static int parseHexColor(String hex) {
        try {
            return Color.parseColor(hex);
        } catch (Exception e) {
            return Color.rgb(79, 70, 229);
        }
    }

    private static String clipText(String value, float max, Paint paint) {
        String clean = PdfSayfa.tekSatir(value == null ? "" : value);
        if (clean.isEmpty()) return "";
        int end = Math.min(paint.breakText(clean, true, max, null), clean.length());
        if (end < clean.length() && end > 0 && Character.isHighSurrogate(clean.charAt(end - 1))) {
            end--;
        }
        String shown = clean.substring(0, end);
        if (end < clean.length()) {
            while (!shown.isEmpty() && paint.measureText(shown + "…") > max) {
                shown = shown.substring(0, shown.length() - 1);
            }
            shown = shown + "…";
        }
        return shown;
    }

    private static void drawSingleLine(Canvas canvas, String value, float x, float y, float max, Paint paint) {
        String shown = clipText(value, max, paint);
        if (!shown.isEmpty()) canvas.drawText(shown, x, y, paint);
    }

    private static void drawCenteredSingleLine(
            Canvas canvas, String value, float x, float y, float max, Paint paint) {
        String shown = clipText(value, max, paint);
        if (shown.isEmpty()) return;
        float w = paint.measureText(shown);
        float cx = x + Math.max(0f, (max - w) / 2f);
        canvas.drawText(shown, cx, y, paint);
    }
}
