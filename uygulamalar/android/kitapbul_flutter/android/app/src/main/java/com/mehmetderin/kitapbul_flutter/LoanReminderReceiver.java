package com.mehmetderin.kitapbul_flutter;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** İade hatırlatma alarmı geldiğinde bildirimleri gösterir. */
public final class LoanReminderReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (LoanReminders.isAlarm(intent)) {
            try {
                LoanReminders.fire(context);
            } catch (Exception ignored) {
                // Bozuk kayıt alıcıyı çökertmesin; uygulama açılınca liste yeniden yazılır.
            }
        }
    }
}
