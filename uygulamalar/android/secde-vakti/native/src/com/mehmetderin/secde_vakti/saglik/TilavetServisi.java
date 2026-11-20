package com.mehmetderin.secde_vakti.saglik;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.media.AudioAttributes;
import android.media.MediaPlayer;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.PowerManager;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * Tilavet ve sesli meal çalar (ön plan servisi): telefon kilitliyken de çalar.
 * Kuyruk: ayet ayet tilavet (her ayet ayrı dosya) ya da tek parça (sure meali).
 * Bildirimde Duraklat / Sonraki / Durdur. Ekranlar {@link #dinleyici} ile çalınan ayeti izler.
 */
public final class TilavetServisi extends Service {

    public static final class Parca {
        public final String adres, baslik;
        public final int sure, ayet;

        public Parca(String adres, String baslik, int sure, int ayet) {
            this.adres = adres;
            this.baslik = baslik;
            this.sure = sure;
            this.ayet = ayet;
        }
    }

    public interface Dinleyici {
        void degisti();
    }

    static final String BASLAT = "secde.tilavet.BASLAT";
    static final String DURAKLAT = "secde.tilavet.DURAKLAT";
    static final String SONRAKI = "secde.tilavet.SONRAKI";
    static final String DURDUR = "secde.tilavet.DURDUR";
    private static final String KANAL = "secde_tilavet";
    private static final int BILDIRIM = 0x5ecd5;

    // Durum (aynı süreçte ekranlarla paylaşılır)
    private static List<Parca> kuyruk = Collections.emptyList();
    private static int sira = -1;
    private static boolean caliyor, hazirlaniyor;
    private static String ustBaslik = "";
    private static String hata;
    public static Dinleyici dinleyici;

    private MediaPlayer oynatici;
    private final Handler ana = new Handler(Looper.getMainLooper());

    /** Ayet ayet tilavet kuyruğu: sure içinde baştan ya da verilen ayetten. */
    public static List<Parca> tilavetKuyrugu(Kuran.Sure s, int basAyet, String hafiz) {
        List<Parca> l = new ArrayList<>();
        for (int a = Math.max(1, basAyet); a <= s.ayetSayisi; a++) {
            l.add(new Parca(Kuran.ayetSesi(hafiz, s.no, a), s.ad + " " + a, s.no, a));
        }
        return l;
    }

    public static void baslat(Context c, List<Parca> k, String baslik) {
        kuyruk = new ArrayList<>(k);
        sira = 0;
        ustBaslik = baslik;
        hata = null;
        caliyor = true;
        bildir();
        Intent i = new Intent(c, TilavetServisi.class).setAction(BASLAT);
        try {
            if (Build.VERSION.SDK_INT >= 26) c.startForegroundService(i);
            else c.startService(i);
        } catch (Throwable t) {
            hata = "Çalma başlatılamadı";
            caliyor = false;
            bildir();
        }
    }

    public static void komut(Context c, String eylem) {
        try {
            c.startService(new Intent(c, TilavetServisi.class).setAction(eylem));
        } catch (Throwable ignored) {
        }
    }

    public static Parca simdiki() {
        return sira >= 0 && sira < kuyruk.size() ? kuyruk.get(sira) : null;
    }

    public static boolean caliyor() {
        return caliyor;
    }

    public static boolean aktif() {
        return simdiki() != null;
    }

    public static boolean hazirlaniyor() {
        return hazirlaniyor;
    }

    public static String baslik() {
        return ustBaslik;
    }

    public static String hata() {
        return hata;
    }

    public static List<Parca> kuyruk() {
        return Collections.unmodifiableList(kuyruk);
    }

    private static void bildir() {
        final Dinleyici d = dinleyici;
        if (d != null) new Handler(Looper.getMainLooper()).post(d::degisti);
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String e = intent == null ? null : intent.getAction();
        onPlana();
        // Süreç yeniden başladıysa (kuyruk boş) bildirim düğmeleri boş bir bildirim bırakmasın
        if (!BASLAT.equals(e) && simdiki() == null) {
            bitir();
            return START_NOT_STICKY;
        }
        if (BASLAT.equals(e)) {
            cal();
        } else if (DURAKLAT.equals(e)) {
            try {
                if (oynatici != null && caliyor && !hazirlaniyor) {
                    oynatici.pause();
                    caliyor = false;
                } else if (!caliyor && (oynatici == null || hata != null)) {
                    // Hata sonrası "Devam": oynatıcı geçersiz durumda; aynı parçayı baştan dene
                    cal();
                    return START_NOT_STICKY;
                } else if (oynatici != null && !caliyor) {
                    oynatici.start();
                    caliyor = true;
                }
            } catch (Throwable t) {
                // Geçersiz durumdaki MediaPlayer çağrısı servisi çökertmesin
                cal();
                return START_NOT_STICKY;
            }
            bildirimGuncelle();
            bildir();
        } else if (SONRAKI.equals(e)) {
            sonraki();
        } else if (DURDUR.equals(e)) {
            bitir();
        }
        return START_NOT_STICKY;
    }

    private void cal() {
        birak();
        Parca p = simdiki();
        if (p == null) {
            bitir();
            return;
        }
        hazirlaniyor = true;
        caliyor = true;
        bildirimGuncelle();
        bildir();
        try {
            oynatici = new MediaPlayer();
            oynatici.setAudioAttributes(new AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build());
            oynatici.setWakeMode(this, PowerManager.PARTIAL_WAKE_LOCK);
            oynatici.setDataSource(p.adres);
            oynatici.setOnPreparedListener(m -> {
                hazirlaniyor = false;
                hata = null;
                m.start();
                bildirimGuncelle();
                bildir();
            });
            oynatici.setOnCompletionListener(m -> sonraki());
            oynatici.setOnErrorListener((m, w, x) -> {
                hazirlaniyor = false;
                caliyor = false;
                hata = "Ses açılamadı. İnternet bağlantısını kontrol edin.";
                bildirimGuncelle();
                bildir();
                return true;
            });
            oynatici.prepareAsync();
        } catch (Throwable t) {
            hazirlaniyor = false;
            caliyor = false;
            hata = "Ses açılamadı.";
            bildirimGuncelle();
            bildir();
        }
    }

    private void sonraki() {
        if (sira + 1 < kuyruk.size()) {
            sira++;
            cal();
        } else {
            bitir();
        }
    }

    private void bitir() {
        birak();
        caliyor = false;
        hazirlaniyor = false;
        sira = -1;
        kuyruk = Collections.emptyList();
        bildir();
        if (Build.VERSION.SDK_INT >= 24) stopForeground(STOP_FOREGROUND_REMOVE);
        stopSelf();
    }

    private void birak() {
        if (oynatici != null) {
            try {
                oynatici.release();
            } catch (Throwable ignored) {
            }
            oynatici = null;
        }
    }

    @Override
    public void onDestroy() {
        birak();
        super.onDestroy();
    }

    private void onPlana() {
        Notification n = bildirim();
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(BILDIRIM, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK);
            } else {
                startForeground(BILDIRIM, n);
            }
        } catch (Throwable t) {
            // Ön plan izni yoksa yine de çalmayı dener (ekran açıkken çalışır)
            NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
            if (nm != null) nm.notify(BILDIRIM, n);
        }
    }

    private void bildirimGuncelle() {
        NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        if (nm != null && aktif()) nm.notify(BILDIRIM, bildirim());
    }

    private PendingIntent eylem(String e, int istek) {
        return PendingIntent.getService(this, istek, new Intent(this, TilavetServisi.class).setAction(e), Kanallar.bayrak());
    }

    private Notification bildirim() {
        NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        if (Build.VERSION.SDK_INT >= 26 && nm != null && nm.getNotificationChannel(KANAL) == null) {
            NotificationChannel k = new NotificationChannel(KANAL, "Tilavet ve meal", NotificationManager.IMPORTANCE_LOW);
            k.setDescription("Kur'an tilaveti ve sesli meal çalarken gösterilir");
            k.setShowBadge(false);
            nm.createNotificationChannel(k);
        }
        Parca p = simdiki();
        Notification.Builder b = Build.VERSION.SDK_INT >= 26 ? new Notification.Builder(this, KANAL) : new Notification.Builder(this);
        Intent ac = new Intent(this, DurumAktivitesi.class).setAction(Intent.ACTION_VIEW)
                .putExtra(DurumAktivitesi.EK_SEKME, 1).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        Kanallar.kucukSimgeAta(b, this);
        b.setColor(Gorunum.bildirimRengi())
                .setContentTitle(p == null ? "Tilavet" : p.baslik)
                .setContentText(hata != null ? hata : hazirlaniyor ? "Yükleniyor… · " + ustBaslik : ustBaslik)
                .setOngoing(caliyor)
                .setOnlyAlertOnce(true)
                .setShowWhen(false)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setContentIntent(PendingIntent.getActivity(this, 0x5ec50, ac, Kanallar.bayrak()))
                .addAction(new Notification.Action.Builder(null, caliyor ? "Duraklat" : "Devam", eylem(DURAKLAT, 0x5ec51)).build())
                .addAction(new Notification.Action.Builder(null, "Sonraki", eylem(SONRAKI, 0x5ec52)).build())
                .addAction(new Notification.Action.Builder(null, "Durdur", eylem(DURDUR, 0x5ec53)).build());
        if (Build.VERSION.SDK_INT >= 24) b.setStyle(new Notification.MediaStyle().setShowActionsInCompactView(0, 1, 2));
        return b.build();
    }
}
