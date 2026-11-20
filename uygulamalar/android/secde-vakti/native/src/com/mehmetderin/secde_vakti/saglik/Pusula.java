package com.mehmetderin.secde_vakti.saglik;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapShader;
import android.graphics.BlurMaskFilter;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RadialGradient;
import android.graphics.Shader;
import android.graphics.SweepGradient;
import android.graphics.Typeface;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import android.view.HapticFeedbackConstants;
import android.view.Surface;
import android.view.View;
import android.view.WindowManager;

/**
 * Kıble pusulası. Kadran telefonun yönüne göre döner (dönüş vektörü sensörü, yumuşatılmış);
 * kadranda Kâbe işareti kıble yönünde durur. Telefonun üst ucu kıbleye ±4° içinde gelince
 * altın ışık halkası yanar ve bir kez titreşir.
 */
public final class Pusula extends View implements SensorEventListener {

    public interface Dinleyici {
        void hizalama(boolean hizali, double telefonYonu);
    }

    private double kible = Double.NaN;
    private float hedefAzimut, azimut;
    private boolean sensorVar, hizali;
    private Dinleyici dinleyici;
    private SensorManager sm;
    private final float[] matris = new float[9], yonelim = new float[3], donusMatris = new float[9];

    private final Paint boya = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint yazi = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint parilti = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint kabeBoya = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.FILTER_BITMAP_FLAG);
    private final Path yol = new Path();
    private Bitmap kabe;

    public Pusula(Context c) {
        super(c);
        setLayerType(LAYER_TYPE_SOFTWARE, null);
        yazi.setTextAlign(Paint.Align.CENTER);
        yazi.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
    }

    public void kible(double derece) {
        kible = derece;
        invalidate();
    }

    public void dinleyici(Dinleyici d) {
        dinleyici = d;
    }

    public boolean sensorVar() {
        return sensorVar;
    }

    /** Testler ve sensörsüz cihazlar için yönü elle verir. */
    public void azimut(float derece) {
        hedefAzimut = derece;
        azimut = derece;
        hizaDenetle();
        invalidate();
    }

    @Override
    protected void onAttachedToWindow() {
        super.onAttachedToWindow();
        sm = (SensorManager) getContext().getSystemService(Context.SENSOR_SERVICE);
        Sensor s = sm == null ? null : sm.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR);
        sensorVar = s != null && sm.registerListener(this, s, SensorManager.SENSOR_DELAY_GAME);
    }

    @Override
    protected void onDetachedFromWindow() {
        super.onDetachedFromWindow();
        if (sm != null) sm.unregisterListener(this);
    }

    @Override
    public void onSensorChanged(SensorEvent e) {
        SensorManager.getRotationMatrixFromVector(matris, e.values);
        int donus = Surface.ROTATION_0;
        try {
            donus = ((WindowManager) getContext().getSystemService(Context.WINDOW_SERVICE)).getDefaultDisplay().getRotation();
        } catch (Throwable ignored) {
        }
        int x = SensorManager.AXIS_X, y = SensorManager.AXIS_Y;
        if (donus == Surface.ROTATION_90) { x = SensorManager.AXIS_Y; y = SensorManager.AXIS_MINUS_X; }
        else if (donus == Surface.ROTATION_180) { x = SensorManager.AXIS_MINUS_X; y = SensorManager.AXIS_MINUS_Y; }
        else if (donus == Surface.ROTATION_270) { x = SensorManager.AXIS_MINUS_Y; y = SensorManager.AXIS_X; }
        SensorManager.remapCoordinateSystem(matris, x, y, donusMatris);
        SensorManager.getOrientation(donusMatris, yonelim);
        hedefAzimut = (float) ((Math.toDegrees(yonelim[0]) + 360) % 360);
        invalidate();
    }

    @Override
    public void onAccuracyChanged(Sensor sensor, int accuracy) {}

    private void hizaDenetle() {
        if (Double.isNaN(kible)) return;
        boolean simdi = Math.abs(Kible.fark(kible, azimut)) <= 4;
        if (simdi != hizali) {
            hizali = simdi;
            if (simdi) performHapticFeedback(HapticFeedbackConstants.LONG_PRESS);
            if (dinleyici != null) dinleyici.hizalama(simdi, azimut);
        }
    }

    @Override
    protected void onDraw(Canvas c) {
        float w = getWidth(), h = getHeight();
        float cx = w / 2, cy = h / 2, R = Math.min(w, h) / 2f * 0.86f;

        // Yumuşak dönüş: en kısa yoldan hedefe yaklaş
        float d = (float) Kible.fark(hedefAzimut, azimut);
        azimut = (azimut + d * 0.18f + 360) % 360;
        hizaDenetle();

        // Hizalanınca altın ışık halkası ve sonar dalgaları
        if (hizali) {
            long tMs = System.currentTimeMillis();
            float nabiz = 0.7f + 0.3f * (float) Math.sin(tMs / 220.0);
            parilti.setMaskFilter(new BlurMaskFilter(R * 0.12f, BlurMaskFilter.Blur.NORMAL));
            parilti.setColor(0xFFF0B35A);
            parilti.setAlpha((int) (230 * nabiz));
            parilti.setStyle(Paint.Style.STROKE);
            parilti.setStrokeWidth(R * 0.10f);
            c.drawCircle(cx, cy, R * 1.02f, parilti);
            parilti.setMaskFilter(null);
            for (int i = 0; i < 2; i++) {
                float p = ((tMs + i * 700L) % 1400L) / 1400f;
                parilti.setAlpha(Math.round(130 * (1f - p)));
                parilti.setStrokeWidth(R * 0.025f * (1f - p * 0.5f));
                c.drawCircle(cx, cy, R * (1.0f + p * 0.16f), parilti);
            }
        }

        // Kadran zemini + merkez 12 köşeli yıldız filigranı
        boya.setStyle(Paint.Style.FILL);
        boya.setShader(new RadialGradient(cx, cy, R, new int[]{0xCC1A1F45, 0xE60B0E22}, null, Shader.TileMode.CLAMP));
        c.drawCircle(cx, cy, R, boya);
        boya.setShader(null);
        boya.setStyle(Paint.Style.STROKE);
        boya.setColor(0x1FF0B35A);
        boya.setStrokeWidth(R * 0.008f);
        float yR = R * 0.44f;
        for (int i = 0; i < 6; i++) {
            double rA = Math.toRadians(i * 30.0);
            float dx = (float) Math.cos(rA) * yR;
            float dy = (float) Math.sin(rA) * yR;
            c.drawLine(cx - dx, cy - dy, cx + dx, cy + dy, boya);
        }
        c.drawCircle(cx, cy, R * 0.34f, boya);
        boya.setStrokeWidth(R * 0.035f);
        boya.setShader(new SweepGradient(cx, cy, new int[]{0xFFF0B35A, 0xFFC07A1E, 0xFFFFE0A0, 0xFFF0B35A}, null));
        c.drawCircle(cx, cy, R, boya);
        boya.setShader(null);

        c.save();
        c.rotate(-azimut, cx, cy);
        // Çentikler
        for (int i = 0; i < 360; i += 5) {
            boolean buyuk = i % 30 == 0;
            boya.setStrokeWidth(buyuk ? R * 0.016f : R * 0.008f);
            boya.setColor(buyuk ? 0xE6FFFFFF : 0x80FFFFFF);
            float r1 = R * 0.93f, r2 = buyuk ? R * 0.82f : R * 0.87f;
            double a = Math.toRadians(i - 90);
            c.drawLine(cx + (float) Math.cos(a) * r1, cy + (float) Math.sin(a) * r1,
                    cx + (float) Math.cos(a) * r2, cy + (float) Math.sin(a) * r2, boya);
        }
        // Yön harfleri (K, D, G, B)
        String[] harf = {"K", "D", "G", "B"};
        yazi.setTextSize(R * 0.13f);
        for (int i = 0; i < 4; i++) {
            double a = Math.toRadians(i * 90 - 90);
            float x = cx + (float) Math.cos(a) * R * 0.68f, y = cy + (float) Math.sin(a) * R * 0.68f + yazi.getTextSize() * 0.36f;
            yazi.setColor(i == 0 ? 0xFFFF8A80 : Color.WHITE);
            c.save();
            c.rotate(azimut, x, y - yazi.getTextSize() * 0.36f);
            c.drawText(harf[i], x, y, yazi);
            c.restore();
        }

        // Kâbe işareti ve kıble çizgisi
        if (!Double.isNaN(kible)) {
            double a = Math.toRadians(kible - 90);
            float kx = cx + (float) Math.cos(a) * R * 0.66f, ky = cy + (float) Math.sin(a) * R * 0.66f;
            boya.setStrokeWidth(R * 0.02f);
            boya.setColor(0xB3F0B35A);
            c.drawLine(cx, cy, kx, ky, boya);
            float kr = R * 0.17f;
            if (kabe == null) kabe = Gorseller.al(getContext(), "k_kabe", (int) (kr * 2));
            if (kabe != null) {
                BitmapShader sh = new BitmapShader(kabe, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP);
                Matrix m = new Matrix();
                float olcek = kr * 2 / Math.min(kabe.getWidth(), kabe.getHeight());
                m.postScale(olcek, olcek);
                m.postTranslate(kx - kabe.getWidth() * olcek / 2, ky - kabe.getHeight() * olcek / 2);
                sh.setLocalMatrix(m);
                c.save();
                c.rotate(azimut, kx, ky);
                kabeBoya.setShader(sh);
                c.drawCircle(kx, ky, kr, kabeBoya);
                c.restore();
            } else {
                boya.setStyle(Paint.Style.FILL);
                boya.setColor(Color.BLACK);
                c.drawRect(kx - kr * 0.6f, ky - kr * 0.6f, kx + kr * 0.6f, ky + kr * 0.6f, boya);
            }
            boya.setStyle(Paint.Style.STROKE);
            boya.setStrokeWidth(R * 0.025f);
            boya.setColor(0xFFF0B35A);
            c.drawCircle(kx, ky, kr, boya);
        }
        c.restore();

        // Sabit üst işaret: telefonun baktığı yön
        boya.setStyle(Paint.Style.FILL);
        boya.setColor(hizali ? 0xFFF0B35A : Color.WHITE);
        yol.reset();
        yol.moveTo(cx, cy - R * 1.08f);
        yol.lineTo(cx - R * 0.07f, cy - R * 0.94f);
        yol.lineTo(cx + R * 0.07f, cy - R * 0.94f);
        yol.close();
        c.drawPath(yol, boya);

        // Orta nokta ve ibre
        yol.reset();
        yol.moveTo(cx, cy - R * 0.45f);
        yol.lineTo(cx + R * 0.05f, cy);
        yol.lineTo(cx, cy + R * 0.12f);
        yol.lineTo(cx - R * 0.05f, cy);
        yol.close();
        c.drawPath(yol, boya);
        boya.setColor(0xFF0B0E22);
        c.drawCircle(cx, cy, R * 0.035f, boya);

        if (Math.abs(d) > 0.2f || hizali) postInvalidateOnAnimation();
    }
}
