package com.mehmetderin.secde_vakti.saglik;

import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.media.AudioManager;
import android.os.Build;

/**
 * "Vakitte titreşime al": her namaz vakti girdiğinde (Güneş hariç) telefon zil modundaysa
 * titreşime alınır, seçilen süre sonra eski hâline döner. Kullanıcı arada zil modunu kendisi
 * değiştirdiyse dokunulmaz. Rahatsız Etmeyin izni gerektirmez (yalnız zil ↔ titreşim).
 */
public final class SessizMod {

    static final String ACIK = "sessiz_acik";
    static final String SURE_DK = "sessiz_sure_dk";
    private static final String BIZ_ALDIK = "sessiz_biz_aldik";
    private static final String BITIS = "sessiz_bitis_ms";

    public static final int[] SURELER = {10, 15, 20, 30, 45};

    private SessizMod() {}

    public static boolean acik(Context c) {
        return Tercihler.sp(c).getBoolean(ACIK, false);
    }

    public static int sure(Context c) {
        return Tercihler.sp(c).getInt(SURE_DK, 20);
    }

    public static void ayarla(Context c, boolean acik, int sureDk) {
        Tercihler.sp(c).edit().putBoolean(ACIK, acik).putInt(SURE_DK, sureDk).apply();
        planla(c);
        if (!acik) geriAl(c, true);
    }

    private static PendingIntent niyet(Context c, String eylem, int istek) {
        Intent i = new Intent(c, ZamanlayiciAlici.class).setAction(eylem);
        return PendingIntent.getBroadcast(c, istek, i, Kanallar.bayrak());
    }

    /** Bir sonraki namaz vaktine (Güneş hariç) titreşim alarmı kurar. */
    public static void planla(Context c) {
        try {
            AlarmManager am = (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
            if (am == null) return;
            PendingIntent pi = niyet(c, ZamanlayiciAlici.SESSIZ_BASLA, 0x5ec40);
            if (!acik(c)) {
                am.cancel(pi);
                return;
            }
            long simdi = System.currentTimeMillis();
            long hedef = 0;
            for (VakitTakvimi.An a : VakitTakvimi.oku(c).vakitler) {
                if (a.zaman > simdi + 1000 && !"sunrise".equals(a.namaz)) { hedef = a.zaman; break; }
            }
            if (hedef == 0) {
                am.cancel(pi);
                return;
            }
            if (Build.VERSION.SDK_INT < 31 || am.canScheduleExactAlarms()) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, hedef, pi);
            } else {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, hedef, pi);
            }
        } catch (Throwable ignored) {
        }
    }

    /** Vakit girdi: zil modundaysa titreşime al, geri dönüş alarmını kur. */
    static void basla(Context c) {
        try {
            if (!acik(c)) return;
            AudioManager ses = (AudioManager) c.getSystemService(Context.AUDIO_SERVICE);
            if (ses == null) return;
            if (ses.getRingerMode() != AudioManager.RINGER_MODE_NORMAL) return;
            ses.setRingerMode(AudioManager.RINGER_MODE_VIBRATE);
            long bitis = System.currentTimeMillis() + sure(c) * 60_000L;
            Tercihler.sp(c).edit().putBoolean(BIZ_ALDIK, true).putLong(BITIS, bitis).apply();

            AlarmManager am = (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
            PendingIntent pi = niyet(c, ZamanlayiciAlici.SESSIZ_BITIR, 0x5ec41);
            if (Build.VERSION.SDK_INT < 31 || am.canScheduleExactAlarms()) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, bitis, pi);
            } else {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, bitis, pi);
            }
            bildir(c, bitis);
        } catch (Throwable ignored) {
        } finally {
            planla(c);
        }
    }

    /** Süre doldu ya da kullanıcı "Şimdi aç" dedi: biz aldıysak ve hâlâ titreşimdeyse zile döndür. */
    static void geriAl(Context c, boolean kullanici) {
        try {
            boolean biz = Tercihler.sp(c).getBoolean(BIZ_ALDIK, false);
            Tercihler.sp(c).edit().putBoolean(BIZ_ALDIK, false).remove(BITIS).apply();
            NotificationManager nm = Kanallar.nm(c);
            if (nm != null) nm.cancel(Kanallar.BILDIRIM_SESSIZ);
            AlarmManager am = (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
            if (am != null) am.cancel(niyet(c, ZamanlayiciAlici.SESSIZ_BITIR, 0x5ec41));
            if (!biz) return;
            AudioManager ses = (AudioManager) c.getSystemService(Context.AUDIO_SERVICE);
            if (ses != null && ses.getRingerMode() == AudioManager.RINGER_MODE_VIBRATE) {
                ses.setRingerMode(AudioManager.RINGER_MODE_NORMAL);
            }
        } catch (Throwable ignored) {
        }
    }

    private static void bildir(Context c, long bitis) {
        NotificationManager nm = Kanallar.nm(c);
        if (nm == null) return;
        Kanallar.kur(c);
        Notification.Builder b = Build.VERSION.SDK_INT >= 26
                ? new Notification.Builder(c, Kanallar.SAYAC)
                : new Notification.Builder(c);
        Kanallar.kucukSimgeAta(b, c);
        b.setColor(Gorunum.bildirimRengi())
                .setContentTitle("Telefon titreşimde")
                .setContentText(Metinler.saat(bitis) + "'e kadar · namaz vakti")
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setWhen(bitis)
                .setUsesChronometer(true)
                .setChronometerCountDown(true)
                .setCategory(Notification.CATEGORY_STATUS)
                .addAction(new Notification.Action.Builder(null, "Zili şimdi aç",
                        niyet(c, ZamanlayiciAlici.SESSIZ_BITIR, 0x5ec42)).build());
        nm.notify(Kanallar.BILDIRIM_SESSIZ, b.build());
    }
}
