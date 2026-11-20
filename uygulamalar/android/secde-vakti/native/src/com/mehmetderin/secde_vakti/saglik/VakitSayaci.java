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
 * İsteğe bağlı, kalıcı "Vakit Sayacı" bildirimi: sıradaki vakte geri sayım ve günün
 * vakitleri. Vakit önbelleğini (VakitTakvimi) kullanır; yoksa kurulu bildirimlere düşer.
 * Vakit girdiğinde AlarmManager ile kendini yeniler.
 */
public final class VakitSayaci {

    private VakitSayaci() {}

    /** Sıradaki vakit: önce takvim, yoksa bildirim kaydı. {namazAnahtari, zaman} ya da null. */
    static Object[] sonraki(Context c) {
        VakitTakvimi.Takvim t = VakitTakvimi.oku(c);
        VakitTakvimi.An a = t.sonraki();
        if (a != null) return new Object[]{a.namaz, a.zaman};
        Vakit v = VakitDeposu.sonrakiVakit(c);
        if (v != null) return new Object[]{v.namaz, v.zaman};
        return null;
    }

    public static void guncelle(Context c) {
        try {
            guncelleIc(c);
        } catch (Throwable ignored) {
        }
    }

    private static void guncelleIc(Context c) {
        NotificationManager nm = Kanallar.nm(c);
        if (nm == null) return;
        if (!Tercihler.sayacAcik(c)) {
            nm.cancel(Kanallar.BILDIRIM_SAYAC);
            alarmIptal(c);
            return;
        }
        Kanallar.kur(c);

        VakitTakvimi.Takvim takvim = VakitTakvimi.oku(c);
        VakitTakvimi.An siradaki = takvim.sonraki();
        String anahtar = null;
        long zaman = 0;
        if (siradaki != null) {
            anahtar = siradaki.namaz;
            zaman = siradaki.zaman;
        } else {
            Vakit v = VakitDeposu.sonrakiVakit(c);
            if (v != null) { anahtar = v.namaz; zaman = v.zaman; }
        }

        Notification.Builder b = Build.VERSION.SDK_INT >= 26
                ? new Notification.Builder(c, Kanallar.SAYAC)
                : new Notification.Builder(c);
        Kanallar.kucukSimgeAta(b, c);
        b.setColor(Gorunum.bildirimRengi())
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setShowWhen(true)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setCategory(Notification.CATEGORY_STATUS);
        PendingIntent ac = Kanallar.durumEkrani(c, 0x5ec01);
        if (ac != null) b.setContentIntent(ac);
        if (Build.VERSION.SDK_INT < 26) b.setPriority(Notification.PRIORITY_LOW);

        if (zaman == 0) {
            b.setContentTitle("Vakit bilgisi yok")
                    .setContentText("Dokunup uygulamayı açın; vakitler yeniden yüklenir.");
            PendingIntent yk = Kanallar.yenidenKur(c, 0x5ec02);
            if (yk != null) b.setContentIntent(yk);
            nm.notify(Kanallar.BILDIRIM_SAYAC, b.build());
            alarmIptal(c);
            return;
        }

        String ad = Metinler.namazAdi(anahtar);
        if (ad == null) ad = "Sıradaki vakit";
        b.setContentTitle(Metinler.yonelme(ad) + " kalan")
                .setContentText(ad + " " + Metinler.saat(zaman) + (takvim.yer != null ? " · " + takvim.yer : ""))
                .setWhen(zaman)
                .setUsesChronometer(true)
                .setChronometerCountDown(true);

        String gun = gununVakitleri(takvim);
        if (gun != null) b.setStyle(new Notification.BigTextStyle().bigText(gun));
        b.addAction(new Notification.Action.Builder(null, "Vakitler", Kanallar.durumEkrani(c, 0x5ec03)).build());
        nm.notify(Kanallar.BILDIRIM_SAYAC, b.build());

        alarmKur(c, zaman + 1500);
    }

    /** "İmsak 05:48 · Güneş 07:14 · Öğle 12:24 · ▸İkindi 15:00 · Akşam 17:23 · Yatsı 18:44" */
    private static String gununVakitleri(VakitTakvimi.Takvim t) {
        List<VakitTakvimi.An> bugun = t.bugun();
        if (bugun.isEmpty()) return null;
        VakitTakvimi.An siradaki = t.sonraki();
        StringBuilder sb = new StringBuilder();
        for (VakitTakvimi.An a : bugun) {
            if (sb.length() > 0) sb.append(" · ");
            if (siradaki != null && a.zaman == siradaki.zaman) sb.append('▸');
            sb.append(a.ad()).append(' ').append(Metinler.saat(a.zaman));
        }
        if (t.hicri != null) sb.append('\n').append(t.hicri);
        return sb.toString();
    }

    private static PendingIntent alarmNiyeti(Context c) {
        Intent i = new Intent(c, ZamanlayiciAlici.class).setAction(ZamanlayiciAlici.SAYAC_YENILE);
        return PendingIntent.getBroadcast(c, 0x5ec10, i, Kanallar.bayrak());
    }

    private static void alarmKur(Context c, long zaman) {
        AlarmManager am = (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
        if (am == null) return;
        PendingIntent pi = alarmNiyeti(c);
        try {
            if (Build.VERSION.SDK_INT < 31 || am.canScheduleExactAlarms()) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, zaman, pi);
            } else {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, zaman, pi);
            }
        } catch (Throwable t) {
            am.set(AlarmManager.RTC, zaman, pi);
        }
    }

    private static void alarmIptal(Context c) {
        AlarmManager am = (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
        if (am != null) am.cancel(alarmNiyeti(c));
    }
}
