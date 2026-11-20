package com.mehmetderin.kitapbul_flutter;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Telefon yeniden başladığında veya uygulama güncellendiğinde alarmı yeniden kurar. */
public final class LoanReminderBootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        if (Intent.ACTION_BOOT_COMPLETED.equals(action) || Intent.ACTION_MY_PACKAGE_REPLACED.equals(action)) {
            try {
                LoanReminders.schedule(context);
            } catch (Exception ignored) {
                // Bir sonraki açılışta yeniden denenir.
            }
        }
    }
}
