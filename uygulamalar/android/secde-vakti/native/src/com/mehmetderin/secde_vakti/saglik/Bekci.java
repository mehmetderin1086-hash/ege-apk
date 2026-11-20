package com.mehmetderin.secde_vakti.saglik;

import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.os.Build;

import java.util.List;

/**
 * Bildirim bekçisi: günde iki kez (ve telefon açılınca) kurulu vakit bildirimlerini sayar.
 * Hiç kalmamışsa ya da 36 saat içinde bitecekse kullanıcıyı uyarır; dokununca uygulama
 * baştan açılır ve Dart tarafı bildirimleri yeniden kurar.
 */
public final class Bekci {

    private static final long KONTROL_ARALIGI_MS = 12L * 60 * 60 * 1000;
    private static final long UYARI_ARALIGI_MS = 20L * 60 * 60 * 1000;
    private static final long BITIS_ESIGI_MS = 36L * 60 * 60 * 1000;

    private Bekci() {}

    /** Bir sonraki denetimi kurar (eşzamanlı alarm gerekmez). */
    public static void planla(Context c) {
        try {
            AlarmManager am = (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
            if (am == null) return;
            Intent i = new Intent(c, ZamanlayiciAlici.class).setAction(ZamanlayiciAlici.BEKCI);
            PendingIntent pi = PendingIntent.getBroadcast(c, 0x5ec20, i, Kanallar.bayrak());
            long zaman = System.currentTimeMillis() + KONTROL_ARALIGI_MS;
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, zaman, pi);
        } catch (Throwable ignored) {
        }
    }

    public static void kontrol(Context c) {
        try {
            kontrolIc(c);
        } catch (Throwable ignored) {
        }
    }

    /** Ekranda gösterilecek bekçi teşhisi; sorun yoksa null. */
    public static String teshis(Context c, List<Vakit> gelecek) {
        if (!BildirimKontrol.kurulumTamam(c)) return null;
        long simdi = System.currentTimeMillis();
        int vakitSayisi = VakitDeposu.say(gelecek, "main");
        if (vakitSayisi == 0) {
            return "Kurulu vakit bildirimi yok. Uygulamayı açınca yeniden kurulur.";
        }
        long son = VakitDeposu.sonVakitZamani(gelecek);
        if (son > 0 && son - simdi < BITIS_ESIGI_MS) {
            return "Vakit bildirimleri " + Metinler.gunVeSaat(son) + " sonrasında bitiyor. Arka plan yenilemesi çalışmamış olabilir.";
        }
        return null;
    }

    private static void kontrolIc(Context c) {
        Tercihler.sp(c).edit().putLong(Tercihler.SON_BEKCI_KONTROL, System.currentTimeMillis()).apply();
        NotificationManager nm = Kanallar.nm(c);
        if (nm == null) return;
        if (!Tercihler.bekciAcik(c)) {
            nm.cancel(Kanallar.BILDIRIM_BEKCI);
            return;
        }
        String sorun = teshis(c, VakitDeposu.gelecek(c));
        if (sorun == null) {
            nm.cancel(Kanallar.BILDIRIM_BEKCI);
            return;
        }
        long simdi = System.currentTimeMillis();
        long son = Tercihler.sp(c).getLong(Tercihler.SON_BEKCI_UYARI, 0);
        if (simdi - son < UYARI_ARALIGI_MS && simdi >= son) return;
        Tercihler.sp(c).edit().putLong(Tercihler.SON_BEKCI_UYARI, simdi).apply();

        Kanallar.kur(c);
        Notification.Builder b = Build.VERSION.SDK_INT >= 26
                ? new Notification.Builder(c, Kanallar.BEKCI)
                : new Notification.Builder(c);
        Kanallar.kucukSimgeAta(b, c);
        b.setColor(Gorunum.bildirimRengi())
                .setContentTitle("Vakit bildirimleri yenilenmeli")
                .setContentText(sorun)
                .setStyle(new Notification.BigTextStyle().bigText(sorun + "\n\nDokunun, Secde Vakti açılıp bildirimleri yeniden kursun."))
                .setAutoCancel(true)
                .setCategory(Notification.CATEGORY_REMINDER);
        PendingIntent yk = Kanallar.yenidenKur(c, 0x5ec21);
        if (yk != null) b.setContentIntent(yk);
        b.addAction(new Notification.Action.Builder(null, "Vakitler", Kanallar.durumEkrani(c, 0x5ec22)).build());
        nm.notify(Kanallar.BILDIRIM_BEKCI, b.build());
    }
}
