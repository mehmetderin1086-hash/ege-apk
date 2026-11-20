package com.mehmetderin.kitapbul_flutter;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Matrix;
import androidx.exifinterface.media.ExifInterface;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;

/**
 * Kamera ve OCR için ortak görsel hazırlığı: boyut denetimi, örnekleme (uzun kenar ≤ 2400 px)
 * ve EXIF yönüne göre döndürme. 1.0.0'daki CameraImage ve BookTextRecognition mantığı.
 */
final class GorselHazirla {
    private static final int UZUN_KENAR = 2400;

    private GorselHazirla() {}

    /** Kamera fotoğrafını JPEG'e çevirir (≤ 4 MB, kalite 90→50). */
    static byte[] kameraFotografi(File file) {
        long length = file.length();
        if (length < 1 || length > 50L * 1024 * 1024) throw new IllegalArgumentException("Fotoğraf boyutu geçersiz");
        BitmapFactory.Options bounds = new BitmapFactory.Options();
        bounds.inJustDecodeBounds = true;
        BitmapFactory.decodeFile(file.getAbsolutePath(), bounds);
        boyutDenetle(bounds);
        BitmapFactory.Options opts = new BitmapFactory.Options();
        opts.inSampleSize = ornekleme(bounds);
        Bitmap original = BitmapFactory.decodeFile(file.getAbsolutePath(), opts);
        if (original == null) throw new IllegalStateException("Fotoğraf çözülemedi");
        int orientation = 1;
        try {
            orientation = new ExifInterface(file.getAbsolutePath())
                    .getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL);
        } catch (Exception ignored) {
            // EXIF yoksa döndürme yapılmaz.
        }
        Bitmap oriented = dondur(original, orientation);
        try {
            for (int quality : new int[] {90, 80, 70, 60, 50}) {
                ByteArrayOutputStream out = new ByteArrayOutputStream();
                if (!oriented.compress(Bitmap.CompressFormat.JPEG, quality, out)) {
                    throw new IllegalStateException("JPEG üretilemedi");
                }
                if (out.size() <= 4 * 1024 * 1024) return out.toByteArray();
            }
            throw new IllegalArgumentException("Fotoğraf çok büyük");
        } finally {
            if (oriented != original) oriented.recycle();
            original.recycle();
        }
    }

    /** OCR için bellekteki görseli çözer ve yönlendirir. Çağıran geri dönüşümden sorumludur. */
    static Bitmap ocrIcin(byte[] bytes) {
        BitmapFactory.Options bounds = new BitmapFactory.Options();
        bounds.inJustDecodeBounds = true;
        BitmapFactory.decodeByteArray(bytes, 0, bytes.length, bounds);
        boyutDenetle(bounds);
        BitmapFactory.Options opts = new BitmapFactory.Options();
        opts.inSampleSize = ornekleme(bounds);
        Bitmap bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.length, opts);
        if (bitmap == null) throw new IllegalStateException("Görsel çözülemedi");
        int orientation = 1;
        try {
            orientation = new ExifInterface(new ByteArrayInputStream(bytes))
                    .getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL);
        } catch (Exception ignored) {
            // PNG/GIF gibi EXIF'siz biçimler.
        }
        Bitmap oriented = dondur(bitmap, orientation);
        if (oriented != bitmap) bitmap.recycle();
        return oriented;
    }

    /** Galeriden seçilen yüksek çözünürlüklü fotoğrafı yönlendirip ≤ 3.5 MB JPEG'e sıkıştırır. */
    static byte[] bellekFotografi(byte[] raw) {
        Bitmap oriented = ocrIcin(raw);
        try {
            for (int quality : new int[] {88, 78, 68, 58, 48}) {
                ByteArrayOutputStream out = new ByteArrayOutputStream();
                if (!oriented.compress(Bitmap.CompressFormat.JPEG, quality, out)) {
                    throw new IllegalStateException("JPEG üretilemedi");
                }
                if (out.size() <= 3_500_000) return out.toByteArray();
            }
            throw new IllegalArgumentException("Fotoğraf çok büyük");
        } finally {
            oriented.recycle();
        }
    }

    private static void boyutDenetle(BitmapFactory.Options o) {
        boolean ok = o.outWidth >= 1 && o.outWidth <= 30000 && o.outHeight >= 1 && o.outHeight <= 30000
                && (long) o.outWidth * o.outHeight <= 150_000_000L;
        if (!ok) throw new IllegalArgumentException("Görsel boyutu geçersiz");
    }

    /**
     * Uzun kenarı 2400 px altına indiren 2'nin kuvveti. (1.0.0'da yalnız yükseklik denetleniyordu;
     * yatay fotoğraflarda gereksiz büyük bitmap ve bellek taşması oluşabiliyordu — düzeltildi.)
     */
    private static int ornekleme(BitmapFactory.Options o) {
        int longest = Math.max(o.outWidth, o.outHeight);
        int sample = 1;
        while (longest / sample > UZUN_KENAR) sample *= 2;
        return sample;
    }

    private static Bitmap dondur(Bitmap src, int orientation) {
        Matrix m = new Matrix();
        switch (orientation) {
            case ExifInterface.ORIENTATION_FLIP_HORIZONTAL: m.setScale(-1f, 1f); break;
            case ExifInterface.ORIENTATION_ROTATE_180: m.setRotate(180f); break;
            case ExifInterface.ORIENTATION_FLIP_VERTICAL: m.setScale(1f, -1f); break;
            case ExifInterface.ORIENTATION_TRANSPOSE: m.setRotate(90f); m.postScale(-1f, 1f); break;
            case ExifInterface.ORIENTATION_ROTATE_90: m.setRotate(90f); break;
            case ExifInterface.ORIENTATION_TRANSVERSE: m.setRotate(270f); m.postScale(-1f, 1f); break;
            case ExifInterface.ORIENTATION_ROTATE_270: m.setRotate(270f); break;
            default: break;
        }
        if (m.isIdentity()) return src;
        return Bitmap.createBitmap(src, 0, 0, src.getWidth(), src.getHeight(), m, true);
    }
}
