package com.mehmetderin.secde_vakti.saglik;

import android.content.Context;
import android.graphics.drawable.GradientDrawable;
import android.view.Gravity;
import android.view.HapticFeedbackConstants;
import android.view.View;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.Calendar;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

/**
 * Kerâhet Vakitleri ve Faziletli Nâfile Namaz Saatleri:
 *  - İşrâk, İstivâ (Zevâl) ve İsfirâr (Gurûb) kerâhet pencereleri
 *  - İşrâk, Duhâ (Kuşluk), Evvâbîn ve Teheccüd (Gecenin Son Üçte Biri) nâfile pencereleri
 *  - Vakitler sekmesi için canlı özet şerit ve Hanefî/Şâfiî fıkıh notlarıyla tam alt sayfa
 */
public final class Kerahet {

    private static final long DK = 60_000L;

    /** Bir kerâhet veya nâfile namaz zaman aralığı. */
    public static final class Pencere {
        public final String kod;
        public final String ad;
        public final String kisaAd;
        public final String aciklama;
        public final String detay;
        public final String rekat;
        public final long baslangic;
        public final long bitis;
        public final long ideal;
        public final boolean kerahet;
        public final boolean bitisDahil;

        Pencere(String kod, String ad, String kisaAd, String aciklama, String detay, String rekat,
                long baslangic, long bitis, long ideal, boolean kerahet, boolean bitisDahil) {
            this.kod = kod;
            this.ad = ad;
            this.kisaAd = kisaAd;
            this.aciklama = aciklama;
            this.detay = detay;
            this.rekat = rekat;
            this.baslangic = baslangic;
            this.bitis = bitis;
            this.ideal = ideal;
            this.kerahet = kerahet;
            this.bitisDahil = bitisDahil;
        }

        public boolean icindeMi(long anMs) {
            return bitisDahil
                    ? (anMs >= baslangic && anMs <= bitis)
                    : (anMs >= baslangic && anMs < bitis);
        }

        public long kalanDk(long anMs) {
            long fark = bitis - anMs;
            if (fark <= 0) return 0;
            return Math.max(1L, (fark + 59_999L) / DK);
        }

        public String saatAraligi() {
            return Metinler.saat(baslangic) + " – " + Metinler.saat(bitis);
        }
    }

    private Kerahet() {}

    public static Pencere aktifKerahet(Context c, VakitTakvimi.Takvim t) {
        return aktifKerahet(c, t, System.currentTimeMillis());
    }

    /**
     * Verilen an 3 kerâhet vaktinden birinin içindeyse ilgili Pencere'yi, değilse null döndürür:
     *  1) İşrâk Kerâheti : [sunrise, sunrise + 45 dk]
     *  2) İstivâ Kerâheti: [dhuhr - 45 dk, dhuhr)
     *  3) İsfirâr Kerâheti: [maghrib - 45 dk, maghrib)
     */
    public static Pencere aktifKerahet(Context c, VakitTakvimi.Takvim t, long simdiMs) {
        HesapMotoru.GunVakitleri gv = HesapMotoru.gun(c, t, simdiMs);
        for (Pencere p : kerahetPencereleri(gv)) {
            if (p.icindeMi(simdiMs)) return p;
        }
        return null;
    }

    /** Verilen anda aktif bir nâfile namaz vakti varsa döndürür (gece yarısı sonrası Teheccüd dâhil). */
    public static Pencere aktifNafile(Context c, VakitTakvimi.Takvim t, long simdiMs) {
        HesapMotoru.GunVakitleri bugun = HesapMotoru.gun(c, t, simdiMs);
        if (simdiMs < bugun.imsak) {
            HesapMotoru.GunVakitleri dun = HesapMotoru.gun(c, t, komsuGunMs(simdiMs, -1));
            Pencere seherTeheccud = teheccudPenceresi(dun.yatsi, bugun.imsak);
            if (seherTeheccud.icindeMi(simdiMs)) return seherTeheccud;
        }
        for (Pencere p : bugunNafileVeKerahet(c, t, simdiMs)) {
            if (!p.kerahet && p.icindeMi(simdiMs)) return p;
        }
        return null;
    }

    /**
     * Günün 3 kerâhet ve 4 müstehap nâfile penceresini başlangıç saatine göre sıralı döndürür.
     */
    public static List<Pencere> bugunNafileVeKerahet(Context c, VakitTakvimi.Takvim t, long simdiMs) {
        HesapMotoru.GunVakitleri gv = HesapMotoru.gun(c, t, simdiMs);
        HesapMotoru.GunVakitleri yarin = HesapMotoru.gun(c, t, komsuGunMs(simdiMs, 1));

        List<Pencere> liste = new ArrayList<>(7);
        liste.addAll(kerahetPencereleri(gv));

        // 1) İşrâk Namazı: sunrise + 45 dk .. sunrise + 90 dk
        long israkBas = gv.gunes + 45L * DK;
        long israkBit = Math.max(israkBas + 15L * DK, Math.min(gv.gunes + 90L * DK, gv.ogle - 45L * DK));
        liste.add(new Pencere(
                "israk",
                "İşrâk Namazı",
                "İşrâk",
                "Güneş bir mızrak boyu yükseldikten sonra kılınan sabah şükrü namazı",
                "Sabah namazını cemaatle kılıp güneş doğuncaya kadar zikir ve tefekkürle meşgul olan, "
                        + "ardından iki rekât işrâk namazı kılan kimseye tam bir hac ve umre sevabı verileceği "
                        + "hadîs-i şerîfte müjdelenmiştir (Tirmizî, Cum'a, 59).",
                "2 veya 4 Rekât",
                israkBas, israkBit, israkBas + 10L * DK, false, false
        ));

        // 2) Duhâ (Kuşluk) Namazı: sunrise + 50 dk .. dhuhr - 45 dk (ideal: sunrise + (dhuhr - sunrise)/3)
        long duhaBas = gv.gunes + 50L * DK;
        long duhaBit = Math.max(duhaBas + 15L * DK, gv.ogle - 45L * DK);
        long duhaIdeal = gv.gunes + Math.max(55L * DK, (gv.ogle - gv.gunes) / 3L);
        if (duhaIdeal > duhaBit) duhaIdeal = (duhaBas + duhaBit) / 2L;
        liste.add(new Pencere(
                "duha",
                "Duhâ (Kuşluk) Namazı",
                "Kuşluk",
                "Gündüzün bereket ve şükür namazı · En faziletli anı: " + Metinler.saat(duhaIdeal),
                "Peygamber Efendimiz (s.a.v.), insan bedenindeki 360 eklemin her biri için her gün sadaka "
                        + "gerektiğini ve kuşluk vaktinde kılınan iki rekât Duhâ namazının bütün bu şükrü "
                        + "karşıladığını bildirmiştir (Müslim, Müsâfirîn, 84). En faziletli vakti gündüzün "
                        + "yaklaşık üçte birinin geçtiği (" + Metinler.saat(duhaIdeal) + ") sıralardır.",
                "2, 4, 8 veya 12 Rekât",
                duhaBas, duhaBit, duhaIdeal, false, false
        ));

        // 3) Evvâbîn Namazı: maghrib + 15 dk .. isha - 10 dk
        long evvabinBas = gv.aksam + 15L * DK;
        long evvabinBit = gv.yatsi - 10L * DK;
        if (evvabinBit <= evvabinBas) {
            evvabinBas = gv.aksam + 8L * DK;
            evvabinBit = Math.max(evvabinBas + 10L * DK, gv.yatsi - 5L * DK);
        }
        liste.add(new Pencere(
                "evvabin",
                "Evvâbîn Namazı",
                "Evvâbîn",
                "Akşam namazından sonra Allah'a yöneliş ve tövbe namazı",
                "Akşam namazının farz ve sünnetinden sonra yatsı vaktine kadar 2, 4 veya 6 rekât olarak kılınır. "
                        + "Allah'a gönülden yönelenlerin (evvâbîn) akşam ile yatsı arasını namazla ihyâ etmesi "
                        + "müstehap görülmüştür (Tirmizî, Mevâkît, 204).",
                "2, 4 veya 6 Rekât",
                evvabinBas, evvabinBit, gv.aksam + 25L * DK, false, false
        ));

        // 4) Teheccüd (Gecenin Son Üçte Biri): isha + 2/3 * (nextDayFajr - isha) .. nextDayFajr - 15 dk
        liste.add(teheccudPenceresi(gv.yatsi, yarin.imsak));

        Collections.sort(liste, new Comparator<Pencere>() {
            @Override
            public int compare(Pencere o1, Pencere o2) {
                int c1 = Long.compare(o1.baslangic, o2.baslangic);
                if (c1 != 0) return c1;
                return Boolean.compare(!o1.kerahet, !o2.kerahet);
            }
        });
        return liste;
    }

    private static List<Pencere> kerahetPencereleri(HesapMotoru.GunVakitleri gv) {
        List<Pencere> k = new ArrayList<>(3);

        // 1) İşrâk Kerâheti: [sunrise, sunrise + 45 dk]
        k.add(new Pencere(
                "israk_kerahet",
                "İşrâk Kerâheti",
                "İşrâk",
                "Güneş doğduktan sonraki ~45 dakikalık yükseliş vakti",
                "Güneşin doğmaya başlamasından ufukta bir mızrak boyu (~5°) yükselmesine kadar geçen "
                        + "sürede farz, vâcip, nâfile veya kazâ hiçbir namaz kılınmaz. Bu vakitte tilâvet "
                        + "secdesi ve cenâze namazı da edâ edilmez.",
                "Namaz Kılınmaz",
                gv.gunes, gv.gunes + 45L * DK, 0L, true, true
        ));

        // 2) İstivâ (Zevâl) Kerâheti: [dhuhr - 45 dk, dhuhr)
        k.add(new Pencere(
                "istiva_kerahet",
                "İstivâ (Zevâl) Kerâheti",
                "İstivâ",
                "Güneş tepe noktasındayken öğleden önceki ~45 dakikalık vakit",
                "Güneşin tam tepe noktasında (zevâl/istivâ) bulunduğu ve öğle vaktine kadar olan ihtiyat "
                        + "süresinde Hanefî mezhebine göre farz, kazâ ve nâfile namaz kılınmaz.\n"
                        + "• Cuma ve Şâfiî Fıkhı Notu: Şâfiî mezhebinde istivâ kerâheti güneşin tepe noktasından "
                        + "meyletmesine kadarki birkaç dakikayla sınırlıdır; ayrıca Cuma günü zevâl vaktinde "
                        + "tahiyyetü'l-mescid ve nâfile namaz kılmak Şâfiî fıkhında mekruh değildir.",
                "Namaz Kılınmaz",
                gv.ogle - 45L * DK, gv.ogle, 0L, true, false
        ));

        // 3) İsfirâr (Gurûb) Kerâheti: [maghrib - 45 dk, maghrib)
        k.add(new Pencere(
                "isfirar_kerahet",
                "İsfirâr (Gurûb) Kerâheti",
                "İsfirâr",
                "Güneş batmadan önceki ~45 dakikalık sararma vakti",
                "Güneşin göz kamaştırmaz hâle gelip sararmasından batışına kadar geçen sürede hiçbir nâfile "
                        + "veya kazâ namazı kılınmaz.\n"
                        + "• İstisnâ: Yalnızca o günün henüz kılınmamış ikindi farzı, vakit çıkmadan yetiştirmek "
                        + "için bu sürede edâ edilebilir (ancak ikindiyi mazeretsiz bu vakte geciktirmek mekruhtur).",
                "Yalnız İkindi Farzı",
                gv.aksam - 45L * DK, gv.aksam, 0L, true, false
        ));

        return k;
    }

    private static Pencere teheccudPenceresi(long yatsiMs, long ertesiImsakMs) {
        long geceSuresi = ertesiImsakMs - yatsiMs;
        if (geceSuresi < 90L * DK) geceSuresi = 6L * 3600_000L;
        long bas = yatsiMs + (geceSuresi * 2L) / 3L;
        long bit = ertesiImsakMs - 15L * DK;
        if (bit <= bas) bit = ertesiImsakMs - 5L * DK;
        return new Pencere(
                "teheccud",
                "Teheccüd (Gecenin Son Üçte Biri)",
                "Teheccüd",
                "Seher vakti icâbet saati · Gecenin son üçte birlik dilimi",
                "Farz namazlardan sonra en faziletli namaz gece namazıdır (Müslim, Sıyâm, 202). "
                        + "Hadîs-i şerîfte Yüce Allah'ın her gecenin son üçte birinde rahmetiyle tecellî ederek "
                        + "'Bana duâ eden yok mu, icâbet edeyim; benden isteyen yok mu, vereyim; bağışlanma "
                        + "dileyen yok mu, bağışlayayım!' buyurduğu haber verilmiştir (Buhârî, Teheccüd, 14).",
                "2 ilâ 8 Rekât",
                bas, bit, (bas + bit) / 2L, false, false
        );
    }

    private static long komsuGunMs(long bazMs, int gunFarki) {
        Calendar cal = Calendar.getInstance();
        cal.setTimeInMillis(bazMs);
        cal.set(Calendar.HOUR_OF_DAY, 12);
        cal.set(Calendar.MINUTE, 0);
        cal.set(Calendar.SECOND, 0);
        cal.set(Calendar.MILLISECOND, 0);
        cal.add(Calendar.DAY_OF_MONTH, gunFarki);
        return cal.getTimeInMillis();
    }

    /**
     * Vakitler sekmesi için kompakt, tıklanabilir durum şeridi:
     *  - Kerâhet vaktindeyse kehribar uyarı hapı: "⚠ Kerâhet Vakti · İstivâ · bitmesine 18 dk ›"
     *  - Değilse dingin nâfile özeti: "✦ İşrâk 08:23 · Kuşluk 09:45 · Teheccüd 03:18 ›"
     */
    public static View ozetSerit(final DurumAktivitesi a, final VakitTakvimi.Takvim t) {
        TemaMotoru.Durum tm = TemaMotoru.aktif(a);
        long simdi = System.currentTimeMillis();
        Pencere kerahet = aktifKerahet(a, t, simdi);
        List<Pencere> bugun = bugunNafileVeKerahet(a, t, simdi);

        LinearLayout satir = new LinearLayout(a);
        satir.setOrientation(LinearLayout.HORIZONTAL);
        satir.setGravity(Gravity.CENTER_VERTICAL);
        satir.setPadding(a.dp(14), a.dp(11), a.dp(14), a.dp(11));

        float rPx = a.dp(16);
        if (kerahet != null) {
            GradientDrawable bg = new GradientDrawable();
            bg.setCornerRadius(rPx);
            bg.setColor((tm.uyari & 0x00FFFFFF) | (tm.acik ? 0x22000000 : 0x2E000000));
            bg.setStroke(Math.max(1, a.dp(1)), (tm.uyari & 0x00FFFFFF) | 0x99000000);
            satir.setBackground(bg);

            String yazi = "⚠ Kerâhet Vakti · " + kerahet.kisaAd + " · bitmesine " + kerahet.kalanDk(simdi) + " dk";
            TextView tv = metin(a, tm, yazi, 13, tm.uyari, true);
            satir.addView(tv, new LinearLayout.LayoutParams(0, -2, 1f));
            TextView ok = metin(a, tm, "›", 17, tm.uyari, true);
            ok.setPadding(a.dp(8), 0, 0, 0);
            satir.addView(ok);
        } else {
            satir.setBackground(tm.kartArkaPlani(a));
            Pencere israk = bul(bugun, "israk");
            Pencere duha = bul(bugun, "duha");
            Pencere teh = bul(bugun, "teheccud");
            if (simdi < HesapMotoru.gun(a, t, simdi).imsak) {
                HesapMotoru.GunVakitleri dun = HesapMotoru.gun(a, t, komsuGunMs(simdi, -1));
                HesapMotoru.GunVakitleri bgv = HesapMotoru.gun(a, t, simdi);
                teh = teheccudPenceresi(dun.yatsi, bgv.imsak);
            }

            String israkS = israk != null ? Metinler.saat(israk.baslangic) : "--:--";
            String kuslukS = duha != null ? Metinler.saat(duha.ideal > 0 ? duha.ideal : duha.baslangic) : "--:--";
            String tehS = teh != null ? Metinler.saat(teh.baslangic) : "--:--";

            Pencere canliNafile = aktifNafile(a, t, simdi);
            String metinStr = "✦ İşrâk " + israkS + " · Kuşluk " + kuslukS + " · Teheccüd " + tehS;
            int renk = tm.soluk;
            if (canliNafile != null) {
                metinStr = "✦ Şimdi " + canliNafile.kisaAd + " Vakti (" + canliNafile.kalanDk(simdi) + " dk) · "
                        + "İşrâk " + israkS + " · Teheccüd " + tehS;
                renk = tm.iyi;
            }
            TextView tv = metin(a, tm, metinStr, 13, renk, canliNafile != null);
            satir.addView(tv, new LinearLayout.LayoutParams(0, -2, 1f));
            TextView ok = metin(a, tm, "›", 17, tm.vurgu, true);
            ok.setPadding(a.dp(8), 0, 0, 0);
            satir.addView(ok);
        }

        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(0, 0, 0, a.dp(12));
        satir.setLayoutParams(lp);
        satir.setClickable(true);
        a.basmaEfekti(satir);
        satir.setOnClickListener(v -> {
            v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            a.guvenli("kerahet", () -> sayfaAc(a, t));
        });
        return satir;
    }

    /** Kerâhet ve Nâfile Vakitler tam alt sayfasını açar. */
    public static void sayfaAc(final DurumAktivitesi a, final VakitTakvimi.Takvim t) {
        TemaMotoru.Durum tm = TemaMotoru.aktif(a);
        long simdi = System.currentTimeMillis();
        HesapMotoru.GunVakitleri gv = HesapMotoru.gun(a, t, simdi);
        Pencere kerahet = aktifKerahet(a, t, simdi);
        Pencere nafile = aktifNafile(a, t, simdi);
        List<Pencere> tum = bugunNafileVeKerahet(a, t, simdi);

        LinearLayout s = a.sutun();

        // 1) Canlı Durum Kartı
        LinearLayout canliKart = kart(a, tm);
        if (kerahet != null) {
            GradientDrawable uBg = new GradientDrawable();
            uBg.setCornerRadius(a.dp(20));
            uBg.setColor((tm.uyari & 0x00FFFFFF) | (tm.acik ? 0x24000000 : 0x33000000));
            uBg.setStroke(Math.max(1, a.dp(1)), (tm.uyari & 0x00FFFFFF) | 0xAA000000);
            canliKart.setBackground(uBg);

            canliKart.addView(metin(a, tm, "⚠ ŞU AN KERÂHET VAKTİNDESİNİZ", 12, tm.uyari, true));
            canliKart.addView(metin(a, tm, kerahet.ad + " (" + kerahet.saatAraligi() + ")", 19, tm.metin, true));
            canliKart.addView(metin(a, tm, "Kerâhet vaktinin çıkmasına " + kerahet.kalanDk(simdi) + " dakika kaldı. "
                    + kerahet.aciklama + ".", 14, tm.soluk, false));
        } else if (nafile != null) {
            canliKart.addView(metin(a, tm, "✦ MÜSTEHAP NÂFİLE VAKTİ AÇIK", 12, tm.iyi, true));
            canliKart.addView(metin(a, tm, nafile.ad + " (" + nafile.saatAraligi() + ")", 19, tm.metin, true));
            canliKart.addView(metin(a, tm, "Vaktin bitmesine " + nafile.kalanDk(simdi) + " dk var · Önerilen: "
                    + nafile.rekat, 14, tm.soluk, false));
        } else {
            canliKart.addView(metin(a, tm, "✓ NAMAZ KILINABİLİR VAKİT", 12, tm.iyi, true));
            canliKart.addView(metin(a, tm, "Şu an kerâhet vakti dışında bulunuyorsunuz", 18, tm.metin, true));
            canliKart.addView(metin(a, tm, "Farz, vâcip, sünnet, nâfile ve kazâ namazlarınızı gönül huzuruyla "
                    + "edâ edebilirsiniz.", 14, tm.soluk, false));
        }
        if (t != null && t.kibleSaati() != null) {
            a.bosluk(canliKart, 6);
            canliKart.addView(metin(a, tm, "🧭 Bugün güneşle kıble saati: " + t.kibleSaati(), 12, tm.vurgu, true));
        }
        s.addView(canliKart);

        // 2) 3 Kerâhet Vakti Bölümü
        s.addView(bolumBasligi(a, tm, "Kerâhet Vakitleri (3 Mekruh Vakit)"));
        for (Pencere p : tum) {
            if (p.kerahet) {
                s.addView(pencereKarti(a, tm, p, simdi));
            }
        }

        // 3) 4 Faziletli Nâfile Namaz Vakti Bölümü
        s.addView(bolumBasligi(a, tm, "Faziletli Nâfile Namaz Saatleri"));
        if (simdi < gv.imsak) {
            HesapMotoru.GunVakitleri dun = HesapMotoru.gun(a, t, komsuGunMs(simdi, -1));
            Pencere seher = teheccudPenceresi(dun.yatsi, gv.imsak);
            if (seher.icindeMi(simdi)) {
                s.addView(pencereKarti(a, tm, seher, simdi));
            }
        }
        for (Pencere p : tum) {
            if (!p.kerahet) {
                s.addView(pencereKarti(a, tm, p, simdi));
            }
        }

        // 4) Mezhep ve Fıkıh Özeti Kartı
        s.addView(bolumBasligi(a, tm, "Fıkhî Özet (Hanefî ve Şâfiî)"));
        LinearLayout fikihKart = kart(a, tm);
        fikihKart.addView(metin(a, tm, "Kazâ ve Nâfile Namazlarda Mezhep Hükümleri", 16, tm.metin, true));
        a.bosluk(fikihKart, 4);
        fikihKart.addView(metin(a, tm,
                "• Hanefî Mezhebi: Yukarıdaki 3 tam kerâhet (tahrîmen mekruh) vaktinde kazâ namazları, "
                        + "vitir, cenâze namazı (vakit içinde hazır olmadıkça) ve nâfile namazlar kılınmaz. "
                        + "Sabah namazından güneş doğana kadar ve ikindi farzından güneş sararıncaya kadar ise "
                        + "yalnız nâfile kılınmaz; kazâ namazları kılınabilir.\n\n"
                        + "• Şâfiî Mezhebi: Sebebe bağlı namazlar (kazâ namazı, cenâze namazı, tahiyyetü'l-mescid, "
                        + "abdest şükür namazı) kerâhet vakitlerinde de kılınabilir. Cuma günü ise zevâl (istivâ) "
                        + "vaktinde mutlak nâfile kılmak da mekruh değildir.",
                13, tm.soluk, false));
        if (gv.yaklasik) {
            a.bosluk(fikihKart, 6);
            fikihKart.addView(metin(a, tm, "Not: Vakitler seçili hesaplama metoduna ("
                    + HesapMotoru.aktifMetot(a).ad + ") göre astronomik olarak hesaplanmıştır.", 12, tm.silik, false));
        }
        s.addView(fikihKart);

        ScrollView sv = a.sayfa(s);
        sv.setPadding(0, 0, 0, 0);
        a.altSayfa("Kerâhet ve Nâfile Vakitler", sv, "mihrap");
    }

    private static View pencereKarti(DurumAktivitesi a, TemaMotoru.Durum tm, Pencere p, long simdi) {
        LinearLayout k = kart(a, tm);
        boolean aktif = p.icindeMi(simdi);
        boolean gecti = !aktif && p.bitis <= simdi;

        if (aktif) {
            GradientDrawable vurgulu = new GradientDrawable();
            vurgulu.setCornerRadius(a.dp(20));
            int bazRenk = p.kerahet ? tm.uyari : tm.iyi;
            vurgulu.setColor((bazRenk & 0x00FFFFFF) | (tm.acik ? 0x20000000 : 0x2A000000));
            vurgulu.setStroke(Math.max(1, a.dp(1)), (bazRenk & 0x00FFFFFF) | 0x99000000);
            k.setBackground(vurgulu);
        }

        // Üst satır: Başlık + Saat Aralığı
        LinearLayout ust = new LinearLayout(a);
        ust.setOrientation(LinearLayout.HORIZONTAL);
        ust.setGravity(Gravity.CENTER_VERTICAL);

        String simge = p.kerahet ? "⚠  " : "✦  ";
        int baslikRenk = p.kerahet ? (aktif ? tm.uyari : tm.metin) : (aktif ? tm.iyi : tm.metin);
        TextView tvAd = metin(a, tm, simge + p.ad, 16, gecti ? tm.silik : baslikRenk, true);
        ust.addView(tvAd, new LinearLayout.LayoutParams(0, -2, 1f));

        TextView tvSaat = metin(a, tm, p.saatAraligi(), 15,
                aktif ? (p.kerahet ? tm.uyari : tm.iyi) : (gecti ? tm.silik : tm.vurgu), true);
        ust.addView(tvSaat);
        k.addView(ust);

        // Rozet satırı: Rekât/Hüküm + Canlı durum
        LinearLayout rozetSatir = new LinearLayout(a);
        rozetSatir.setOrientation(LinearLayout.HORIZONTAL);
        rozetSatir.setGravity(Gravity.CENTER_VERTICAL);
        rozetSatir.setPadding(0, a.dp(4), 0, a.dp(4));

        rozetSatir.addView(rozet(a, tm, p.rekat, p.kerahet ? tm.kotu : tm.vurgu));
        if (aktif) {
            View r2 = rozet(a, tm, "Şu An · " + p.kalanDk(simdi) + " dk kaldı", p.kerahet ? tm.uyari : tm.iyi);
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-2, -2);
            lp.setMargins(a.dp(6), 0, 0, 0);
            rozetSatir.addView(r2, lp);
        } else if (!gecti) {
            long baslamasinaDk = Math.max(1L, (p.baslangic - simdi + 59_999L) / DK);
            String kalanMetni = baslamasinaDk >= 60
                    ? (baslamasinaDk / 60) + " sa " + (baslamasinaDk % 60) + " dk sonra"
                    : baslamasinaDk + " dk sonra";
            View r2 = rozet(a, tm, kalanMetni, tm.soluk);
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-2, -2);
            lp.setMargins(a.dp(6), 0, 0, 0);
            rozetSatir.addView(r2, lp);
        }
        k.addView(rozetSatir);

        k.addView(metin(a, tm, p.aciklama, 13, tm.vurgu, true));
        a.bosluk(k, 2);
        k.addView(metin(a, tm, p.detay, 13, tm.soluk, false));
        return k;
    }

    private static View rozet(DurumAktivitesi a, TemaMotoru.Durum tm, String yazi, int renk) {
        TextView tv = metin(a, tm, yazi, 11, renk, true);
        tv.setShadowLayer(0, 0, 0, 0);
        tv.setPadding(a.dp(9), a.dp(3), a.dp(9), a.dp(3));
        GradientDrawable g = new GradientDrawable();
        g.setCornerRadius(a.dp(10));
        g.setColor((renk & 0x00FFFFFF) | (tm.acik ? 0x1A000000 : 0x26000000));
        g.setStroke(1, (renk & 0x00FFFFFF) | 0x66000000);
        tv.setBackground(g);
        return tv;
    }

    private static Pencere bul(List<Pencere> l, String kod) {
        for (Pencere p : l) if (kod.equals(p.kod)) return p;
        return null;
    }

    private static LinearLayout kart(DurumAktivitesi a, TemaMotoru.Durum tm) {
        LinearLayout k = a.cam();
        k.setBackground(tm.kartArkaPlani(a));
        return k;
    }

    private static TextView bolumBasligi(DurumAktivitesi a, TemaMotoru.Durum tm, String s) {
        TextView t = a.altBaslik(s);
        t.setTextColor(tm.vurgu);
        if (tm.acik) t.setShadowLayer(0, 0, 0, 0);
        return t;
    }

    private static TextView metin(DurumAktivitesi a, TemaMotoru.Durum tm, String s, int sp, int renk, boolean kalin) {
        TextView tv = a.metin(s, TemaMotoru.olcekliSp(a, sp), renk, kalin);
        if (tm.acik) tv.setShadowLayer(0, 0, 0, 0);
        return tv;
    }
}
