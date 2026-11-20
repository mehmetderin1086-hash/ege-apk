package com.mehmetderin.kitapbul_flutter;

import android.graphics.Bitmap;
import android.graphics.Rect;
import com.google.mlkit.vision.common.InputImage;
import com.google.mlkit.vision.text.Text;
import com.google.mlkit.vision.text.TextRecognition;
import com.google.mlkit.vision.text.TextRecognizer;
import com.google.mlkit.vision.text.latin.TextRecognizerOptions;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/** Kapak / künye sayfası OCR'ı (ML Kit Latin, cihaz üzerinde, çevrimdışı). */
final class BookTextRecognition {
    interface Sonuc {
        void basarili(Map<String, Object> sonuc);
        void basarisiz();
    }

    private static final int EN_FAZLA_SATIR = 200;

    private BookTextRecognition() {}

    static void recognize(final byte[] bytes, final Sonuc sonuc) {
        new Thread(() -> {
            Bitmap prepared = null;
            TextRecognizer client = null;
            try {
                prepared = GorselHazirla.ocrIcin(bytes);
                final Bitmap image = prepared;
                final TextRecognizer recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS);
                client = recognizer;
                recognizer.process(InputImage.fromBitmap(image, 0))
                        .addOnSuccessListener(text -> sonuc.basarili(donustur(text)))
                        .addOnFailureListener(e -> sonuc.basarisiz())
                        .addOnCompleteListener(t -> {
                            recognizer.close();
                            image.recycle();
                        });
            } catch (Exception | OutOfMemoryError e) {
                if (client != null) client.close();
                if (prepared != null) prepared.recycle();
                sonuc.basarisiz();
            }
        }, "kitapbul-ocr").start();
    }

    private static Map<String, Object> donustur(Text result) {
        List<Map<String, Object>> lines = new ArrayList<>();
        outer:
        for (Text.TextBlock block : result.getTextBlocks()) {
            for (Text.Line line : block.getLines()) {
                if (lines.size() >= EN_FAZLA_SATIR) break outer;
                Rect box = line.getBoundingBox();
                Map<String, Object> m = new HashMap<>();
                m.put("text", kes(line.getText(), 2000));
                m.put("height", box != null ? box.height() : 0);
                m.put("top", box != null ? box.top : 0);
                m.put("left", box != null ? box.left : 0);
                m.put("confidence", (double) line.getConfidence());
                lines.add(m);
            }
        }
        Map<String, Object> out = new HashMap<>();
        out.put("text", kes(result.getText(), 100000));
        out.put("lines", lines);
        return out;
    }

    private static String kes(String s, int n) {
        return s.length() <= n ? s : s.substring(0, n);
    }
}
