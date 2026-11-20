package com.mehmetderin.secde_vakti.saglik;

import android.app.AlertDialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.res.AssetFileDescriptor;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.media.MediaPlayer;
import android.text.Editable;
import android.text.TextWatcher;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.HapticFeedbackConstants;
import android.view.View;
import android.view.ViewGroup;
import android.view.animation.OvershootInterpolator;
import android.widget.AbsListView;
import android.widget.BaseAdapter;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Random;

import static com.mehmetderin.secde_vakti.saglik.DurumAktivitesi.ALTIN;
import static com.mehmetderin.secde_vakti.saglik.DurumAktivitesi.BEYAZ;
import static com.mehmetderin.secde_vakti.saglik.DurumAktivitesi.IYI;
import static com.mehmetderin.secde_vakti.saglik.DurumAktivitesi.KOTU;
import static com.mehmetderin.secde_vakti.saglik.DurumAktivitesi.KOYU;
import static com.mehmetderin.secde_vakti.saglik.DurumAktivitesi.SILIK;
import static com.mehmetderin.secde_vakti.saglik.DurumAktivitesi.SOLUK;

/**
 * Kur'an bölümü: sure listesi ve arama, sure okuyucu (Arapça + meal, tilavet, vurgu, yer imi,
 * kelime kelime), sesli meal, yer imleri, Elif-Ba (harfler, harekeler, test), Dualar, Esmâü'l-Hüsnâ.
 * Görünüm yardımcıları ana menüden (DurumAktivitesi) gelir.
 */
final class KuranArayuz {

    static final String BESMELE = "بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ";

    private final DurumAktivitesi a;
    private final List<View> oynaticilar = new ArrayList<>();

    // Açık sure okuyucu
    private View okuyucuSayfa;
    private ListView liste;
    private AyetListesi ayetListesi;
    private Kuran.Sure acikSure;

    private MediaPlayer harfSesi;
    private final Random rnd = new Random();

    KuranArayuz(DurumAktivitesi a) {
        this.a = a;
    }

    // ================================================================ yaşam döngüsü

    void devam() {
        TilavetServisi.dinleyici = this::tilavetDegisti;
        tilavetDegisti();
    }

    void durakla() {
        TilavetServisi.dinleyici = null;
        if (harfSesi != null) {
            try {
                harfSesi.release();
            } catch (Throwable ignored) {
            }
            harfSesi = null;
        }
    }

    void altSayfaKapandi(View v) {
        if (v == okuyucuSayfa) {
            okuyucuSayfa = null;
            liste = null;
            ayetListesi = null;
            acikSure = null;
        }
    }

    private void tilavetDegisti() {
        for (View o : new ArrayList<>(oynaticilar)) {
            if (o.getTag() instanceof Runnable) ((Runnable) o.getTag()).run();
        }
        if (ayetListesi != null) {
            ayetListesi.notifyDataSetChanged();
            TilavetServisi.Parca p = TilavetServisi.simdiki();
            if (p != null && acikSure != null && p.sure == acikSure.no && liste != null) {
                int konum = p.ayet; // başlık satırı 0
                if (konum < liste.getFirstVisiblePosition() || konum > liste.getLastVisiblePosition() - 1) {
                    liste.smoothScrollToPositionFromTop(konum, a.dp(80));
                }
            }
        }
    }

    // ================================================================ Kur'an sekmesi

    LinearLayout sekme() {
        LinearLayout s = a.sutun();
        a.sayfaBasligi(s, "Kur'an-ı Kerim", "114 sure · Türkçe meal · tilavet · Elif-Ba");

        int[] son = Kuran.sonOkunan(a);
        if (son != null) {
            Kuran.Sure su = Kuran.sure(a, son[0]);
            if (su != null) {
                LinearLayout k = a.cam();
                k.setOrientation(LinearLayout.HORIZONTAL);
                k.setGravity(Gravity.CENTER_VERTICAL);
                LinearLayout y = new LinearLayout(a);
                y.setOrientation(LinearLayout.VERTICAL);
                y.addView(a.metin("KALDIĞIN YER", 12, ALTIN, true));
                y.addView(a.metin(su.ad + " · " + son[1] + ". ayet", 18, BEYAZ, true));
                k.addView(y, new LinearLayout.LayoutParams(0, -2, 1f));
                k.addView(a.metin("Devam ›", 15, ALTIN, true));
                k.setClickable(true);
                a.basmaEfekti(k);
                final int[] ss = son;
                k.setOnClickListener(v -> sureAc(ss[0], ss[1]));
                s.addView(k);
            }
        }

        s.addView(oynaticiCubugu());
        s.addView(HatimTakip.ozetKart(a));

        s.addView(a.altBaslik("Öğren ve dinle"));
        HorizontalScrollView yatay = new HorizontalScrollView(a);
        yatay.setHorizontalScrollBarEnabled(false);
        yatay.setOverScrollMode(View.OVER_SCROLL_NEVER);
        LinearLayout sira = new LinearLayout(a);
        sira.addView(a.kutucuk("k_hilal", "Hatim Takibi", "30 cüz · sesli", 0xFF1B5A45, () -> HatimTakip.sayfaAc(a)), a.kutucukDuzeni(140, 140, true));
        sira.addView(a.kutucuk("mihrap", "Namaz Sûreleri", "Ezber · ezan", 0xFF5A3A1B, () -> EzanStudyo.sayfaAc(a)), a.kutucukDuzeni(140, 140, false));
        sira.addView(a.kutucuk("elifba_bg", "Elif-Ba", "Harfler · test", 0xFF3A2A6A, this::elifBaAc), a.kutucukDuzeni(140, 140, false));
        sira.addView(a.kutucuk("k_kubbe", "Sesli meal", "10 okuyucu", 0xFF2A3A7A, this::sesliMealAc), a.kutucukDuzeni(140, 140, false));
        sira.addView(a.kutucuk("k_dua", "Dualar", "Günlük dualar", 0xFF8A3A3A, this::dualarAc), a.kutucukDuzeni(140, 140, false));
        sira.addView(a.kutucuk("k_cini", "Esmâü'l-Hüsnâ", "99 isim", 0xFF1A4A7A, this::esmaAc), a.kutucukDuzeni(140, 140, false));
        sira.addView(a.kutucuk("kuran_bg", "Yer imleri", "Kaydedilenler", 0xFF6A3A12, this::yerImleriAc), a.kutucukDuzeni(140, 140, false));
        yatay.addView(sira);
        s.addView(yatay, new LinearLayout.LayoutParams(-1, -2));
        a.bosluk(s, 6);

        s.addView(a.altBaslik("Sureler"));
        final EditText ara = arama("Sure ara: ad ya da numara");
        s.addView(ara);
        final LinearLayout k = a.cam();
        k.setPadding(a.dp(6), a.dp(6), a.dp(6), a.dp(6));
        final List<View> satirlar = new ArrayList<>();
        final List<String> anahtarlar = new ArrayList<>();
        for (Kuran.Sure su : Kuran.sureler(a)) {
            View r = sureSatiri(su);
            satirlar.add(r);
            anahtarlar.add(su.no + " " + Kuran.sade(su.ad) + " " + su.arapca);
            k.addView(r);
        }
        if (satirlar.isEmpty()) k.addView(a.metin("Kur'an verisi okunamadı.", 15, KOTU, false));
        ara.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence x, int b, int c, int d) {}
            @Override public void onTextChanged(CharSequence x, int b, int c, int d) {}
            @Override public void afterTextChanged(Editable e) {
                String q = Kuran.sade(e.toString());
                for (int i = 0; i < satirlar.size(); i++) {
                    String an = anahtarlar.get(i);
                    boolean uy = q.isEmpty() || an.startsWith(q + " ") || an.contains(" " + q) || an.contains(q);
                    satirlar.get(i).setVisibility(uy ? View.VISIBLE : View.GONE);
                }
            }
        });
        s.addView(k);
        return s;
    }

    private View sureSatiri(final Kuran.Sure su) {
        LinearLayout r = new LinearLayout(a);
        r.setGravity(Gravity.CENTER_VERTICAL);
        r.setPadding(a.dp(8), a.dp(10), a.dp(10), a.dp(10));
        r.addView(numara(su.no, 15), new LinearLayout.LayoutParams(a.dp(38), a.dp(38)));
        LinearLayout y = new LinearLayout(a);
        y.setOrientation(LinearLayout.VERTICAL);
        y.setPadding(a.dp(12), 0, 0, 0);
        y.addView(a.metin(su.ad, 16, BEYAZ, true));
        y.addView(a.metin(su.yer + " · " + su.ayetSayisi + " ayet" + (Kuran.kelimeVar(a, su.no) ? " · kelime meali" : ""), 12, SOLUK, false));
        r.addView(y, new LinearLayout.LayoutParams(0, -2, 1f));
        TextView ar = a.metin(su.arapca, 22, ALTIN, false);
        ar.setTypeface(Varlik.kuranYazisi(a));
        r.addView(ar);
        r.setClickable(true);
        r.setContentDescription(su.ad + " suresi");
        a.basmaEfekti(r);
        r.setOnClickListener(v -> {
            v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            int[] son = Kuran.sonOkunan(a);
            sureAc(su.no, son != null && son[0] == su.no ? son[1] : 1);
        });
        return r;
    }

    private TextView numara(int n, int sp) {
        TemaMotoru.Durum tm = TemaMotoru.aktif(a);
        TextView t = a.metin(String.valueOf(n), sp, tm.vurgu, true);
        t.setGravity(Gravity.CENTER);
        t.setShadowLayer(0, 0, 0, 0);
        GradientDrawable g = new GradientDrawable();
        g.setShape(GradientDrawable.OVAL);
        g.setColor((tm.vurgu & 0x00FFFFFF) | (tm.acik ? 0x22000000 : 0x33000000));
        g.setStroke(a.dp(1), (tm.vurgu & 0x00FFFFFF) | 0x99000000);
        t.setBackground(g);
        return t;
    }

    private EditText arama(String ipucu) {
        TemaMotoru.Durum tm = TemaMotoru.aktif(a);
        EditText e = new EditText(a);
        e.setHint(ipucu);
        e.setHintTextColor(tm.silik);
        e.setTextColor(tm.metin);
        e.setSingleLine(true);
        e.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15 * tm.yaziOlcegi);
        e.setPadding(a.dp(16), a.dp(12), a.dp(16), a.dp(12));
        GradientDrawable g = new GradientDrawable();
        g.setColor(tm.acik ? 0xE6FFFFFF : 0x33000000);
        g.setStroke(1, tm.acik ? 0x441F5C4B : 0x4DFFFFFF);
        g.setCornerRadius(a.dp(16));
        e.setBackground(g);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(0, 0, 0, a.dp(10));
        e.setLayoutParams(lp);
        return e;
    }

    // ================================================================ oynatıcı çubuğu

    /** Tilavet/meal çalarken görünen çubuk: başlık, durum, ⏯ ⏭ ⏹. Tilavet değiştikçe kendini günceller. */
    View oynaticiCubugu() {
        final LinearLayout k = a.cam();
        k.setOrientation(LinearLayout.HORIZONTAL);
        k.setGravity(Gravity.CENTER_VERTICAL);
        final LinearLayout y = new LinearLayout(a);
        y.setOrientation(LinearLayout.VERTICAL);
        final TextView ust = a.metin("", 15, BEYAZ, true);
        final TextView alt = a.metin("", 12, SOLUK, false);
        y.addView(ust);
        y.addView(alt);
        k.addView(y, new LinearLayout.LayoutParams(0, -2, 1f));
        final TextView oynat = simgeDugme("⏸");
        oynat.setContentDescription("Duraklat ya da devam et");
        oynat.setOnClickListener(v -> TilavetServisi.komut(a, TilavetServisi.DURAKLAT));
        TextView sonraki = simgeDugme("⏭");
        sonraki.setContentDescription("Sonraki");
        sonraki.setOnClickListener(v -> TilavetServisi.komut(a, TilavetServisi.SONRAKI));
        TextView dur = simgeDugme("⏹");
        dur.setContentDescription("Durdur");
        dur.setOnClickListener(v -> TilavetServisi.komut(a, TilavetServisi.DURDUR));
        k.addView(oynat);
        k.addView(sonraki);
        k.addView(dur);
        Runnable guncelle = () -> {
            TilavetServisi.Parca p = TilavetServisi.simdiki();
            k.setVisibility(p == null ? View.GONE : View.VISIBLE);
            if (p == null) return;
            ust.setText((TilavetServisi.caliyor() ? "▶ " : "❚❚ ") + p.baslik);
            String d = TilavetServisi.hata() != null ? TilavetServisi.hata()
                    : TilavetServisi.hazirlaniyor() ? "Yükleniyor… · " + TilavetServisi.baslik() : TilavetServisi.baslik();
            alt.setText(d);
            alt.setTextColor(TilavetServisi.hata() != null ? KOTU : SOLUK);
            oynat.setText(TilavetServisi.caliyor() ? "⏸" : "▶");
        };
        k.setTag(guncelle);
        oynaticilar.add(k);
        k.addOnAttachStateChangeListener(new View.OnAttachStateChangeListener() {
            @Override public void onViewAttachedToWindow(View v) {
                if (!oynaticilar.contains(k)) oynaticilar.add(k);
                guncelle.run();
            }
            @Override public void onViewDetachedFromWindow(View v) {
                oynaticilar.remove(k);
            }
        });
        guncelle.run();
        return k;
    }

    private TextView simgeDugme(String s) {
        TemaMotoru.Durum tm = TemaMotoru.aktif(a);
        TextView t = a.metin(s, 18, tm.birincilDugmeYaziRengi(), true);
        t.setShadowLayer(0, 0, 0, 0);
        t.setGravity(Gravity.CENTER);
        GradientDrawable g = tm.birincilDugme(a, 21);
        g.setShape(GradientDrawable.OVAL);
        t.setBackground(g);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(a.dp(42), a.dp(42));
        lp.setMargins(a.dp(6), 0, 0, 0);
        t.setLayoutParams(lp);
        t.setClickable(true);
        a.basmaEfekti(t);
        return t;
    }

    private TextView cip(String s, boolean secili, View.OnClickListener l) {
        TemaMotoru.Durum tm = TemaMotoru.aktif(a);
        TextView c = a.metin(s, 14, secili ? tm.birincilDugmeYaziRengi() : tm.metin, true);
        c.setShadowLayer(0, 0, 0, 0);
        c.setPadding(a.dp(14), a.dp(8), a.dp(14), a.dp(8));
        c.setBackground(tm.cipArkaPlani(a, secili, 18));
        c.setOnClickListener(v -> {
            v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            l.onClick(v);
        });
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-2, -2);
        lp.setMargins(0, 0, a.dp(8), 0);
        c.setLayoutParams(lp);
        return c;
    }

    // ================================================================ sure okuyucu

    void sureAc(int no, int ayet) {
        a.guvenli("sureAc " + no, () -> sureAcIc(no, ayet));
    }

    private void sureAcIc(int no, int ayet) {
        final Kuran.Sure su = Kuran.sure(a, no);
        if (su == null) return;
        // Okuyucu en üstteyse yenisiyle değiştir (yer imi / kaldığın yer ile başka sureye geçiş)
        if (okuyucuSayfa != null && !a.altYigin.isEmpty() && a.altYigin.get(a.altYigin.size() - 1) == okuyucuSayfa) a.altSayfaKapat();
        acikSure = su;

        LinearLayout icerik = new LinearLayout(a);
        icerik.setOrientation(LinearLayout.VERTICAL);

        // Eylem şeridi
        HorizontalScrollView yatay = new HorizontalScrollView(a);
        yatay.setHorizontalScrollBarEnabled(false);
        LinearLayout ciplar = new LinearLayout(a);
        ciplar.setPadding(a.dp(16), 0, a.dp(16), a.dp(8));
        ciplar.addView(cip("▶ Tilavet", true, v -> tilavetBaslat(su, ilkGorunenAyet())));
        ciplar.addView(cip("Meal dinle", false, v -> mealDinle(su)));
        ciplar.addView(cip("Hâfız", false, v -> hafizSec()));
        ciplar.addView(cip("A−", false, v -> { Kuran.yaziBoyu(a, Kuran.yaziBoyu(a) - 2); if (ayetListesi != null) ayetListesi.notifyDataSetChanged(); }));
        ciplar.addView(cip("A+", false, v -> { Kuran.yaziBoyu(a, Kuran.yaziBoyu(a) + 2); if (ayetListesi != null) ayetListesi.notifyDataSetChanged(); }));
        ciplar.addView(cip("Görünüm", false, v -> gorunumSec()));
        yatay.addView(ciplar);
        icerik.addView(yatay);

        FrameLayout govde = new FrameLayout(a);
        final TextView yukleniyor = a.ortala(a.metin("Yükleniyor…", 16, SOLUK, false));
        govde.addView(yukleniyor, new FrameLayout.LayoutParams(-1, -2, Gravity.CENTER));
        liste = new ListView(a);
        liste.setDivider(null);
        liste.setDividerHeight(0);
        liste.setCacheColorHint(Color.TRANSPARENT);
        liste.setSelector(new android.graphics.drawable.ColorDrawable(Color.TRANSPARENT));
        liste.setVerticalScrollBarEnabled(false);
        liste.setClipToPadding(false);
        liste.setPadding(a.dp(14), 0, a.dp(14), a.dp(24));
        liste.addHeaderView(sureBasligi(su), null, false);
        govde.addView(liste, new FrameLayout.LayoutParams(-1, -1));
        icerik.addView(govde, new LinearLayout.LayoutParams(-1, 0, 1f));

        View cubuk = oynaticiCubugu();
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(a.dp(14), a.dp(6), a.dp(14), a.dp(4));
        icerik.addView(cubuk, lp);

        a.altSayfa(su.no + ". " + su.ad, icerik, "kuran_bg");
        okuyucuSayfa = a.altYigin.get(a.altYigin.size() - 1);

        final int hedef = Math.max(1, Math.min(su.ayetSayisi, ayet));
        final ListView buListe = liste;
        new Thread(() -> {
            final List<Kuran.Ayet> l = Kuran.ayetler(a, su.no);
            a.runOnUiThread(() -> {
                if (liste != buListe) return;
                yukleniyor.setVisibility(View.GONE);
                ayetListesi = new AyetListesi(su, l);
                buListe.setAdapter(ayetListesi);
                if (hedef > 1) buListe.setSelectionFromTop(hedef, a.dp(8));
                buListe.setOnScrollListener(new AbsListView.OnScrollListener() {
                    private int sonKayit = hedef;

                    @Override public void onScrollStateChanged(AbsListView v, int s) {}
                    @Override public void onScroll(AbsListView v, int ilk, int adet, int toplam) {
                        // Her karede değil, yalnız görünen ilk ayet değişince kaydet
                        int ayetNo = Math.min(su.ayetSayisi, ilk);
                        if (ilk > 0 && ayetNo != sonKayit) {
                            sonKayit = ayetNo;
                            Kuran.sonOkunan(a, su.no, ayetNo);
                        }
                    }
                });
            });
        }, "secde-kuran").start();
        Kuran.sonOkunan(a, su.no, hedef);
    }

    private int ilkGorunenAyet() {
        if (liste == null) return 1;
        return Math.max(1, liste.getFirstVisiblePosition());
    }

    private View sureBasligi(Kuran.Sure su) {
        LinearLayout k = a.cam();
        k.setGravity(Gravity.CENTER_HORIZONTAL);
        TextView ar = a.ortala(a.metin(su.arapca, 40, ALTIN, false));
        ar.setTypeface(Varlik.kuranYazisi(a));
        k.addView(ar);
        k.addView(a.ortala(a.metin(su.ad + " Suresi", 18, BEYAZ, true)));
        k.addView(a.ortala(a.metin(su.yer + " · " + su.ayetSayisi + " ayet · " + Kuran.hafizAdi(Kuran.hafiz(a)), 12, SOLUK, false)));
        if (su.besmele && su.no != 1 && su.no != 9) {
            TextView b = a.ortala(a.metin(BESMELE, 26, BEYAZ, false));
            b.setTypeface(Varlik.kuranYazisi(a));
            b.setPadding(0, a.dp(10), 0, 0);
            k.addView(b);
        }
        k.setLayoutParams(new AbsListView.LayoutParams(-1, -2));
        LinearLayout sar = new LinearLayout(a);
        sar.setOrientation(LinearLayout.VERTICAL);
        sar.setPadding(0, 0, 0, a.dp(12));
        sar.addView(k);
        sar.setLayoutParams(new AbsListView.LayoutParams(-1, -2));
        return sar;
    }

    private final class AyetListesi extends BaseAdapter {
        final Kuran.Sure su;
        final List<Kuran.Ayet> ayetler;

        AyetListesi(Kuran.Sure su, List<Kuran.Ayet> ayetler) {
            this.su = su;
            this.ayetler = ayetler;
        }

        @Override public int getCount() { return ayetler.size(); }
        @Override public Object getItem(int i) { return ayetler.get(i); }
        @Override public long getItemId(int i) { return i; }

        @Override
        public View getView(int i, View eski, ViewGroup ust) {
            final Kuran.Ayet ay = ayetler.get(i);
            final TemaMotoru.Durum tm = TemaMotoru.aktif(a);
            LinearLayout k = new LinearLayout(a);
            k.setOrientation(LinearLayout.VERTICAL);
            k.setPadding(a.dp(14), a.dp(12), a.dp(14), a.dp(14));
            TilavetServisi.Parca p = TilavetServisi.simdiki();
            boolean okunuyor = p != null && p.sure == su.no && p.ayet == ay.no;
            GradientDrawable g = new GradientDrawable();
            g.setCornerRadius(a.dp(18));
            int vurguDolgu = (tm.vurgu & 0x00FFFFFF) | (tm.acik ? 0x26000000 : 0x40000000);
            g.setColor(okunuyor ? vurguDolgu : (tm.acik ? 0xEBFFFFFF : tm.camUst));
            g.setStroke(okunuyor ? a.dp(2) : 1, okunuyor ? ((tm.vurgu & 0x00FFFFFF) | 0xCC000000) : tm.camKenar);
            k.setBackground(g);
            AbsListView.LayoutParams lp = new AbsListView.LayoutParams(-1, -2);
            k.setLayoutParams(lp);

            LinearLayout ustSatir = new LinearLayout(a);
            ustSatir.setGravity(Gravity.CENTER_VERTICAL);
            ustSatir.addView(numara(ay.no, 12), new LinearLayout.LayoutParams(a.dp(30), a.dp(30)));
            TextView bos = new TextView(a);
            ustSatir.addView(bos, new LinearLayout.LayoutParams(0, 1, 1f));
            if (okunuyor) ustSatir.addView(a.metin("okunuyor  ", 12, ALTIN, true));
            if (Kuran.yerImi(a, su.no, ay.no)) ustSatir.addView(a.metin("★", 18, ALTIN, true));
            k.addView(ustSatir);

            int gor = Kuran.gorunum(a);
            if (gor != 2) {
                TextView ar = a.metin(ay.arapca, Kuran.yaziBoyu(a), BEYAZ, false);
                ar.setTypeface(Varlik.kuranYazisi(a));
                // Sağdan sola: kısa ayetler de sağa yaslansın (END, RTL paragrafta sola düşer)
                ar.setTextDirection(View.TEXT_DIRECTION_RTL);
                ar.setTextAlignment(View.TEXT_ALIGNMENT_GRAVITY);
                ar.setGravity(Gravity.RIGHT);
                ar.setLineSpacing(0, 1.55f);
                ar.setPadding(0, a.dp(6), 0, a.dp(6));
                k.addView(ar);
            }
            if (gor != 1) {
                k.addView(a.metin(ay.meal, 16, gor == 2 ? BEYAZ : SOLUK, false));
                if (ay.dipnot != null && !ay.dipnot.isEmpty()) k.addView(a.metin(ay.dipnot, 12, SILIK, false));
            }
            k.setOnClickListener(v -> ayetMenusu(su, ay));
            LinearLayout sar = new LinearLayout(a);
            sar.setPadding(0, 0, 0, a.dp(10));
            sar.setLayoutParams(new AbsListView.LayoutParams(-1, -2));
            sar.addView(k, new LinearLayout.LayoutParams(-1, -2));
            return sar;
        }
    }

    private void ayetMenusu(final Kuran.Sure su, final Kuran.Ayet ay) {
        final boolean imli = Kuran.yerImi(a, su.no, ay.no);
        final boolean kelime = Kuran.kelimeVar(a, su.no);
        List<String> s = new ArrayList<>();
        s.add("Buradan itibaren dinle");
        s.add("Yalnız bu ayeti dinle");
        s.add(imli ? "Yer iminden çıkar" : "Yer imi ekle");
        if (kelime) s.add("Kelime kelime meal");
        s.add("Kart olarak paylaş");
        s.add("Kopyala");
        s.add("Paylaş");
        new AlertDialog.Builder(a)
                .setTitle(su.ad + " " + ay.no)
                .setItems(s.toArray(new String[0]), (d, w) -> {
                    String sec = s.get(w);
                    if (sec.startsWith("Buradan")) tilavetBaslat(su, ay.no);
                    else if (sec.startsWith("Yalnız")) {
                        List<TilavetServisi.Parca> k = Collections.singletonList(new TilavetServisi.Parca(
                                Kuran.ayetSesi(Kuran.hafiz(a), su.no, ay.no), su.ad + " " + ay.no, su.no, ay.no));
                        TilavetServisi.baslat(a, k, Kuran.hafizAdi(Kuran.hafiz(a)));
                    } else if (sec.startsWith("Yer")) {
                        boolean eklendi = Kuran.yerImiDegistir(a, su.no, ay.no);
                        Toast.makeText(a, eklendi ? "Yer imi eklendi" : "Yer imi kaldırıldı", Toast.LENGTH_SHORT).show();
                        if (ayetListesi != null) ayetListesi.notifyDataSetChanged();
                    } else if (sec.startsWith("Kelime")) kelimeKelime(su, ay);
                    else if (sec.startsWith("Kart")) {
                        PaylasimKarti.ozelMetinleAc(a, VakitTakvimi.oku(a), PaylasimKarti.SABLON_AYET,
                                ay.arapca, ay.meal, su.ad + " Sûresi, " + ay.no + ". Âyet");
                    } else if (sec.equals("Kopyala")) {
                        ClipboardManager cm = (ClipboardManager) a.getSystemService(Context.CLIPBOARD_SERVICE);
                        if (cm != null) cm.setPrimaryClip(ClipData.newPlainText("Ayet", ayetMetni(su, ay)));
                        Toast.makeText(a, "Ayet kopyalandı", Toast.LENGTH_SHORT).show();
                    } else {
                        try {
                            a.startActivity(Intent.createChooser(new Intent(Intent.ACTION_SEND).setType("text/plain")
                                    .putExtra(Intent.EXTRA_TEXT, ayetMetni(su, ay)), "Ayeti paylaş"));
                        } catch (Throwable ignored) {
                        }
                    }
                })
                .show();
    }

    private static String ayetMetni(Kuran.Sure su, Kuran.Ayet ay) {
        return ay.arapca + "\n\n" + ay.meal + "\n\n(" + su.ad + ", " + ay.no + ")";
    }

    private void kelimeKelime(Kuran.Sure su, Kuran.Ayet ay) {
        List<Kuran.Kelime> l = Kuran.kelimeler(a, su.no, ay.no);
        LinearLayout k = new LinearLayout(a);
        k.setOrientation(LinearLayout.VERTICAL);
        k.setPadding(a.dp(20), a.dp(12), a.dp(20), a.dp(4));
        for (Kuran.Kelime w : l) {
            LinearLayout r = new LinearLayout(a);
            r.setGravity(Gravity.CENTER_VERTICAL);
            r.setPadding(0, a.dp(6), 0, a.dp(6));
            TextView ar = new TextView(a);
            ar.setText(w.arapca);
            ar.setTypeface(Varlik.kuranYazisi(a));
            ar.setTextSize(TypedValue.COMPLEX_UNIT_SP, 24);
            r.addView(ar, new LinearLayout.LayoutParams(a.dp(110), -2));
            TextView tr = new TextView(a);
            tr.setText(w.meal + (w.okunus.isEmpty() ? "" : "\n" + w.okunus));
            tr.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15);
            r.addView(tr, new LinearLayout.LayoutParams(0, -2, 1f));
            k.addView(r);
        }
        ScrollView sv = new ScrollView(a);
        sv.addView(k);
        new AlertDialog.Builder(a).setTitle("Kelime kelime · " + su.ad + " " + ay.no).setView(sv)
                .setPositiveButton("Tamam", null).show();
    }

    private void tilavetBaslat(Kuran.Sure su, int ayet) {
        String h = Kuran.hafiz(a);
        TilavetServisi.baslat(a, TilavetServisi.tilavetKuyrugu(su, ayet, h), Kuran.hafizAdi(h));
        Toast.makeText(a, su.ad + " " + ayet + ". ayetten tilavet · internet gerekir", Toast.LENGTH_SHORT).show();
    }

    private void mealDinle(Kuran.Sure su) {
        String[] m = Kuran.mealSesi(a, su.no, Kuran.mealOkuyucu(a));
        if (m == null) {
            Toast.makeText(a, "Bu surenin sesli meali yok", Toast.LENGTH_SHORT).show();
            return;
        }
        TilavetServisi.baslat(a, Collections.singletonList(new TilavetServisi.Parca(m[1], su.ad + " meali", su.no, 0)),
                "Sesli meal · " + m[0]);
    }

    private void hafizSec() {
        String[] ad = new String[Kuran.HAFIZLAR.length];
        int secili = 0;
        for (int i = 0; i < ad.length; i++) {
            ad[i] = Kuran.HAFIZLAR[i][1];
            if (Kuran.HAFIZLAR[i][0].equals(Kuran.hafiz(a))) secili = i;
        }
        new AlertDialog.Builder(a).setTitle("Tilavet okuyucusu")
                .setSingleChoiceItems(ad, secili, (d, w) -> {
                    Kuran.hafiz(a, Kuran.HAFIZLAR[w][0]);
                    d.dismiss();
                    Toast.makeText(a, Kuran.HAFIZLAR[w][1], Toast.LENGTH_SHORT).show();
                }).setNegativeButton("Vazgeç", null).show();
    }

    private void gorunumSec() {
        String[] ad = {"Arapça ve meal", "Yalnız Arapça", "Yalnız meal"};
        new AlertDialog.Builder(a).setTitle("Görünüm")
                .setSingleChoiceItems(ad, Kuran.gorunum(a), (d, w) -> {
                    Kuran.gorunum(a, w);
                    d.dismiss();
                    if (ayetListesi != null) ayetListesi.notifyDataSetChanged();
                }).setNegativeButton("Vazgeç", null).show();
    }

    // ================================================================ sesli meal

    void sesliMealAc() {
        a.guvenli("sesliMealAc", this::sesliMealAcIc);
    }

    private void sesliMealAcIc() {
        LinearLayout s = a.sutun();
        s.addView(a.metin("Surelerin Türkçe meali, okuyucu sesiyle (internet gerekir). Telefon kilitliyken de çalar.", 14, SOLUK, false));
        a.bosluk(s, 8);
        s.addView(oynaticiCubugu());
        s.addView(a.altBaslik("Okuyucu"));
        final HorizontalScrollView yatay = new HorizontalScrollView(a);
        yatay.setHorizontalScrollBarEnabled(false);
        final LinearLayout ciplar = new LinearLayout(a);
        yatay.addView(ciplar);
        s.addView(yatay);
        final Runnable[] ciz = new Runnable[1];
        ciz[0] = () -> {
            ciplar.removeAllViews();
            String sec = Kuran.mealOkuyucu(a);
            List<String> ok = Kuran.mealOkuyuculari(a);
            if (sec == null && !ok.isEmpty()) sec = ok.get(0);
            for (final String o : ok) {
                ciplar.addView(cip(o, o.equals(sec), v -> {
                    Kuran.mealOkuyucu(a, o);
                    ciz[0].run();
                }));
            }
        };
        ciz[0].run();
        a.bosluk(s, 6);
        s.addView(a.altBaslik("Sureler"));
        final EditText ara = arama("Sure ara");
        s.addView(ara);
        LinearLayout k = a.cam();
        k.setPadding(a.dp(6), a.dp(6), a.dp(6), a.dp(6));
        final List<View> satirlar = new ArrayList<>();
        final List<String> anahtar = new ArrayList<>();
        for (final Kuran.Sure su : Kuran.sureler(a)) {
            LinearLayout r = new LinearLayout(a);
            r.setGravity(Gravity.CENTER_VERTICAL);
            r.setPadding(a.dp(8), a.dp(8), a.dp(8), a.dp(8));
            r.addView(numara(su.no, 14), new LinearLayout.LayoutParams(a.dp(34), a.dp(34)));
            TextView ad = a.metin(su.ad, 16, BEYAZ, true);
            ad.setPadding(a.dp(12), 0, 0, 0);
            r.addView(ad, new LinearLayout.LayoutParams(0, -2, 1f));
            r.addView(a.metin("▶", 18, ALTIN, true));
            r.setClickable(true);
            a.basmaEfekti(r);
            r.setOnClickListener(v -> mealDinle(su));
            satirlar.add(r);
            anahtar.add(su.no + " " + Kuran.sade(su.ad));
            k.addView(r);
        }
        ara.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence x, int b, int c, int d) {}
            @Override public void onTextChanged(CharSequence x, int b, int c, int d) {}
            @Override public void afterTextChanged(Editable e) {
                String q = Kuran.sade(e.toString());
                for (int i = 0; i < satirlar.size(); i++)
                    satirlar.get(i).setVisibility(q.isEmpty() || anahtar.get(i).contains(q) ? View.VISIBLE : View.GONE);
            }
        });
        s.addView(k);
        a.altSayfa("Sesli meal", sargi(s), "kuran_bg");
    }

    private ScrollView sargi(LinearLayout s) {
        ScrollView sv = new ScrollView(a);
        sv.setVerticalScrollBarEnabled(false);
        sv.setOverScrollMode(View.OVER_SCROLL_NEVER);
        sv.addView(s);
        return sv;
    }

    // ================================================================ yer imleri

    void yerImleriAc() {
        a.guvenli("yerImleriAc", this::yerImleriAcIc);
    }

    private void yerImleriAcIc() {
        final LinearLayout s = a.sutun();
        final List<int[]> imler = new ArrayList<>();
        for (String k : Kuran.yerImleri(a)) {
            try {
                String[] p = k.split(":");
                imler.add(new int[]{Integer.parseInt(p[0]), Integer.parseInt(p[1])});
            } catch (Throwable ignored) {
            }
        }
        Collections.sort(imler, (x, y) -> x[0] != y[0] ? x[0] - y[0] : x[1] - y[1]);
        if (imler.isEmpty()) {
            LinearLayout k = a.cam();
            k.addView(a.metin("Henüz yer imi yok", 17, BEYAZ, true));
            k.addView(a.metin("Bir ayete dokunup \"Yer imi ekle\"yi seçin.", 14, SOLUK, false));
            s.addView(k);
        }
        for (final int[] im : imler) {
            final Kuran.Sure su = Kuran.sure(a, im[0]);
            if (su == null) continue;
            LinearLayout k = a.cam();
            k.addView(a.metin("★ " + su.ad + " · " + im[1] + ". ayet", 16, ALTIN, true));
            final TextView meal = a.metin("", 14, SOLUK, false);
            meal.setMaxLines(3);
            meal.setEllipsize(android.text.TextUtils.TruncateAt.END);
            k.addView(meal);
            k.setClickable(true);
            a.basmaEfekti(k);
            k.setOnClickListener(v -> sureAc(su.no, im[1]));
            k.setOnLongClickListener(v -> {
                Kuran.yerImiDegistir(a, su.no, im[1]);
                v.animate().alpha(0f).setDuration(250).withEndAction(() -> s.removeView(v)).start();
                Toast.makeText(a, "Yer imi kaldırıldı", Toast.LENGTH_SHORT).show();
                return true;
            });
            s.addView(k);
            new Thread(() -> {
                try {
                    List<Kuran.Ayet> l = Kuran.ayetler(a, su.no);
                    // Bozuk kayıtta (ayet 0 ya da sure dışı) arka plan iş parçacığı uygulamayı çökertmesin
                    if (im[1] >= 1 && im[1] - 1 < l.size()) {
                        final String m = l.get(im[1] - 1).meal;
                        a.runOnUiThread(() -> meal.setText(m));
                    }
                } catch (Throwable t) {
                    Hata.kaydet(a, "Yer imi meali", t);
                }
            }, "secde-yerimi").start();
        }
        if (!imler.isEmpty()) s.addView(a.metin("Kaldırmak için uzun basın.", 12, SILIK, false));
        a.altSayfa("Yer imleri", sargi(s), "kuran_bg");
    }

    // ================================================================ Elif-Ba

    private static final class Harf {
        final String id, harf, ad, ses;
        final boolean kalin;

        Harf(String id, String harf, String ad, String ses, boolean kalin) {
            this.id = id;
            this.harf = harf;
            this.ad = ad;
            this.ses = ses;
            this.kalin = kalin;
        }
    }

    /** Harekeli okunuşta ünsüzün Türkçe karşılığı ve kalın (a/ı/u) okunup okunmadığı. */
    private static final String[][] SESLER = {
            {"alif", "", "0"}, {"ba", "b", "0"}, {"ta", "t", "0"}, {"tha", "s", "0"}, {"jim", "c", "0"},
            {"ha", "h", "1"}, {"kha", "h", "1"}, {"dal", "d", "0"}, {"dhal", "z", "0"}, {"ra", "r", "1"},
            {"zay", "z", "0"}, {"sin", "s", "0"}, {"shin", "ş", "0"}, {"sad", "s", "1"}, {"dad", "d", "1"},
            {"tta", "t", "1"}, {"zza", "z", "1"}, {"ayn", "'", "1"}, {"ghayn", "ğ", "1"}, {"fa", "f", "0"},
            {"qaf", "k", "1"}, {"kaf", "k", "0"}, {"lam", "l", "0"}, {"mim", "m", "0"}, {"nun", "n", "0"},
            {"waw", "v", "0"}, {"he", "h", "0"}, {"ya", "y", "0"},
    };

    private List<Harf> harfler() {
        List<Harf> l = new ArrayList<>();
        try {
            JSONArray j = new JSONArray(Varlik.flutterMetin(a, "assets/elifba/sources.json"));
            for (int i = 0; i < j.length(); i++) {
                JSONObject o = j.getJSONObject(i);
                String id = o.getString("id");
                String ses = "";
                boolean kalin = false;
                for (String[] s : SESLER) if (s[0].equals(id)) { ses = s[1]; kalin = "1".equals(s[2]); }
                l.add(new Harf(id, o.optString("letter"), o.optString("name"), ses, kalin));
            }
        } catch (Throwable ignored) {
        }
        return l;
    }

    private void harfCal(Harf h) {
        try {
            if (harfSesi != null) harfSesi.release();
            harfSesi = new MediaPlayer();
            AssetFileDescriptor fd = Varlik.flutterSes(a, "assets/elifba/" + h.id + ".mp3");
            if (fd != null) {
                harfSesi.setDataSource(fd.getFileDescriptor(), fd.getStartOffset(), fd.getLength());
                fd.close();
            } else {
                String d = System.getProperty("secde.flutter.dizin");
                if (d == null) return;
                harfSesi.setDataSource(new File(d, "assets/elifba/" + h.id + ".mp3").getAbsolutePath());
            }
            harfSesi.setOnPreparedListener(MediaPlayer::start);
            harfSesi.prepareAsync();
        } catch (Throwable ignored) {
        }
    }

    void elifBaAc() {
        a.guvenli("elifBaAc", this::elifBaAcIc);
    }

    private void elifBaAcIc() {
        final List<Harf> harfler = harfler();
        final LinearLayout s = a.sutun();
        s.addView(a.metin("Arap harflerini sesleriyle öğrenin, harekelerle okumayı deneyin, sonra kendinizi sınayın.", 14, SOLUK, false));
        a.bosluk(s, 8);

        // Harekeler kartı (seçili harf)
        final LinearLayout hareke = a.cam();
        final Harf[] secili = {harfler.isEmpty() ? null : harfler.get(1 < harfler.size() ? 1 : 0)};
        final Runnable harekeCiz = () -> {
            hareke.removeAllViews();
            Harf h = secili[0];
            if (h == null) return;
            hareke.addView(a.metin("HAREKELER · " + h.ad.toUpperCase(Metinler.TR), 12, ALTIN, true));
            LinearLayout r = new LinearLayout(a);
            String[] isim = {"Üstün", "Esre", "Ötre", "Cezm"};
            String[] isaret = {"َ", "ِ", "ُ", "ْ"};
            String[] unlu = h.kalin ? new String[]{"a", "ı", "u", ""} : new String[]{"e", "i", "u", ""};
            for (int i = 0; i < 4; i++) {
                if (i == 3 && h.ses.isEmpty()) continue;
                LinearLayout hu = new LinearLayout(a);
                hu.setOrientation(LinearLayout.VERTICAL);
                hu.setGravity(Gravity.CENTER);
                String yazi = i == 3 ? "ا" + h.harf + isaret[3] : h.harf + isaret[i];
                TextView ar = a.ortala(a.metin(yazi, 38, BEYAZ, false));
                ar.setTypeface(Varlik.kuranYazisi(a));
                hu.addView(ar);
                String oku = i == 3 ? (h.kalin ? "a" : "e") + h.ses : (h.ses + unlu[i]);
                hu.addView(a.ortala(a.metin(oku.isEmpty() ? "-" : oku, 18, ALTIN, true)));
                hu.addView(a.ortala(a.metin(isim[i], 11, SOLUK, false)));
                r.addView(hu, new LinearLayout.LayoutParams(0, -2, 1f));
            }
            hareke.addView(r);
            hareke.addView(a.metin(h.kalin ? "Kalın harf: a, ı, u ile okunur." : "İnce harf: e, i, u ile okunur.", 12, SILIK, false));
        };

        s.addView(a.altBaslik("Harfler · dokunun, dinleyin"));
        LinearLayout izgara = a.cam();
        izgara.setPadding(a.dp(6), a.dp(8), a.dp(6), a.dp(8));
        LinearLayout satir = null;
        for (int i = 0; i < harfler.size(); i++) {
            if (i % 4 == 0) {
                satir = new LinearLayout(a);
                izgara.addView(satir);
            }
            final Harf h = harfler.get(i);
            LinearLayout kart = new LinearLayout(a);
            kart.setOrientation(LinearLayout.VERTICAL);
            kart.setGravity(Gravity.CENTER);
            kart.setPadding(0, a.dp(8), 0, a.dp(8));
            GradientDrawable g = new GradientDrawable();
            g.setCornerRadius(a.dp(16));
            boolean acik = TemaMotoru.aktif(a).acik;
            g.setColor(acik ? 0x161E6B55 : 0x26FFFFFF);
            g.setStroke(1, acik ? 0x331E6B55 : 0x33FFFFFF);
            kart.setBackground(g);
            TextView ar = a.ortala(a.metin(h.harf, 34, ALTIN, false));
            ar.setTypeface(Varlik.kuranYazisi(a));
            kart.addView(ar);
            kart.addView(a.ortala(a.metin(h.ad, 13, BEYAZ, true)));
            kart.setContentDescription("Harf " + h.ad);
            kart.setClickable(true);
            kart.setOnClickListener(v -> {
                v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
                harfCal(h);
                v.animate().scaleX(1.15f).scaleY(1.15f).setDuration(120).withEndAction(() ->
                        v.animate().scaleX(1f).scaleY(1f).setDuration(260).setInterpolator(new OvershootInterpolator(3f)).start()).start();
                secili[0] = h;
                harekeCiz.run();
            });
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, -2, 1f);
            lp.setMargins(a.dp(4), a.dp(4), a.dp(4), a.dp(4));
            satir.addView(kart, lp);
        }
        if (satir != null) while (satir.getChildCount() < 4) satir.addView(new View(a), new LinearLayout.LayoutParams(0, 1, 1f));
        s.addView(izgara);

        harekeCiz.run();
        s.addView(hareke);

        s.addView(a.altBaslik("Harf testi"));
        s.addView(harfTesti(harfler));
        a.altSayfa("Elif-Ba", sargi(s), "elifba_bg");
    }

    /** Sesi dinletir, dört harften doğrusunu seçtirir; puanı saklar. */
    private View harfTesti(final List<Harf> harfler) {
        final LinearLayout k = a.cam();
        final android.content.SharedPreferences sp = a.getSharedPreferences("secde_kuran", Context.MODE_PRIVATE);
        final TextView puan = a.metin("", 14, SOLUK, false);
        final TextView soru = a.metin("Sesi dinleyin, doğru harfi seçin.", 16, BEYAZ, true);
        final TextView geri = a.metin("", 15, BEYAZ, true);
        final LinearLayout secenek = new LinearLayout(a);
        final Harf[] hedef = new Harf[1];
        k.addView(puan);
        k.addView(soru);
        TextView dinle = a.dugme("🔊  Sesi dinle", true, v -> { if (hedef[0] != null) harfCal(hedef[0]); });
        k.addView(dinle);
        k.addView(secenek);
        k.addView(geri);
        final Runnable[] yeni = new Runnable[1];
        yeni[0] = () -> {
            int d = sp.getInt("elifba_dogru", 0), t = sp.getInt("elifba_soru", 0);
            puan.setText("Doğru " + d + " / " + t);
            geri.setText("");
            secenek.removeAllViews();
            if (harfler.size() < 4) return;
            List<Harf> karisik = new ArrayList<>(harfler);
            Collections.shuffle(karisik, rnd);
            List<Harf> dort = new ArrayList<>(karisik.subList(0, 4));
            hedef[0] = dort.get(rnd.nextInt(4));
            for (final Harf h : dort) {
                final TextView b = a.metin(h.harf, 36, BEYAZ, false);
                b.setTypeface(Varlik.kuranYazisi(a));
                b.setGravity(Gravity.CENTER);
                b.setShadowLayer(0, 0, 0, 0);
                final GradientDrawable g = new GradientDrawable();
                g.setCornerRadius(a.dp(16));
                boolean acik = TemaMotoru.aktif(a).acik;
                g.setColor(acik ? 0x161E6B55 : 0x26FFFFFF);
                g.setStroke(1, acik ? 0x441E6B55 : 0x4DFFFFFF);
                b.setBackground(g);
                b.setContentDescription("Seçenek " + h.ad);
                b.setOnClickListener(v -> {
                    boolean dogru = h == hedef[0];
                    sp.edit().putInt("elifba_soru", sp.getInt("elifba_soru", 0) + 1)
                            .putInt("elifba_dogru", sp.getInt("elifba_dogru", 0) + (dogru ? 1 : 0)).apply();
                    g.setColor(dogru ? 0x667FD1A8 : 0x66FF8A80);
                    b.setBackground(g);
                    if (dogru) {
                        v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
                        geri.setText("✓ Doğru: " + h.ad);
                        geri.setTextColor(IYI);
                        v.animate().scaleX(1.12f).scaleY(1.12f).setDuration(150).withEndAction(() ->
                                v.animate().scaleX(1f).scaleY(1f).setDuration(200).start()).start();
                        a.getWindow().getDecorView().postDelayed(yeni[0], 900);
                    } else {
                        v.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS);
                        geri.setText("✗ Bu " + h.ad + ". Doğrusu: " + hedef[0].ad);
                        geri.setTextColor(KOTU);
                        v.animate().translationX(a.dp(8)).setDuration(60).withEndAction(() ->
                                v.animate().translationX(-a.dp(8)).setDuration(60).withEndAction(() ->
                                        v.animate().translationX(0).setDuration(60).start()).start()).start();
                        a.getWindow().getDecorView().postDelayed(yeni[0], 1600);
                    }
                    puan.setText("Doğru " + sp.getInt("elifba_dogru", 0) + " / " + sp.getInt("elifba_soru", 0));
                });
                LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, a.dp(72), 1f);
                lp.setMargins(a.dp(4), a.dp(10), a.dp(4), a.dp(4));
                secenek.addView(b, lp);
            }
        };
        yeni[0].run();
        return k;
    }

    // ================================================================ Dualar ve Esmâ

    void dualarAc() {
        a.guvenli("dualarAc", this::dualarAcIc);
    }

    private void dualarAcIc() {
        LinearLayout s = a.sutun();
        try {
            JSONArray j = new JSONArray(Varlik.flutterMetin(a, "assets/data/Duas.json"));
            for (int i = 0; i < j.length(); i++) {
                final JSONObject o = j.getJSONObject(i);
                LinearLayout k = a.cam();
                k.addView(a.metin(o.optString("title"), 17, ALTIN, true));
                if (!o.optString("arabic").isEmpty()) {
                    TextView ar = a.metin(o.optString("arabic"), 22, BEYAZ, false);
                    ar.setTypeface(Varlik.kuranYazisi(a));
                    ar.setGravity(Gravity.RIGHT);
                    ar.setLineSpacing(0, 1.4f);
                    k.addView(ar);
                }
                k.addView(a.metin(o.optString("reading"), 15, BEYAZ, false));
                k.addView(a.metin(o.optString("meaning"), 14, SOLUK, false));
                LinearLayout altSatir = new LinearLayout(a);
                altSatir.setGravity(Gravity.CENTER_VERTICAL);
                altSatir.addView(a.metin(o.optString("source"), 12, SILIK, false), new LinearLayout.LayoutParams(0, -2, 1f));
                TextView paylas = a.metin("Kart Paylaş ›", 13, ALTIN, true);
                paylas.setPadding(a.dp(8), a.dp(4), 0, a.dp(2));
                paylas.setOnClickListener(v -> PaylasimKarti.ozelMetinleAc(a, VakitTakvimi.oku(a),
                        PaylasimKarti.SABLON_HADIS_DUA, o.optString("arabic"), o.optString("meaning"),
                        o.optString("title") + (o.optString("source").isEmpty() ? "" : " · " + o.optString("source"))));
                altSatir.addView(paylas);
                k.addView(altSatir);
                k.setOnLongClickListener(v -> {
                    ClipboardManager cm = (ClipboardManager) a.getSystemService(Context.CLIPBOARD_SERVICE);
                    if (cm != null) cm.setPrimaryClip(ClipData.newPlainText("Dua",
                            o.optString("title") + "\n" + o.optString("reading") + "\n" + o.optString("meaning")));
                    Toast.makeText(a, "Dua kopyalandı", Toast.LENGTH_SHORT).show();
                    return true;
                });
                s.addView(k);
            }
            s.addView(a.metin("Kopyalamak için uzun basın.", 12, SILIK, false));
        } catch (Throwable t) {
            s.addView(a.metin("Dualar okunamadı.", 15, KOTU, false));
        }
        a.altSayfa("Dualar", sargi(s), "k_dua");
    }

    void esmaAc() {
        a.guvenli("esmaAc", this::esmaAcIc);
    }

    private void esmaAcIc() {
        LinearLayout s = a.sutun();
        final EditText ara = arama("İsim ya da anlam ara");
        s.addView(ara);
        final List<View> kartlar = new ArrayList<>();
        final List<String> anahtar = new ArrayList<>();
        try {
            JSONArray j = new JSONArray(Varlik.flutterMetin(a, "assets/data/EsmaulHusna.json"));
            LinearLayout k = a.cam();
            k.setPadding(a.dp(8), a.dp(6), a.dp(8), a.dp(6));
            for (int i = 0; i < j.length(); i++) {
                JSONObject o = j.getJSONObject(i);
                LinearLayout r = new LinearLayout(a);
                r.setGravity(Gravity.CENTER_VERTICAL);
                r.setPadding(a.dp(4), a.dp(8), a.dp(4), a.dp(8));
                r.addView(numara(i, 12), new LinearLayout.LayoutParams(a.dp(34), a.dp(34)));
                LinearLayout y = new LinearLayout(a);
                y.setOrientation(LinearLayout.VERTICAL);
                y.setPadding(a.dp(12), 0, 0, 0);
                y.addView(a.metin(o.optString("name"), 16, ALTIN, true));
                y.addView(a.metin(o.optString("meaning"), 14, SOLUK, false));
                r.addView(y, new LinearLayout.LayoutParams(0, -2, 1f));
                kartlar.add(r);
                anahtar.add(Kuran.sade(o.optString("name") + " " + o.optString("meaning")));
                k.addView(r);
            }
            s.addView(k);
        } catch (Throwable t) {
            s.addView(a.metin("Esmâü'l-Hüsnâ okunamadı.", 15, KOTU, false));
        }
        ara.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence x, int b, int c, int d) {}
            @Override public void onTextChanged(CharSequence x, int b, int c, int d) {}
            @Override public void afterTextChanged(Editable e) {
                String q = Kuran.sade(e.toString());
                for (int i = 0; i < kartlar.size(); i++)
                    kartlar.get(i).setVisibility(q.isEmpty() || anahtar.get(i).contains(q) ? View.VISIBLE : View.GONE);
            }
        });
        a.altSayfa("Esmâü'l-Hüsnâ", sargi(s), "kandil");
    }
}
