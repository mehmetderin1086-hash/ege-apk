package com.mehmetderin.secde_vakti.saglik;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONArray;
import org.json.JSONObject;

import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Date;
import java.util.List;
import java.util.Locale;

/** Zikirmatik verisi: zikir listesi, özel zikirler, sayılar, hedefler, 7 günlük grafik ve toplam sayım (kalıcı). */
public final class Zikir {

    public static final class Tanim {
        public final String ad, arapca, anlam;
        public final int hedef;
        public final boolean ozel;

        Tanim(String ad, String arapca, String anlam, int hedef) {
            this(ad, arapca, anlam, hedef, false);
        }

        Tanim(String ad, String arapca, String anlam, int hedef, boolean ozel) {
            this.ad = ad;
            this.arapca = arapca;
            this.anlam = anlam;
            this.hedef = hedef;
            this.ozel = ozel;
        }
    }

    public static final Tanim[] LISTE = {
            new Tanim("Sübhânallah", "سُبْحَانَ اللّٰهِ", "Allah'ı her türlü eksiklikten tenzih ederim", 33),
            new Tanim("Elhamdülillah", "اَلْحَمْدُ لِلّٰهِ", "Hamd Allah'a mahsustur", 33),
            new Tanim("Allâhu ekber", "اَللّٰهُ أَكْبَرُ", "Allah en büyüktür", 33),
            new Tanim("Lâ ilâhe illallah", "لَا إِلٰهَ إِلَّا اللّٰهُ", "Allah'tan başka ilâh yoktur", 100),
            new Tanim("Estağfirullah", "أَسْتَغْفِرُ اللّٰهَ", "Allah'tan bağışlanma dilerim", 100),
            new Tanim("Salavât-ı şerîfe", "اَللّٰهُمَّ صَلِّ عَلٰى مُحَمَّدٍ", "Allah'ım, Hz. Muhammed'e salât eyle", 100),
            new Tanim("Lâ havle ve lâ kuvvete", "لَا حَوْلَ وَلَا قُوَّةَ إِلَّا بِاللّٰهِ", "Güç ve kuvvet ancak Allah'tandır", 100),
            new Tanim("Sübhânallâhi ve bihamdihî", "سُبْحَانَ اللّٰهِ وَبِحَمْدِهِ", "Allah'ı hamd ile tesbih ederim", 100),
            new Tanim("Hasbünallâhu ve ni'me'l-vekîl", "حَسْبُنَا اللّٰهُ وَنِعْمَ الْوَكِيلُ", "Allah bize yeter, O ne güzel vekildir", 100),
            new Tanim("Yâ Hayyu Yâ Kayyûm", "يَا حَيُّ يَا قَيُّومُ", "Ey diri ve her şeyi ayakta tutan Allah'ım", 99),
    };

    public static final int[] HEDEFLER = {33, 99, 100, 313, 500, 1000};

    private final SharedPreferences sp;

    public Zikir(Context c) {
        sp = c.getSharedPreferences("secde_zikir", Context.MODE_PRIVATE);
    }

    public List<Tanim> tumTanimlar() {
        List<Tanim> t = new ArrayList<>();
        for (Tanim x : LISTE) t.add(x);
        for (Tanim x : ozelTanimlar()) t.add(x);
        return t;
    }

    public List<Tanim> ozelTanimlar() {
        List<Tanim> l = new ArrayList<>();
        try {
            String j = sp.getString("ozel_zikirler", null);
            if (j == null || j.isEmpty()) return l;
            JSONArray a = new JSONArray(j);
            for (int i = 0; i < a.length(); i++) {
                JSONObject o = a.optJSONObject(i);
                if (o == null) continue;
                String ad = o.optString("ad", "").trim();
                if (ad.isEmpty()) continue;
                l.add(new Tanim(ad, o.optString("arapca", ""), o.optString("anlam", "Özel zikir"),
                        Math.max(1, o.optInt("hedef", 100)), true));
            }
        } catch (Throwable ignored) {
        }
        return l;
    }

    public int ozelEkle(String ad, String arapca, String anlam, int hedef) {
        if (ad == null || ad.trim().isEmpty()) return secili();
        try {
            String j = sp.getString("ozel_zikirler", "[]");
            JSONArray a = new JSONArray(j);
            JSONObject o = new JSONObject();
            o.put("ad", ad.trim());
            o.put("arapca", arapca == null ? "" : arapca.trim());
            o.put("anlam", anlam == null || anlam.trim().isEmpty() ? "Özel zikir" : anlam.trim());
            o.put("hedef", Math.max(1, hedef));
            a.put(o);
            int yeniIndex = LISTE.length + a.length() - 1;
            sp.edit().putString("ozel_zikirler", a.toString()).putInt("secili", yeniIndex).apply();
            return yeniIndex;
        } catch (Throwable ignored) {
            return secili();
        }
    }

    public void ozelSil(int genelIndex) {
        int ozelIdx = genelIndex - LISTE.length;
        if (ozelIdx < 0) return;
        try {
            JSONArray a = new JSONArray(sp.getString("ozel_zikirler", "[]"));
            JSONArray yeni = new JSONArray();
            for (int i = 0; i < a.length(); i++) if (i != ozelIdx) yeni.put(a.get(i));
            sp.edit().putString("ozel_zikirler", yeni.toString()).putInt("secili", 0).apply();
        } catch (Throwable ignored) {
        }
    }

    public Tanim tanim(int i) {
        List<Tanim> tum = tumTanimlar();
        if (tum.isEmpty()) return LISTE[0];
        int idx = Math.max(0, Math.min(tum.size() - 1, i));
        return tum.get(idx);
    }

    public int secili() {
        int ust = Math.max(1, tumTanimlar().size()) - 1;
        return Math.max(0, Math.min(ust, sp.getInt("secili", 0)));
    }

    public void sec(int i) {
        int ust = Math.max(1, tumTanimlar().size()) - 1;
        sp.edit().putInt("secili", Math.max(0, Math.min(ust, i))).apply();
    }

    public int sayi(int i) {
        return sp.getInt("sayi_" + i, 0);
    }

    public int hedef(int i) {
        return sp.getInt("hedef_" + i, tanim(i).hedef);
    }

    public void hedef(int i, int h) {
        sp.edit().putInt("hedef_" + i, Math.max(1, h)).apply();
    }

    /** Namaz tesbihatı: ilk üç zikirde hedef dolunca sıradakine geç. */
    public boolean tesbihat() {
        return sp.getBoolean("tesbihat", true);
    }

    public void tesbihat(boolean a) {
        sp.edit().putBoolean("tesbihat", a).apply();
    }

    /** Görünüm modu: true ise 3D Boncuklu Tesbih, false ise Dairesel Kadran (varsayılan false: mevcut test uyumu). */
    public boolean boncukModu() {
        return sp.getBoolean("boncuk_modu", false);
    }

    public void boncukModu(boolean acik) {
        sp.edit().putBoolean("boncuk_modu", acik).apply();
    }

    /** Boncuk malzemesi: 0 Kehribar, 1 Zümrüt, 2 Oltu, 3 İnci Sedef, 4 Firuze. */
    public int boncukMalzeme() {
        return Math.max(0, Math.min(4, sp.getInt("boncuk_malzeme", 0)));
    }

    public void boncukMalzeme(int m) {
        sp.edit().putInt("boncuk_malzeme", Math.max(0, Math.min(4, m))).apply();
    }

    /** Bir artırır; yeni sayıyı döndürür. Günlük, 7 günlük tarihçe ve toplam sayımı da artırır. */
    public int artir(int i) {
        int yeni = sayi(i) + 1;
        String bugun = bugun();
        int gunluk = bugun.equals(sp.getString("gun", "")) ? sp.getInt("gunluk", 0) : 0;
        String gunAnahtar = "gun_" + bugun;
        int gunTarihce = sp.getInt(gunAnahtar, gunluk);
        sp.edit()
                .putInt("sayi_" + i, yeni)
                .putString("gun", bugun)
                .putInt("gunluk", gunluk + 1)
                .putInt(gunAnahtar, gunTarihce + 1)
                .putLong("toplam", sp.getLong("toplam", 0) + 1)
                .apply();
        return yeni;
    }

    public void sifirla(int i) {
        sp.edit().putInt("sayi_" + i, 0).apply();
    }

    public int gunluk() {
        return bugun().equals(sp.getString("gun", "")) ? sp.getInt("gunluk", 0) : 0;
    }

    public long toplam() {
        return sp.getLong("toplam", 0);
    }

    /** Son 7 günün zikir sayıları (0: 6 gün önce … 6: bugün). */
    public int[] sonYediGun() {
        int[] d = new int[7];
        SimpleDateFormat f = new SimpleDateFormat("yyyy-MM-dd", Locale.ROOT);
        Calendar cal = Calendar.getInstance();
        cal.add(Calendar.DAY_OF_MONTH, -6);
        String bugun = bugun();
        for (int i = 0; i < 7; i++) {
            String k = f.format(cal.getTime());
            if (k.equals(bugun)) d[i] = Math.max(gunluk(), sp.getInt("gun_" + k, 0));
            else d[i] = sp.getInt("gun_" + k, 0);
            cal.add(Calendar.DAY_OF_MONTH, 1);
        }
        return d;
    }

    /** Son 7 günün kısa gün adları ("Pzt", "Sal", …). */
    public String[] sonYediGunEtiket() {
        String[] e = new String[7];
        SimpleDateFormat f = new SimpleDateFormat("EEE", Metinler.TR);
        Calendar cal = Calendar.getInstance();
        cal.add(Calendar.DAY_OF_MONTH, -6);
        for (int i = 0; i < 7; i++) {
            e[i] = i == 6 ? "Bugün" : f.format(cal.getTime());
            cal.add(Calendar.DAY_OF_MONTH, 1);
        }
        return e;
    }

    private static String bugun() {
        return new SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).format(new Date());
    }
}
