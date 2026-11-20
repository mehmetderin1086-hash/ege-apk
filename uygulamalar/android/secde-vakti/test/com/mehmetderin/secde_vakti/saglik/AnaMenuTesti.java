package com.mehmetderin.secde_vakti.saglik;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.os.SystemClock;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Switch;
import android.widget.TextView;

import org.robolectric.RuntimeEnvironment;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.Shadows;
import org.robolectric.android.controller.ActivityController;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.GraphicsMode;
import org.robolectric.annotation.LooperMode;
import org.robolectric.shadows.ShadowLooper;

import java.io.File;
import java.io.FileOutputStream;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.List;
import java.util.Locale;
import java.util.TimeZone;
import java.util.concurrent.TimeUnit;

/**
 * Secde ana menüsü uçtan uca testleri (Robolectric, gerçek çizim). Her sekmenin ekran görüntüsü
 * "cikti" sistem özelliğindeki klasöre PNG olarak yazılır.
 */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 34, qualifiers = "w411dp-h891dp-xxhdpi", application = SecdeUygulama.class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@LooperMode(LooperMode.Mode.PAUSED)
public class AnaMenuTesti {

    private Context c;

    @Before
    public void veriKur() throws Exception {
        TimeZone.setDefault(TimeZone.getTimeZone("Europe/Istanbul"));
        c = RuntimeEnvironment.getApplication();
        for (Thread t : Thread.getAllStackTraces().keySet()) {
            if ("secde-baslangic".equals(t.getName())) {
                try { t.join(2500); } catch (InterruptedException ignored) {}
            }
        }
        SharedPreferences f = c.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE);
        f.edit()
                .putBoolean("flutter.settings.onboarded", true)
                .putString("flutter.schedule.json", takvimJson().toString())
                .putLong("flutter.notifications.lastRescheduleMs", System.currentTimeMillis() - 3600_000L)
                .commit();
        c.getSharedPreferences("scheduled_notifications", Context.MODE_PRIVATE).edit()
                .putString("scheduled_notifications", bildirimJson().toString()).commit();
        // Açılış diyaloğu testleri bozmasın
        Tercihler.sp(c).edit().putInt("tanitilan_surum", 99).putLong("son_uyari_ms", System.currentTimeMillis()).commit();
        TemaMotoru.temaSec(c, "zumrut");
        TemaMotoru.kartBicimiSec(c, TemaMotoru.KART_YUMUSAK);
        TemaMotoru.desenSec(c, -1);
        TemaMotoru.sahneModuSec(c, "");
        TemaMotoru.yaziOlcegiSec(c, 1.0f);
        TemaMotoru.yuksekKontrastSec(c, false);
        HesapMotoru.metotSec(c, "diyanet");
        HesapMotoru.asriSaniSec(c, false);
        RamazanModu.herZamanGosterSec(c, false);
    }

    // ------------------------------------------------------------ örnek veri (İstanbul)

    private static final int[][] SAAT = {{6, 12}, {7, 38}, {12, 59}, {15, 34}, {17, 57}, {19, 19}};
    private static final String[] NAMAZ = {"fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"};

    private static String yerel(Calendar g) {
        SimpleDateFormat f = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.ROOT);
        f.setTimeZone(TimeZone.getTimeZone("Europe/Istanbul"));
        return f.format(g.getTime());
    }

    private static JSONObject takvimJson() throws Exception {
        JSONObject o = new JSONObject();
        o.put("placeName", "İstanbul, Fatih");
        o.put("latitude", 41.0082);
        o.put("longitude", 28.9784);
        o.put("timeZoneIdentifier", "Europe/Istanbul");
        o.put("source", "diyanet");
        JSONArray gunler = new JSONArray();
        Calendar g = Calendar.getInstance(TimeZone.getTimeZone("Europe/Istanbul"));
        g.set(Calendar.HOUR_OF_DAY, 0);
        g.set(Calendar.MINUTE, 0);
        g.set(Calendar.SECOND, 0);
        g.set(Calendar.MILLISECOND, 0);
        for (int d = 0; d < 31; d++) {
            JSONObject gun = new JSONObject();
            gun.put("dayStart", yerel(g));
            gun.put("hicriDate", (20 + d) % 30 + 1 + " Cemâziyelevvel 1448");
            gun.put("qiblaTime", "12:" + (10 + d % 40));
            JSONArray t = new JSONArray();
            for (int i = 0; i < 6; i++) {
                Calendar x = (Calendar) g.clone();
                x.set(Calendar.HOUR_OF_DAY, SAAT[i][0]);
                x.set(Calendar.MINUTE, SAAT[i][1] + (i == 4 ? -d / 3 : 0));
                t.put(new JSONObject().put("prayer", NAMAZ[i]).put("date", yerel(x)));
            }
            gun.put("times", t);
            gunler.put(gun);
            g.add(Calendar.DAY_OF_MONTH, 1);
        }
        o.put("days", gunler);
        return o;
    }

    private static JSONArray bildirimJson() throws Exception {
        JSONArray a = new JSONArray();
        Calendar g = Calendar.getInstance(TimeZone.getTimeZone("Europe/Istanbul"));
        long simdi = g.getTimeInMillis();
        int id = 1;
        for (int d = 0; d < 30; d++) {
            for (int i = 0; i < 6; i++) {
                if (i == 1) continue;
                Calendar x = (Calendar) g.clone();
                x.add(Calendar.DAY_OF_MONTH, d);
                x.set(Calendar.HOUR_OF_DAY, SAAT[i][0]);
                x.set(Calendar.MINUTE, SAAT[i][1]);
                x.set(Calendar.SECOND, 0);
                if (x.getTimeInMillis() < simdi) continue;
                a.put(new JSONObject().put("id", id++).put("title", Metinler.namazAdi(NAMAZ[i]) + " Vakti")
                        .put("body", Metinler.namazAdi(NAMAZ[i]) + " vakti girdi.").put("channelId", "sekine_alarm_ezan")
                        .put("scheduledDateTime", yerel(x).substring(0, 19)).put("timeZoneName", "Europe/Istanbul")
                        .put("payload", "{\"kind\":\"main\",\"prayer\":\"" + NAMAZ[i] + "\"}"));
            }
        }
        Calendar ayet = (Calendar) g.clone();
        ayet.add(Calendar.HOUR_OF_DAY, 3);
        a.put(new JSONObject().put("id", 900).put("title", "Günün Ayeti")
                .put("body", "Şüphesiz zorlukla beraber bir kolaylık vardır. — İnşirâh, 6")
                .put("scheduledDateTime", yerel(ayet).substring(0, 19)).put("timeZoneName", "Europe/Istanbul")
                .put("payload", "{\"kind\":\"verse\"}"));
        Calendar kandil = (Calendar) g.clone();
        kandil.add(Calendar.DAY_OF_MONTH, 9);
        kandil.set(Calendar.HOUR_OF_DAY, 9);
        a.put(new JSONObject().put("id", 901).put("title", "Regâib Kandili")
                .put("body", "Kandiliniz mübarek olsun.")
                .put("scheduledDateTime", yerel(kandil).substring(0, 19)).put("timeZoneName", "Europe/Istanbul")
                .put("payload", "{\"kind\":\"holy\"}"));
        return a;
    }

    // ------------------------------------------------------------ yardımcılar

    private static void bekle(long ms) {
        ShadowLooper.idleMainLooper(ms, TimeUnit.MILLISECONDS);
    }

    private static void resim(Activity a, String ad) throws Exception {
        bekle(1800);
        View kok = a.getWindow().getDecorView();
        Bitmap b = Bitmap.createBitmap(kok.getWidth(), kok.getHeight(), Bitmap.Config.ARGB_8888);
        kok.draw(new Canvas(b));
        File dizin = new File(System.getProperty("cikti", "/tmp"));
        dizin.mkdirs();
        try (FileOutputStream f = new FileOutputStream(new File(dizin, ad + ".png"))) {
            b.compress(Bitmap.CompressFormat.PNG, 100, f);
        }
    }

    private static <T extends View> List<T> bul(View v, Class<T> tur) {
        List<T> l = new ArrayList<>();
        if (tur.isInstance(v)) l.add(tur.cast(v));
        if (v instanceof ViewGroup) {
            ViewGroup g = (ViewGroup) v;
            for (int i = 0; i < g.getChildCount(); i++) l.addAll(bul(g.getChildAt(i), tur));
        }
        return l;
    }

    private static TextView yaziIle(View kok, String metin) {
        for (TextView t : bul(kok, TextView.class)) {
            if (t.getVisibility() == View.VISIBLE && t.getText() != null && t.getText().toString().contains(metin)) return t;
        }
        return null;
    }

    private static View aciklamaIle(View kok, String aciklama) {
        if (kok.getContentDescription() != null && kok.getContentDescription().toString().equals(aciklama)) return kok;
        if (kok instanceof ViewGroup) {
            ViewGroup g = (ViewGroup) kok;
            for (int i = 0; i < g.getChildCount(); i++) {
                View v = aciklamaIle(g.getChildAt(i), aciklama);
                if (v != null) return v;
            }
        }
        return null;
    }

    private static void dokun(View v) {
        long t = SystemClock.uptimeMillis();
        v.dispatchTouchEvent(MotionEvent.obtain(t, t, MotionEvent.ACTION_DOWN, v.getWidth() / 2f, v.getHeight() / 2f, 0));
        v.dispatchTouchEvent(MotionEvent.obtain(t, t + 40, MotionEvent.ACTION_UP, v.getWidth() / 2f, v.getHeight() / 2f, 0));
    }

    private DurumAktivitesi ac() {
        return ac(new Intent(c, DurumAktivitesi.class));
    }

    private DurumAktivitesi ac(Intent i) {
        Tercihler.sp(c).edit().putInt("son_sekme", 0).commit();
        ActivityController<DurumAktivitesi> k = Robolectric.buildActivity(DurumAktivitesi.class, i).setup();
        bekle(1500);
        return k.get();
    }

    // ------------------------------------------------------------ testler

    @Test
    public void sekmelerCizilirVeTiklaninca() throws Exception {
        DurumAktivitesi a = ac();
        View kok = a.getWindow().getDecorView();
        assertEquals(0, a.sekme());
        assertNotNull("Konum başlığı", yaziIle(kok, "İstanbul, Fatih"));
        assertNotNull("Günün ayeti kartı", yaziIle(kok, "zorlukla beraber"));
        assertNotNull("Mübarek gün kartı", yaziIle(kok, "Regâib Kandili"));
        assertNotNull("Geri sayım", yaziIle(kok, "SIRADAKİ"));
        resim(a, "1_vakitler");

        String[] ad = {"Vakitler", "Kur'an", "Kıble", "Zikir", "Menü"};
        for (int i = 1; i < 5; i++) {
            View hucre = aciklamaIle(kok, ad[i] + " sekmesi");
            assertNotNull(ad[i] + " sekme butonu", hucre);
            assertTrue(hucre.performClick());
            bekle(800);
            assertEquals("Sekme butonu " + ad[i], i, a.sekme());
            resim(a, (i + 1) + "_" + ad[i].toLowerCase(new Locale("tr")).replace("ı", "i").replace("ü", "u").replace("'", ""));
        }
        // Geri tuşu ilk sekmeye döner
        a.onBackPressed();
        bekle(800);
        assertEquals(0, a.sekme());
    }

    @Test
    public void resimliButonlarSekmeAcar() {
        DurumAktivitesi a = ac();
        View kok = a.getWindow().getDecorView();
        Kutucuk kible = null;
        for (Kutucuk k : bul(kok, Kutucuk.class)) if (k.baslik().equals("Kıble")) { kible = k; break; }
        assertNotNull(kible);
        assertTrue(kible.performClick());
        bekle(600);
        assertEquals(DurumAktivitesi.S_KIBLE, a.sekme());
    }

    @Test
    public void konumVeSehirSeciciTakvimiYeniler() {
        DurumAktivitesi a = ac(new Intent(c, DurumAktivitesi.class).putExtra(DurumAktivitesi.EK_SEKME, DurumAktivitesi.S_MENU));
        bekle(600);
        View kok = a.getWindow().getDecorView();
        Kutucuk konumKutusu = null;
        for (Kutucuk k : bul(kok, Kutucuk.class)) if (k.baslik().equals("Konum & Şehir")) { konumKutusu = k; break; }
        assertNotNull("Menüde Konum & Şehir kutusu bulunmalı", konumKutusu);
        konumKutusu.performClick();
        bekle(600);
        assertEquals("Konum alt sayfası açılmalı", 1, a.altSayfaSayisi());
        View konya = aciklamaIle(a.getWindow().getDecorView(), "Şehir Konya");
        assertNotNull("81 il listesinde Konya bulunmalı", konya);
        konya.performClick();
        bekle(600);
        assertEquals(0, a.altSayfaSayisi());
        VakitTakvimi.Takvim yeniTakvim = VakitTakvimi.oku(c);
        assertEquals("Konya", yeniTakvim.yer);
        assertEquals(35 * 6, yeniTakvim.vakitler.size());
    }

    @Test
    public void geriTusuAltSayfaSekmeVeGorevAkisiniKorur() {
        DurumAktivitesi a = ac(new Intent(c, DurumAktivitesi.class).putExtra(DurumAktivitesi.EK_ANA, true));
        a.sekmeyeGec(DurumAktivitesi.S_KIBLE);
        bekle(400);
        a.bolumAc("takvim");
        bekle(400);
        assertEquals(1, a.altSayfaSayisi());
        a.geriTusuIsle();
        bekle(400);
        assertEquals("Önce alt sayfa kapanmalı", 0, a.altSayfaSayisi());
        assertEquals(DurumAktivitesi.S_KIBLE, a.sekme());
        a.geriTusuIsle();
        bekle(400);
        assertEquals("Sonra Vakitler sekmesine dönmeli", DurumAktivitesi.S_VAKIT, a.sekme());
        a.geriTusuIsle();
        assertFalse("Ana etkinlik sonlanıp eski ekrana düşmemeli", a.isFinishing());
        assertNull("Eski MainActivity başlatılmamalı", Shadows.shadowOf(a).getNextStartedActivity());
    }

    @Test
    public void zikirmatikSayarVeTesbihattaGecer() throws Exception {
        DurumAktivitesi a = ac(new Intent(c, DurumAktivitesi.class).putExtra(DurumAktivitesi.EK_SEKME, DurumAktivitesi.S_ZIKIR));
        bekle(800);
        assertEquals(DurumAktivitesi.S_ZIKIR, a.sekme());
        ZikirDaire z = bul(a.getWindow().getDecorView(), ZikirDaire.class).get(0);
        for (int i = 0; i < 33; i++) dokun(z);
        bekle(1500);
        Zikir veri = new Zikir(c);
        assertEquals(33, veri.sayi(0));
        assertEquals("33 Sübhânallah sonrası Elhamdülillah'a geçmeli", 1, veri.secili());
        assertEquals(33, veri.gunluk());
        for (int i = 0; i < 5; i++) dokun(bul(a.getWindow().getDecorView(), ZikirDaire.class).get(0));
        bekle(300);
        assertEquals(5, veri.sayi(1));
        resim(a, "6_zikir_sayilmis");
    }

    @Test
    public void kibleHesabiVePusulaHizalamasi() throws Exception {
        double yon = Kible.yon(41.0082, 28.9784);
        assertEquals("İstanbul kıble yönü", 151.6, yon, 0.5);
        assertEquals("İstanbul–Kâbe uzaklığı", 2400, Kible.uzaklikKm(41.0082, 28.9784), 30);
        assertEquals("Güneydoğu", Kible.yonAdi(yon));
        assertEquals(-20, Kible.fark(340, 0), 0.001);

        DurumAktivitesi a = ac(new Intent(c, DurumAktivitesi.class).putExtra(DurumAktivitesi.EK_SEKME, DurumAktivitesi.S_KIBLE));
        bekle(800);
        View kok = a.getWindow().getDecorView();
        assertNotNull(yaziIle(kok, "152°"));
        assertNotNull(yaziIle(kok, "Kâbe'ye"));
        assertNotNull("Kıble saati", yaziIle(kok, "kıble saati 12:10"));
        Pusula p = bul(kok, Pusula.class).get(0);
        p.azimut((float) yon);
        bekle(300);
        resim(a, "7_kible_hizali");
    }

    @Test
    public void acilisMenusuHerZamanAcikKalir() {
        assertTrue(Tercihler.acilisMenu(c));
        Tercihler.acilisMenu(c, false);
        assertTrue("Eski 1.0 ekranına dönüş kalıcı olarak engellenmeli", Tercihler.acilisMenu(c));
    }

    @Test
    public void eskiMainActivityHerNiyetteDurumAktivitesineYonlenipKapanir() {
        // 1) Normal başlatıcı niyeti
        Intent baslat = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                .setClassName(c, DurumAktivitesi.ANA_ACTIVITY);
        Activity f1 = Robolectric.buildActivity(com.mehmetderin.secde_vakti.MainActivity.class, baslat).create().get();
        Intent s1 = Shadows.shadowOf(f1).getNextStartedActivity();
        assertNotNull("Simgeden açılışta DurumAktivitesi açılmalı", s1);
        assertEquals(DurumAktivitesi.class.getName(), s1.getComponent().getClassName());
        assertTrue("Eski MainActivity anında kapanmalı", f1.isFinishing());

        // 2) Bildirime dokunarak açılış (SELECT_NOTIFICATION): eski 1.0 ekranında takılı kalmamalı!
        Intent bildirim = new Intent("SELECT_NOTIFICATION").setClassName(c, DurumAktivitesi.ANA_ACTIVITY);
        Activity f2 = Robolectric.buildActivity(com.mehmetderin.secde_vakti.MainActivity.class, bildirim).create().get();
        Intent s2 = Shadows.shadowOf(f2).getNextStartedActivity();
        assertNotNull("Bildirim tıklaması da DurumAktivitesi'ne yönlenmeli", s2);
        assertEquals(DurumAktivitesi.class.getName(), s2.getComponent().getClassName());
        assertTrue("Bildirim açılışında da eski MainActivity kapanmalı", f2.isFinishing());

        // 3) EK_DOGRUDAN bayrağı verilse bile eski ekran açılamaz
        Intent dogrudan = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                .putExtra(DurumAktivitesi.EK_DOGRUDAN, true)
                .setClassName(c, DurumAktivitesi.ANA_ACTIVITY);
        Activity f3 = Robolectric.buildActivity(com.mehmetderin.secde_vakti.MainActivity.class, dogrudan).create().get();
        Intent s3 = Shadows.shadowOf(f3).getNextStartedActivity();
        assertNotNull(s3);
        assertEquals(DurumAktivitesi.class.getName(), s3.getComponent().getClassName());
        assertTrue(f3.isFinishing());
    }

    @Test
    public void takvimOkuyucuVeBildirimDeposu() {
        VakitTakvimi.Takvim t = VakitTakvimi.oku(c);
        assertEquals(31 * 6, t.vakitler.size());
        assertEquals(41.0082, t.enlem, 1e-6);
        assertEquals(6, t.bugun().size());
        assertNotNull(t.hicri);
        assertEquals("12:10", t.kibleSaati());
        assertEquals("09:05", VakitTakvimi.saatMetni("9:05", null));
        assertEquals("12:34", VakitTakvimi.saatMetni("12:34:00", null));
        List<Vakit> g = VakitDeposu.gelecek(c);
        assertTrue(VakitDeposu.say(g, "main") > 100);
        assertEquals(1, VakitDeposu.say(g, "holy"));
    }

    // ------------------------------------------------------------ Kur'an bölümü

    private static void bekleKadar(java.util.function.BooleanSupplier kosul, long ms) {
        long son = System.currentTimeMillis() + ms;
        while (!kosul.getAsBoolean() && System.currentTimeMillis() < son) {
            bekle(100);
            try { Thread.sleep(30); } catch (InterruptedException ignored) { }
        }
    }

    @Test
    public void kuranVerisiVeSesAdresleri() {
        assertEquals(114, Kuran.sureler(c).size());
        Kuran.Sure bakara = Kuran.sure(c, 2);
        assertEquals("Bakara", bakara.ad);
        assertEquals(286, bakara.ayetSayisi);
        assertEquals("Medenî", bakara.yer);
        assertEquals(286, Kuran.ayetler(c, 2).size());
        assertEquals(6236, toplamAyet());
        assertTrue(Kuran.ayetler(c, 1).get(1).meal.startsWith("Hamt"));
        List<Kuran.Kelime> k = Kuran.kelimeler(c, 1, 1);
        assertEquals(4, k.size());
        assertEquals("adıyla", k.get(0).meal);
        List<TilavetServisi.Parca> q = TilavetServisi.tilavetKuyrugu(bakara, 255, "Alafasy_128kbps");
        assertEquals(32, q.size());
        assertEquals("https://everyayah.com/data/Alafasy_128kbps/002255.mp3", q.get(0).adres);
        assertEquals(10, Kuran.mealOkuyuculari(c).size());
        String[] meal = Kuran.mealSesi(c, 36, "Hakan Vanlı");
        assertNotNull(meal);
        assertEquals("Hakan Vanlı", meal[0]);
        assertTrue(meal[1].startsWith("https://"));
        assertTrue(Kuran.yerImiDegistir(c, 2, 255));
        assertTrue(Kuran.yerImi(c, 2, 255));
        assertFalse(Kuran.yerImiDegistir(c, 2, 255));
    }

    private int toplamAyet() {
        int n = 0;
        for (int i = 1; i <= 114; i++) n += Kuran.ayetler(c, i).size();
        return n;
    }

    @Test
    public void kuranSekmesiVeSureOkuyucu() throws Exception {
        DurumAktivitesi a = ac(new Intent(c, DurumAktivitesi.class).putExtra(DurumAktivitesi.EK_SEKME, DurumAktivitesi.S_KURAN));
        bekle(800);
        assertEquals(DurumAktivitesi.S_KURAN, a.sekme());
        View kok = a.getWindow().getDecorView();
        assertNotNull(yaziIle(kok, "Kur'an-ı Kerim"));
        View bakara = aciklamaIle(kok, "Bakara suresi");
        assertNotNull("Sure listesi", bakara);
        assertNotNull(aciklamaIle(kok, "Nâs suresi"));
        resim(a, "8_kuran_sekmesi");

        assertTrue(bakara.performClick());
        bekle(600);
        assertEquals(1, a.altSayfaSayisi());
        final android.widget.ListView[] l = new android.widget.ListView[1];
        bekleKadar(() -> {
            List<android.widget.ListView> x = bul(a.getWindow().getDecorView(), android.widget.ListView.class);
            l[0] = x.isEmpty() ? null : x.get(0);
            return l[0] != null && l[0].getAdapter() != null && l[0].getAdapter().getCount() >= 287;
        }, 15000);
        assertNotNull(l[0]);
        assertEquals("Başlık + 286 ayet", 287, l[0].getAdapter().getCount());
        bekle(800);
        resim(a, "9_bakara_okuyucu");
        int[] son = Kuran.sonOkunan(c);
        assertNotNull(son);
        assertEquals(2, son[0]);

        a.onBackPressed();
        bekle(600);
        assertEquals("Geri tuşu alt sayfayı kapatır", 0, a.altSayfaSayisi());
        assertEquals(DurumAktivitesi.S_KURAN, a.sekme());
    }

    @Test
    public void elifBaHarflerVeTest() throws Exception {
        DurumAktivitesi a = ac();
        a.bolumAc("elifba");
        bekle(800);
        View kok = a.getWindow().getDecorView();
        int harf = 0, secenek = 0;
        for (View v : bul(kok, View.class)) {
            CharSequence d = v.getContentDescription();
            if (d == null) continue;
            if (d.toString().startsWith("Harf ")) harf++;
            if (d.toString().startsWith("Seçenek ")) secenek++;
        }
        assertEquals(28, harf);
        assertEquals(4, secenek);
        assertTrue(aciklamaIle(kok, "Harf Be").performClick());
        bekle(300);
        assertNotNull("Harekeler: be, bi, bu", yaziIle(kok, "HAREKELER · BE"));
        resim(a, "10_elifba");
        View ilk = null;
        for (View v : bul(kok, View.class)) {
            CharSequence d = v.getContentDescription();
            if (d != null && d.toString().startsWith("Seçenek ")) { ilk = v; break; }
        }
        assertTrue(ilk.performClick());
        assertEquals(1, c.getSharedPreferences("secde_kuran", Context.MODE_PRIVATE).getInt("elifba_soru", 0));
    }

    @Test
    public void dualarEsmaTakvimAltSayfalari() throws Exception {
        DurumAktivitesi a = ac();
        a.bolumAc("dualar");
        bekle(800);
        assertNotNull(yaziIle(a.getWindow().getDecorView(), "Rabbenâ Duası"));
        resim(a, "11_dualar");
        a.onBackPressed();
        bekle(500);
        a.bolumAc("esma");
        bekle(800);
        assertNotNull(yaziIle(a.getWindow().getDecorView(), "Er-Rahmân"));
        resim(a, "12_esma");
        a.onBackPressed();
        bekle(500);
        a.bolumAc("takvim");
        bekle(800);
        assertNotNull(yaziIle(a.getWindow().getDecorView(), "Regâib Kandili"));
        a.bolumAc("meal");
        bekle(800);
        assertEquals(2, a.altSayfaSayisi());
        assertNotNull(yaziIle(a.getWindow().getDecorView(), "Hakan Vanlı"));
        resim(a, "13_sesli_meal");
        a.onBackPressed();
        a.onBackPressed();
        bekle(600);
        assertEquals(0, a.altSayfaSayisi());
    }

    // ------------------------------------------------------------ 1.5.1: denetim ve onarım

    @Test
    public void gizlenenBolumlerGeriAcilir() {
        SharedPreferences f = c.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE);
        f.edit().putBoolean("flutter.home.showLearning.v2", false).putBoolean("flutter.home.showSpiritual.v2", false)
                .putBoolean("flutter.home.showDiscovery.v2", false).commit();
        Tercihler.sp(c).edit().remove("bolumler_acik_v2").commit();
        Gorunum.bolumleriGeriAc(c);
        assertTrue(f.getBoolean("flutter.home.showLearning.v2", false));
        assertTrue(f.getBoolean("flutter.home.showSpiritual.v2", false));
        assertTrue(f.getBoolean("flutter.home.showDiscovery.v2", false));
        // Kullanıcı sonra kendisi gizlerse bir daha dokunulmaz
        f.edit().putBoolean("flutter.home.showDiscovery.v2", false).commit();
        Gorunum.bolumleriGeriAc(c);
        assertFalse(f.getBoolean("flutter.home.showDiscovery.v2", true));
    }

    @Test
    public void denetimVeHataKaydi() throws Exception {
        Hata.kaydet(c, "deneme", new IllegalStateException("örnek"));
        assertNotNull(Hata.son(c));
        List<Denetim.Sonuc> l = Denetim.calistir(c);
        java.util.Map<String, Denetim.Sonuc> m = new java.util.HashMap<>();
        for (Denetim.Sonuc s : l) m.put(s.ad, s);
        assertEquals(m.get("Kur'an verisi").ayrinti, 1, m.get("Kur'an verisi").seviye);
        assertEquals(1, m.get("Kur'an metni ve meal").seviye);
        assertEquals(1, m.get("Kur'an yazı tipi").seviye);
        assertEquals(1, m.get("Sesli meal dizini").seviye);
        assertEquals(0, m.get("Son hata kaydı").seviye);
        String r = Denetim.rapor(c, l);
        assertTrue(r.contains("Secde Vakti denetim raporu"));

        DurumAktivitesi a = ac(new Intent(c, DurumAktivitesi.class).putExtra(DurumAktivitesi.EK_SEKME, DurumAktivitesi.S_MENU));
        bekle(800);
        TextView b = yaziIle(a.getWindow().getDecorView(), "Uygulamayı denetle");
        assertNotNull(b);
        b.performClick();
        bekle(500);
        assertEquals(1, a.altSayfaSayisi());
        bekleKadar(() -> yaziIle(a.getWindow().getDecorView(), "Raporu kopyala") != null, 30000);
        assertNotNull(yaziIle(a.getWindow().getDecorView(), "Raporu kopyala"));
        resim(a, "14_denetim");
    }

    @Test
    public void bolumAcmaHatasiUygulamayiKapatmaz() {
        DurumAktivitesi a = ac();
        a.guvenli("deneme", () -> { throw new RuntimeException("bozuk"); });
        assertFalse(a.isFinishing());
        assertTrue(Hata.son(c).contains("bozuk"));
    }

    // ------------------------------------------------------------ 2.0: Tema Stüdyosu, İbadet, Maneviyat ve Sosyal Kartlar

    @Test
    public void onAltiTemaVeInciGunduzAcikMod() throws Exception {
        assertEquals(16, TemaMotoru.TEMALAR.length);
        for (TemaMotoru.Tema t : TemaMotoru.TEMALAR) {
            TemaMotoru.temaSec(c, t.kod);
            TemaMotoru.Durum d = TemaMotoru.aktif(c);
            assertEquals(t.kod, d.tema.kod);
            assertNotNull(d.kartArkaPlani(c));
        }

        TemaMotoru.temaSec(c, "iznik_cinisi");
        DurumAktivitesi a = ac();
        a.bolumAc("tema");
        bekle(800);
        assertEquals(1, a.altSayfaSayisi());
        View inci = aciklamaIle(a.getWindow().getDecorView(), "Tema İnci Ferahlığı · Açık");
        assertNotNull("Tema galerisinde İnci Ferahlığı kartı bulunmalı", inci);
        resim(a, "15_tema_studyo");

        assertTrue(inci.performClick());
        bekle(600);
        assertEquals("inci_gunduz", TemaMotoru.temaKodu(c));
        assertTrue(TemaMotoru.aktif(c).acik);

        a.onBackPressed();
        bekle(600);
        assertEquals(0, a.altSayfaSayisi());
        resim(a, "16_inci_acik_tema");
    }

    @Test
    public void hesapMotoruVeKerahetPencereleri() throws Exception {
        VakitTakvimi.Takvim t = VakitTakvimi.oku(c);
        long simdi = System.currentTimeMillis();
        assertEquals(7, HesapMotoru.METOTLAR.length);
        for (HesapMotoru.Metot m : HesapMotoru.METOTLAR) {
            HesapMotoru.metotSec(c, m.kod);
            HesapMotoru.asriSaniSec(c, false);
            HesapMotoru.GunVakitleri gv = HesapMotoru.gun(c, t, simdi);
            assertTrue(m.kod, gv.imsak < gv.gunes && gv.gunes < gv.ogle && gv.ogle < gv.ikindi && gv.ikindi < gv.aksam && gv.aksam < gv.yatsi);
        }
        HesapMotoru.metotSec(c, "mwl");
        HesapMotoru.asriSaniSec(c, false);
        long ikindiEvvel = HesapMotoru.gun(c, t, simdi).ikindi;
        HesapMotoru.asriSaniSec(c, true);
        long ikindiSani = HesapMotoru.gun(c, t, simdi).ikindi;
        assertTrue("Asr-ı Sânî ikindi vakti Asr-ı Evvel'den sonra olmalı", ikindiSani > ikindiEvvel + 20 * 60_000L);

        List<Kerahet.Pencere> pencereler = Kerahet.bugunNafileVeKerahet(c, t, simdi);
        assertEquals(7, pencereler.size());

        DurumAktivitesi a = ac();
        a.bolumAc("kerahet");
        bekle(800);
        assertEquals(1, a.altSayfaSayisi());
        assertNotNull(yaziIle(a.getWindow().getDecorView(), "İşrâk"));
    }

    @Test
    public void namazTakibiSeriOzelHalVeIsiHaritasi() throws Exception {
        c.getSharedPreferences("secde_namaz_takip", Context.MODE_PRIVATE).edit().clear().commit();
        String bugun = new SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).format(Calendar.getInstance().getTime());
        for (int i = 0; i < 5; i++) {
            NamazTakip.durumSec(c, bugun, i, i % 2 == 0 ? NamazTakip.EDA : NamazTakip.CEMAAT);
        }
        assertEquals(5, NamazTakip.bugunTamamlanan(c));
        assertEquals(1, NamazTakip.seri(c));

        // Özel Hâl (Mazeret) modu seriyi korur
        NamazTakip.durumSec(c, bugun, 4, NamazTakip.BEKLIYOR);
        NamazTakip.mazeretModuSec(c, true);
        assertTrue(NamazTakip.mazeretModu(c));
        assertEquals(1, NamazTakip.seri(c));
        NamazTakip.mazeretModuSec(c, false);

        DurumAktivitesi a = ac();
        a.bolumAc("namaz_takip");
        bekle(800);
        assertEquals(1, a.altSayfaSayisi());
        assertFalse(bul(a.getWindow().getDecorView(), NamazTakip.IsiHaritasiView.class).isEmpty());
        resim(a, "17_namaz_takip");
    }

    @Test
    public void kazaOrucVeOtuzGunlukImsakiye() throws Exception {
        c.getSharedPreferences("secde_kaza_oruc", Context.MODE_PRIVATE).edit().clear().commit();
        for (int i = 0; i < 6; i++) KazaTakip.borcAyarla(c, i, 10);
        assertEquals(60, KazaTakip.toplamBorc(c));
        KazaTakip.artir(c, 0, -1);
        assertEquals(59, KazaTakip.toplamBorc(c));
        assertEquals(1, KazaTakip.bugunKilinanKaza(c));

        KazaTakip.kazaOrucuBorcuAyarla(c, 4);
        KazaTakip.orucIsaretle(c, "2026-11-12", KazaTakip.ORUC_KAZA);
        assertEquals("Kazâ orucu işaretlenince borç 1 düşmeli", 3, KazaTakip.kazaOrucuBorcu(c));

        RamazanModu.herZamanGosterSec(c, true);
        DurumAktivitesi a = ac();
        assertNotNull(yaziIle(a.getWindow().getDecorView(), "30 Günlük İmsakiye"));
        a.bolumAc("kaza");
        bekle(800);
        resim(a, "18_kaza_oruc");
        a.onBackPressed();
        bekle(500);
        a.bolumAc("imsakiye");
        bekle(800);
        assertNotNull(yaziIle(a.getWindow().getDecorView(), "İftar"));
        resim(a, "19_imsakiye");
    }

    @Test
    public void boncukluZikirTesbihatHatimVeEzanStudyo() throws Exception {
        Zikir zv = new Zikir(c);
        zv.boncukModu(true);
        zv.boncukMalzeme(1);
        int eklenen = zv.ozelEkle("Yâ Şâfî", "يَا شَافِي", "Şifâ veren Allah", 33);
        assertTrue(eklenen >= Zikir.LISTE.length);

        DurumAktivitesi a = ac(new Intent(c, DurumAktivitesi.class).putExtra(DurumAktivitesi.EK_SEKME, DurumAktivitesi.S_ZIKIR));
        bekle(800);
        BoncukluZikirView bv = bul(a.getWindow().getDecorView(), BoncukluZikirView.class).get(0);
        assertEquals(View.VISIBLE, bv.getVisibility());
        bv.say();
        bv.say();
        bekle(400);
        assertEquals(2, zv.sayi(eklenen));
        resim(a, "20_boncuklu_zikir");
        zv.boncukModu(false);

        a.bolumAc("tesbihat");
        bekle(800);
        assertNotNull(yaziIle(a.getWindow().getDecorView(), "Sübhânallah"));
        resim(a, "21_tesbihat");
        a.onBackPressed();
        bekle(500);

        HatimTakip.cuzDurumuSec(c, 1, HatimTakip.DURUM_TAMAMLANDI);
        assertEquals(1, HatimTakip.tamamlananCuzSayisi(c));
        a.bolumAc("hatim");
        bekle(800);
        assertNotNull(yaziIle(a.getWindow().getDecorView(), "1. Cüz"));
        a.onBackPressed();
        bekle(500);

        a.bolumAc("ezan_studyo");
        bekle(800);
        assertNotNull(yaziIle(a.getWindow().getDecorView(), "Medîne"));
        resim(a, "22_ezan_studyo");
    }

    @Test
    public void camilerHicriManeviPaketVePaylasimKarti() throws Exception {
        int[] h = HicriTakvim.miladidenHicriye(2026, 11, 12);
        assertTrue(h[0] >= 1447 && h[1] >= 1 && h[1] <= 12 && h[2] >= 1 && h[2] <= 30);
        int[] m = HicriTakvim.hicridenMiladiye(h[0], h[1], h[2]);
        assertEquals(2026, m[0]);
        assertEquals(11, m[1]);
        assertEquals(12, m[2]);

        DurumAktivitesi a = ac();
        a.bolumAc("hicri");
        bekle(800);
        assertNotNull(yaziIle(a.getWindow().getDecorView(), "Mevlid Kandili"));
        resim(a, "23_hicri_takvim");
        a.onBackPressed();
        bekle(500);

        a.bolumAc("camiler");
        bekle(800);
        assertFalse(bul(a.getWindow().getDecorView(), CamilerSayfasi.CamiRadarView.class).isEmpty());
        resim(a, "24_camiler_radar");
        a.onBackPressed();
        bekle(500);

        a.bolumAc("manevi");
        bekle(800);
        assertNotNull(yaziIle(a.getWindow().getDecorView(), "HADÎS"));
        a.onBackPressed();
        bekle(500);

        VakitTakvimi.Takvim takvim = VakitTakvimi.oku(c);
        Bitmap kart = PaylasimKarti.kartUret(c, takvim, TemaMotoru.bul("kabe_kisvesi"),
                PaylasimKarti.SABLON_VAKITLER, false, null, null, null);
        assertNotNull(kart);
        assertEquals(1080, kart.getWidth());
        assertEquals(1350, kart.getHeight());
        File dizin = new File(System.getProperty("cikti", "/tmp"));
        dizin.mkdirs();
        try (FileOutputStream fos = new FileOutputStream(new File(dizin, "25_paylasim_karti.png"))) {
            kart.compress(Bitmap.CompressFormat.PNG, 100, fos);
        }
    }

    @Test
    public void manzaraPaketleriEfektlerGokYorungesiVeHuzurModu() throws Exception {
        // 1. Sahne paketi ve sabit arka plan çözümleme testleri
        TemaMotoru.sabitArkaPlanSec(c, "");
        TemaMotoru.sahnePaketiSec(c, TemaMotoru.PAKET_HAREMEYN);
        assertEquals("bg_mekke_gece", TemaMotoru.sahneAnahtariCoz(c, "vakit_5"));
        assertEquals("bg_medine_ravza", TemaMotoru.sahneAnahtariCoz(c, "vakit_2"));

        TemaMotoru.sahnePaketiSec(c, TemaMotoru.PAKET_KUDUS_AKSA);
        assertEquals("bg_kudus_aksa", TemaMotoru.sahneAnahtariCoz(c, "vakit_1"));
        assertEquals("bg_selcuklu_avlu", TemaMotoru.sahneAnahtariCoz(c, "vakit_3"));

        TemaMotoru.sahnePaketiSec(c, TemaMotoru.PAKET_OSMANLI_GECE);
        assertEquals("bg_teheccud_pencere", TemaMotoru.sahneAnahtariCoz(c, "vakit_0"));

        TemaMotoru.sabitArkaPlanSec(c, "bg_mekke_gece");
        assertEquals("bg_mekke_gece", TemaMotoru.sahneAnahtariCoz(c, "vakit_2"));

        TemaMotoru.efektYogunluguSec(c, TemaMotoru.EFEKT_SADE);
        assertEquals(TemaMotoru.EFEKT_SADE, TemaMotoru.efektYogunlugu(c));
        TemaMotoru.sahneNetlikSec(c, TemaMotoru.NETLIK_CANLI);
        assertEquals(TemaMotoru.NETLIK_CANLI, TemaMotoru.sahneNetlik(c));

        // 2. Vakitler ana ekranında GökYörünge, hızlı namaz çetelesi ve Mekke arka planı
        TemaMotoru.efektYogunluguSec(c, TemaMotoru.EFEKT_ZENGIN);
        DurumAktivitesi a = ac();
        bekle(700);
        assertFalse(bul(a.getWindow().getDecorView(), GokYorungeView.class).isEmpty());
        View hizliSabah = aciklamaIle(a.getWindow().getDecorView(), "Hızlı işaretle Sabah");
        assertNotNull(hizliSabah);
        int oncekiNamaz = NamazTakip.bugunTamamlanan(c);
        hizliSabah.performClick();
        bekle(250);
        assertTrue(NamazTakip.bugunTamamlanan(c) > oncekiNamaz);
        resim(a, "27_mekke_arka_plan");

        // 3. Huzur & Tefekkür modu açılış, nefes hâlesi zikir ve ambiyans geçişi
        a.bolumAc("huzur");
        bekle(900);
        List<HuzurModu.NefesHalesiView> haleler = bul(a.getWindow().getDecorView(), HuzurModu.NefesHalesiView.class);
        assertFalse(haleler.isEmpty());
        int oncekiZikir = new Zikir(c).gunluk();
        haleler.get(0).performClick();
        bekle(300);
        assertEquals(oncekiZikir + 1, new Zikir(c).gunluk());
        resim(a, "26_huzur_modu");

        // Tercihleri varsayılana döndür
        TemaMotoru.sabitArkaPlanSec(c, "");
        TemaMotoru.sahnePaketiSec(c, TemaMotoru.PAKET_KLASIK);
    }
}
