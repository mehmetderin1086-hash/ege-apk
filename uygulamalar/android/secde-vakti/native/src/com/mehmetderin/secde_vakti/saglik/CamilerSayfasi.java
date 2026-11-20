package com.mehmetderin.secde_vakti.saglik;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.BlurMaskFilter;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.DashPathEffect;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RadialGradient;
import android.graphics.Shader;
import android.graphics.SweepGradient;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.text.TextUtils;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.HapticFeedbackConstants;
import android.view.MotionEvent;
import android.view.View;
import android.widget.FrameLayout;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Collections;
import java.util.List;
import java.util.Locale;

/**
 * Yakındaki Camiler Konum Radarı (OpenStreetMap Overpass + çevrimdışı önbellek + Canvas radar),
 * haftalık sıfırlanan Cuma Sünnetleri Kontrol Listesi ve Bayram · Terâvih · Teheccüd · Vitir · Cenâze
 * Namazı adım adım fıkıh rehberi.
 */
public final class CamilerSayfasi {

    private static final double VARSAYILAN_ENLEM = 41.0054;
    private static final double VARSAYILAN_BOYLAM = 28.9768;
    private static final String SP_AD = "secde_camiler";

    private static final String[] OVERPASS_ADRESLERI = {
            "https://overpass-api.de/api/interpreter",
            "https://overpass.kumi.systems/api/interpreter"
    };

    private static final int[] YARICAPLAR = {1000, 3000, 5000};
    private static final String[] YARICAP_ETIKET = {"1 km", "3 km", "5 km"};

    private static final String[][] CUMA_SUNNETLERI = {
            {"gusul", "Boy abdesti (gusül) almak",
                    "\"Cuma günü gusletmek, ergenlik çağına ulaşan her Müslüman için müekked bir vazifedir.\" (Buhârî, Cuma 2)"},
            {"kiyafet", "Temiz kıyafet ve güzel koku",
                    "En temiz elbiseleri giymek, misvak/ağız bakımı yapmak ve kimseyi rahatsız etmeyecek güzel koku (îtır) sürünmek."},
            {"kehf", "Kehf Sûresi okumak",
                    "\"Kim Cuma günü Kehf Sûresi'ni okursa, iki Cuma arasını aydınlatan mânevî bir nûr ihsân edilir.\" (Hâkim)"},
            {"salavat", "Çokça Salavât-ı Şerîfe getirmek",
                    "\"Cuma günü ve gecesi bana çokça salavât getirin; zîra salavâtınız bana arz olunur.\" (Ebû Dâvûd, Vitir 26)"},
            {"erken", "Camiye erken gitmek",
                    "Ezanı beklemeden yürüyerek camiye gitmek, cemaatin omuzlarını yarıp geçmemek ve tahiyyetü'l-mescid kılmak."},
            {"hutbe", "Hutbeyi huşû ile dinlemek",
                    "İmam minbere çıktığında dünya kelâmını kesip kalbiyle ve kulağıyla tam bir sükûnet içinde hutbeyi dinlemek."},
            {"temizlik", "Tırnak ve temizlik bakımı",
                    "Tırnakları kesmek ve fıtrî sünnet temizliklerini Cuma namazı vaktinden evvel tamamlamak."},
            {"icabet", "İcâbet saatinde duâ etmek",
                    "Cuma gününde duâların geri çevrilmediği gizli icâbet vaktini (hutbe–namaz arası veya ikindi sonrası) duâ ile değerlendirmek."}
    };

    /** Bulunan cami kaydı. */
    public static final class Cami implements Comparable<Cami> {
        public final String ad;
        public final String adres;
        public final double enlem;
        public final double boylam;
        public final double mesafeMetre;
        public final double kerteriz;

        Cami(String ad, String adres, double enlem, double boylam, double mesafeMetre, double kerteriz) {
            this.ad = ad;
            this.adres = adres;
            this.enlem = enlem;
            this.boylam = boylam;
            this.mesafeMetre = mesafeMetre;
            this.kerteriz = kerteriz;
        }

        @Override
        public int compareTo(Cami o) {
            return Double.compare(this.mesafeMetre, o.mesafeMetre);
        }
    }

    private CamilerSayfasi() {}

    /** Yakındaki Camiler, Cuma Sünnetleri ve Bayram/Cenâze Rehberi alt sayfasını açar. */
    public static void sayfaAc(final DurumAktivitesi a, VakitTakvimi.Takvim takvimGirdi) {
        if (a == null) return;
        a.guvenli("camilerSayfasi", () -> {
            final VakitTakvimi.Takvim t = takvimGirdi != null ? takvimGirdi : VakitTakvimi.oku(a);
            final TemaMotoru.Durum tema = TemaMotoru.aktif(a);
            final SharedPreferences sp = a.getSharedPreferences(SP_AD, Context.MODE_PRIVATE);

            final LinearLayout dis = a.sutun();

            // Üst sekme (mod) seçici çipler
            HorizontalScrollView modYatay = new HorizontalScrollView(a);
            modYatay.setHorizontalScrollBarEnabled(false);
            modYatay.setOverScrollMode(View.OVER_SCROLL_NEVER);
            final LinearLayout modSatir = new LinearLayout(a);
            modSatir.setOrientation(LinearLayout.HORIZONTAL);
            modYatay.addView(modSatir);
            dis.addView(modYatay, new LinearLayout.LayoutParams(-1, -2));
            a.bosluk(dis, 12);

            final LinearLayout govde = new LinearLayout(a);
            govde.setOrientation(LinearLayout.VERTICAL);
            dis.addView(govde, new LinearLayout.LayoutParams(-1, -2));

            final String[] modAdlari = {
                    "Yakındaki Camiler",
                    "Cuma Sünnetleri",
                    "Bayram ve Cenâze Rehberi"
            };
            final int[] aktifMod = {Math.max(0, Math.min(2, sp.getInt("son_mod", 0)))};
            final Runnable[] modCiz = new Runnable[1];

            modCiz[0] = () -> {
                modSatir.removeAllViews();
                for (int i = 0; i < modAdlari.length; i++) {
                    final int idx = i;
                    boolean secili = aktifMod[0] == i;
                    TextView cip = cipOlustur(a, tema, modAdlari[i], secili, v -> {
                        if (aktifMod[0] == idx) return;
                        aktifMod[0] = idx;
                        sp.edit().putInt("son_mod", idx).apply();
                        modCiz[0].run();
                    });
                    modSatir.addView(cip);
                }
                govde.removeAllViews();
                if (aktifMod[0] == 0) {
                    yakindakiCamilerModu(a, tema, sp, t, govde);
                } else if (aktifMod[0] == 1) {
                    cumaSunnetleriModu(a, tema, sp, govde);
                } else {
                    bayramVeCenazeModu(a, tema, govde);
                }
            };

            modCiz[0].run();

            ScrollView sv = a.sayfa(dis);
            sv.setPadding(0, 0, 0, 0);
            a.altSayfa("Yakındaki Camiler ve Rehber", sv, "kible_bg");
        });
    }

    // ================================================================ MOD 1 · YAKINDAKİ CAMİLER

    private static void yakindakiCamilerModu(final DurumAktivitesi a,
                                             final TemaMotoru.Durum tema,
                                             final SharedPreferences sp,
                                             final VakitTakvimi.Takvim t,
                                             final LinearLayout govde) {
        final boolean gercekKonum = t != null && !Double.isNaN(t.enlem) && !Double.isNaN(t.boylam);
        final double enlem = gercekKonum ? t.enlem : VARSAYILAN_ENLEM;
        final double boylam = gercekKonum ? t.boylam : VARSAYILAN_BOYLAM;
        final double kibleDerece = Kible.yon(enlem, boylam);

        if (!gercekKonum) {
            LinearLayout uyariKart = kart(a, tema);
            GradientDrawable ug = new GradientDrawable();
            ug.setCornerRadius(a.dp(18));
            ug.setColor(tema.acik ? 0x1FB26200 : 0x33FFC66D);
            ug.setStroke(Math.max(1, a.dp(1)), tema.acik ? 0x66B26200 : 0x80FFC66D);
            uyariKart.setBackground(ug);
            uyariKart.addView(yazi(a, tema, "KONUM BİLGİSİ", 11, tema.uyari, true));
            uyariKart.addView(yazi(a, tema,
                    "Varsayılan konum (İstanbul) gösteriliyor; kendi konumunuz için vakit konumunu güncelleyin",
                    14, tema.metin, false));
            uyariKart.addView(dugme(a, tema, "Haritada Yakınımdaki Camileri Aç", true,
                    v -> haritaSorguAc(a, "geo:0,0?q=cami", "https://www.google.com/maps/search/?api=1&query=cami")));
            govde.addView(uyariKart);
        }

        // Yarıçap seçici + Yenile + Harita kısayolu
        LinearLayout ustCubuk = new LinearLayout(a);
        ustCubuk.setOrientation(LinearLayout.HORIZONTAL);
        ustCubuk.setGravity(Gravity.CENTER_VERTICAL);

        final int[] seciliYaricapIdx = {yaricapIndeksi(sp.getInt("yaricap_m", 3000))};
        final LinearLayout yaricapKutu = new LinearLayout(a);
        yaricapKutu.setOrientation(LinearLayout.HORIZONTAL);
        ustCubuk.addView(yaricapKutu, new LinearLayout.LayoutParams(0, -2, 1f));

        final Runnable[] veriYukle = new Runnable[1];
        final boolean[] zorlaAg = {false};

        TextView yenileDugme = cipOlustur(a, tema, "Yenile ↻", false, v -> {
            zorlaAg[0] = true;
            if (veriYukle[0] != null) veriYukle[0].run();
        });
        ustCubuk.addView(yenileDugme);
        govde.addView(ustCubuk);
        a.bosluk(govde, 10);

        // Radar Kartı
        LinearLayout radarKart = kart(a, tema);
        radarKart.setGravity(Gravity.CENTER_HORIZONTAL);
        String konumBaslik = gercekKonum && t.yer != null && !t.yer.isEmpty()
                ? t.yer
                : (gercekKonum ? String.format(Locale.ROOT, "%.4f°, %.4f°", enlem, boylam) : "İstanbul · Sultanahmet");
        TextView ustBilgi = yazi(a, tema, konumBaslik + "  ·  Kıble " + Math.round(kibleDerece) + "° (" + Kible.yonAdi(kibleDerece) + ")",
                13, tema.soluk, true);
        ustBilgi.setGravity(Gravity.CENTER);
        radarKart.addView(ustBilgi);
        a.bosluk(radarKart, 8);

        final CamiRadarView radar = new CamiRadarView(a);
        radar.kibleAyarla(kibleDerece);
        int radarBoy = a.dp(234);
        FrameLayout radarKabi = new FrameLayout(a);
        radarKabi.addView(radar, new FrameLayout.LayoutParams(radarBoy, radarBoy, Gravity.CENTER));
        radarKart.addView(radarKabi, new LinearLayout.LayoutParams(-1, radarBoy));

        final TextView seciliEtiket = yazi(a, tema,
                "Altın ışın Kıble yönünü, zümrüt noktalar yakındaki camileri gösterir.",
                12, tema.silik, false);
        seciliEtiket.setGravity(Gravity.CENTER);
        seciliEtiket.setPadding(a.dp(6), a.dp(8), a.dp(6), 0);
        radarKart.addView(seciliEtiket);

        radar.secimDinleyici(cami -> {
            if (cami != null) {
                seciliEtiket.setText("✦ " + cami.ad + " · " + mesafeMetni(cami.mesafeMetre)
                        + " · " + Kible.yonAdi(cami.kerteriz));
                seciliEtiket.setTextColor(tema.vurgu);
            }
        });

        govde.addView(radarKart);

        // Durum satırı ve liste kabı
        final TextView durumMetni = yazi(a, tema, "Yakındaki camiler aranıyor…", 13, tema.soluk, true);
        durumMetni.setPadding(a.dp(4), a.dp(2), a.dp(4), a.dp(8));
        govde.addView(durumMetni);

        final LinearLayout listeKabi = new LinearLayout(a);
        listeKabi.setOrientation(LinearLayout.VERTICAL);
        govde.addView(listeKabi);

        if (gercekKonum) {
            govde.addView(dugme(a, tema, "Haritada Yakınımdaki Camileri Aç", false,
                    v -> haritaSorguAc(a,
                            String.format(Locale.ROOT, "geo:%.5f,%.5f?q=cami", enlem, boylam),
                            "https://www.google.com/maps/search/?api=1&query=cami")));
        }

        final int[] istekNo = {0};

        final Runnable yaricapCiz = new Runnable() {
            @Override
            public void run() {
                yaricapKutu.removeAllViews();
                for (int i = 0; i < YARICAPLAR.length; i++) {
                    final int idx = i;
                    boolean secili = seciliYaricapIdx[0] == i;
                    TextView c = cipOlustur(a, tema, YARICAP_ETIKET[i], secili, v -> {
                        if (seciliYaricapIdx[0] == idx) return;
                        seciliYaricapIdx[0] = idx;
                        sp.edit().putInt("yaricap_m", YARICAPLAR[idx]).apply();
                        run();
                        veriYukle[0].run();
                    });
                    yaricapKutu.addView(c);
                }
            }
        };

        veriYukle[0] = () -> {
            final int buIstek = ++istekNo[0];
            final int yaricap = YARICAPLAR[seciliYaricapIdx[0]];
            final String onbellekAnahtar = onbellekAnahtari(enlem, boylam, yaricap);
            final String zamanAnahtar = onbellekAnahtar + "_zaman";
            final boolean zorla = zorlaAg[0];
            zorlaAg[0] = false;

            radar.yaricapAyarla(yaricap);

            String kayitliJson = sp.getString(onbellekAnahtar, null);
            long kayitZamani = sp.getLong(zamanAnahtar, 0L);
            List<Cami> onbellekListe = kayitliJson != null ? jsonCoz(kayitliJson, enlem, boylam, yaricap) : null;

            if (onbellekListe != null && !onbellekListe.isEmpty()) {
                radar.camileriAyarla(onbellekListe);
                listeDoldur(a, tema, listeKabi, onbellekListe);
                durumMetni.setText(onbellekListe.size() + " cami bulundu (" + (yaricap / 1000) + " km yarıçap)");
                durumMetni.setTextColor(tema.iyi);
                boolean taze = (System.currentTimeMillis() - kayitZamani) < 12L * 3600_000L;
                if (taze && !zorla) return;
                durumMetni.setText(onbellekListe.size() + " cami (güncelleniyor…)");
            } else {
                listeKabi.removeAllViews();
                radar.camileriAyarla(Collections.<Cami>emptyList());
                durumMetni.setText("OpenStreetMap üzerinden " + (yaricap / 1000) + " km çevredeki camiler taranıyor…");
                durumMetni.setTextColor(tema.soluk);
            }

            final boolean onbellekVar = onbellekListe != null && !onbellekListe.isEmpty();
            new Thread(() -> {
                final String yeniJson = overpassSorgula(enlem, boylam, yaricap);
                final List<Cami> yeniListe = yeniJson != null ? jsonCoz(yeniJson, enlem, boylam, yaricap) : null;
                if (yeniJson != null && yeniListe != null) {
                    sp.edit()
                            .putString(onbellekAnahtar, yeniJson)
                            .putLong(zamanAnahtar, System.currentTimeMillis())
                            .apply();
                }
                if (a.isFinishing() || a.isDestroyed()) return;
                a.runOnUiThread(() -> {
                    if (buIstek != istekNo[0] || a.isFinishing() || a.isDestroyed()) return;
                    if (yeniListe != null) {
                        radar.camileriAyarla(yeniListe);
                        listeDoldur(a, tema, listeKabi, yeniListe);
                        if (yeniListe.isEmpty()) {
                            durumMetni.setText((yaricap / 1000) + " km çevrede kayıtlı cami bulunamadı; yarıçapı büyütmeyi deneyin.");
                            durumMetni.setTextColor(tema.uyari);
                        } else {
                            durumMetni.setText(yeniListe.size() + " cami bulundu · en yakını " + mesafeMetni(yeniListe.get(0).mesafeMetre));
                            durumMetni.setTextColor(tema.iyi);
                        }
                    } else if (onbellekVar) {
                        durumMetni.setText("Çevrimdışı önbellekten gösteriliyor · internet gelince yenileyebilirsiniz.");
                        durumMetni.setTextColor(tema.soluk);
                    } else {
                        durumMetni.setText("İnternet bağlantısı kurulamadı. Çevrimdışı harita uygulamasından camileri açabilirsiniz.");
                        durumMetni.setTextColor(tema.uyari);
                    }
                });
            }, "secde-camiler-overpass").start();
        };

        yaricapCiz.run();
        veriYukle[0].run();
    }

    private static void listeDoldur(final DurumAktivitesi a,
                                    final TemaMotoru.Durum tema,
                                    final LinearLayout listeKabi,
                                    final List<Cami> camiler) {
        listeKabi.removeAllViews();
        for (int i = 0; i < camiler.size(); i++) {
            final Cami c = camiler.get(i);
            LinearLayout k = kart(a, tema);

            LinearLayout ust = new LinearLayout(a);
            ust.setOrientation(LinearLayout.HORIZONTAL);
            ust.setGravity(Gravity.CENTER_VERTICAL);

            TextView siraRozet = yazi(a, tema, String.valueOf(i + 1), 12, tema.vurgu, true);
            siraRozet.setGravity(Gravity.CENTER);
            GradientDrawable rg = new GradientDrawable();
            rg.setShape(GradientDrawable.OVAL);
            rg.setColor((tema.vurgu & 0x00FFFFFF) | 0x28000000);
            rg.setStroke(Math.max(1, a.dp(1)), (tema.vurgu & 0x00FFFFFF) | 0x88000000);
            siraRozet.setBackground(rg);
            ust.addView(siraRozet, new LinearLayout.LayoutParams(a.dp(30), a.dp(30)));

            LinearLayout baslikAlan = new LinearLayout(a);
            baslikAlan.setOrientation(LinearLayout.VERTICAL);
            baslikAlan.setPadding(a.dp(10), 0, a.dp(6), 0);
            baslikAlan.addView(yazi(a, tema, c.ad, 16, tema.metin, true));
            int yuruyusDk = Math.max(1, Math.round((float) c.mesafeMetre / 80f));
            String altBilgi = mesafeMetni(c.mesafeMetre) + "  ·  " + yuruyusDk + " dk yürüyüş  ·  " + Kible.yonAdi(c.kerteriz);
            baslikAlan.addView(yazi(a, tema, altBilgi, 13, tema.iyi, true));
            if (c.adres != null && !c.adres.isEmpty()) {
                baslikAlan.addView(yazi(a, tema, c.adres, 12, tema.soluk, false));
            }
            ust.addView(baslikAlan, new LinearLayout.LayoutParams(0, -2, 1f));

            TextView yolDugme = yazi(a, tema, "Yol Tarifi ›", 13, tema.birincilDugmeYaziRengi(), true);
            yolDugme.setShadowLayer(0, 0, 0, 0);
            yolDugme.setGravity(Gravity.CENTER);
            yolDugme.setPadding(a.dp(12), a.dp(8), a.dp(12), a.dp(8));
            yolDugme.setBackground(tema.birincilDugme(a, 14));
            yolDugme.setClickable(true);
            a.basmaEfekti(yolDugme);
            yolDugme.setOnClickListener(v -> {
                v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
                yolTarifiAc(a, c);
            });
            ust.addView(yolDugme);

            k.addView(ust);
            listeKabi.addView(k);
        }
    }

    private static void yolTarifiAc(Context c, Cami cami) {
        String koordinat = String.format(Locale.ROOT, "%.6f,%.6f", cami.enlem, cami.boylam);
        String etiketli = koordinat + "(" + cami.ad + ")";
        String geoUri = "geo:" + koordinat + "?q=" + Uri.encode(etiketli);
        String webYedek = "https://www.google.com/maps/search/?api=1&query=" + Uri.encode(koordinat);
        haritaSorguAc(c, geoUri, webYedek);
    }

    private static void haritaSorguAc(Context c, String geoUri, String webYedek) {
        try {
            Intent i = new Intent(Intent.ACTION_VIEW, Uri.parse(geoUri));
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            c.startActivity(i);
            return;
        } catch (Throwable ignored) {
        }
        try {
            Intent w = new Intent(Intent.ACTION_VIEW, Uri.parse(webYedek));
            w.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            c.startActivity(w);
        } catch (Throwable t) {
            Toast.makeText(c, "Harita uygulaması bulunamadı", Toast.LENGTH_SHORT).show();
        }
    }

    private static String onbellekAnahtari(double enlem, double boylam, int yaricapMetre) {
        return String.format(Locale.ROOT, "c_%.3f_%.3f_%d", enlem, boylam, yaricapMetre);
    }

    private static int yaricapIndeksi(int metre) {
        for (int i = 0; i < YARICAPLAR.length; i++) {
            if (YARICAPLAR[i] == metre) return i;
        }
        return 1;
    }

    private static String overpassSorgula(double enlem, double boylam, int yaricapMetre) {
        String sorgu = String.format(Locale.ROOT,
                "[out:json][timeout:10];(node[\"amenity\"=\"place_of_worship\"][\"religion\"=\"muslim\"](around:%d,%.5f,%.5f);"
                        + "way[\"amenity\"=\"place_of_worship\"][\"religion\"=\"muslim\"](around:%d,%.5f,%.5f););out center 35;",
                yaricapMetre, enlem, boylam, yaricapMetre, enlem, boylam);
        for (String adres : OVERPASS_ADRESLERI) {
            HttpURLConnection bag = null;
            try {
                byte[] veri = ("data=" + URLEncoder.encode(sorgu, "UTF-8")).getBytes(StandardCharsets.UTF_8);
                bag = (HttpURLConnection) new URL(adres).openConnection();
                bag.setRequestMethod("POST");
                bag.setConnectTimeout(8000);
                bag.setReadTimeout(8000);
                bag.setDoOutput(true);
                bag.setRequestProperty("User-Agent", "SecdeVakti/2.0");
                bag.setRequestProperty("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8");
                bag.setRequestProperty("Accept", "application/json");
                try (OutputStream out = bag.getOutputStream()) {
                    out.write(veri);
                }
                int kod = bag.getResponseCode();
                if (kod >= 200 && kod < 300) {
                    try (InputStream in = bag.getInputStream()) {
                        ByteArrayOutputStream tampon = new ByteArrayOutputStream();
                        byte[] dizi = new byte[16 * 1024];
                        int okunan;
                        while ((okunan = in.read(dizi)) > 0) tampon.write(dizi, 0, okunan);
                        String yanit = new String(tampon.toByteArray(), StandardCharsets.UTF_8);
                        if (yanit.contains("\"elements\"")) return yanit;
                    }
                }
            } catch (Throwable ignored) {
            } finally {
                if (bag != null) {
                    try {
                        bag.disconnect();
                    } catch (Throwable ignored) {
                    }
                }
            }
        }
        return null;
    }

    static List<Cami> jsonCoz(String hamJson, double merkezEnlem, double merkezBoylam, int yaricapMetre) {
        List<Cami> hamListe = new ArrayList<>();
        try {
            JSONObject kok = new JSONObject(hamJson);
            JSONArray elemanlar = kok.optJSONArray("elements");
            if (elemanlar == null) return hamListe;
            for (int i = 0; i < elemanlar.length(); i++) {
                JSONObject e = elemanlar.optJSONObject(i);
                if (e == null) continue;
                double cEnlem = e.optDouble("lat", Double.NaN);
                double cBoylam = e.optDouble("lon", Double.NaN);
                if (Double.isNaN(cEnlem) || Double.isNaN(cBoylam)) {
                    JSONObject merkez = e.optJSONObject("center");
                    if (merkez != null) {
                        cEnlem = merkez.optDouble("lat", Double.NaN);
                        cBoylam = merkez.optDouble("lon", Double.NaN);
                    }
                }
                if (Double.isNaN(cEnlem) || Double.isNaN(cBoylam)) continue;
                JSONObject etiketler = e.optJSONObject("tags");
                String ad = "";
                String adres = "";
                if (etiketler != null) {
                    ad = etiketler.optString("name:tr", "").trim();
                    if (ad.isEmpty()) ad = etiketler.optString("name", "").trim();
                    if (ad.isEmpty()) ad = etiketler.optString("official_name", "").trim();
                    String mahalle = ilkDolu(
                            etiketler.optString("addr:neighbourhood", ""),
                            etiketler.optString("addr:suburb", ""),
                            etiketler.optString("addr:quarter", ""),
                            etiketler.optString("addr:district", ""));
                    String sokak = etiketler.optString("addr:street", "").trim();
                    if (!mahalle.isEmpty() && !sokak.isEmpty()) adres = mahalle + " · " + sokak;
                    else if (!mahalle.isEmpty()) adres = mahalle;
                    else if (!sokak.isEmpty()) adres = sokak;
                }
                if (ad.isEmpty()) ad = "Cami / Mescid";
                double mesafe = haversineMetre(merkezEnlem, merkezBoylam, cEnlem, cBoylam);
                if (mesafe > yaricapMetre * 1.25) continue;
                double kerteriz = kerterizDerece(merkezEnlem, merkezBoylam, cEnlem, cBoylam);
                hamListe.add(new Cami(ad, adres, cEnlem, cBoylam, mesafe, kerteriz));
            }
        } catch (Throwable ignored) {
        }
        Collections.sort(hamListe);
        // Aynı caminin hem bina (way) hem nokta (node) kaydı varsa 40 m içindeki kopyayı tekilleştir
        List<Cami> tekil = new ArrayList<>();
        for (Cami aday : hamListe) {
            boolean kopya = false;
            for (Cami mevcut : tekil) {
                double ara = haversineMetre(aday.enlem, aday.boylam, mevcut.enlem, mevcut.boylam);
                if (ara < 40.0 && (aday.ad.equalsIgnoreCase(mevcut.ad) || "Cami / Mescid".equals(aday.ad))) {
                    kopya = true;
                    break;
                }
            }
            if (!kopya) {
                tekil.add(aday);
                if (tekil.size() >= 30) break;
            }
        }
        return tekil;
    }

    private static String ilkDolu(String... adaylar) {
        for (String s : adaylar) {
            if (s != null && !s.trim().isEmpty()) return s.trim();
        }
        return "";
    }

    static double haversineMetre(double en1, double boy1, double en2, double boy2) {
        double f1 = Math.toRadians(en1), f2 = Math.toRadians(en2);
        double df = f2 - f1, dl = Math.toRadians(boy2 - boy1);
        double a = Math.sin(df / 2.0) * Math.sin(df / 2.0)
                + Math.cos(f1) * Math.cos(f2) * Math.sin(dl / 2.0) * Math.sin(dl / 2.0);
        return 6371008.8 * 2.0 * Math.atan2(Math.sqrt(a), Math.sqrt(Math.max(0.0, 1.0 - a)));
    }

    static double kerterizDerece(double en1, double boy1, double en2, double boy2) {
        double f1 = Math.toRadians(en1), f2 = Math.toRadians(en2);
        double dl = Math.toRadians(boy2 - boy1);
        double y = Math.sin(dl) * Math.cos(f2);
        double x = Math.cos(f1) * Math.sin(f2) - Math.sin(f1) * Math.cos(f2) * Math.cos(dl);
        return (Math.toDegrees(Math.atan2(y, x)) + 360.0) % 360.0;
    }

    private static String mesafeMetni(double metre) {
        if (metre < 1000.0) return Math.max(1L, Math.round(metre)) + " m";
        return String.format(Metinler.TR, "%.1f km", metre / 1000.0);
    }

    // ================================================================ MOD 2 · CUMA SÜNNETLERİ

    /** Her Cuma günü 00:00 itibarıyla yenilenen yyyy-ww hafta anahtarı. */
    static String cumaHaftaAnahtari(long simdiMs) {
        Calendar cal = Calendar.getInstance();
        cal.setTimeInMillis(simdiMs);
        cal.setFirstDayOfWeek(Calendar.FRIDAY);
        cal.setMinimalDaysInFirstWeek(1);
        int yil = cal.get(Calendar.YEAR);
        int hafta = cal.get(Calendar.WEEK_OF_YEAR);
        // Yıl sonu/başı geçişinde hafta 1'e dönerse yılı da uyumlu tut
        if (cal.get(Calendar.MONTH) == Calendar.DECEMBER && hafta == 1) yil++;
        return String.format(Locale.ROOT, "%04d-%02d", yil, hafta);
    }

    private static void cumaSunnetleriModu(final DurumAktivitesi a,
                                           final TemaMotoru.Durum tema,
                                           final SharedPreferences sp,
                                           final LinearLayout govde) {
        final String haftaAnahtar = cumaHaftaAnahtari(System.currentTimeMillis());
        Calendar bugun = Calendar.getInstance();
        boolean bugunCuma = bugun.get(Calendar.DAY_OF_WEEK) == Calendar.FRIDAY;

        // Üst ilerleme özeti kartı
        LinearLayout ozetKart = kart(a, tema);
        ozetKart.addView(yazi(a, tema,
                bugunCuma ? "MÜBÂREK CUMA GÜNÜ · HAFTALIK SÜNNET TAKİBİ" : "CUMA SÜNNETLERİ KONTROL LİSTESİ",
                11, tema.vurgu, true));
        final TextView sayacBaslik = yazi(a, tema, "", 20, tema.metin, true);
        ozetKart.addView(sayacBaslik);
        final TextView altAciklama = yazi(a, tema,
                "Hafta anahtarı (" + haftaAnahtar + ") ile her Cuma sabahı liste otomatik yenilenir.",
                13, tema.soluk, false);
        ozetKart.addView(altAciklama);
        a.bosluk(ozetKart, 8);

        // İlerleme çubuğu
        FrameLayout cubukDis = new FrameLayout(a);
        GradientDrawable cdArka = new GradientDrawable();
        cdArka.setCornerRadius(a.dp(6));
        cdArka.setColor(tema.acik ? 0x2214211C : 0x33FFFFFF);
        cubukDis.setBackground(cdArka);
        final View cubukIc = new View(a);
        GradientDrawable ciArka = new GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT,
                new int[]{tema.vurguKoyu, tema.vurgu});
        ciArka.setCornerRadius(a.dp(6));
        cubukIc.setBackground(ciArka);
        cubukDis.addView(cubukIc, new FrameLayout.LayoutParams(0, a.dp(10)));
        ozetKart.addView(cubukDis, new LinearLayout.LayoutParams(-1, a.dp(10)));
        govde.addView(ozetKart);

        final LinearLayout maddelerKabi = new LinearLayout(a);
        maddelerKabi.setOrientation(LinearLayout.VERTICAL);
        govde.addView(maddelerKabi);

        final Runnable guncelle = new Runnable() {
            @Override
            public void run() {
                int tamam = 0;
                for (String[] m : CUMA_SUNNETLERI) {
                    if (sp.getBoolean("cuma_" + haftaAnahtar + "_" + m[0], false)) tamam++;
                }
                sayacBaslik.setText(tamam == CUMA_SUNNETLERI.length
                        ? "Elhamdülillah · 8 / 8 Sünnet Tamamlandı!"
                        : "Tamamlanan: " + tamam + " / " + CUMA_SUNNETLERI.length + " Sünnet");
                sayacBaslik.setTextColor(tamam == CUMA_SUNNETLERI.length ? tema.iyi : tema.metin);

                final int tamamSayisi = tamam;
                cubukDis.post(() -> {
                    int tamGen = cubukDis.getWidth();
                    if (tamGen <= 0) return;
                    FrameLayout.LayoutParams lp = (FrameLayout.LayoutParams) cubukIc.getLayoutParams();
                    lp.width = Math.round(tamGen * (tamamSayisi / (float) CUMA_SUNNETLERI.length));
                    cubukIc.setLayoutParams(lp);
                });

                maddelerKabi.removeAllViews();
                for (final String[] m : CUMA_SUNNETLERI) {
                    final String kod = m[0];
                    final String anahtar = "cuma_" + haftaAnahtar + "_" + kod;
                    final boolean isaretli = sp.getBoolean(anahtar, false);

                    LinearLayout satirKart = kart(a, tema);
                    LinearLayout ust = new LinearLayout(a);
                    ust.setOrientation(LinearLayout.HORIZONTAL);
                    ust.setGravity(Gravity.CENTER_VERTICAL);

                    TextView kutu = yazi(a, tema, isaretli ? "✓" : "", 16,
                            isaretli ? tema.birincilDugmeYaziRengi() : tema.metin, true);
                    kutu.setShadowLayer(0, 0, 0, 0);
                    kutu.setGravity(Gravity.CENTER);
                    GradientDrawable kg = new GradientDrawable();
                    kg.setCornerRadius(a.dp(9));
                    if (isaretli) {
                        kg.setColors(new int[]{tema.vurguKoyu, tema.vurgu});
                    } else {
                        kg.setColor(tema.acik ? 0x1414211C : 0x22FFFFFF);
                        kg.setStroke(Math.max(1, a.dp(1)), tema.acik ? 0x5514211C : 0x66FFFFFF);
                    }
                    kutu.setBackground(kg);
                    ust.addView(kutu, new LinearLayout.LayoutParams(a.dp(30), a.dp(30)));

                    LinearLayout metinAlan = new LinearLayout(a);
                    metinAlan.setOrientation(LinearLayout.VERTICAL);
                    metinAlan.setPadding(a.dp(12), 0, 0, 0);
                    TextView baslik = yazi(a, tema, m[1], 16, isaretli ? tema.vurgu : tema.metin, true);
                    metinAlan.addView(baslik);
                    metinAlan.addView(yazi(a, tema, m[2], 13, tema.soluk, false));
                    ust.addView(metinAlan, new LinearLayout.LayoutParams(0, -2, 1f));

                    satirKart.addView(ust);

                    if ("kehf".equals(kod)) {
                        TextView kehfDugme = dugme(a, tema, "Kehf Sûresi'ni Aç ›", false, v -> {
                            if (a.kuranArayuz != null) a.kuranArayuz.sureAc(18, 1);
                        });
                        satirKart.addView(kehfDugme);
                    }

                    satirKart.setClickable(true);
                    a.basmaEfekti(satirKart);
                    satirKart.setOnClickListener(v -> {
                        v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
                        sp.edit().putBoolean(anahtar, !isaretli).apply();
                        run();
                    });

                    maddelerKabi.addView(satirKart);
                }
            }
        };
        guncelle.run();

        // Cuma Duâsı Kartı
        LinearLayout duaKart = kart(a, tema);
        duaKart.addView(yazi(a, tema, "CUMA GÜNÜ VE İCÂBET VAKTİ DUÂSI", 11, tema.vurgu, true));
        TextView arapca = yazi(a, tema,
                "اَللّٰهُمَّ يَا غَنِيُّ يَا حَمِيدُ يَا مُبْدِئُ يَا مُعِيدُ يَا رَحِيمُ يَا وَدُودُ أَغْنِنِي بِحَلَالِكَ عَنْ حَرَامِكَ وَبِطَاعَتِكَ عَنْ مَعْصِيَتِكَ وَبِفَضْلِكَ عَمَّنْ سِوَاكَ",
                23, tema.metin, false);
        arapca.setTypeface(Varlik.kuranYazisi(a));
        arapca.setLineSpacing(0, 1.35f);
        arapca.setGravity(Gravity.RIGHT);
        duaKart.addView(arapca);
        a.bosluk(duaKart, 6);
        duaKart.addView(yazi(a, tema,
                "Okunuşu: Allâhümme yâ Ğaniyyü yâ Hamîdü yâ Mübdiü yâ Muîdü yâ Rahîmü yâ Vedûd! Ağninî bi-halâlike an harâmike ve bi-tâatike an ma'siyetike ve bi-fadlike ammen sivâk.",
                13, tema.vurgu, true));
        duaKart.addView(yazi(a, tema,
                "Anlamı: Allah'ım! Ey hiçbir şeye muhtaç olmayan Ğanî, hamde lâyık Hamîd, yoktan var eden Mübdi', tekrar dirilten Muîd, sonsuz merhamet sahibi Rahîm ve kullarını seven Vedûd! Beni helâlinle yetindirip haramından koru; tâatinle meşgul edip günahlardan uzaklaştır ve lütfunla beni Senden başkasına muhtaç etme. (Tirmizî, Daavât 110)",
                13, tema.soluk, false));
        govde.addView(duaKart);
    }

    // ================================================================ MOD 3 · BAYRAM, TERÂVİH, VİTİR & CENÂZE REHBERİ

    private static void bayramVeCenazeModu(final DurumAktivitesi a,
                                           final TemaMotoru.Durum tema,
                                           final LinearLayout govde) {
        // Alt filtre çipleri: Tümü veya ilgili rehbere hızlı odaklanma
        HorizontalScrollView filtreYatay = new HorizontalScrollView(a);
        filtreYatay.setHorizontalScrollBarEnabled(false);
        filtreYatay.setOverScrollMode(View.OVER_SCROLL_NEVER);
        final LinearLayout filtreSatir = new LinearLayout(a);
        filtreSatir.setOrientation(LinearLayout.HORIZONTAL);
        filtreYatay.addView(filtreSatir);
        govde.addView(filtreYatay);
        a.bosluk(govde, 10);

        final LinearLayout kartlarKabi = new LinearLayout(a);
        kartlarKabi.setOrientation(LinearLayout.VERTICAL);
        govde.addView(kartlarKabi);

        final String[] bolumler = {"Tümü", "Bayram Namazı", "Terâvih", "Vitir ve Kunut", "Teheccüd", "Cenâze Namazı"};
        final int[] seciliFiltre = {0};
        final Runnable[] ciz = new Runnable[1];

        ciz[0] = () -> {
            filtreSatir.removeAllViews();
            for (int i = 0; i < bolumler.length; i++) {
                final int idx = i;
                filtreSatir.addView(cipOlustur(a, tema, bolumler[i], seciliFiltre[0] == i, v -> {
                    seciliFiltre[0] = idx;
                    ciz[0].run();
                }));
            }
            kartlarKabi.removeAllViews();
            int f = seciliFiltre[0];
            if (f == 0 || f == 1) bayramRehberiEkle(a, tema, kartlarKabi);
            if (f == 0 || f == 2) teravihRehberiEkle(a, tema, kartlarKabi);
            if (f == 0 || f == 3) vitirVeKunutEkle(a, tema, kartlarKabi);
            if (f == 0 || f == 4) teheccudRehberiEkle(a, tema, kartlarKabi);
            if (f == 0 || f == 5) cenazeRehberiEkle(a, tema, kartlarKabi);
        };
        ciz[0].run();
    }

    private static void bayramRehberiEkle(DurumAktivitesi a, TemaMotoru.Durum tema, LinearLayout p) {
        LinearLayout k = kart(a, tema);
        k.addView(yazi(a, tema, "2 REK'AT · VÂCİP · CEMAATLE KILINIR", 11, tema.vurgu, true));
        k.addView(yazi(a, tema, "Ramazan ve Kurban Bayramı Namazı (6 Zâid Tekbirli)", 18, tema.metin, true));
        k.addView(yazi(a, tema,
                "Bayram namazında ezan ve kamet getirilmez; hutbe ise Cuma namazının aksine namazdan sonra okunur ve dinlenmesi sünnettir.",
                13, tema.soluk, false));
        a.bosluk(k, 8);

        adimSatiri(a, tema, k, "Niyet", "İmama Uyarak Başlangıç",
                "\"Niyet ettim Allah rızâsı için Ramazan (veya Kurban) Bayramı namazını kılmaya, uydum hazır olan imama\" diyerek niyet edilir. \"Allâhu ekber\" (İftitah tekbiri) ile eller bağlanır, imamla birlikte sessizce Sübhâneke okunur.");
        adimSatiri(a, tema, k, "1–3", "1. Rek'at · 1., 2. ve 3. Zâid Tekbirler",
                "• 1. Zâid Tekbir: İmamla birlikte \"Allâhu ekber\" diyerek eller kulak hizasına kaldırılır ve iki yana salınır (3 tesbih miktarı beklenir).\n"
                        + "• 2. Zâid Tekbir: Tekrar \"Allâhu ekber\" diyerek eller kulaklara kaldırılır ve yine iki yana salınır.\n"
                        + "• 3. Zâid Tekbir: Üçüncü kez \"Allâhu ekber\" diyerek eller kulaklara kaldırılır ve bu defa göbek/göğüs altına bağlanır!\n"
                        + "Ardından imam gizlice Eûzü-Besmele, açıktan Fâtiha ve zamm-ı sûre okur (cemaat susup dinler). Rükû ve secdeler yapılarak 2. rek'ata kalkılır.");
        adimSatiri(a, tema, k, "4–6", "2. Rek'at · Kıraatten Sonra 4., 5. ve 6. Zâid Tekbirler",
                "İmam gizlice Besmele çekip açıktan Fâtiha ve zamm-ı sûreyi okuduktan sonra rükûya gitmeden önce tekbirler alınır:\n"
                        + "• 4. Zâid Tekbir: \"Allâhu ekber\" diyerek eller kulaklara kaldırılır ve yana salınır.\n"
                        + "• 5. Zâid Tekbir: \"Allâhu ekber\" diyerek eller kulaklara kaldırılır ve yana salınır.\n"
                        + "• 6. Zâid Tekbir: \"Allâhu ekber\" diyerek eller kulaklara kaldırılır ve yine yana salınır (bağlanmaz!).\n"
                        + "• Rükû Tekbiri: Hemen peşinden 7. lafız olarak \"Allâhu ekber\" denilip eller kulaklara kaldırılmadan doğrudan rükûya eğilinir.");
        adimSatiri(a, tema, k, "Son", "Son Oturuş, Selâm ve Teşrîk Tekbirleri",
                "Secdelerden sonra son oturuşta Ettehiyyâtü, Allâhümme salli, Allâhümme bârik ve Rabbenâ duâları okunup sağa ve sola selâm verilir. Kurban Bayramı'nda Arefe günü sabah namazından 4. gün ikindi namazına kadar (23 vakit) farz namazlardan hemen sonra Teşrîk Tekbiri getirmek vâciptir:\n"
                        + "\"Allâhu ekber Allâhu ekber, lâ ilâhe illallâhu vallâhu ekber, Allâhu ekber ve lillâhi'l-hamd.\"");
        p.addView(k);
    }

    private static void teravihRehberiEkle(DurumAktivitesi a, TemaMotoru.Durum tema, LinearLayout p) {
        LinearLayout k = kart(a, tema);
        k.addView(yazi(a, tema, "RAMAZAN-I ŞERİF SÜNNET-İ MÜEKKEDESİ · 8 VEYA 20 REK'AT", 11, tema.vurgu, true));
        k.addView(yazi(a, tema, "Terâvih Namazı Kılınışı Rehberi", 18, tema.metin, true));
        k.addView(yazi(a, tema,
                "Yatsı namazının 4 rek'at farzı ve 2 rek'at son sünnetinden sonra, Vitir namazından önce cemaatle veya ferdi olarak kılınır.",
                13, tema.soluk, false));
        a.bosluk(k, 8);

        adimSatiri(a, tema, k, "2'şer", "2 Rek'atta Bir Selâm Usûlü (Efdal Olan)",
                "Sabah namazının sünneti gibi her 2 rek'atta bir oturuşta Tahiyyât, Salli-Bârik ve Rabbenâ duâları okunarak selâm verilir. Yanılma ihtimâli en az ve sünnete en yakın usûldür.");
        adimSatiri(a, tema, k, "4'er", "4 Rek'atta Bir Selâm Usûlü",
                "İkindi namazının sünneti gibi kılınır: 2. rek'at sonundaki ilk oturuşta Tahiyyât ile birlikte Salli ve Bârik duâları okunur; 3. rek'ata kalkınca Sübhâneke ve Eûzü-Besmele okunup Fâtiha + zamm-ı sûre ile devam edilir.");
        adimSatiri(a, tema, k, "8/20", "8 Rek'at ve 20 Rek'at Uygulaması & Tervîha",
                "Hz. Ömer devrinden beri İslâm dünyasında cemaatle 20 rek'at (5 tervîha × 4 rek'at) kılınması yerleşmiş sünnettir; yorgunluk veya mazeret hâlinde 8 rek'at kılınması da Hz. Âişe validemizin rivâyetine dayanır. Her 4 rek'at sonunda kısa bir dinlenme (tervîha) yapılır ve Salavât-ı Ümmiyye getirilir.");
        p.addView(k);
    }

    private static void vitirVeKunutEkle(DurumAktivitesi a, TemaMotoru.Durum tema, LinearLayout p) {
        LinearLayout k = kart(a, tema);
        k.addView(yazi(a, tema, "3 REK'AT · VÂCİP · GECENİN SON NAMAZI", 11, tema.vurgu, true));
        k.addView(yazi(a, tema, "Vitir Namazı ve Kunut Duâları", 18, tema.metin, true));
        adimSatiri(a, tema, k, "1–2", "İlk İki Rek'at ve İlk Oturuş",
                "1. rek'atta Sübhâneke, Eûzü-Besmele, Fâtiha ve zamm-ı sûre; 2. rek'atta Besmele, Fâtiha ve zamm-ı sûre okunur. İlk oturuşta yalnız Ettehiyyâtü okunup \"Allâhu ekber\" ile 3. rek'ata kalkılır.");
        adimSatiri(a, tema, k, "3", "3. Rek'at · Kunut Tekbiri ve Duâları",
                "Besmele, Fâtiha ve zamm-ı sûre okunduktan sonra rükûya eğilmeden ayakta \"Allâhu ekber\" diyerek eller kulak hizasına kaldırılır, tekrar bağlanır ve sessizce Kunut Duâları okunur; ardından rükû, secdeler ve son oturuşla tamamlanır.");
        a.bosluk(k, 8);

        // Kunut 1
        duaKutusu(a, tema, k, "KUNUT DUÂSI · 1",
                "اَللّٰهُمَّ إِنَّا نَسْتَعِينُكَ وَنَسْتَغْفِرُكَ وَنَسْتَهْدِيكَ، وَنُؤْمِنُ بِكَ وَنَتُوبُ إِلَيْكَ، وَنَتَوَكَّلُ عَلَيْكَ، وَنُثْنِي عَلَيْكَ الْخَيْرَ كُلَّهُ نَشْكُرُكَ وَلَا نَكْفُرُكَ، وَنَخْلَعُ وَنَتْرُكُ مَنْ يَفْجُرُكَ",
                "Allâhümme innâ nesteînüke ve nestağfiruke ve nestehdîk, ve nü'minü bike ve netûbü ileyk, ve netevekkelü aleyk, ve nüsnî aleyke'l-hayra küllehû neşküruke ve lâ nekfüruk, ve nahleu ve netrukü men yefcüruk.",
                "Allah'ım! Senden yardım isteriz, günahlarımızı bağışlamanı isteriz, râzı olduğun şeylere hidâyet etmeni isteriz. Sana îmân ederiz, Sana tevbe ederiz, Sana güveniriz. Bize verdiğin bütün nimetleri bilerek Seni hayır ile överiz. Sana şükrederiz, hiçbir nimetini inkâr etmez ve onları başkalarından bilmeyiz. Nimetlerini inkâr eden ve Sana karşı geleni bırakırız.");
        a.bosluk(k, 8);

        // Kunut 2
        duaKutusu(a, tema, k, "KUNUT DUÂSI · 2",
                "اَللّٰهُمَّ إِيَّاكَ نَعْبُدُ وَلَكَ نُصَلِّي وَنَسْجُدُ، وَإِلَيْكَ نَسْعٰى وَنَحْفِدُ، نَرْجُو رَحْمَتَكَ وَنَخْشٰى عَذَابَكَ، إِنَّ عَذَابَكَ بِالْكُفَّارِ مُلْحِقٌ",
                "Allâhümme iyyâke na'büdü ve leke nusallî ve nescüd, ve ileyke nes'â ve nahfid, nercû rahmeteke ve nahşâ azâbek, inne azâbeke bi'l-küffâri mülhık.",
                "Allah'ım! Biz yalnız Sana kulluk ederiz. Namazı yalnız Senin için kılarız, ancak Sana secde ederiz. Yalnız Sana koşar ve Sana yaklaştıracak şeyleri kazanmaya çalışırız. İbâdetlerini sevinçle yaparız. Rahmetinin devamını ve çoğalmasını dileriz. Azâbından korkarız; şüphesiz Senin azâbın kâfirlere ve inançsızlara ulaşır.");
        p.addView(k);
    }

    private static void teheccudRehberiEkle(DurumAktivitesi a, TemaMotoru.Durum tema, LinearLayout p) {
        LinearLayout k = kart(a, tema);
        k.addView(yazi(a, tema, "SEHER VAKTİNİN NÛRU · 2 İLÂ 8 REK'AT NÂFİLE", 11, tema.vurgu, true));
        k.addView(yazi(a, tema, "Teheccüd Namazı Rehberi", 18, tema.metin, true));
        k.addView(yazi(a, tema,
                "\"Farz namazlardan sonra en fazîletli namaz gece kılınan (teheccüd) namazıdır.\" (Müslim, Sıyâm 202). Yatsı namazından sonra bir miktar uyuyup imsak vaktinden önce (özellikle gecenin son üçte birinde) uyanılarak 2'şer rek'atta selâm verilmek sûretiyle 2, 4, 6 veya 8 rek'at kılınır; peşinden henüz kılınmadıysa Vitir namazı edâ edilir.",
                13, tema.soluk, false));
        p.addView(k);
    }

    private static void cenazeRehberiEkle(DurumAktivitesi a, TemaMotoru.Durum tema, LinearLayout p) {
        LinearLayout k = kart(a, tema);
        k.addView(yazi(a, tema, "FARZ-I KİFÂYE · RÜKÛSUZ VE SECDESİZ · AYAKTA 4 TEKBİR", 11, tema.vurgu, true));
        k.addView(yazi(a, tema, "Cenâze Namazı Kılınışı (4 Tekbir Sırası)", 18, tema.metin, true));
        k.addView(yazi(a, tema,
                "Cenâze namazı vefât eden mü'min kardeşimize duâ mâhiyetindedir; abdestli olarak kıbleye dönülür, rükû ve secde yapılmaz.",
                13, tema.soluk, false));
        a.bosluk(k, 8);

        adimSatiri(a, tema, k, "1", "1. Tekbir (İftitah) ve Sübhâneke",
                "\"Allah için namaza, meyyit için duâya, er kişi (veya hatun kişi / sabî) niyetine, uydum hazır olan imama\" diyerek niyet edilir. \"Allâhu ekber\" diyerek eller kulaklara kaldırılıp göbek altına bağlanır. Sessizce Sübhâneke duâsı \"ve celle senâük\" ilâvesiyle okunur.");
        adimSatiri(a, tema, k, "2", "2. Tekbir ve Salli–Bârik Duâları",
                "Eller kulaklara kaldırılmadan imamla birlikte \"Allâhu ekber\" denilir. Sessizce Allâhümme salli ve Allâhümme bârik duâları okunur.");
        adimSatiri(a, tema, k, "3", "3. Tekbir ve Cenâze Duâsı",
                "Yine eller kaldırılmadan \"Allâhu ekber\" denilir. Bilenler Cenâze Duâsı'nı (\"Allâhümmeğfir li-hayyinâ ve meyyitinâ...\"), ezbere bilmeyenler ise \"Rabbenâ âtinâ...\" duâsını veya \"Allâhümmeğfir leh\" niyâzını okur.");
        adimSatiri(a, tema, k, "4", "4. Tekbir ve Selâm",
                "Eller kaldırılmadan dördüncü kez \"Allâhu ekber\" denilir; bir şey okunmadan önce sağa, sonra sola \"Es-selâmü aleyküm ve rahmetullâh\" diyerek selâm verilir ve eller iki yana bırakılır.");
        a.bosluk(k, 8);

        duaKutusu(a, tema, k, "CENÂZE DUÂSI",
                "اَللّٰهُمَّ اغْفِرْ لِحَيِّنَا وَمَيِّتِنَا وَشَاهِدِنَا وَغَائِبِنَا وَكَبِيرِنَا وَصَغِيرِنَا وَذَكَرِنَا وَأُنْثَانَا",
                "Allâhümmeğfir li-hayyinâ ve meyyitinâ ve şâhidinâ ve ğâibinâ ve kebîrinâ ve sağîrinâ ve zekerinâ ve ünsânâ...",
                "Allah'ım! Dirimizi ve ölümüzü, burada bulunanımızı ve bulunmayanımızı, büyüğümüzü ve küçüğümüzü, erkeğimizi ve kadınımızı bağışla. İslâm üzere yaşat ve îmân üzere ruhumuzu kabzet.");
        p.addView(k);
    }

    private static void adimSatiri(DurumAktivitesi a, TemaMotoru.Durum tema, LinearLayout p,
                                   String rozetMetni, String baslik, String aciklama) {
        LinearLayout satir = new LinearLayout(a);
        satir.setOrientation(LinearLayout.HORIZONTAL);
        satir.setPadding(0, a.dp(6), 0, a.dp(6));

        TextView rozet = yazi(a, tema, rozetMetni, 11, tema.birincilDugmeYaziRengi(), true);
        rozet.setShadowLayer(0, 0, 0, 0);
        rozet.setGravity(Gravity.CENTER);
        rozet.setBackground(tema.birincilDugme(a, 10));
        LinearLayout.LayoutParams rlp = new LinearLayout.LayoutParams(a.dp(40), a.dp(28));
        rlp.setMargins(0, a.dp(2), a.dp(10), 0);
        satir.addView(rozet, rlp);

        LinearLayout metinKutu = new LinearLayout(a);
        metinKutu.setOrientation(LinearLayout.VERTICAL);
        metinKutu.addView(yazi(a, tema, baslik, 15, tema.metin, true));
        metinKutu.addView(yazi(a, tema, aciklama, 13, tema.soluk, false));
        satir.addView(metinKutu, new LinearLayout.LayoutParams(0, -2, 1f));

        p.addView(satir);
    }

    private static void duaKutusu(DurumAktivitesi a, TemaMotoru.Durum tema, LinearLayout p,
                                  String etiket, String arapcaMetin, String okunus, String meal) {
        LinearLayout kutu = new LinearLayout(a);
        kutu.setOrientation(LinearLayout.VERTICAL);
        kutu.setPadding(a.dp(12), a.dp(10), a.dp(12), a.dp(10));
        GradientDrawable g = new GradientDrawable();
        g.setCornerRadius(a.dp(14));
        g.setColor(tema.acik ? 0x121E6B55 : 0x22000000);
        g.setStroke(Math.max(1, a.dp(1)), (tema.vurgu & 0x00FFFFFF) | 0x44000000);
        kutu.setBackground(g);

        kutu.addView(yazi(a, tema, etiket, 11, tema.vurgu, true));
        TextView ar = yazi(a, tema, arapcaMetin, 22, tema.metin, false);
        ar.setTypeface(Varlik.kuranYazisi(a));
        ar.setLineSpacing(0, 1.38f);
        ar.setGravity(Gravity.RIGHT);
        kutu.addView(ar);
        a.bosluk(kutu, 4);
        kutu.addView(yazi(a, tema, "Okunuşu: " + okunus, 13, tema.vurgu, true));
        kutu.addView(yazi(a, tema, "Anlamı: " + meal, 13, tema.soluk, false));
        p.addView(kutu);
    }

    // ================================================================ GÖRÜNÜM YARDIMCILARI

    private static LinearLayout kart(DurumAktivitesi a, TemaMotoru.Durum tema) {
        LinearLayout k = new LinearLayout(a);
        k.setOrientation(LinearLayout.VERTICAL);
        k.setPadding(a.dp(16), a.dp(14), a.dp(16), a.dp(14));
        k.setBackground(tema.kartArkaPlani(a));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(0, 0, 0, a.dp(12));
        k.setLayoutParams(lp);
        return k;
    }

    private static TextView yazi(Context c, TemaMotoru.Durum tema, String metin, int bazSp, int renk, boolean kalin) {
        TextView t = new TextView(c);
        t.setText(metin);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, TemaMotoru.olcekliSp(c, bazSp));
        t.setTextColor(renk);
        t.setTypeface(kalin ? Typeface.create("sans-serif-medium", Typeface.NORMAL) : Typeface.DEFAULT);
        t.setLineSpacing(0, 1.16f);
        int p = TemaMotoru.dp(c, 2);
        t.setPadding(0, p, 0, p);
        if (!tema.acik) {
            t.setShadowLayer(TemaMotoru.dp(c, 4), 0, TemaMotoru.dp(c, 1), 0x55000000);
        }
        return t;
    }

    private static TextView cipOlustur(DurumAktivitesi a, TemaMotoru.Durum tema,
                                       String metin, boolean secili, View.OnClickListener tik) {
        TextView c = yazi(a, tema, metin, 13, secili ? tema.birincilDugmeYaziRengi() : tema.metin, true);
        c.setShadowLayer(0, 0, 0, 0);
        c.setSingleLine(true);
        c.setEllipsize(TextUtils.TruncateAt.END);
        c.setPadding(a.dp(14), a.dp(8), a.dp(14), a.dp(8));
        c.setBackground(tema.cipArkaPlani(a, secili, 18));
        c.setClickable(true);
        a.basmaEfekti(c);
        c.setOnClickListener(v -> {
            v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            tik.onClick(v);
        });
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-2, -2);
        lp.setMargins(0, 0, a.dp(8), 0);
        c.setLayoutParams(lp);
        return c;
    }

    private static TextView dugme(DurumAktivitesi a, TemaMotoru.Durum tema,
                                  String metin, boolean birincil, View.OnClickListener tik) {
        TextView b = yazi(a, tema, metin, 14, birincil ? tema.birincilDugmeYaziRengi() : tema.metin, true);
        b.setShadowLayer(0, 0, 0, 0);
        b.setGravity(Gravity.CENTER);
        b.setMinHeight(a.dp(44));
        b.setPadding(a.dp(14), a.dp(8), a.dp(14), a.dp(8));
        b.setBackground(birincil ? tema.birincilDugme(a, 15) : tema.ikincilDugme(a, 15));
        b.setClickable(true);
        a.basmaEfekti(b);
        b.setOnClickListener(v -> {
            v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            tik.onClick(v);
        });
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(0, a.dp(10), 0, 0);
        b.setLayoutParams(lp);
        return b;
    }

    // ================================================================ SAF CANVAS CAMİ RADAR GÖRÜNÜMÜ

    /**
     * Saf Canvas konumsal radar kadranı: koyu cam disk, K/D/G/B yön çentikleri, eşmerkezli mesafe halkaları,
     * altın Kıble ışını ve bulunan camiler için parlayan zümrüt noktalar.
     */
    public static final class CamiRadarView extends View {

        public interface SecimDinleyici {
            void secildi(Cami cami);
        }

        private final Paint zeminBoya = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint cizgiBoya = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint yaziBoya = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint noktaBoya = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint haleBoya = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Path yol = new Path();

        private double kibleDerece = 151.0;
        private int yaricapMetre = 3000;
        private List<Cami> camiler = Collections.emptyList();
        private int seciliIndeks = 0;
        private SecimDinleyici dinleyici;

        public CamiRadarView(Context c) {
            super(c);
            setLayerType(LAYER_TYPE_SOFTWARE, null);
            yaziBoya.setTextAlign(Paint.Align.CENTER);
            yaziBoya.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        }

        public void kibleAyarla(double derece) {
            this.kibleDerece = derece;
            invalidate();
        }

        public void yaricapAyarla(int metre) {
            this.yaricapMetre = Math.max(250, metre);
            invalidate();
        }

        public void camileriAyarla(List<Cami> liste) {
            this.camiler = liste == null ? Collections.<Cami>emptyList() : new ArrayList<>(liste);
            this.seciliIndeks = this.camiler.isEmpty() ? -1 : 0;
            invalidate();
        }

        public void secimDinleyici(SecimDinleyici d) {
            this.dinleyici = d;
        }

        @Override
        public boolean onTouchEvent(MotionEvent event) {
            if (event.getActionMasked() == MotionEvent.ACTION_DOWN && !camiler.isEmpty()) {
                float w = getWidth(), h = getHeight();
                float cx = w / 2f, cy = h / 2f;
                float R = Math.min(w, h) / 2f * 0.84f;
                float dokunX = event.getX(), dokunY = event.getY();
                int enYakin = -1;
                float enKucuk = R * 0.22f;
                for (int i = 0; i < camiler.size(); i++) {
                    Cami c = camiler.get(i);
                    float oran = Math.min(0.90f, Math.max(0.08f, (float) (c.mesafeMetre / (double) yaricapMetre)));
                    double rad = Math.toRadians(c.kerteriz - 90.0);
                    float nx = cx + (float) Math.cos(rad) * (R * oran);
                    float ny = cy + (float) Math.sin(rad) * (R * oran);
                    float fark = (float) Math.hypot(dokunX - nx, dokunY - ny);
                    if (fark < enKucuk) {
                        enKucuk = fark;
                        enYakin = i;
                    }
                }
                if (enYakin >= 0) {
                    seciliIndeks = enYakin;
                    performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK);
                    if (dinleyici != null) dinleyici.secildi(camiler.get(enYakin));
                    invalidate();
                    return true;
                }
            }
            return super.onTouchEvent(event);
        }

        @Override
        protected void onDraw(Canvas c) {
            float w = getWidth(), h = getHeight();
            if (w <= 0 || h <= 0) return;
            float cx = w / 2f, cy = h / 2f;
            float R = Math.min(w, h) / 2f * 0.86f;

            // Koyu cam radar diski
            zeminBoya.setStyle(Paint.Style.FILL);
            zeminBoya.setShader(new RadialGradient(cx, cy, R,
                    new int[]{0xEE102A22, 0xF2081410, 0xFA040B09},
                    new float[]{0f, 0.72f, 1f}, Shader.TileMode.CLAMP));
            c.drawCircle(cx, cy, R, zeminBoya);
            zeminBoya.setShader(null);

            // Hafif radar tarama dilimi
            zeminBoya.setShader(new SweepGradient(cx, cy,
                    new int[]{0x0052C2A6, 0x0052C2A6, 0x2452C2A6, 0x0052C2A6},
                    new float[]{0f, 0.72f, 0.96f, 1f}));
            c.drawCircle(cx, cy, R * 0.96f, zeminBoya);
            zeminBoya.setShader(null);

            // Dış altın/zümrüt çerçeve
            cizgiBoya.setStyle(Paint.Style.STROKE);
            cizgiBoya.setPathEffect(null);
            cizgiBoya.setStrokeWidth(Math.max(2f, R * 0.022f));
            cizgiBoya.setColor(0x66D9B76A);
            c.drawCircle(cx, cy, R, cizgiBoya);

            // Eşmerkezli mesafe halkaları (1/3, 2/3, 3/3)
            cizgiBoya.setStrokeWidth(Math.max(1f, R * 0.009f));
            cizgiBoya.setPathEffect(new DashPathEffect(new float[]{R * 0.04f, R * 0.03f}, 0));
            cizgiBoya.setColor(0x367FD1A8);
            for (int k = 1; k <= 3; k++) {
                float hr = R * (k / 3f) * 0.90f;
                c.drawCircle(cx, cy, hr, cizgiBoya);
            }
            cizgiBoya.setPathEffect(null);

            // Eksen çizgileri
            cizgiBoya.setColor(0x24FFFFFF);
            c.drawLine(cx - R * 0.90f, cy, cx + R * 0.90f, cy, cizgiBoya);
            c.drawLine(cx, cy - R * 0.90f, cx, cy + R * 0.90f, cizgiBoya);

            // Derece çentikleri
            for (int aci = 0; aci < 360; aci += 15) {
                boolean anaYon = aci % 90 == 0;
                cizgiBoya.setStrokeWidth(anaYon ? R * 0.018f : R * 0.009f);
                cizgiBoya.setColor(anaYon ? 0xCCFFFFFF : 0x55FFFFFF);
                float rDis = R * 0.98f;
                float rIc = anaYon ? R * 0.90f : R * 0.94f;
                double rad = Math.toRadians(aci - 90.0);
                c.drawLine(cx + (float) Math.cos(rad) * rDis, cy + (float) Math.sin(rad) * rDis,
                        cx + (float) Math.cos(rad) * rIc, cy + (float) Math.sin(rad) * rIc, cizgiBoya);
            }

            // K / D / G / B harfleri
            String[] yonHarf = {"K", "D", "G", "B"};
            yaziBoya.setTextSize(R * 0.115f);
            for (int i = 0; i < 4; i++) {
                double rad = Math.toRadians(i * 90.0 - 90.0);
                float hx = cx + (float) Math.cos(rad) * (R * 0.79f);
                float hy = cy + (float) Math.sin(rad) * (R * 0.79f) + yaziBoya.getTextSize() * 0.35f;
                yaziBoya.setColor(i == 0 ? 0xFFFF8A80 : 0xCCFFFFFF);
                c.drawText(yonHarf[i], hx, hy, yaziBoya);
            }

            // Halka mesafe etiketi
            yaziBoya.setTextSize(R * 0.082f);
            yaziBoya.setColor(0x887FD1A8);
            String disEtiket = (yaricapMetre / 1000) + " km";
            c.drawText(disEtiket, cx + R * 0.56f, cy - R * 0.04f, yaziBoya);

            // Altın Kıble ışını
            if (!Double.isNaN(kibleDerece)) {
                double kRad = Math.toRadians(kibleDerece - 90.0);
                float kx = cx + (float) Math.cos(kRad) * (R * 0.88f);
                float ky = cy + (float) Math.sin(kRad) * (R * 0.88f);

                haleBoya.setStyle(Paint.Style.STROKE);
                haleBoya.setStrokeWidth(R * 0.045f);
                haleBoya.setColor(0x44F0B35A);
                haleBoya.setMaskFilter(new BlurMaskFilter(Math.max(1f, R * 0.04f), BlurMaskFilter.Blur.NORMAL));
                c.drawLine(cx, cy, kx, ky, haleBoya);
                haleBoya.setMaskFilter(null);

                cizgiBoya.setStrokeWidth(Math.max(2f, R * 0.018f));
                cizgiBoya.setColor(0xEEF0B35A);
                c.drawLine(cx, cy, kx, ky, cizgiBoya);

                // Uçta altın Kâbe eşkenar dörtgeni
                float dr = R * 0.048f;
                yol.reset();
                yol.moveTo(kx, ky - dr);
                yol.lineTo(kx + dr, ky);
                yol.lineTo(kx, ky + dr);
                yol.lineTo(kx - dr, ky);
                yol.close();
                noktaBoya.setStyle(Paint.Style.FILL);
                noktaBoya.setColor(0xFFF5CF5B);
                c.drawPath(yol, noktaBoya);
            }

            // Cami noktaları (parlayan zümrüt)
            haleBoya.setStyle(Paint.Style.FILL);
            haleBoya.setMaskFilter(new BlurMaskFilter(Math.max(1f, R * 0.055f), BlurMaskFilter.Blur.NORMAL));
            for (int i = camiler.size() - 1; i >= 0; i--) {
                Cami cami = camiler.get(i);
                boolean secili = i == seciliIndeks;
                float oran = Math.min(0.90f, Math.max(0.08f, (float) (cami.mesafeMetre / (double) yaricapMetre)));
                double rad = Math.toRadians(cami.kerteriz - 90.0);
                float nx = cx + (float) Math.cos(rad) * (R * oran);
                float ny = cy + (float) Math.sin(rad) * (R * oran);

                haleBoya.setColor(secili ? 0xCC7FD1A8 : 0x8852C2A6);
                c.drawCircle(nx, ny, secili ? R * 0.095f : R * 0.065f, haleBoya);

                noktaBoya.setStyle(Paint.Style.FILL);
                noktaBoya.setColor(secili ? 0xFFA8FFD2 : 0xFF52E5A8);
                c.drawCircle(nx, ny, secili ? R * 0.044f : R * 0.032f, noktaBoya);

                if (secili) {
                    noktaBoya.setStyle(Paint.Style.STROKE);
                    noktaBoya.setStrokeWidth(Math.max(1.5f, R * 0.014f));
                    noktaBoya.setColor(Color.WHITE);
                    c.drawCircle(nx, ny, R * 0.062f, noktaBoya);
                }
            }
            haleBoya.setMaskFilter(null);

            // Merkez: kullanıcının konumu
            noktaBoya.setStyle(Paint.Style.FILL);
            noktaBoya.setColor(0x44FFFFFF);
            c.drawCircle(cx, cy, R * 0.065f, noktaBoya);
            noktaBoya.setColor(Color.WHITE);
            c.drawCircle(cx, cy, R * 0.030f, noktaBoya);
        }
    }
}
