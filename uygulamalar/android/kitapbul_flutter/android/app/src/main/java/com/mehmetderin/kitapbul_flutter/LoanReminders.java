package com.mehmetderin.kitapbul_flutter;

import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

/**
 * Ödünç iade günü ve geciken kitap özeti bildirimleri. Liste Dart tarafından
 * `kitapbul/loan_reminders` kanalıyla yazılır; alarm ve teslim kayıtları SharedPreferences'tadır.
 */
final class LoanReminders {
    static final String CHANNEL = "loan_due";
    private static final String ACTION = "com.mehmetderin.kitapbul_flutter.LOAN_REMINDER";
    private static final String PREFS = "loan_reminders";
    private static final String TAG = "loan_due_summary";
    private static final int NOTIFICATION_ID = 7304;
    private static final String OVERDUE_TAG = "overdue_summary";
    private static final int OVERDUE_ID = 7305;
    private static final int FLAGS = PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE;

    private LoanReminders() {}

    private static String dateKey(long time) {
        return new SimpleDateFormat("yyyy-MM-dd", Locale.US).format(new Date(time));
    }

    private static List<Long> dueTimes(JSONArray items) throws JSONException {
        List<Long> out = new ArrayList<>(items.length());
        for (int i = 0; i < items.length(); i++) out.add(items.getJSONObject(i).getLong("due"));
        return out;
    }

    private static PendingIntent alarm(Context context) {
        Intent intent = new Intent(context, LoanReminderReceiver.class).setAction(ACTION);
        return PendingIntent.getBroadcast(context, NOTIFICATION_ID, intent, FLAGS);
    }

    static boolean isAlarm(Intent intent) {
        return ACTION.equals(intent.getAction());
    }

    static boolean allowed(Context context) {
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        if (Build.VERSION.SDK_INT >= 33
                && context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != 0) {
            return false;
        }
        if (!manager.areNotificationsEnabled()) return false;
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel channel = manager.getNotificationChannel(CHANNEL);
            if (channel != null && channel.getImportance() == NotificationManager.IMPORTANCE_NONE) return false;
        }
        return true;
    }

    static synchronized void replace(Context context, List<Map<String, Object>> items) throws JSONException {
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        JSONObject oldDelivered = new JSONObject(prefs.getString("delivered", "{}"));
        JSONArray next = new JSONArray();
        JSONObject delivered = new JSONObject();
        Set<String> ids = new HashSet<>();
        for (Map<String, Object> item : items) {
            Object idO = item.get("id");
            Object titleO = item.get("title");
            Object personO = item.get("person");
            Object dueO = item.get("due");
            if (!(idO instanceof String)) throw new IllegalArgumentException("Kimlik eksik");
            if (!(titleO instanceof String)) throw new IllegalArgumentException("Kitap eksik");
            if (!(personO instanceof String)) throw new IllegalArgumentException("Kişi eksik");
            if (!(dueO instanceof Number)) throw new IllegalArgumentException("Tarih eksik");
            String id = (String) idO;
            String title = (String) titleO;
            String person = (String) personO;
            long due = ((Number) dueO).longValue();
            if (id.trim().isEmpty() || id.length() > 1024 || title.length() > 1000 || person.length() > 1000
                    || !ids.add(id) || due <= 0) {
                throw new IllegalArgumentException("Hatırlatma kaydı geçersiz");
            }
            next.put(new JSONObject().put("id", id).put("title", title).put("person", person).put("due", due));
            if (oldDelivered.optLong(id, -1L) == due) delivered.put(id, due);
        }
        boolean changed = !next.toString().equals(prefs.getString("items", "[]"));
        if (changed) {
            NotificationManager manager = context.getSystemService(NotificationManager.class);
            manager.cancel(TAG, NOTIFICATION_ID);
            manager.cancel(OVERDUE_TAG, OVERDUE_ID);
        }
        SharedPreferences.Editor editor = prefs.edit()
                .putString("items", next.toString())
                .putString("delivered", delivered.toString());
        if (changed) editor.remove("summary_at");
        if (!editor.commit()) throw new IllegalStateException("Hatırlatmalar kaydedilemedi");
        schedule(context);
    }

    static synchronized void schedule(Context context) {
        try {
            SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
            JSONArray items = new JSONArray(prefs.getString("items", "[]"));
            JSONObject delivered = new JSONObject(prefs.getString("delivered", "{}"));
            long now = System.currentTimeMillis();
            boolean izin = allowed(context);
            Long next = null;
            for (int i = 0; i < items.length(); i++) {
                JSONObject item = items.getJSONObject(i);
                long due = item.getLong("due");
                if (delivered.optLong(item.getString("id"), -1L) != due && (due > now || izin)) {
                    long fire = Math.max(due, now + 5000L);
                    if (next == null || fire < next) next = fire;
                }
            }
            long previousSummary = prefs.getLong("summary_at", 0L);
            String lastSummaryDay = prefs.getString("summary_day", "");
            boolean preserve = izin && previousSummary > 0 && previousSummary <= now
                    && dateKey(previousSummary).equals(dateKey(now)) && !dateKey(now).equals(lastSummaryDay);
            Long summaryAt = preserve ? Long.valueOf(previousSummary) : OverdueSchedule.nextSummary(dueTimes(items), now);
            prefs.edit().putLong("summary_at", summaryAt != null ? summaryAt : 0L).commit();
            if (summaryAt != null && (summaryAt > now || izin)) {
                long fire = Math.max(summaryAt, now + 5000L);
                if (next == null || fire < next) next = fire;
            }
            AlarmManager manager = context.getSystemService(AlarmManager.class);
            PendingIntent pending = alarm(context);
            manager.cancel(pending);
            if (next != null) manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, pending);
        } catch (JSONException e) {
            // Bozuk kayıt: alarm kurulmaz, Dart bir sonraki eşitlemede listeyi yeniler.
        }
    }

    static synchronized void fire(Context context) throws JSONException {
        if (!allowed(context)) {
            schedule(context);
            return;
        }
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        JSONArray items = new JSONArray(prefs.getString("items", "[]"));
        JSONObject delivered = new JSONObject(prefs.getString("delivered", "{}"));
        long now = System.currentTimeMillis();
        List<JSONObject> due = new ArrayList<>();
        for (int i = 0; i < items.length(); i++) {
            JSONObject item = items.getJSONObject(i);
            if (item.getLong("due") <= now && delivered.optLong(item.getString("id"), -1L) != item.getLong("due")) {
                due.add(item);
            }
        }
        if (!due.isEmpty()) {
            String body = due.size() == 1
                    ? due.get(0).getString("title") + " — " + due.get(0).getString("person") + " iade etmeli."
                    : due.size() + " kitabın iade günü geldi. Ödünç listesinden inceleyin.";
            goster(context, TAG, NOTIFICATION_ID, "Kitap iade günü", body);
            for (JSONObject item : due) delivered.put(item.getString("id"), item.getLong("due"));
            prefs.edit().putString("delivered", delivered.toString()).commit();
        }
        long summaryAt = prefs.getLong("summary_at", 0L);
        String today = dateKey(now);
        if (summaryAt > 0 && summaryAt <= now && !today.equals(prefs.getString("summary_day", ""))) {
            int count = OverdueSchedule.overdueCount(dueTimes(items), now);
            if (count > 0) {
                goster(context, OVERDUE_TAG, OVERDUE_ID, "Geciken kitaplar",
                        count + " kitabın iade tarihi geçti. Kimlerde olduğunu Ödünç sekmesinde görebilirsiniz.");
            }
            prefs.edit().putString("summary_day", today).remove("summary_at").commit();
        }
        schedule(context);
    }

    private static void goster(Context context, String tag, int id, String title, String body) {
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(new NotificationChannel(CHANNEL, "İade hatırlatmaları",
                    NotificationManager.IMPORTANCE_DEFAULT));
        }
        Intent open = new Intent(context, MainActivity.class)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent launch = PendingIntent.getActivity(context, id, open, FLAGS);
        Notification.Builder b = Build.VERSION.SDK_INT >= 26
                ? new Notification.Builder(context, CHANNEL)
                : new Notification.Builder(context);
        manager.notify(tag, id, b.setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(new Notification.BigTextStyle().bigText(body))
                .setContentIntent(launch)
                .setAutoCancel(true)
                .build());
    }
}
