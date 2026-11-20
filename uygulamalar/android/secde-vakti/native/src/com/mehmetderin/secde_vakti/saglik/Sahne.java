package com.mehmetderin.secde_vakti.saglik;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.LinearGradient;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RadialGradient;
import android.graphics.Shader;
import android.os.SystemClock;
import android.view.View;

import java.util.ArrayList;
import java.util.List;
import java.util.Random;

/**
 * Canlı arka plan sahnesi. Vakte, seçili sahne paketine (Haremeyn, Kudüs, Osmanlı, Klasik)
 * veya sabitlenen özel manzaraya göre (Ken Burns + kaydırma paralaksı):
 *  - Çok katmanlı atmosferik efektler: 4 köşeli yıldız parıltıları, çift kayan yıldız,
 *    kuzey/ufuk nur hâlesi, ateşböceği nurları, gündüz hacimsel güneş hüzmeleri (God rays),
 *    sis/bulut şeridi, süzülen sığın/güvercin siluetleri ve dokunuşta yayılan nur halkası.
 *  - Ayarlanabilir perde netliği ("canli", "dengeli", "okuma") ve efekt yoğunluğu.
 */
public final class Sahne extends View {

    // Vakit paletleri: gökyüzü üst, orta, ufuk; silüet; güneş/ay rengi
    private static final int[][] GOK = {
            {0xFF0B1033, 0xFF27306B, 0xFF8A6A9A, 0xFF0A0D24, 0xFFF3E7C8},  // İmsak: tan yeri
            {0xFF3B6EA8, 0xFF9DB9DA, 0xFFF6C89A, 0xFF2A2440, 0xFFFFE2A8},  // Güneş: gün doğumu
            {0xFF2F7FD0, 0xFF7DB8EC, 0xFFD6ECFA, 0xFF2B3550, 0xFFFFFFFF},  // Öğle
            {0xFF3D6FA6, 0xFFE0B57A, 0xFFF4D7A1, 0xFF3A2C2A, 0xFFFFE0A0},  // İkindi: altın ışık
            {0xFF2A1F55, 0xFFB4507A, 0xFFF29B5C, 0xFF1A1230, 0xFFFFC07A},  // Akşam: gün batımı
            {0xFF05071A, 0xFF111A44, 0xFF26306A, 0xFF04050F, 0xFFF4ECD0},  // Yatsı: gece
    };

    // Görüntülenen sahne: "vakit_0".."vakit_5", "kandil", "mihrap", "huzur", "bg_*"
    private String anahtar = "vakit_5";
    private String oncekiAnahtar = null;
    private long gecisBasi;
    private static final long GECIS_MS = 1600;

    private final java.util.HashMap<String, Bitmap> fotolar = new java.util.HashMap<>();
    private final java.util.HashSet<String> denendi = new java.util.HashSet<>();

    private final Paint boya = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint fotoBoya = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.FILTER_BITMAP_FLAG);
    private final Matrix matris = new Matrix();
    private final Path yol = new Path();

    private float[] yildizX, yildizY, yildizR, yildizFaz;
    private float[] zerreX, zerreY, zerreR, zerreHiz, zerreFaz;
    private float[] kusX, kusY, kusHiz, kusFaz;
    private long kayanBasi = -1;
    private float kayanX, kayanY;
    private long ikinciKayanBasi = -1;
    private float ikinciKayanX, ikinciKayanY;
    private float kaydirmaHedefPx = 0f, kaydirmaAnlikPx = 0f;
    private final List<float[]> dokunusDalgalari = new ArrayList<>(4);
    private final Random rnd = new Random(1453);
    private boolean canli = true;

    public Sahne(Context c) {
        super(c);
        setLayerType(LAYER_TYPE_HARDWARE, null);
    }

    /** Gösterilecek vakit (0..5). */
    public void vakit(int v) {
        goster("vakit_" + Math.max(0, Math.min(5, v)));
    }

    /** Gösterilecek sahne; değişirse yumuşak geçiş. */
    public void goster(String yeni) {
        if (yeni == null || yeni.equals(anahtar)) return;
        oncekiAnahtar = anahtar;
        anahtar = yeni;
        gecisBasi = SystemClock.uptimeMillis();
        invalidate();
    }

    /** Sayfa kaydırmasına göre arka planda yumuşak derinlik paralaksı uygular. */
    public void kaydirmaOfseti(int scrollY) {
        float dp = getResources().getDisplayMetrics().density;
        kaydirmaHedefPx = Math.max(0f, Math.min(34f * dp, scrollY * 0.085f));
        invalidate();
    }

    /** Ekrana dokunulduğunda zarif bir nur dalgası başlatır. */
    public void dokunusEfekti(float x, float y) {
        if (dokunusDalgalari.size() >= 3) dokunusDalgalari.remove(0);
        dokunusDalgalari.add(new float[]{x, y, SystemClock.uptimeMillis()});
        invalidate();
    }

    /** Kodla çizim için vakit numarası. */
    private static int vakitOf(String k) {
        if (k != null && k.startsWith("vakit_") && k.length() == 7) {
            int v = k.charAt(6) - '0';
            if (v >= 0 && v <= 5) return v;
        }
        if ("bg_medine_ravza".equals(k)) return 2;
        if ("bg_selcuklu_avlu".equals(k)) return 3;
        if ("bg_kudus_aksa".equals(k)) return 4;
        if ("bg_mekke_gece".equals(k) || "bg_teheccud_pencere".equals(k) || "huzur".equals(k)) return 5;
        return 5;
    }

    private static boolean geceEfekti(String k) {
        int v = vakitOf(k);
        return "kandil".equals(k) || "kible_bg".equals(k)
                || "bg_mekke_gece".equals(k) || "bg_teheccud_pencere".equals(k) || "huzur".equals(k)
                || (k != null && k.startsWith("vakit_") && (v == 0 || v == 5));
    }

    private static boolean seherVeyaAksam(String k) {
        return "bg_kudus_aksa".equals(k) || "vakit_1".equals(k) || "vakit_4".equals(k);
    }

    public void canli(boolean c) {
        canli = c;
        if (c) postInvalidateOnAnimation();
    }

    private Bitmap foto(String k) {
        if (!denendi.contains(k)) {
            denendi.add(k);
            Bitmap b = Gorseller.al(getContext(), k, 0);
            if (b != null) fotolar.put(k, b);
        }
        return fotolar.get(k);
    }

    @Override
    protected void onSizeChanged(int w, int h, int ow, int oh) {
        super.onSizeChanged(w, h, ow, oh);
        int n = 96;
        yildizX = new float[n]; yildizY = new float[n]; yildizR = new float[n]; yildizFaz = new float[n];
        for (int i = 0; i < n; i++) {
            yildizX[i] = rnd.nextFloat() * w;
            yildizY[i] = rnd.nextFloat() * h * 0.60f;
            yildizR[i] = 0.7f + rnd.nextFloat() * 1.9f;
            yildizFaz[i] = rnd.nextFloat() * 6.283f;
        }
        int m = 42;
        zerreX = new float[m]; zerreY = new float[m]; zerreR = new float[m]; zerreHiz = new float[m]; zerreFaz = new float[m];
        for (int i = 0; i < m; i++) {
            zerreX[i] = rnd.nextFloat() * w;
            zerreY[i] = rnd.nextFloat() * h;
            zerreR[i] = 1.6f + rnd.nextFloat() * 3.8f;
            zerreHiz[i] = 6f + rnd.nextFloat() * 18f;
            zerreFaz[i] = rnd.nextFloat() * 6.283f;
        }
        int k = 5;
        kusX = new float[k]; kusY = new float[k]; kusHiz = new float[k]; kusFaz = new float[k];
        for (int i = 0; i < k; i++) {
            kusX[i] = rnd.nextFloat() * w;
            kusY[i] = h * (0.14f + rnd.nextFloat() * 0.24f);
            kusHiz[i] = 14f + rnd.nextFloat() * 14f;
            kusFaz[i] = rnd.nextFloat() * 6.283f;
        }
    }

    @Override
    protected void onDraw(Canvas c) {
        int w = getWidth(), h = getHeight();
        if (w == 0 || h == 0) return;
        long t = SystemClock.uptimeMillis();
        TemaMotoru.Durum tm = TemaMotoru.aktif(getContext());
        kaydirmaAnlikPx += (kaydirmaHedefPx - kaydirmaAnlikPx) * 0.22f;

        if (TemaMotoru.SAHNE_DUZ_AMOLED.equals(tm.sahneModu)) {
            oncekiAnahtar = null;
            boya.setShader(null);
            boya.setColor(tm.zemin);
            boya.setAlpha(255);
            c.drawRect(0, 0, w, h, boya);
            if (!"saf_amoled".equals(tm.tema.kod)) {
                int ustParilti = tm.acik ? renkAlfa(tm.ana, 24) : renkAlfa(tm.heroBas, 95);
                boya.setShader(new RadialGradient(w * 0.5f, h * 0.08f, Math.max(w, h) * 0.65f,
                        new int[]{ustParilti, Color.TRANSPARENT}, null, Shader.TileMode.CLAMP));
                c.drawRect(0, 0, w, h, boya);
                boya.setShader(null);
            }
            if (tm.desen != GeometrikDesen.KAPALI) {
                float dp = getResources().getDisplayMetrics().density;
                GeometrikDesen.ciz(c, w, h, dp, tm.desen, tm.acik ? tm.ana : tm.vurgu, tm.acik ? 20 : 16, boya);
            }
            return;
        }

        String hedefGorsel = TemaMotoru.sahneAnahtariCoz(getContext(), anahtar);
        String oncekiGorsel = oncekiAnahtar == null ? null : TemaMotoru.sahneAnahtariCoz(getContext(), oncekiAnahtar);

        float gecis = 1f;
        if (oncekiGorsel != null && !oncekiGorsel.equals(hedefGorsel)) {
            gecis = Math.min(1f, (t - gecisBasi) / (float) GECIS_MS);
            gecis = gecis * gecis * (3 - 2 * gecis);
        }
        if (oncekiGorsel != null && !oncekiGorsel.equals(hedefGorsel) && gecis < 1f) {
            katman(c, oncekiGorsel, 255, t, tm);
            katman(c, hedefGorsel, Math.round(255 * gecis), t, tm);
        } else {
            oncekiAnahtar = null;
            katman(c, hedefGorsel, 255, t, tm);
        }
        efektler(c, t, hedefGorsel, tm);
        perde(c, w, h, tm);
        if (tm.desen != GeometrikDesen.KAPALI) {
            float dp = getResources().getDisplayMetrics().density;
            GeometrikDesen.ciz(c, w, h, dp, tm.desen, tm.acik ? tm.ana : tm.vurgu, tm.acik ? 16 : 11, boya);
        }
        dokunusCiz(c, t, tm);

        if (canli && isShown()) postInvalidateOnAnimation();
    }

    private void katman(Canvas c, String k, int alfa, long t, TemaMotoru.Durum tm) {
        boolean zorlaCizim = TemaMotoru.SAHNE_CIZIM.equals(tm.sahneModu)
                || TemaMotoru.SAHNE_DINAMIK_GOK.equals(tm.sahneModu);
        Bitmap b = zorlaCizim ? null : foto(k);
        if (b != null) {
            fotoCiz(c, b, alfa, t);
        } else {
            sahneCiz(c, vakitOf(k), alfa, t, tm);
        }
    }

    /** Ken Burns + kaydırma paralaksı: yumuşak yakınlaşma ve sayfa kaydıkça derinlik hissi. */
    private void fotoCiz(Canvas c, Bitmap b, int alfa, long t) {
        int w = getWidth(), h = getHeight();
        float taban = Math.max(w / (float) b.getWidth(), h / (float) b.getHeight());
        double faz = (t % 42000L) / 42000.0 * 2 * Math.PI;
        float olcek = taban * (1.12f + 0.04f * (float) Math.sin(faz));
        float bw = b.getWidth() * olcek, bh = b.getHeight() * olcek;
        float dx = (w - bw) / 2f + (float) Math.cos(faz) * (bw - w) * 0.25f;
        float dy = (h - bh) / 2f + (float) Math.sin(faz * 0.7) * (bh - h) * 0.2f - kaydirmaAnlikPx;
        matris.reset();
        matris.postScale(olcek, olcek);
        matris.postTranslate(dx, dy);
        fotoBoya.setAlpha(alfa);
        c.drawBitmap(b, matris, fotoBoya);
    }

    /** Kodla çizilen sahne (tema renkleriyle harmanlanır). */
    private void sahneCiz(Canvas c, int v, int alfa, long t, TemaMotoru.Durum tm) {
        int w = getWidth(), h = getHeight();
        int[] p = GOK[v];
        int gok0 = TemaMotoru.karistir(p[0], tm.zemin, 0.45f);
        int gok1 = TemaMotoru.karistir(p[1], tm.heroBas, 0.42f);
        int gok2 = TemaMotoru.karistir(p[2], tm.heroSon, 0.30f);
        int siluet = TemaMotoru.karistir(p[3], tm.zemin, 0.50f);
        boya.setShader(new LinearGradient(0, 0, 0, h * 0.72f, new int[]{gok0, gok1, gok2}, new float[]{0f, 0.55f, 1f}, Shader.TileMode.CLAMP));
        boya.setAlpha(alfa);
        c.drawRect(0, 0, w, h, boya);
        boya.setShader(null);

        float ufuk = h * 0.70f;
        // Güneş / ay
        float gx, gy, gr;
        boolean gece = v == 0 || v == 5;
        switch (v) {
            case 0: gx = w * 0.78f; gy = h * 0.16f; break;
            case 1: gx = w * 0.30f; gy = ufuk - h * 0.05f; break;
            case 2: gx = w * 0.70f; gy = h * 0.12f; break;
            case 3: gx = w * 0.80f; gy = h * 0.34f; break;
            case 4: gx = w * 0.26f; gy = ufuk - h * 0.02f; break;
            default: gx = w * 0.76f; gy = h * 0.14f; break;
        }
        gr = gece ? w * 0.06f : w * 0.085f;
        float nabiz = 1f + 0.04f * (float) Math.sin(t / 1400.0);
        boya.setShader(new RadialGradient(gx, gy, gr * 4.2f * nabiz,
                new int[]{renkAlfa(p[4], 110), renkAlfa(p[4], 0)}, null, Shader.TileMode.CLAMP));
        boya.setAlpha(alfa);
        c.drawCircle(gx, gy, gr * 4.2f * nabiz, boya);
        boya.setShader(null);
        boya.setColor(p[4]);
        boya.setAlpha(alfa);
        if (!gece) c.drawCircle(gx, gy, gr, boya);
        if (gece) {
            // Hilal: ay dairesinden kaydırılmış daire çıkarılır (gökyüzü ne renk olursa olsun doğru görünür)
            yol.reset();
            yol.addCircle(gx, gy, gr, Path.Direction.CW);
            Path kes = new Path();
            kes.addCircle(gx + gr * 0.42f, gy - gr * 0.18f, gr * 0.92f, Path.Direction.CW);
            yol.op(kes, Path.Op.DIFFERENCE);
            boya.setColor(p[4]);
            boya.setAlpha(alfa);
            c.drawPath(yol, boya);
        }

        // Su
        boya.setShader(new LinearGradient(0, ufuk, 0, h, new int[]{karart(p[2], 0.55f), karart(p[0], 0.35f)}, null, Shader.TileMode.CLAMP));
        boya.setAlpha(alfa);
        c.drawRect(0, ufuk, w, h, boya);
        boya.setShader(null);
        // Suda ışık yolu
        boya.setColor(p[4]);
        for (int i = 0; i < 9; i++) {
            float y = ufuk + 8 + i * (h - ufuk) / 11f;
            float gen = gr * (1.4f - i * 0.1f) * (1f + 0.25f * (float) Math.sin(t / 700.0 + i));
            boya.setAlpha((int) (alfa * (0.28f - i * 0.025f)));
            c.drawRect(gx - gen, y, gx + gen, y + 2.2f, boya);
        }

        // Uzak tepe silueti
        boya.setColor(karart(siluet, 1.35f));
        boya.setAlpha((int) (alfa * 0.65f));
        yol.reset();
        yol.moveTo(0, ufuk);
        for (int i = 0; i <= 8; i++) {
            float x = w * i / 8f;
            yol.lineTo(x, ufuk - h * (0.018f + 0.012f * (float) Math.sin(i * 1.7)));
        }
        yol.lineTo(w, ufuk);
        yol.close();
        c.drawPath(yol, boya);

        // Cami silueti + yansıması
        camiCiz(c, w * 0.5f, ufuk, w * 0.86f, siluet, alfa, gece || v == 4, t);
        c.save();
        c.scale(1f, -0.45f, 0, ufuk);
        camiCiz(c, w * 0.5f, ufuk, w * 0.86f, siluet, (int) (alfa * 0.18f), false, t);
        c.restore();
    }

    /** Osmanlı tarzı cami: büyük kubbe, yarım kubbeler, dört minare (şerefeli), alem. */
    private void camiCiz(Canvas c, float ox, float taban, float gen, int renk, int alfa, boolean isikli, long t) {
        float u = gen / 100f;
        boya.setShader(null);
        boya.setColor(renk);
        boya.setAlpha(alfa);
        yol.reset();
        // Gövde
        yol.addRect(ox - 34 * u, taban - 16 * u, ox + 34 * u, taban, Path.Direction.CW);
        // Yan yarım kubbeler
        yol.addOval(ox - 30 * u, taban - 26 * u, ox - 10 * u, taban - 8 * u, Path.Direction.CW);
        yol.addOval(ox + 10 * u, taban - 26 * u, ox + 30 * u, taban - 8 * u, Path.Direction.CW);
        // Kasnak + ana kubbe
        yol.addRect(ox - 16 * u, taban - 24 * u, ox + 16 * u, taban - 14 * u, Path.Direction.CW);
        yol.addOval(ox - 17 * u, taban - 40 * u, ox + 17 * u, taban - 10 * u, Path.Direction.CW);
        // Küçük kubbeler
        for (float k : new float[]{-38, -24, 24, 38}) {
            yol.addOval(ox + (k - 4) * u, taban - 20 * u, ox + (k + 4) * u, taban - 12 * u, Path.Direction.CW);
            yol.addRect(ox + (k - 4) * u, taban - 16 * u, ox + (k + 4) * u, taban, Path.Direction.CW);
        }
        // Minareler
        for (float m : new float[]{-46, -40, 40, 46}) {
            boolean dis = Math.abs(m) > 43;
            float boy = dis ? 58 : 68;
            float x = ox + m * u;
            yol.addRect(x - 1.3f * u, taban - boy * u, x + 1.3f * u, taban, Path.Direction.CW);
            // Şerefeler
            for (float s : new float[]{0.62f, 0.80f}) {
                yol.addRect(x - 2.2f * u, taban - boy * s * u - 0.8f * u, x + 2.2f * u, taban - boy * s * u + 0.6f * u, Path.Direction.CW);
            }
            // Külah
            yol.moveTo(x - 1.4f * u, taban - boy * u);
            yol.lineTo(x, taban - (boy + 9) * u);
            yol.lineTo(x + 1.4f * u, taban - boy * u);
            yol.close();
        }
        // Alem çubuğu
        yol.addRect(ox - 0.35f * u, taban - 46 * u, ox + 0.35f * u, taban - 39 * u, Path.Direction.CW);
        c.drawPath(yol, boya);
        // Alem hilali
        boya.setStyle(Paint.Style.STROKE);
        boya.setStrokeWidth(0.8f * u);
        c.drawArc(ox - 2 * u, taban - 50.5f * u, ox + 2 * u, taban - 46.5f * u, 200, 220, false, boya);
        boya.setStyle(Paint.Style.FILL);

        if (isikli) {
            // Kandil ışıkları: pencereler ve şerefeler hafif titrer
            boya.setColor(0xFFFFD27A);
            for (int i = -5; i <= 5; i++) {
                float tit = 0.65f + 0.35f * (float) Math.sin(t / 380.0 + i * 1.3);
                boya.setAlpha((int) (alfa * 0.85f * tit));
                c.drawRect(ox + i * 5 * u - 0.9f * u, taban - 9 * u, ox + i * 5 * u + 0.9f * u, taban - 5 * u, boya);
            }
            for (float m : new float[]{-46, -40, 40, 46}) {
                boolean dis = Math.abs(m) > 43;
                float boy = dis ? 58 : 68;
                for (float s : new float[]{0.62f, 0.80f}) {
                    float tit = 0.6f + 0.4f * (float) Math.sin(t / 450.0 + m + s * 10);
                    boya.setAlpha((int) (alfa * tit));
                    c.drawCircle(ox + m * u, taban - boy * s * u - 1.4f * u, 0.9f * u, boya);
                }
            }
        }
    }

    private void efektler(Canvas c, long t, String aktifGorsel, TemaMotoru.Durum tm) {
        if (yildizX == null || TemaMotoru.EFEKT_KAPALI.equals(tm.efektYogunlugu)) return;
        int w = getWidth(), h = getHeight();
        boolean zengin = !TemaMotoru.EFEKT_SADE.equals(tm.efektYogunlugu);
        boolean gece = geceEfekti(aktifGorsel);
        boolean alacakaranlik = seherVeyaAksam(aktifGorsel);
        float yogunluk = zengin ? 1f : 0.45f;
        float dp = getResources().getDisplayMetrics().density;

        if (gece || alacakaranlik) {
            float seherCarp = alacakaranlik ? 0.42f : ("vakit_0".equals(aktifGorsel) ? 0.6f : 1f);
            boya.setShader(null);
            boya.setStyle(Paint.Style.FILL);
            int yildizSayi = zengin ? yildizX.length : Math.min(48, yildizX.length);

            // Yumuşak üst gök nur hâlesi
            if (zengin && gece) {
                float halesiY = h * (0.14f + 0.02f * (float) Math.sin(t / 3200.0));
                boya.setShader(new RadialGradient(w * 0.52f, halesiY, w * 0.72f,
                        new int[]{renkAlfa(tm.vurgu, 26), renkAlfa(tm.ana, 14), Color.TRANSPARENT},
                        new float[]{0f, 0.45f, 1f}, Shader.TileMode.CLAMP));
                c.drawRect(0, 0, w, h * 0.55f, boya);
                boya.setShader(null);
            }

            // Yıldızlar + 4 köşeli yıldız parıltıları
            for (int i = 0; i < yildizSayi; i++) {
                float parilti = 0.35f + 0.65f * (0.5f + 0.5f * (float) Math.sin(t / 900.0 + yildizFaz[i]));
                int alfa = Math.round(185 * parilti * seherCarp);
                boya.setColor((i % 7 == 0) ? 0xFFFFEAC2 : Color.WHITE);
                boya.setAlpha(alfa);
                c.drawCircle(yildizX[i], yildizY[i], yildizR[i], boya);
                if (zengin && i < 14 && parilti > 0.72f) {
                    float kol = yildizR[i] * (2.6f + 1.1f * (parilti - 0.72f));
                    boya.setAlpha(Math.round(115 * parilti * seherCarp));
                    boya.setStrokeWidth(Math.max(1f, 0.8f * dp));
                    c.drawLine(yildizX[i] - kol, yildizY[i], yildizX[i] + kol, yildizY[i], boya);
                    c.drawLine(yildizX[i], yildizY[i] - kol, yildizX[i], yildizY[i] + kol, boya);
                }
            }

            // Çift kayan yıldız
            if (zengin) {
                long dongu = t % 11000L;
                if (dongu < 900) {
                    if (kayanBasi != t / 11000L) {
                        kayanBasi = t / 11000L;
                        kayanX = w * (0.15f + rnd.nextFloat() * 0.55f);
                        kayanY = h * (0.05f + rnd.nextFloat() * 0.18f);
                    }
                    kayanYildizCiz(c, w, h, dongu / 900f, kayanX, kayanY, 1f);
                }
                long dongu2 = (t + 5400L) % 15000L;
                if (dongu2 < 780) {
                    if (ikinciKayanBasi != (t + 5400L) / 15000L) {
                        ikinciKayanBasi = (t + 5400L) / 15000L;
                        ikinciKayanX = w * (0.35f + rnd.nextFloat() * 0.5f);
                        ikinciKayanY = h * (0.07f + rnd.nextFloat() * 0.16f);
                    }
                    kayanYildizCiz(c, w, h, dongu2 / 780f, ikinciKayanX, ikinciKayanY, -0.85f);
                }
            }

            // Altın kandil / ateşböceği zerreleri
            int zSayi = zengin ? 22 : 10;
            float sn = t / 1000f;
            for (int i = 0; i < zSayi && i < zerreX.length; i++) {
                float yBase = h * 0.42f + (zerreY[i] % (h * 0.56f));
                float y = yBase - (sn * zerreHiz[i] * 0.7f) % (h * 0.52f);
                if (y < h * 0.25f) y += h * 0.52f;
                float x = zerreX[i] + 18f * (float) Math.sin(sn * 0.5f + zerreFaz[i]);
                float a = (0.30f + 0.50f * (0.5f + 0.5f * (float) Math.sin(sn * 1.4f + zerreFaz[i]))) * yogunluk;
                boya.setColor(0xFFFFD488);
                boya.setAlpha(Math.round(55 * a));
                c.drawCircle(x, y, zerreR[i] * 2.4f, boya);
                boya.setColor(Color.WHITE);
                boya.setAlpha(Math.round(180 * a));
                c.drawCircle(x, y, zerreR[i] * 0.65f, boya);
            }
        }

        if (!gece || alacakaranlik) {
            float sn = t / 1000f;
            // Hacimsel güneş ışığı hüzmeleri (God rays)
            if (zengin) {
                boya.setStyle(Paint.Style.FILL);
                for (int i = 0; i < 3; i++) {
                    float salinim = 0.55f + 0.45f * (float) Math.sin(sn * 0.42f + i * 1.9f);
                    int rAlpha = Math.round((alacakaranlik ? 26 : 34) * salinim);
                    float basX = w * (0.12f + i * 0.28f);
                    float tabanX = basX + w * 0.34f;
                    yol.reset();
                    yol.moveTo(basX, 0);
                    yol.lineTo(basX + w * 0.14f, 0);
                    yol.lineTo(tabanX + w * 0.28f, h * 0.68f);
                    yol.lineTo(tabanX - w * 0.05f, h * 0.68f);
                    yol.close();
                    boya.setShader(new LinearGradient(basX, 0, tabanX, h * 0.68f,
                            Color.argb(rAlpha, 255, 224, 156), Color.TRANSPARENT, Shader.TileMode.CLAMP));
                    c.drawPath(yol, boya);
                }
                boya.setShader(null);
            }

            // Süzülen nur & bokeh zerreleri
            int zSayi = zengin ? zerreX.length : zerreX.length / 2;
            for (int i = 0; i < zSayi; i++) {
                float y = (zerreY[i] - sn * zerreHiz[i]) % h;
                if (y < 0) y += h;
                float x = zerreX[i] + 16f * (float) Math.sin(sn * 0.6f + zerreFaz[i]);
                float a = (0.24f + 0.28f * (float) Math.sin(sn * 1.3f + zerreFaz[i])) * yogunluk;
                boya.setColor(i % 4 == 0 ? 0xFFFFDF9B : Color.WHITE);
                boya.setAlpha(Math.round(70 * Math.max(0.05f, a)));
                c.drawCircle(x, y, zerreR[i] * 1.9f, boya);
                boya.setAlpha(Math.round(210 * Math.max(0.05f, a)));
                c.drawCircle(x, y, zerreR[i] * 0.7f, boya);
            }

            // Gökyüzünde süzülen güvercin / kırlangıç silüetleri
            if (zengin && kusX != null) {
                boya.setStyle(Paint.Style.STROKE);
                boya.setStrokeWidth(Math.max(1.2f, 1.3f * dp));
                boya.setStrokeCap(Paint.Cap.ROUND);
                for (int i = 0; i < kusX.length; i++) {
                    float kx = (kusX[i] + sn * kusHiz[i]) % (w + 60f * dp) - 30f * dp;
                    float ky = kusY[i] + 7f * dp * (float) Math.sin(sn * 0.9f + kusFaz[i]);
                    float kanat = 4.5f * dp;
                    float cirp = (float) Math.sin(sn * 5.2f + kusFaz[i]) * 2.8f * dp;
                    boya.setColor(tm.acik ? 0x551E322C : 0x66FFEAC2);
                    yol.reset();
                    yol.moveTo(kx - kanat, ky - cirp);
                    yol.quadTo(kx - kanat * 0.4f, ky - 2.2f * dp, kx, ky);
                    yol.quadTo(kx + kanat * 0.4f, ky - 2.2f * dp, kx + kanat, ky - cirp);
                    c.drawPath(yol, boya);
                }
                boya.setStyle(Paint.Style.FILL);
            }
        }
    }

    private void kayanYildizCiz(Canvas c, int w, int h, float ilerleme, float sx, float sy, float yon) {
        float x = sx + yon * ilerleme * w * 0.34f;
        float y = sy + ilerleme * h * 0.13f;
        float dx = yon * w * 0.12f;
        float dy = h * 0.045f;
        boya.setShader(new LinearGradient(x, y, x - dx, y - dy,
                Color.argb((int) (235 * (1 - ilerleme)), 255, 240, 200), Color.TRANSPARENT, Shader.TileMode.CLAMP));
        boya.setStrokeWidth(2.4f);
        boya.setStyle(Paint.Style.STROKE);
        c.drawLine(x, y, x - dx, y - dy, boya);
        boya.setShader(null);
        boya.setStyle(Paint.Style.FILL);
        boya.setColor(Color.argb((int) (240 * (1 - ilerleme)), 255, 255, 255));
        c.drawCircle(x, y, 2.2f, boya);
    }

    private void dokunusCiz(Canvas c, long t, TemaMotoru.Durum tm) {
        if (dokunusDalgalari.isEmpty() || TemaMotoru.EFEKT_KAPALI.equals(tm.efektYogunlugu)) return;
        float maxR = Math.min(getWidth(), getHeight()) * 0.30f;
        boya.setShader(null);
        boya.setStyle(Paint.Style.STROKE);
        float dp = getResources().getDisplayMetrics().density;
        for (int i = dokunusDalgalari.size() - 1; i >= 0; i--) {
            float[] d = dokunusDalgalari.get(i);
            float p = (t - d[2]) / 650f;
            if (p >= 1f) {
                dokunusDalgalari.remove(i);
                continue;
            }
            float yariCap = 12f * dp + maxR * (1f - (1f - p) * (1f - p));
            int a = Math.round(135 * (1f - p));
            boya.setColor((tm.vurgu & 0x00FFFFFF) | (a << 24));
            boya.setStrokeWidth((2.2f * (1f - p) + 0.6f) * dp);
            c.drawCircle(d[0], d[1], yariCap, boya);
            if (p < 0.7f) {
                int a2 = Math.round(80 * (1f - p / 0.7f));
                boya.setColor(0x00FFFFFF | (a2 << 24));
                boya.setStrokeWidth(1.2f * dp);
                c.drawCircle(d[0], d[1], yariCap * 0.62f, boya);
            }
        }
        boya.setStyle(Paint.Style.FILL);
    }

    /** Okunabilirlik ve tema atmosferi: netlik ayarına ("canli", "dengeli", "okuma") göre perde. */
    private void perde(Canvas c, int w, int h, TemaMotoru.Durum tm) {
        boya.setStyle(Paint.Style.FILL);
        if (tm.acik) {
            int[] alfalar;
            if (TemaMotoru.NETLIK_CANLI.equals(tm.sahneNetlik)) {
                alfalar = new int[]{118, 86, 178, 228};
            } else if (TemaMotoru.NETLIK_DENGELI.equals(tm.sahneNetlik)) {
                alfalar = new int[]{172, 140, 206, 238};
            } else {
                alfalar = new int[]{215, 185, 225, 245};
            }
            boya.setShader(new LinearGradient(0, 0, 0, h,
                    new int[]{renkAlfa(tm.zemin, alfalar[0]), renkAlfa(tm.zemin, alfalar[1]),
                            renkAlfa(tm.zemin, alfalar[2]), renkAlfa(tm.zemin, alfalar[3])},
                    new float[]{0f, 0.32f, 0.65f, 1f}, Shader.TileMode.CLAMP));
        } else {
            int[] alfalar;
            if (TemaMotoru.NETLIK_CANLI.equals(tm.sahneNetlik)) {
                alfalar = new int[]{42, 14, 110, 208};
            } else if (TemaMotoru.NETLIK_DENGELI.equals(tm.sahneNetlik)) {
                alfalar = new int[]{76, 26, 118, 218};
            } else {
                alfalar = new int[]{108, 38, 128, 226};
            }
            int ust = renkAlfa(tm.heroSon, alfalar[0]);
            int orta1 = renkAlfa(tm.zemin, alfalar[1]);
            int orta2 = renkAlfa(tm.zemin, alfalar[2]);
            int alt = renkAlfa(tm.zemin, alfalar[3]);
            boya.setShader(new LinearGradient(0, 0, 0, h,
                    new int[]{ust, orta1, orta2, alt},
                    new float[]{0f, 0.30f, 0.60f, 1f}, Shader.TileMode.CLAMP));
        }
        boya.setAlpha(255);
        c.drawRect(0, 0, w, h, boya);
        boya.setShader(null);
    }

    private static int renkAlfa(int renk, int a) {
        return (renk & 0x00FFFFFF) | (a << 24);
    }

    private static int karart(int renk, float k) {
        int r = Math.min(255, (int) (Color.red(renk) * k));
        int g = Math.min(255, (int) (Color.green(renk) * k));
        int b = Math.min(255, (int) (Color.blue(renk) * k));
        return Color.rgb(r, g, b);
    }

    /** Namaz anahtarından sahne vakti. */
    public static int vakitNo(String namaz) {
        if (namaz == null) return 5;
        switch (namaz) {
            case "fajr": return 0;
            case "sunrise": return 1;
            case "dhuhr": return 2;
            case "asr": return 3;
            case "maghrib": return 4;
            default: return 5;
        }
    }
}
