package com.mehmetderin.secde_vakti.saglik;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RadialGradient;
import android.graphics.Shader;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Handler;
import android.os.Looper;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.HapticFeedbackConstants;
import android.view.View;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

/**
 * Huzur & Tefekkür Modu:
 *  - Nefes ritmine uyumlu büyüyüp küçülen nur hâlesi
 *  - Canlı saat, sıradaki namaz sayacı ve tek dokunuşla sessiz zikir halkası
 *  - Arka plan atmosferini (Teheccüd, Mekke, Medîne, Kudüs, Selçuklu) anında değiştirme
 *  - Ekran açık kalma desteği ve hikmetli sözü paylaşım kartına aktarma
 */
public final class HuzurModu {

    private static final String[][] TEFEKKUR = {
            {"أَلَا بِذِكْرِ اللَّهِ تَطْمَئِنُّ الْقُلُوبُ", "Bilesiniz ki kalpler ancak Allah'ı anmakla huzur bulur.", "Ra'd Sûresi · 13/28"},
            {"فَإِنَّ مَعَ الْعُسْرِ يُسْرًا", "Şüphesiz her zorluğun yanında bir kolaylık vardır.", "İnşirâh Sûresi · 94/5"},
            {"وَهُوَ مَعَكُمْ أَيْنَ مَا كُنتُمْ", "Nerede olursanız olun, O sizinle beraberdir.", "Hadîd Sûresi · 57/4"},
            {"رَبِّ زِدْنِي عِلْمًا", "Rabbim, ilmimi ve basîretimi artır.", "Tâ-Hâ Sûresi · 20/114"},
            {"حَسْبُنَا اللَّهُ وَنِعْمَ الْوَكِيلُ", "Allah bize yeter; O ne güzel vekildir.", "Âl-i İmrân · 3/173"}
    };

    private static final String[][] SAHNELER = {
            {"bg_teheccud_pencere", "Teheccüd Kemeri"},
            {"bg_mekke_gece", "Mekke · Kâbe"},
            {"bg_medine_ravza", "Medîne · Ravza"},
            {"bg_kudus_aksa", "Kudüs · Aksâ"},
            {"bg_selcuklu_avlu", "Selçuklu Avlusu"}
    };

    private HuzurModu() {}

    public static void sayfaAc(DurumAktivitesi a) {
        final TemaMotoru.Durum d = TemaMotoru.aktif(a);
        final Zikir zikir = new Zikir(a);
        final int[] sozIndex = {(int) (System.currentTimeMillis() / 60000L) % TEFEKKUR.length};
        final int[] oturumZikir = {0};

        ScrollView sv = new ScrollView(a);
        sv.setVerticalScrollBarEnabled(false);
        sv.setClipToPadding(false);

        final LinearLayout kok = new LinearLayout(a);
        kok.setOrientation(LinearLayout.VERTICAL);
        kok.setPadding(a.dp(18), a.dp(8), a.dp(18), a.dp(32));
        sv.addView(kok, new ScrollView.LayoutParams(-1, -2));

        // 1. Üst canlı saat + sıradaki vakit + nefes hâlesi
        final NefesHalesiView hale = new NefesHalesiView(a, d);
        LinearLayout.LayoutParams hlp = new LinearLayout.LayoutParams(-1, a.dp(236));
        hlp.setMargins(0, a.dp(4), 0, a.dp(12));
        hale.setLayoutParams(hlp);
        hale.setContentDescription("Huzur nefes ve zikir hâlesi");
        kok.addView(hale);

        final TextView saatTv = new TextView(a);
        saatTv.setTextColor(Color.WHITE);
        saatTv.setTextSize(TypedValue.COMPLEX_UNIT_SP, 44);
        saatTv.setTypeface(Typeface.create("sans-serif-light", Typeface.NORMAL));
        saatTv.setGravity(Gravity.CENTER);
        saatTv.setFontFeatureSettings("tnum");
        saatTv.setShadowLayer(a.dp(8), 0, a.dp(2), 0x80000000);
        kok.addView(saatTv);

        final TextView kalanTv = a.ortala(a.metin("", 15, DurumAktivitesi.ALTIN, true));
        kok.addView(kalanTv);

        final TextView oturumTv = a.ortala(a.metin("Dokunarak sessiz zikir çekin · Bugün: " + zikir.gunluk(), 13, DurumAktivitesi.SOLUK, false));
        oturumTv.setPadding(0, a.dp(4), 0, a.dp(12));
        kok.addView(oturumTv);

        hale.setClickable(true);
        a.basmaEfekti(hale);
        hale.setOnClickListener(v -> {
            v.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP);
            zikir.artir(0);
            oturumZikir[0]++;
            hale.zikirSayisi(oturumZikir[0]);
            oturumTv.setText("Bu huzur oturumunda: " + oturumZikir[0] + " zikir  ·  Bugün: " + zikir.gunluk());
        });

        // 2. Tefekkür / Âyet kartı
        final LinearLayout sozKart = a.cam();
        TextView kartEtiket = a.metin("TEFEKKÜR & KALP SÜKÛNU", 11, DurumAktivitesi.ALTIN, true);
        sozKart.addView(kartEtiket);

        final TextView arapcaTv = new TextView(a);
        arapcaTv.setTypeface(Varlik.kuranYazisi(a));
        arapcaTv.setTextSize(TypedValue.COMPLEX_UNIT_SP, TemaMotoru.olcekliSp(a, 24));
        arapcaTv.setTextColor(d.vurgu);
        arapcaTv.setGravity(Gravity.CENTER);
        arapcaTv.setPadding(0, a.dp(10), 0, a.dp(8));
        sozKart.addView(arapcaTv);

        final TextView mealTv = a.ortala(a.metin("", 16, DurumAktivitesi.BEYAZ, false));
        sozKart.addView(mealTv);

        final TextView kaynakTv = a.ortala(a.metin("", 12, DurumAktivitesi.SOLUK, true));
        kaynakTv.setPadding(0, a.dp(4), 0, a.dp(10));
        sozKart.addView(kaynakTv);

        Runnable sozuGuncelle = () -> {
            String[] parca = TEFEKKUR[sozIndex[0]];
            arapcaTv.setText(parca[0]);
            mealTv.setText(parca[1]);
            kaynakTv.setText(parca[2]);
        };
        sozuGuncelle.run();

        LinearLayout sozEylem = new LinearLayout(a);
        sozEylem.addView(a.dugme("Sonraki Âyet", false, v -> {
            sozIndex[0] = (sozIndex[0] + 1) % TEFEKKUR.length;
            sozuGuncelle.run();
        }), a.yarim(true));
        sozEylem.addView(a.dugme("Kart Paylaş", true, v -> {
            String[] p = TEFEKKUR[sozIndex[0]];
            PaylasimKarti.ozelMetinleAc(a, VakitTakvimi.oku(a), PaylasimKarti.SABLON_AYET, p[0], p[1], p[2]);
        }), a.yarim(false));
        sozKart.addView(sozEylem);
        kok.addView(sozKart);

        // 3. Ambiyans sahnesi seçici + ekran açık tutma anahtarı
        LinearLayout sahneKart = a.cam();
        a.baslik(sahneKart, "Huzur Ambiyansı");
        for (int i = 0; i < SAHNELER.length; i += 2) {
            LinearLayout r = new LinearLayout(a);
            LinearLayout.LayoutParams rlp = new LinearLayout.LayoutParams(-1, -2);
            rlp.setMargins(0, 0, 0, a.dp(8));
            r.setLayoutParams(rlp);
            for (int j = 0; j < 2 && i + j < SAHNELER.length; j++) {
                final String key = SAHNELER[i + j][0];
                final String label = SAHNELER[i + j][1];
                TextView hap = new TextView(a);
                hap.setText(label);
                hap.setGravity(Gravity.CENTER);
                hap.setTextColor(Color.WHITE);
                hap.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12.5f);
                hap.setPadding(a.dp(10), a.dp(10), a.dp(10), a.dp(10));
                GradientDrawable bg = new GradientDrawable();
                bg.setCornerRadius(a.dp(14));
                bg.setColor(0x28FFFFFF);
                bg.setStroke(a.dp(1), 0x44F0B35A);
                hap.setBackground(bg);
                hap.setClickable(true);
                a.basmaEfekti(hap);
                hap.setOnClickListener(v -> {
                    v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
                    if (a.sahneRef() != null) a.sahneRef().goster(key);
                    Toast.makeText(a, label + " sahnesi açıldı", Toast.LENGTH_SHORT).show();
                });
                LinearLayout.LayoutParams clp = new LinearLayout.LayoutParams(0, -2, 1f);
                if (j == 0) clp.setMargins(0, 0, a.dp(6), 0);
                r.addView(hap, clp);
            }
            sahneKart.addView(r);
        }

        LinearLayout ekranSatir = new LinearLayout(a);
        ekranSatir.setGravity(Gravity.CENTER_VERTICAL);
        ekranSatir.setPadding(0, a.dp(6), 0, a.dp(2));
        LinearLayout yaziSol = new LinearLayout(a);
        yaziSol.setOrientation(LinearLayout.VERTICAL);
        yaziSol.addView(a.metin("Tefekkürde ekran açık kalsın", 14, DurumAktivitesi.BEYAZ, true));
        yaziSol.addView(a.metin("Bu ekran açıkken telefon uykuya geçmez", 12, DurumAktivitesi.SOLUK, false));
        ekranSatir.addView(yaziSol, new LinearLayout.LayoutParams(0, -2, 1f));
        final Switch sw = new Switch(a);
        sw.setContentDescription("Tefekkürde ekran açık kalsın");
        sw.setOnCheckedChangeListener((btn, acik) -> {
            hale.setKeepScreenOn(acik);
            sv.setKeepScreenOn(acik);
        });
        ekranSatir.addView(sw);
        sahneKart.addView(ekranSatir);
        kok.addView(sahneKart);

        // Saat & sayaç yenileme döngüsü
        final Handler h = new Handler(Looper.getMainLooper());
        final Runnable guncelle = new Runnable() {
            @Override
            public void run() {
                if (!sv.isAttachedToWindow()) return;
                long ms = System.currentTimeMillis();
                saatTv.setText(new SimpleDateFormat("HH:mm:ss", Metinler.TR).format(new Date(ms)));
                VakitTakvimi.An sonraki = VakitTakvimi.oku(a).sonraki();
                if (sonraki != null && sonraki.zaman > ms) {
                    kalanTv.setText(Metinler.yonelme(sonraki.ad()) + " " + Metinler.sure(sonraki.zaman - ms));
                } else {
                    kalanTv.setText("Gece sükûneti");
                }
                h.postDelayed(this, 1000L);
            }
        };
        sv.addOnAttachStateChangeListener(new View.OnAttachStateChangeListener() {
            @Override public void onViewAttachedToWindow(View v) { h.post(guncelle); }
            @Override public void onViewDetachedFromWindow(View v) { h.removeCallbacks(guncelle); }
        });

        a.altSayfa("Huzur & Tefekkür", sv, "huzur");
    }

    /** 4 saniye nefes al / 4 saniye ver ritminde dalgalanan konsantrik nur hâlesi. */
    public static final class NefesHalesiView extends View {

        private final TemaMotoru.Durum d;
        private final Paint boya = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint yazi = new Paint(Paint.ANTI_ALIAS_FLAG);
        private int zikirSayisi = 0;

        public NefesHalesiView(Context c, TemaMotoru.Durum d) {
            super(c);
            this.d = d;
            yazi.setTextAlign(Paint.Align.CENTER);
        }

        public void zikirSayisi(int s) {
            this.zikirSayisi = s;
            invalidate();
        }

        @Override
        protected void onDraw(Canvas c) {
            int w = getWidth(), h = getHeight();
            if (w <= 0 || h <= 0) return;
            float dp = getResources().getDisplayMetrics().density;
            float cx = w * 0.5f, cy = h * 0.5f;
            float maxR = Math.min(w, h) * 0.44f;

            // 8 saniyelik nefes döngüsü: 0..4 sn al, 4..8 sn ver
            long mod = System.currentTimeMillis() % 8000L;
            boolean nefesAl = mod < 4000L;
            float faz = (mod % 4000L) / 4000f;
            float yumusak = nefesAl
                    ? (float) (0.5 - 0.5 * Math.cos(faz * Math.PI))
                    : (float) (0.5 + 0.5 * Math.cos(faz * Math.PI));

            float icR = maxR * (0.48f + 0.34f * yumusak);
            boya.setStyle(Paint.Style.FILL);
            boya.setShader(new RadialGradient(cx, cy, maxR,
                    new int[]{renkAlfa(d.vurgu, 120), renkAlfa(d.ana, 45), Color.TRANSPARENT},
                    new float[]{0f, 0.62f, 1f}, Shader.TileMode.CLAMP));
            c.drawCircle(cx, cy, maxR * (0.78f + 0.22f * yumusak), boya);
            boya.setShader(null);

            for (int i = 0; i < 3; i++) {
                float r = icR * (0.72f + i * 0.16f);
                boya.setStyle(Paint.Style.STROKE);
                boya.setStrokeWidth((2.2f - i * 0.45f) * dp);
                boya.setColor(i == 0 ? d.vurgu : Color.WHITE);
                boya.setAlpha(Math.round((190 - i * 48) * (0.65f + 0.35f * yumusak)));
                c.drawCircle(cx, cy, r, boya);
            }

            yazi.setColor(Color.WHITE);
            yazi.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
            yazi.setTextSize(17f * dp);
            String baslik = zikirSayisi > 0 ? "Sübhânallah  ·  " + zikirSayisi : (nefesAl ? "Nefes Al · Zikret" : "Yavaşça Bırak");
            c.drawText(baslik, cx, cy + 5f * dp, yazi);

            yazi.setColor(0xCCFFFFFF);
            yazi.setTypeface(Typeface.DEFAULT);
            yazi.setTextSize(11.5f * dp);
            c.drawText("Zikir halkasına dokunun", cx, cy + 25f * dp, yazi);

            if (isShown()) postInvalidateDelayed(35);
        }

        private static int renkAlfa(int renk, int a) {
            return (renk & 0x00FFFFFF) | (Math.max(0, Math.min(255, a)) << 24);
        }
    }
}
