package com.mehmetderin.secde_vakti.saglik;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.util.LruCache;

import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;

/**
 * APK'daki assets/secde/&lt;ad&gt;.webp görsellerini yükler ve önbellekte tutar.
 * Testlerde (Robolectric) "secde.gorsel.dizin" sistem özelliği verilirse o klasörden okur.
 */
final class Gorseller {

    /** Önbellek: en çok 40 MB, düşük bellekli cihazlarda yığının 1/8'i (OutOfMemory riskini azaltır). */
    private static final int ONBELLEK_BOYU =
            (int) Math.max(8L * 1024 * 1024, Math.min(40L * 1024 * 1024, Runtime.getRuntime().maxMemory() / 8));

    private static final LruCache<String, Bitmap> ONBELLEK = new LruCache<String, Bitmap>(ONBELLEK_BOYU) {
        @Override
        protected int sizeOf(String k, Bitmap b) {
            return b.getByteCount();
        }
    };

    private Gorseller() {}

    /** Görseli en az hedefGenislik piksel genişliğinde yükler (gereksiz büyüklüğü küçültür). */
    static Bitmap al(Context c, String ad, int hedefGenislik) {
        String anahtar = ad + "@" + hedefGenislik;
        Bitmap b = ONBELLEK.get(anahtar);
        if (b != null) return b;
        try {
            BitmapFactory.Options o = new BitmapFactory.Options();
            o.inJustDecodeBounds = true;
            try (InputStream in = ac(c, ad)) {
                if (in == null) return null;
                BitmapFactory.decodeStream(in, null, o);
            }
            int orneklem = 1;
            while (hedefGenislik > 0 && o.outWidth / (orneklem * 2) >= hedefGenislik) orneklem *= 2;
            BitmapFactory.Options o2 = new BitmapFactory.Options();
            o2.inSampleSize = orneklem;
            o2.inPreferredConfig = Bitmap.Config.ARGB_8888;
            try (InputStream in = ac(c, ad)) {
                b = BitmapFactory.decodeStream(in, null, o2);
            }
            if (b != null) ONBELLEK.put(anahtar, b);
            return b;
        } catch (Throwable t) {
            return null;
        }
    }

    private static InputStream ac(Context c, String ad) {
        for (String uzanti : new String[]{".webp", ".jpg", ".png"}) {
            try {
                return c.getAssets().open("secde/" + ad + uzanti);
            } catch (Throwable ignored) {
            }
        }
        String dizin = System.getProperty("secde.gorsel.dizin");
        if (dizin != null) {
            for (String uzanti : new String[]{".webp", ".jpg", ".png"}) {
                File f = new File(dizin, ad + uzanti);
                if (f.isFile()) {
                    try {
                        return new FileInputStream(f);
                    } catch (Throwable ignored) {
                    }
                }
            }
        }
        return null;
    }
}
