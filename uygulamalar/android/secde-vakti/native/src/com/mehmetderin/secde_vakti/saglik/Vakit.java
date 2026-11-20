package com.mehmetderin.secde_vakti.saglik;

/** flutter_local_notifications kaydından okunan, kurulmuş tek bir bildirim. */
public final class Vakit implements Comparable<Vakit> {

    public final int id;
    public final String baslik;
    public final String metin;
    /** Dart planındaki tür: main, pre, sahur, iftar, friday, holy, verse. */
    public final String tur;
    /** Namaz adı (fajr, sunrise, dhuhr, asr, maghrib, isha) ya da null. */
    public final String namaz;
    public final String kanal;
    /** Bir sonraki çalma anı (epoch ms). */
    public final long zaman;
    public final boolean tekrarli;

    Vakit(int id, String baslik, String metin, String tur, String namaz, String kanal, long zaman, boolean tekrarli) {
        this.id = id;
        this.baslik = baslik == null ? "" : baslik;
        this.metin = metin == null ? "" : metin;
        this.tur = tur == null ? "" : tur;
        this.namaz = namaz;
        this.kanal = kanal;
        this.zaman = zaman;
        this.tekrarli = tekrarli;
    }

    public boolean vakitBildirimi() {
        return "main".equals(tur);
    }

    /** Ekranda gösterilecek kısa ad: "İkindi", "Sahur", "Cuma"... */
    public String kisaAd() {
        if (namaz != null && ("main".equals(tur) || "pre".equals(tur))) {
            String ad = Metinler.namazAdi(namaz);
            if (ad != null) return "pre".equals(tur) ? ad + " (önce)" : ad;
        }
        String t = Metinler.turAdi(tur);
        return t != null ? t : (baslik.isEmpty() ? "Bildirim" : baslik);
    }

    @Override
    public int compareTo(Vakit o) {
        return Long.compare(zaman, o.zaman);
    }
}
