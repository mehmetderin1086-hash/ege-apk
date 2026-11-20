package com.mehmetderin.secde_vakti.saglik;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

/**
 * Kur'an verisi (uygulamanın içindeki dosyalardan, internetsiz):
 *  - kuran_bilmek_offline.json: 114 sure bilgisi, 20 sure için kelime kelime meal
 *  - quranenc.json: 6236 ayetin Arapçası ve Türkçe meali (Rowwad), dipnotlar
 *  - assets/secde/meal_ses.json: sure → okuyucu → sesli meal adresi (derlemede üretilir)
 * Tilavet adresleri: everyayah.com (uygulamanın kendi ayet zamanlamalarıyla aynı okuyucular).
 */
public final class Kuran {

    public static final class Sure {
        public final int no, ayetSayisi;
        public final String ad, arapca, yer;
        public final boolean besmele;

        Sure(int no, String ad, String arapca, String yer, int ayetSayisi, boolean besmele) {
            this.no = no;
            this.ad = ad;
            this.arapca = arapca;
            this.yer = yer;
            this.ayetSayisi = ayetSayisi;
            this.besmele = besmele;
        }
    }

    public static final class Ayet {
        public final int sure, no;
        public final String arapca, meal, dipnot;

        Ayet(int sure, int no, String arapca, String meal, String dipnot) {
            this.sure = sure;
            this.no = no;
            this.arapca = arapca;
            this.meal = meal;
            this.dipnot = dipnot;
        }
    }

    public static final class Kelime {
        public final String arapca, meal, okunus;

        Kelime(String arapca, String meal, String okunus) {
            this.arapca = arapca;
            this.meal = meal;
            this.okunus = okunus;
        }
    }

    /** Tilavet okuyucuları: everyayah klasörü, görünen ad. */
    public static final String[][] HAFIZLAR = {
            {"Alafasy_128kbps", "Mişârî Râşid el-Afâsî"},
            {"Husary_64kbps", "Mahmûd Halîl el-Husarî"},
            {"Minshawy_Murattal_128kbps", "Muhammed Sıddîk el-Minşâvî"},
    };

    private static List<Sure> sureler;
    private static List<List<Ayet>> ayetler;
    private static JSONObject kelimeVeri;
    private static JSONObject mealSes;

    private Kuran() {}

    public static synchronized List<Sure> sureler(Context c) {
        if (sureler != null) return sureler;
        List<Sure> l = new ArrayList<>();
        try {
            JSONObject o = new JSONObject(Varlik.flutterMetin(c, "assets/data/kuran_bilmek_offline.json"));
            JSONArray a = o.getJSONArray("chapters");
            for (int i = 0; i < a.length(); i++) {
                JSONObject s = a.getJSONObject(i);
                JSONObject tr = s.optJSONObject("translated_name");
                l.add(new Sure(s.getInt("id"), tr != null ? tr.optString("name", s.optString("name_simple")) : s.optString("name_simple"),
                        s.optString("name_arabic"), "madinah".equals(s.optString("revelation_place")) ? "Medenî" : "Mekkî",
                        s.optInt("verses_count"), s.optBoolean("bismillah_pre", true)));
            }
            kelimeVeri = o.optJSONObject("bundled_verses");
        } catch (Throwable ignored) {
        }
        // Okuma başarısızsa boş listeyi önbelleğe alma; sonraki çağrı yeniden denesin
        if (!l.isEmpty()) sureler = l;
        return l;
    }

    public static Sure sure(Context c, int no) {
        for (Sure s : sureler(c)) if (s.no == no) return s;
        return null;
    }

    public static synchronized List<Ayet> ayetler(Context c, int sure) {
        List<List<Ayet>> veri = ayetler;
        if (veri == null) {
            List<List<Ayet>> l = new ArrayList<>();
            for (int i = 0; i <= 114; i++) l.add(new ArrayList<>());
            int adet = 0;
            try {
                JSONArray a = new JSONObject(Varlik.flutterMetin(c, "assets/data/quranenc.json")).getJSONArray("verses");
                for (int i = 0; i < a.length(); i++) {
                    // Bozuk tek bir kayıt bütün Kur'an'ın yüklenmesini engellemesin
                    try {
                        JSONObject v = a.getJSONObject(i);
                        int s = Integer.parseInt(v.getString("sura").trim());
                        if (s < 1 || s > 114) continue;
                        l.get(s).add(new Ayet(s, Integer.parseInt(v.getString("aya").trim()), v.optString("arabic_text"),
                                v.optString("translation"), v.optString("footnotes")));
                        adet++;
                    } catch (Throwable ignored) {
                    }
                }
            } catch (Throwable ignored) {
            }
            // Okuma başarısızsa boş veriyi önbelleğe alma; sonraki çağrı yeniden denesin
            if (adet > 0) ayetler = l;
            veri = l;
        }
        return sure >= 1 && sure <= 114 ? veri.get(sure) : Collections.<Ayet>emptyList();
    }

    /** Kelime kelime meal (yalnız uygulamada bulunan 20 sure için); yoksa boş. */
    public static List<Kelime> kelimeler(Context c, int sure, int ayet) {
        sureler(c);
        List<Kelime> l = new ArrayList<>();
        try {
            if (kelimeVeri == null) return l;
            JSONArray a = kelimeVeri.optJSONArray(String.valueOf(sure));
            if (a == null) return l;
            for (int i = 0; i < a.length(); i++) {
                JSONObject v = a.getJSONObject(i);
                if (v.optInt("verse_number") != ayet) continue;
                JSONArray w = v.getJSONArray("words");
                for (int j = 0; j < w.length(); j++) {
                    JSONObject k = w.getJSONObject(j);
                    if (!"word".equals(k.optString("char_type_name"))) continue;
                    JSONObject m = k.optJSONObject("translation"), o = k.optJSONObject("transliteration");
                    l.add(new Kelime(k.optString("text_uthmani"), m == null ? "" : m.optString("text"), o == null ? "" : o.optString("text")));
                }
                break;
            }
        } catch (Throwable ignored) {
        }
        return l;
    }

    public static boolean kelimeVar(Context c, int sure) {
        sureler(c);
        return kelimeVeri != null && kelimeVeri.has(String.valueOf(sure));
    }

    // ------------------------------------------------------------ ses

    public static String ayetSesi(String hafiz, int sure, int ayet) {
        return String.format(Locale.ROOT, "https://everyayah.com/data/%s/%03d%03d.mp3", hafiz, sure, ayet);
    }

    private static synchronized JSONObject mealSes(Context c) {
        if (mealSes == null) {
            try {
                mealSes = new JSONObject(Varlik.secdeMetin(c, "meal_ses.json"));
            } catch (Throwable t) {
                mealSes = new JSONObject();
            }
        }
        return mealSes;
    }

    /** Sesli meal okuyucuları (çoktan aza). */
    public static List<String> mealOkuyuculari(Context c) {
        List<String> l = new ArrayList<>();
        JSONArray a = mealSes(c).optJSONArray("okuyucular");
        if (a != null) for (int i = 0; i < a.length(); i++) l.add(a.optString(i));
        return l;
    }

    /** Surenin sesli meali; okuyucu yoksa ilk bulunan. {okuyucu, adres} ya da null. */
    public static String[] mealSesi(Context c, int sure, String okuyucu) {
        JSONObject s = mealSes(c).optJSONObject("sure");
        JSONObject o = s == null ? null : s.optJSONObject(String.valueOf(sure));
        if (o == null || o.length() == 0) return null;
        if (okuyucu != null && o.has(okuyucu)) return new String[]{okuyucu, o.optString(okuyucu)};
        for (String ok : mealOkuyuculari(c)) if (o.has(ok)) return new String[]{ok, o.optString(ok)};
        String ilk = o.keys().next();
        return new String[]{ilk, o.optString(ilk)};
    }

    // ------------------------------------------------------------ okuma geçmişi ve yer imleri

    private static SharedPreferences sp(Context c) {
        return c.getSharedPreferences("secde_kuran", Context.MODE_PRIVATE);
    }

    public static void sonOkunan(Context c, int sure, int ayet) {
        sp(c).edit().putInt("son_sure", sure).putInt("son_ayet", ayet).apply();
    }

    /** {sure, ayet} ya da null. */
    public static int[] sonOkunan(Context c) {
        int s = sp(c).getInt("son_sure", 0);
        return s == 0 ? null : new int[]{s, sp(c).getInt("son_ayet", 1)};
    }

    public static Set<String> yerImleri(Context c) {
        return new HashSet<>(sp(c).getStringSet("yer_imleri", new HashSet<>()));
    }

    public static boolean yerImi(Context c, int sure, int ayet) {
        return yerImleri(c).contains(sure + ":" + ayet);
    }

    /** Yer imini ekler ya da kaldırır; yeni durumu döndürür. */
    public static boolean yerImiDegistir(Context c, int sure, int ayet) {
        Set<String> s = yerImleri(c);
        String k = sure + ":" + ayet;
        boolean ekli = !s.remove(k);
        if (ekli) s.add(k);
        sp(c).edit().putStringSet("yer_imleri", s).apply();
        return ekli;
    }

    public static String hafiz(Context c) {
        return sp(c).getString("hafiz", HAFIZLAR[0][0]);
    }

    public static void hafiz(Context c, String h) {
        sp(c).edit().putString("hafiz", h).apply();
    }

    public static String mealOkuyucu(Context c) {
        return sp(c).getString("meal_okuyucu", null);
    }

    public static void mealOkuyucu(Context c, String o) {
        sp(c).edit().putString("meal_okuyucu", o).apply();
    }

    /** Okuma yazı boyutu (sp). */
    public static int yaziBoyu(Context c) {
        return sp(c).getInt("yazi", 26);
    }

    public static void yaziBoyu(Context c, int b) {
        sp(c).edit().putInt("yazi", Math.max(18, Math.min(44, b))).apply();
    }

    /** 0: Arapça + meal, 1: yalnız Arapça, 2: yalnız meal. */
    public static int gorunum(Context c) {
        return sp(c).getInt("gorunum", 0);
    }

    public static void gorunum(Context c, int g) {
        sp(c).edit().putInt("gorunum", g).apply();
    }

    public static String hafizAdi(String klasor) {
        for (String[] h : HAFIZLAR) if (h[0].equals(klasor)) return h[1];
        return klasor;
    }

    /** "bakara", "2", "Al-i İmran" → arama için sadeleştirilmiş metin. */
    static String sade(String s) {
        if (s == null) return "";
        s = s.toLowerCase(Metinler.TR);
        StringBuilder b = new StringBuilder();
        for (char ch : java.text.Normalizer.normalize(s, java.text.Normalizer.Form.NFD).toCharArray()) {
            if (Character.getType(ch) == Character.NON_SPACING_MARK) continue;
            switch (ch) {
                case 'ı': ch = 'i'; break;
                case 'ş': ch = 's'; break;
                case 'ç': ch = 'c'; break;
                case 'ğ': ch = 'g'; break;
                case 'ö': ch = 'o'; break;
                case 'ü': ch = 'u'; break;
                default: break;
            }
            if (Character.isLetterOrDigit(ch)) b.append(ch);
        }
        return b.toString();
    }
}
