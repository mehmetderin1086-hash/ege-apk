package com.mehmetderin.secde_vakti.saglik;

import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.Date;
import java.util.Locale;

/** Türkçe adlar ve tarih/süre biçimleri. */
public final class Metinler {

    static final Locale TR = new Locale("tr", "TR");

    private Metinler() {}

    public static String namazAdi(String anahtar) {
        if (anahtar == null) return null;
        switch (anahtar) {
            case "fajr": return "İmsak";
            case "sunrise": return "Güneş";
            case "dhuhr": return "Öğle";
            case "asr": return "İkindi";
            case "maghrib": return "Akşam";
            case "isha": return "Yatsı";
            default: return null;
        }
    }

    public static String turAdi(String tur) {
        if (tur == null) return null;
        switch (tur) {
            case "main": return "Vakit";
            case "pre": return "Vakit öncesi";
            case "sahur": return "Sahur";
            case "iftar": return "İftar";
            case "friday": return "Cuma";
            case "holy": return "Mübarek gün";
            case "verse": return "Günün ayeti";
            default: return null;
        }
    }

    /** "İkindi" -> "İkindi'ye", "Akşam" -> "Akşam'a" (ünlü uyumuna göre yönelme eki). */
    public static String yonelme(String ad) {
        if (ad == null || ad.isEmpty()) return ad;
        String kucuk = ad.toLowerCase(TR);
        char sonUnlu = 0;
        for (int i = kucuk.length() - 1; i >= 0; i--) {
            char c = kucuk.charAt(i);
            if ("aeıioöuü".indexOf(c) >= 0) { sonUnlu = c; break; }
        }
        boolean ince = "eiöü".indexOf(sonUnlu) >= 0;
        char son = kucuk.charAt(kucuk.length() - 1);
        boolean unluyleBiter = "aeıioöuü".indexOf(son) >= 0;
        String ek = (unluyleBiter ? "y" : "") + (ince ? "e" : "a");
        return ad + "'" + ek;
    }

    public static String saat(long ms) {
        return new SimpleDateFormat("HH:mm", TR).format(new Date(ms));
    }

    /** "Bugün 15:42", "Yarın 05:10", "Cuma 13:05", "12 Aralık 18:10". */
    public static String gunVeSaat(long ms) {
        Calendar simdi = Calendar.getInstance();
        Calendar c = Calendar.getInstance();
        c.setTimeInMillis(ms);
        int gunFarki = gunFarki(simdi, c);
        String gun;
        if (gunFarki == 0) gun = "Bugün";
        else if (gunFarki == 1) gun = "Yarın";
        else if (gunFarki == -1) gun = "Dün";
        else if (gunFarki > 1 && gunFarki < 7) gun = new SimpleDateFormat("EEEE", TR).format(new Date(ms));
        else gun = new SimpleDateFormat("d MMMM", TR).format(new Date(ms));
        return gun + " " + saat(ms);
    }

    /** "22 Aralık" */
    public static String gunAy(long ms) {
        return new SimpleDateFormat("d MMMM", TR).format(new Date(ms));
    }

    public static String tarih(long ms) {
        return new SimpleDateFormat("d MMMM EEEE", TR).format(new Date(ms));
    }

    static int gunFarki(Calendar a, Calendar b) {
        Calendar x = (Calendar) a.clone();
        Calendar y = (Calendar) b.clone();
        for (Calendar k : new Calendar[]{x, y}) {
            k.set(Calendar.HOUR_OF_DAY, 12);
            k.set(Calendar.MINUTE, 0);
            k.set(Calendar.SECOND, 0);
            k.set(Calendar.MILLISECOND, 0);
        }
        return (int) Math.round((y.getTimeInMillis() - x.getTimeInMillis()) / 86_400_000.0);
    }

    /** Kalan süre: "2 sa 14 dk", "38 dk", "45 sn", "3 gün 2 sa". */
    public static String sure(long ms) {
        if (ms < 0) ms = 0;
        long sn = ms / 1000;
        long gun = sn / 86400;
        long sa = (sn % 86400) / 3600;
        long dk = (sn % 3600) / 60;
        if (gun > 0) return gun + " gün" + (sa > 0 ? " " + sa + " sa" : "");
        if (sa > 0) return sa + " sa" + (dk > 0 ? " " + dk + " dk" : "");
        if (dk > 0) return dk + " dk";
        return (sn % 60) + " sn";
    }

    /** Sayaç gösterimi: "01:14:05". */
    public static String sayac(long ms) {
        if (ms < 0) ms = 0;
        long sn = ms / 1000;
        return String.format(Locale.ROOT, "%02d:%02d:%02d", sn / 3600, (sn % 3600) / 60, sn % 60);
    }
}
