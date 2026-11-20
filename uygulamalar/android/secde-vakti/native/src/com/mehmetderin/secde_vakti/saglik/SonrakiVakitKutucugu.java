package com.mehmetderin.secde_vakti.saglik;

import android.app.PendingIntent;
import android.content.Intent;
import android.graphics.drawable.Icon;
import android.os.Build;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;

/**
 * Hızlı Ayarlar kutucuğu: bir sonraki vakti ve kalan süreyi gösterir,
 * dokununca bildirim durum ekranını açar.
 */
public final class SonrakiVakitKutucugu extends TileService {

    @Override
    public void onStartListening() {
        super.onStartListening();
        try {
            guncelle();
        } catch (Throwable ignored) {
        }
    }

    @Override
    public void onTileAdded() {
        super.onTileAdded();
        try {
            guncelle();
        } catch (Throwable ignored) {
        }
    }

    private void guncelle() {
        Tile t = getQsTile();
        if (t == null) return;
        Object[] v = VakitSayaci.sonraki(this);
        t.setIcon(Icon.createWithResource(this, android.R.drawable.ic_lock_idle_alarm));
        if (v == null) {
            t.setLabel("Vakit yok");
            if (Build.VERSION.SDK_INT >= 29) t.setSubtitle("Uygulamayı açın");
            t.setState(Tile.STATE_INACTIVE);
        } else {
            String ad = Metinler.namazAdi((String) v[0]);
            if (ad == null) ad = "Sıradaki vakit";
            long zaman = (Long) v[1];
            String kalan = Metinler.sure(zaman - System.currentTimeMillis());
            if (Build.VERSION.SDK_INT >= 29) {
                t.setLabel(ad + " " + Metinler.saat(zaman));
                t.setSubtitle(kalan + " kaldı");
            } else {
                t.setLabel(ad + " " + Metinler.saat(zaman) + " · " + kalan);
            }
            t.setState(Tile.STATE_ACTIVE);
        }
        t.updateTile();
    }

    @Override
    public void onClick() {
        super.onClick();
        try {
            Intent i = new Intent(this, DurumAktivitesi.class).setAction(Intent.ACTION_VIEW)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
            if (Build.VERSION.SDK_INT >= 34) {
                startActivityAndCollapse(PendingIntent.getActivity(this, 0x5ec30, i, Kanallar.bayrak()));
            } else {
                startActivityAndCollapse(i);
            }
        } catch (Throwable ignored) {
        }
    }
}
