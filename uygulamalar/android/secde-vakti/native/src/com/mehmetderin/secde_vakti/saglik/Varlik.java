package com.mehmetderin.secde_vakti.saglik;

import android.content.Context;
import android.content.res.AssetFileDescriptor;
import android.graphics.Typeface;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;

/**
 * Uygulamanın içindeki Flutter dosyalarına (assets/flutter_assets/...) ve Secde dosyalarına
 * (assets/secde/...) erişim. Testlerde "secde.flutter.dizin" / "secde.gorsel.dizin" klasörlerinden okur.
 */
final class Varlik {

    private Varlik() {}

    /** "assets/data/quranenc.json" gibi Flutter varlık yolu. */
    static InputStream flutter(Context c, String yol) {
        try {
            return c.getAssets().open("flutter_assets/" + yol);
        } catch (Throwable ignored) {
        }
        String d = System.getProperty("secde.flutter.dizin");
        if (d != null) {
            try {
                return new FileInputStream(new File(d, yol));
            } catch (Throwable ignored) {
            }
        }
        return null;
    }

    static String flutterMetin(Context c, String yol) {
        try (InputStream in = flutter(c, yol)) {
            if (in == null) return null;
            return oku(in);
        } catch (Throwable t) {
            return null;
        }
    }

    /** assets/secde/&lt;ad&gt; metni (ör. meal_ses.json). */
    static String secdeMetin(Context c, String ad) {
        try (InputStream in = c.getAssets().open("secde/" + ad)) {
            return oku(in);
        } catch (Throwable ignored) {
        }
        String d = System.getProperty("secde.veri.dizin");
        if (d != null) {
            try (InputStream in = new FileInputStream(new File(d, ad))) {
                return oku(in);
            } catch (Throwable ignored) {
            }
        }
        return null;
    }

    /** MediaPlayer için Flutter ses dosyası (sıkıştırılmamışsa); yoksa null. */
    static AssetFileDescriptor flutterSes(Context c, String yol) {
        try {
            return c.getAssets().openFd("flutter_assets/" + yol);
        } catch (Throwable t) {
            return null;
        }
    }

    private static Typeface kuranYazi;
    private static String kuranYaziDosya;

    /** Kur'an ve Arapça metinler için seçili Mushaf yazı tipi (AmiriQuran / Scheherazade / NotoNaskh / Lateef). */
    static Typeface kuranYazisi(Context c) {
        String secim = TemaMotoru.arapcaYaziTipiDosyasi(c);
        if (kuranYazi == null || !secim.equals(kuranYaziDosya)) {
            kuranYazi = null;
            kuranYaziDosya = secim;
            for (String aday : new String[]{secim, "AmiriQuran-Regular.ttf"}) {
                try {
                    kuranYazi = Typeface.createFromAsset(c.getAssets(), "flutter_assets/assets/fonts/" + aday);
                    if (kuranYazi != null) break;
                } catch (Throwable t) {
                    try {
                        String d = System.getProperty("secde.flutter.dizin");
                        if (d != null) {
                            File f = new File(d, "assets/fonts/" + aday);
                            if (f.isFile()) {
                                kuranYazi = Typeface.createFromFile(f);
                                if (kuranYazi != null) break;
                            }
                        }
                    } catch (Throwable ignored) {
                    }
                }
            }
            if (kuranYazi == null) kuranYazi = Typeface.SERIF;
        }
        return kuranYazi;
    }

    private static String oku(InputStream in) throws java.io.IOException {
        ByteArrayOutputStream b = new ByteArrayOutputStream();
        byte[] tampon = new byte[64 * 1024];
        int n;
        while ((n = in.read(tampon)) > 0) b.write(tampon, 0, n);
        return new String(b.toByteArray(), StandardCharsets.UTF_8);
    }
}
