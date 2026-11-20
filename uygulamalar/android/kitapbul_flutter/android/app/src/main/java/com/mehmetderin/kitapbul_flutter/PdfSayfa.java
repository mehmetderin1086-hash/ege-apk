package com.mehmetderin.kitapbul_flutter;

import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.pdf.PdfDocument;
import java.io.ByteArrayOutputStream;
import java.io.IOException;

/**
 * Çok sayfalı A4 PDF'lerde ortak sayfa ve satır kaydırma mantığı.
 * 1.0.0 APK'sındaki CatalogPdf / InventoryPdf / TextbookReportPdf yardımcılarının birleşik hâli.
 */
final class PdfSayfa {
    /** Yeni sayfa açıldığında başlığı çizer ve ilk satırın y konumunu döndürür. */
    interface Baslik {
        float ciz(Canvas canvas, float margin);
    }

    static final int GENISLIK = 595;
    static final int YUKSEKLIK = 842;

    final PdfDocument doc = new PdfDocument();
    final float margin;
    final Paint small;
    private final Baslik baslik;
    private final float satirAraligi;
    private final float altSinir;
    private PdfDocument.Page page;
    private int pageNumber;
    float y;

    PdfSayfa(float margin, Paint small, float satirAraligi, float altSinir, Baslik baslik) {
        this.margin = margin;
        this.small = small;
        this.satirAraligi = satirAraligi;
        this.altSinir = altSinir;
        this.baslik = baslik;
    }

    void yeniSayfa() {
        pageNumber++;
        page = doc.startPage(new PdfDocument.PageInfo.Builder(GENISLIK, YUKSEKLIK, pageNumber).create());
        y = baslik.ciz(page.getCanvas(), margin);
    }

    void sayfayiKapat() {
        if (page == null) return;
        page.getCanvas().drawText("Kitap Bul · " + pageNumber, margin, YUKSEKLIK - 24f, small);
        doc.finishPage(page);
        page = null;
    }

    /** y belirtilen eşiği aşmışsa sayfayı kapatıp yenisini açar. */
    void gerekirseYeniSayfa(float esik) {
        if (y > YUKSEKLIK - esik) {
            sayfayiKapat();
            yeniSayfa();
        }
    }

    /** Metni sözcük sınırlarında kaydırarak yazar; sayfa sonunda yeni sayfaya geçer. */
    void satir(String text, Paint paint, float indent) {
        String rest = text.replaceAll("[\\r\\n]+", " ").trim();
        float maxWidth = GENISLIK - 2 * margin - indent;
        while (!rest.isEmpty()) {
            if (y > YUKSEKLIK - altSinir) {
                sayfayiKapat();
                yeniSayfa();
            }
            int count = kirilmaNoktasi(rest, paint, maxWidth);
            page.getCanvas().drawText(rest.substring(0, count), margin + indent, y, paint);
            y += satirAraligi;
            rest = ltrim(rest.substring(count));
        }
    }

    byte[] bitir() throws IOException {
        sayfayiKapat();
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        doc.writeTo(out);
        return out.toByteArray();
    }

    /** Hata durumunda açık sayfayı kapatıp belgeyi serbest bırakır. */
    void kapat() {
        if (page != null) {
            try {
                doc.finishPage(page);
            } catch (Exception ignored) {
                // Belge zaten bozuk; yalnız kaynak bırakılır.
            }
            page = null;
        }
        doc.close();
    }

    static int kirilmaNoktasi(String rest, Paint paint, float maxWidth) {
        int count = Math.max(paint.breakText(rest, true, maxWidth, null), 1);
        if (count < rest.length() && count > 1 && Character.isHighSurrogate(rest.charAt(count - 1))) {
            count--;
        }
        if (count < rest.length() && !Character.isWhitespace(rest.charAt(count))) {
            int boundary = rest.lastIndexOf(' ', count - 1);
            if (boundary > 0) count = boundary;
        }
        return count;
    }

    static String ltrim(String s) {
        int i = 0;
        while (i < s.length() && Character.isWhitespace(s.charAt(i))) i++;
        return s.substring(i);
    }

    static String tekSatir(String s) {
        return s.replaceAll("[\\r\\n]+", " ").trim();
    }
}
