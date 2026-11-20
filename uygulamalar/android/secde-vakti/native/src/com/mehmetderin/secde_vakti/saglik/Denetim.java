package com.mehmetderin.secde_vakti.saglik;

import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.res.AssetFileDescriptor;
import android.os.Build;

import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.List;

/**
 * Uygulamanın telefonda kendi kendini denetlemesi: Kur'an verisi, yazı tipi, sesler, ağ,
 * uygulamanın Flutter ekranı, çalma servisi, sesli meal dizini ve son hata. Sonuç kopyalanabilir rapor olur.
 * Ağ denetimi yaptığı için arka plan iş parçacığında çağrılmalıdır.
 */
final class Denetim {

    static final class Sonuc {
        final String ad, ayrinti;
        final int seviye; // 1 iyi, 0 uyarı, -1 sorun

        Sonuc(String ad, int seviye, String ayrinti) {
            this.ad = ad;
            this.seviye = seviye;
            this.ayrinti = ayrinti;
        }
    }

    private Denetim() {}

    static List<Sonuc> calistir(Context c) {
        List<Sonuc> l = new ArrayList<>();

        // Uygulamanın içindeki Flutter verileri
        String[][] dosya = {
                {"assets/data/quranenc.json", "Kur'an metni ve meal"},
                {"assets/data/kuran_bilmek_offline.json", "Sure bilgileri ve kelime meali"},
                {"assets/data/Duas.json", "Dualar"},
                {"assets/data/EsmaulHusna.json", "Esmâü'l-Hüsnâ"},
                {"assets/elifba/sources.json", "Elif-Ba harf listesi"},
                {"assets/fonts/AmiriQuran-Regular.ttf", "Kur'an yazı tipi"},
        };
        for (String[] d : dosya) {
            long boy = boyut(c, d[0]);
            l.add(new Sonuc(d[1], boy > 0 ? 1 : -1, boy > 0 ? (boy / 1024) + " KB" : "okunamadı: " + d[0]));
        }

        // Kur'an verisi çözümleniyor mu
        try {
            int sure = Kuran.sureler(c).size();
            int bakara = Kuran.ayetler(c, 2).size();
            l.add(new Sonuc("Kur'an verisi", sure == 114 && bakara == 286 ? 1 : -1, sure + " sure, Bakara " + bakara + " ayet"));
        } catch (Throwable t) {
            Hata.kaydet(c, "Denetim: Kur'an verisi", t);
            l.add(new Sonuc("Kur'an verisi", -1, t.toString()));
        }

        // Elif-Ba sesi (sıkıştırılmamış olmalı)
        try {
            AssetFileDescriptor fd = Varlik.flutterSes(c, "assets/elifba/ba.mp3");
            l.add(new Sonuc("Elif-Ba sesleri", fd != null ? 1 : -1, fd != null ? "ba.mp3 " + fd.getLength() + " bayt" : "açılamadı"));
            if (fd != null) fd.close();
        } catch (Throwable t) {
            l.add(new Sonuc("Elif-Ba sesleri", -1, t.toString()));
        }

        // Sesli meal dizini
        int okuyucu = Kuran.mealOkuyuculari(c).size();
        String[] meal = Kuran.mealSesi(c, 36, null);
        l.add(new Sonuc("Sesli meal dizini", okuyucu > 0 && meal != null ? 1 : -1, okuyucu + " okuyucu"));

        // Uygulamanın birleşik ana ekranı (DurumAktivitesi)
        try {
            Intent i = new Intent().setComponent(new ComponentName(c.getPackageName(), DurumAktivitesi.class.getName()));
            boolean var = c.getPackageManager().resolveActivity(i, 0) != null;
            l.add(new Sonuc("Uygulamanın ana ekranı", var ? 1 : 0, var ? "birleşik 2.2 ekranı etkin" : "manifest denetimi"));
        } catch (Throwable t) {
            l.add(new Sonuc("Uygulamanın ana ekranı", 0, t.toString()));
        }

        // Flutter ana ekranında gizlenmiş bölüm var mı
        try {
            java.util.Map<String, ?> f = c.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).getAll();
            StringBuilder gizli = new StringBuilder();
            for (String[] b : new String[][]{{"flutter.home.showLearning.v2", "Öğrenme (Kur'an, Elif-Ba)"},
                    {"flutter.home.showSpiritual.v2", "Manevi"}, {"flutter.home.showDiscovery.v2", "Keşfet"}}) {
                if (Boolean.FALSE.equals(f.get(b[0]))) gizli.append(gizli.length() > 0 ? ", " : "").append(b[1]);
            }
            l.add(new Sonuc("Uygulama ana ekranı bölümleri", gizli.length() == 0 ? 1 : 0,
                    gizli.length() == 0 ? "hepsi görünür" : "gizli: " + gizli));
        } catch (Throwable ignored) {
        }

        // Çalma servisi tanımlı mı
        try {
            c.getPackageManager().getServiceInfo(new ComponentName(c, TilavetServisi.class), 0);
            l.add(new Sonuc("Tilavet servisi", 1, "tanımlı"));
        } catch (Throwable t) {
            l.add(new Sonuc("Tilavet servisi", -1, "manifestte yok"));
        }

        // Ağ
        l.add(ag("Tilavet sunucusu (everyayah.com)", Kuran.ayetSesi(Kuran.HAFIZLAR[0][0], 1, 1)));
        if (meal != null) l.add(ag("Sesli meal sunucusu", meal[1]));

        // Bildirimler
        List<BildirimKontrol.Sorun> sorunlar = BildirimKontrol.sorunlariBul(c, false);
        StringBuilder sb = new StringBuilder();
        for (BildirimKontrol.Sorun s : sorunlar) sb.append(sb.length() > 0 ? ", " : "").append(s.baslik);
        l.add(new Sonuc("Bildirim ayarları", sorunlar.isEmpty() ? 1 : 0, sorunlar.isEmpty() ? "sorun yok" : sb.toString()));

        String h = Hata.son(c);
        l.add(new Sonuc("Son hata kaydı", h == null ? 1 : 0, h == null ? "yok" : h));
        return l;
    }

    private static long boyut(Context c, String yol) {
        try (InputStream in = Varlik.flutter(c, yol)) {
            if (in == null) return -1;
            long n = 0;
            byte[] b = new byte[64 * 1024];
            int r;
            while ((r = in.read(b)) > 0) n += r;
            return n;
        } catch (Throwable t) {
            return -1;
        }
    }

    private static Sonuc ag(String ad, String adres) {
        HttpURLConnection b = null;
        try {
            b = (HttpURLConnection) new URL(adres).openConnection();
            b.setRequestMethod("HEAD");
            b.setConnectTimeout(7000);
            b.setReadTimeout(7000);
            b.setInstanceFollowRedirects(true);
            int kod = b.getResponseCode();
            return new Sonuc(ad, kod >= 200 && kod < 400 ? 1 : -1, "HTTP " + kod);
        } catch (Throwable t) {
            return new Sonuc(ad, -1, "bağlanamadı: " + t.getClass().getSimpleName()
                    + (t.getMessage() == null ? "" : " " + t.getMessage()));
        } finally {
            if (b != null) b.disconnect();
        }
    }

    static String rapor(Context c, List<Sonuc> l) {
        StringBuilder r = new StringBuilder("Secde Vakti denetim raporu\n");
        try {
            PackageInfo pi = c.getPackageManager().getPackageInfo(c.getPackageName(), 0);
            r.append("Sürüm: ").append(pi.versionName).append('\n');
        } catch (Throwable ignored) {
        }
        r.append("Cihaz: ").append(Build.MANUFACTURER).append(' ').append(Build.MODEL)
                .append(", Android ").append(Build.VERSION.RELEASE).append(" (API ").append(Build.VERSION.SDK_INT).append(")\n");
        r.append("Zaman: ").append(Metinler.gunVeSaat(System.currentTimeMillis())).append("\n\n");
        for (Sonuc s : l) {
            r.append(s.seviye > 0 ? "✓ " : s.seviye == 0 ? "! " : "✗ ").append(s.ad).append(": ").append(s.ayrinti).append('\n');
        }
        return r.toString();
    }
}
