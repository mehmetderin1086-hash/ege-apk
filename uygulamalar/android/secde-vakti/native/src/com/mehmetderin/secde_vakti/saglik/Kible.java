package com.mehmetderin.secde_vakti.saglik;

/** Kâbe yönü (kuzeyden saat yönünde derece) ve büyük çember uzaklığı. */
public final class Kible {

    public static final double KABE_ENLEM = 21.422487;
    public static final double KABE_BOYLAM = 39.826206;

    private Kible() {}

    /** Verilen konumdan Kâbe'ye başlangıç yönü, 0..360 derece. */
    public static double yon(double enlem, double boylam) {
        double f1 = Math.toRadians(enlem), f2 = Math.toRadians(KABE_ENLEM);
        double dl = Math.toRadians(KABE_BOYLAM - boylam);
        double y = Math.sin(dl) * Math.cos(f2);
        double x = Math.cos(f1) * Math.sin(f2) - Math.sin(f1) * Math.cos(f2) * Math.cos(dl);
        double d = Math.toDegrees(Math.atan2(y, x));
        return (d + 360) % 360;
    }

    /** Kâbe'ye uzaklık, km (haversine). */
    public static double uzaklikKm(double enlem, double boylam) {
        double f1 = Math.toRadians(enlem), f2 = Math.toRadians(KABE_ENLEM);
        double df = f2 - f1, dl = Math.toRadians(KABE_BOYLAM - boylam);
        double a = Math.sin(df / 2) * Math.sin(df / 2) + Math.cos(f1) * Math.cos(f2) * Math.sin(dl / 2) * Math.sin(dl / 2);
        return 6371.0088 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    }

    /** İki yön arasındaki en kısa fark, -180..180. */
    public static double fark(double a, double b) {
        double d = ((a - b) % 360 + 540) % 360 - 180;
        return d;
    }

    /** "Güneydoğu" gibi 8 yönlü ad. */
    public static String yonAdi(double derece) {
        String[] ad = {"Kuzey", "Kuzeydoğu", "Doğu", "Güneydoğu", "Güney", "Güneybatı", "Batı", "Kuzeybatı"};
        return ad[(int) Math.round(((derece % 360) + 360) % 360 / 45.0) % 8];
    }
}
