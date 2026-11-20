package com.mehmetderin.secde_vakti.saglik;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.PorterDuff;
import android.graphics.PorterDuffXfermode;
import android.graphics.drawable.Icon;
import android.os.Build;

/** Android katmanının bildirim kanalları ve ortak PendingIntent'ler. */
final class Kanallar {

    static final String SAYAC = "secde_sayac";
    static final String BEKCI = "secde_bekci";
    static final String TEST = "secde_test";

    static final int BILDIRIM_SAYAC = 0x5ecd1;
    static final int BILDIRIM_BEKCI = 0x5ecd2;
    static final int BILDIRIM_TEST = 0x5ecde;
    static final int BILDIRIM_SESSIZ = 0x5ecd3;

    private Kanallar() {}

    static NotificationManager nm(Context c) {
        return (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
    }

    static void kur(Context c) {
        if (Build.VERSION.SDK_INT < 26) return;
        NotificationManager nm = nm(c);
        if (nm == null) return;
        try {
            NotificationChannel sayac = new NotificationChannel(SAYAC, "Vakit Sayacı", NotificationManager.IMPORTANCE_LOW);
            sayac.setDescription("Bir sonraki vakte kalan süreyi gösteren sessiz, kalıcı bildirim");
            sayac.setShowBadge(false);
            sayac.setSound(null, null);
            sayac.enableVibration(false);
            nm.createNotificationChannel(sayac);

            NotificationChannel bekci = new NotificationChannel(BEKCI, "Bildirim Bekçisi", NotificationManager.IMPORTANCE_DEFAULT);
            bekci.setDescription("Vakit bildirimleri kurulu değilse ya da bitmek üzereyse uyarır");
            nm.createNotificationChannel(bekci);

            NotificationChannel test = new NotificationChannel(TEST, "Bildirim Testi", NotificationManager.IMPORTANCE_HIGH);
            test.setDescription("Bildirim ayarlarını denemek için gönderilen test bildirimi");
            nm.createNotificationChannel(test);
        } catch (Throwable ignored) {
        }
    }

    static int bayrak() {
        return PendingIntent.FLAG_UPDATE_CURRENT | (Build.VERSION.SDK_INT >= 23 ? PendingIntent.FLAG_IMMUTABLE : 0);
    }

    /** Uygulamayı doğrudan güncel DurumAktivitesi ile açan PendingIntent. */
    static PendingIntent uygulamayiAc(Context c, int istek) {
        return durumEkrani(c, istek);
    }

    /** Vakit takvimi ve bildirimleri yerel motordan tazeleyerek DurumAktivitesi'ni açan PendingIntent. */
    static PendingIntent yenidenKur(Context c, int istek) {
        Intent i = new Intent(c, DurumAktivitesi.class)
                .setAction(Intent.ACTION_VIEW)
                .putExtra(DurumAktivitesi.EK_YENIDEN_KUR, true)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        return PendingIntent.getActivity(c, istek, i, bayrak());
    }

    static PendingIntent durumEkrani(Context c, int istek) {
        Intent i = new Intent(c, DurumAktivitesi.class)
                .setAction(Intent.ACTION_VIEW)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        return PendingIntent.getActivity(c, istek, i, bayrak());
    }

    private static Icon durumCubuguHilal;

    static int kucukSimge(Context c) {
        int s = c.getApplicationInfo().icon;
        return s != 0 ? s : android.R.drawable.ic_lock_idle_alarm;
    }

    /** Durum çubuğunda düz kare yerine keskin hilal-yıldız silüeti gösterir. */
    static void kucukSimgeAta(Notification.Builder b, Context c) {
        if (Build.VERSION.SDK_INT >= 23) {
            try {
                if (durumCubuguHilal == null) {
                    durumCubuguHilal = Icon.createWithBitmap(hilalYildizBitmap());
                }
                b.setSmallIcon(durumCubuguHilal);
                return;
            } catch (Throwable ignored) {
            }
        }
        b.setSmallIcon(kucukSimge(c));
    }

    private static Bitmap hilalYildizBitmap() {
        int n = 72;
        Bitmap bmp = Bitmap.createBitmap(n, n, Bitmap.Config.ARGB_8888);
        Canvas cv = new Canvas(bmp);
        Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
        p.setColor(Color.WHITE);
        p.setStyle(Paint.Style.FILL);
        cv.drawCircle(n * 0.46f, n * 0.50f, n * 0.36f, p);
        Paint sil = new Paint(Paint.ANTI_ALIAS_FLAG);
        sil.setXfermode(new PorterDuffXfermode(PorterDuff.Mode.CLEAR));
        cv.drawCircle(n * 0.58f, n * 0.44f, n * 0.29f, sil);

        Path yildiz = new Path();
        float cx = n * 0.68f, cy = n * 0.38f, disR = n * 0.13f, icR = n * 0.055f;
        for (int i = 0; i < 10; i++) {
            double aci = Math.toRadians(-90 + i * 36.0);
            float r = (i % 2 == 0) ? disR : icR;
            float x = cx + (float) (Math.cos(aci) * r);
            float y = cy + (float) (Math.sin(aci) * r);
            if (i == 0) yildiz.moveTo(x, y);
            else yildiz.lineTo(x, y);
        }
        yildiz.close();
        cv.drawPath(yildiz, p);
        return bmp;
    }
}
