package com.mehmetderin.secde_vakti.saglik;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;

/** BildirimKontrol.testPlanla'nın kurduğu alarm çalınca test bildirimini gösterir. */
public final class TestAlarmAlici extends BroadcastReceiver {

    static final String EYLEM = "com.mehmetderin.secde_vakti.TEST_BILDIRIMI";

    @Override
    public void onReceive(Context c, Intent intent) {
        if (intent == null || !EYLEM.equals(intent.getAction())) return;
        goster(c, true);
    }

    /**
     * Test bildirimini gösterir. Vakit bildirimlerinin kullandığı ezan kanalı açıksa onu
     * kullanır; böylece test, gerçek ezan bildirimiyle aynı kanal ayarlarından geçer.
     */
    static void goster(Context c, boolean alarmdan) {
        try {
            NotificationManager nm = Kanallar.nm(c);
            if (nm == null) return;
            Kanallar.kur(c);

            String kanal = Kanallar.TEST;
            if (Build.VERSION.SDK_INT >= 26) {
                NotificationChannel ezan = nm.getNotificationChannel("sekine_alarm_default");
                if (ezan != null && ezan.getImportance() != NotificationManager.IMPORTANCE_NONE) {
                    kanal = ezan.getId();
                }
            }

            String saat = Metinler.saat(System.currentTimeMillis());
            String kisa = alarmdan
                    ? "Zamanlanmış test çalıştı. Ezan ve vakit uyarıları da bu yoldan gelir."
                    : "Anında test. Bildirim izni ve kanal açık.";
            String uzun = alarmdan
                    ? "Zamanlanmış test bildirimi zamanında geldi: alarm izni, pil ayarı ve bildirim kanalı çalışıyor. "
                    + "Vakit bildirimleri de bu yoldan (AlarmManager) gelir."
                    : "Bu bildirim anında gönderildi; yalnızca bildirim izni ve kanalın açık olduğunu gösterir. "
                    + "Telefon kilitliyken gelip gelmediğini görmek için \"1 dakika sonra\" testini kullanın.";

            Notification.Builder b = Build.VERSION.SDK_INT >= 26
                    ? new Notification.Builder(c, kanal)
                    : new Notification.Builder(c);
            Kanallar.kucukSimgeAta(b, c);
            b.setColor(Gorunum.bildirimRengi())
                    .setContentTitle("Test bildirimi (" + saat + ")")
                    .setContentText(kisa)
                    .setStyle(new Notification.BigTextStyle().bigText(uzun))
                    .setAutoCancel(true)
                    .setCategory(Notification.CATEGORY_REMINDER);
            PendingIntent ac = Kanallar.durumEkrani(c, 0x5ecdf);
            if (ac != null) b.setContentIntent(ac);
            if (Build.VERSION.SDK_INT < 26) {
                b.setPriority(Notification.PRIORITY_HIGH).setDefaults(Notification.DEFAULT_ALL);
            }
            nm.notify(Kanallar.BILDIRIM_TEST, b.build());

            if (alarmdan) {
                Tercihler.sp(c).edit().putLong("son_test_basarili_ms", System.currentTimeMillis()).apply();
            }
        } catch (Throwable ignored) {
        }
    }
}
