package com.mehmetderin.kitapbul_flutter;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.ClipData;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.provider.MediaStore;
import android.provider.Settings;
import androidx.core.content.FileProvider;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;


/**
 * Flutter arayüzünün yerel köprüsü. Kanallar (1.0.0 ile birebir aynı adlar ve yöntemler):
 * kitapbul/camera, kitapbul/ocr, kitapbul/loan_reminders, kitapbul/notifications, kitapbul/files.
 */
public class MainActivity extends FlutterActivity {
    private static final int FILE_REQUEST = 6217;
    private static final int NOTIFICATION_PERMISSION_REQUEST = 6218;
    private static final int CAMERA_PERMISSION_REQUEST = 6219;
    private static final int CAMERA_CAPTURE_REQUEST = 6220;
    private static final int AUDIO_PERMISSION_REQUEST = 6221;
    private static final String RESERVATION_CHANNEL = "reservation_ready";
    private static final int PI_FLAGS = PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE;

    private static final Set<String> FILE_METHODS = new HashSet<>(Arrays.asList(
            "export", "exportCsv", "exportPdf", "exportInventoryPdf", "exportTextbookPdf",
            "exportCertificatePdf", "exportStudentCardsPdf", "exportSpineLabelsPdf", "exportOfficialReportPdf",
            "exportXlsx", "pickXlsx", "import", "inspectIphone",
            "exportZip", "importZip", "pickCover", "pickMultipleImages", "pickStudentsCsv"));
    private static final Set<String> PAYLOAD_METHODS = new HashSet<>(Arrays.asList(
            "export", "exportCsv", "exportPdf", "exportInventoryPdf", "exportTextbookPdf",
            "exportCertificatePdf", "exportStudentCardsPdf", "exportSpineLabelsPdf", "exportOfficialReportPdf"));

    private final Handler main = new Handler(Looper.getMainLooper());

    private MethodChannel.Result cameraResult;
    private File cameraFile;
    private MethodChannel.Result notificationPermissionResult;
    private boolean requestingLoanPermission;
    private VoiceAssistantBridge voiceBridge;
    private MethodChannel.Result audioPermissionResult;
    private String pendingVoiceLocale;

    /** Açık dosya seçici işlemi (aynı anda yalnız bir tane). */
    private MethodChannel.Result pending;
    private String pendingMethod;
    private String exportData;
    private byte[] exportBytes;
    private String exportPath;

    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        BinaryMessenger m = flutterEngine.getDartExecutor().getBinaryMessenger();
        new MethodChannel(m, "kitapbul/camera").setMethodCallHandler(this::onCamera);
        new MethodChannel(m, "kitapbul/ocr").setMethodCallHandler(this::onOcr);
        new MethodChannel(m, "kitapbul/loan_reminders").setMethodCallHandler(this::onLoanReminders);
        new MethodChannel(m, "kitapbul/notifications").setMethodCallHandler(this::onNotifications);
        new MethodChannel(m, "kitapbul/files").setMethodCallHandler(this::onFiles);
        MethodChannel voiceChannel = new MethodChannel(m, "kitapbul/voice");
        if (voiceBridge != null) {
            voiceBridge.destroy();
        }
        voiceBridge = new VoiceAssistantBridge(this, voiceChannel);
        voiceChannel.setMethodCallHandler(this::onVoice);
    }

    @Override
    protected void onDestroy() {
        if (voiceBridge != null) {
            voiceBridge.destroy();
            voiceBridge = null;
        }
        super.onDestroy();
    }

    private void onVoice(MethodCall call, MethodChannel.Result result) {
        if (voiceBridge == null) {
            result.error("unavailable", "Ses köprüsü hazır değil", null);
            return;
        }
        String method = call.method == null ? "" : call.method;
        switch (method) {
            case "status":
                result.success(voiceBridge.status(
                        checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) == 0));
                return;
            case "startListening": {
                String locale = call.argument("locale");
                if (checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) != 0) {
                    if (audioPermissionResult != null) {
                        result.error("busy", "Mikrofon izni bekleniyor", null);
                        return;
                    }
                    audioPermissionResult = result;
                    pendingVoiceLocale = locale;
                    requestPermissions(
                            new String[] {android.Manifest.permission.RECORD_AUDIO},
                            AUDIO_PERMISSION_REQUEST);
                } else {
                    voiceBridge.startListening(locale, result);
                }
                return;
            }
            case "stopListening":
                voiceBridge.stopListening(result);
                return;
            case "cancelListening":
                voiceBridge.cancelListening(result);
                return;
            case "speak": {
                String text = call.argument("text");
                Number rate = call.argument("rate");
                Number pitch = call.argument("pitch");
                String voice = call.argument("voice");
                voiceBridge.speak(
                        text,
                        rate != null ? rate.doubleValue() : 1.0,
                        pitch != null ? pitch.doubleValue() : 1.0,
                        voice,
                        result);
                return;
            }
            case "setVoice": {
                String voice = call.argument("voice");
                voiceBridge.setVoice(voice, result);
                return;
            }
            case "stopSpeaking":
                voiceBridge.stopSpeaking(result);
                return;
            default:
                result.notImplemented();
        }
    }

    private void ui(Runnable r) {
        main.post(r);
    }

    // ---- kitapbul/camera ------------------------------------------------------------------

    private void onCamera(MethodCall call, MethodChannel.Result result) {
        if ("settings".equals(call.method)) {
            try {
                startActivity(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.parse("package:" + getPackageName())));
                result.success(true);
            } catch (Exception e) {
                result.error("settings", "Uygulama ayarları açılamadı", null);
            }
            return;
        }
        if (!"capture".equals(call.method)) {
            result.notImplemented();
            return;
        }
        if (cameraResult != null || pending != null) {
            result.error("busy", "Başka bir işlem açık", null);
            return;
        }
        cameraResult = result;
        if (checkSelfPermission(android.Manifest.permission.CAMERA) != 0) {
            requestPermissions(new String[] {android.Manifest.permission.CAMERA}, CAMERA_PERMISSION_REQUEST);
        } else {
            openCamera();
        }
    }

    private void openCamera() {
        MethodChannel.Result callback = cameraResult;
        if (callback == null) return;
        try {
            File dir = new File(getCacheDir(), "camera");
            dir.mkdirs();
            File[] old = dir.listFiles();
            if (old != null) {
                for (File f : old) if (f.getName().startsWith("capture-")) f.delete();
            }
            File file = File.createTempFile("capture-", ".jpg", dir);
            cameraFile = file;
            Uri uri = FileProvider.getUriForFile(this, getPackageName() + ".camera.files", file);
            Intent intent = new Intent(MediaStore.ACTION_IMAGE_CAPTURE);
            intent.putExtra(MediaStore.EXTRA_OUTPUT, uri);
            intent.setClipData(ClipData.newRawUri("photo", uri));
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
            startActivityForResult(intent, CAMERA_CAPTURE_REQUEST);
        } catch (Exception e) {
            if (cameraFile != null) cameraFile.delete();
            cameraFile = null;
            cameraResult = null;
            callback.error("camera", "Kamera açılamadı", null);
        }
    }

    private void onCameraResult(int resultCode) {
        final MethodChannel.Result callback = cameraResult;
        final File file = cameraFile;
        cameraFile = null;
        if (callback == null) {
            if (file != null) file.delete();
            return;
        }
        if (resultCode != RESULT_OK || file == null) {
            cameraResult = null;
            if (file != null) file.delete();
            callback.success(null);
            return;
        }
        new Thread(() -> {
            try {
                final byte[] photo = GorselHazirla.kameraFotografi(file);
                ui(() -> { cameraResult = null; callback.success(photo); });
            } catch (OutOfMemoryError e) {
                ui(() -> { cameraResult = null; callback.error("camera", "Fotoğraf çok büyük", null); });
            } catch (Exception e) {
                ui(() -> { cameraResult = null; callback.error("camera", "Fotoğraf okunamadı", null); });
            } finally {
                file.delete();
            }
        }, "kitapbul-camera").start();
    }

    // ---- kitapbul/ocr ---------------------------------------------------------------------

    private void onOcr(MethodCall call, final MethodChannel.Result result) {
        if (!"recognize".equals(call.method)) {
            result.notImplemented();
            return;
        }
        byte[] bytes = call.argument("image");
        if (bytes == null || bytes.length == 0 || bytes.length > 4 * 1024 * 1024) {
            result.error("image", "Görsel okunamadı veya çok büyük", null);
            return;
        }
        BookTextRecognition.recognize(bytes, new BookTextRecognition.Sonuc() {
            @Override
            public void basarili(Map<String, Object> sonuc) {
                ui(() -> result.success(sonuc));
            }

            @Override
            public void basarisiz() {
                ui(() -> result.error("ocr", "Görseldeki metin okunamadı", null));
            }
        });
    }

    // ---- kitapbul/loan_reminders ----------------------------------------------------------

    private void onLoanReminders(MethodCall call, MethodChannel.Result result) {
        if (!"replace".equals(call.method)) {
            result.notImplemented();
            return;
        }
        try {
            List<Map<String, Object>> items = call.argument("items");
            if (items == null) throw new IllegalArgumentException("Liste eksik");
            LoanReminders.replace(this, items);
            result.success(true);
        } catch (Exception e) {
            result.error("reminders", "Hatırlatmalar güncellenemedi", null);
        }
    }

    // ---- kitapbul/notifications (hazır rezervasyonlar) -----------------------------------

    private boolean notificationsAllowed() {
        NotificationManager manager = getSystemService(NotificationManager.class);
        boolean permission = Build.VERSION.SDK_INT < 33
                || checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) == 0;
        if (!permission || !manager.areNotificationsEnabled()) return false;
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel ch = manager.getNotificationChannel(RESERVATION_CHANNEL);
            return ch == null || ch.getImportance() != NotificationManager.IMPORTANCE_NONE;
        }
        return true;
    }

    private void requestNotificationPermission(MethodChannel.Result result, boolean loan) {
        boolean allowed = loan ? LoanReminders.allowed(this) : notificationsAllowed();
        if (allowed) {
            result.success(true);
            return;
        }
        if (Build.VERSION.SDK_INT < 33
                || checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) == 0) {
            // İzin var ama bildirimler kapalı: kullanıcı ayarlardan açmalı.
            result.success(false);
            return;
        }
        if (notificationPermissionResult != null) {
            result.error("busy", "Bildirim izni bekleniyor", null);
            return;
        }
        requestingLoanPermission = loan;
        notificationPermissionResult = result;
        requestPermissions(new String[] {android.Manifest.permission.POST_NOTIFICATIONS},
                NOTIFICATION_PERMISSION_REQUEST);
    }

    private void onNotifications(MethodCall call, MethodChannel.Result result) {
        String method = call.method == null ? "" : call.method;
        switch (method) {
            case "status":
                result.success(notificationsAllowed());
                return;
            case "request":
                requestNotificationPermission(result, false);
                return;
            case "requestLoan":
                requestNotificationPermission(result, true);
                return;
            case "settings":
                try {
                    Intent intent = Build.VERSION.SDK_INT >= 26
                            ? new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                    .putExtra(Settings.EXTRA_APP_PACKAGE, getPackageName())
                            : new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                    Uri.parse("package:" + getPackageName()));
                    startActivity(intent);
                    result.success(true);
                } catch (Exception e) {
                    result.error("settings", "Bildirim ayarları açılamadı", null);
                }
                return;
            case "cancel": {
                String id = call.argument("id");
                if (id == null || id.trim().isEmpty()) {
                    result.error("invalid", "Rezervasyon kimliği eksik", null);
                    return;
                }
                getSystemService(NotificationManager.class).cancel("reservation:" + id, 1);
                result.success(true);
                return;
            }
            case "ready":
                showReservationReady(call, result);
                return;
            default:
                result.notImplemented();
        }
    }

    private void showReservationReady(MethodCall call, MethodChannel.Result result) {
        String id = call.argument("id");
        String title = call.argument("title");
        String person = call.argument("person");
        Number expires = call.argument("expiresAtMillis");
        if (id == null || id.trim().isEmpty() || title == null || title.trim().isEmpty()
                || person == null || person.trim().isEmpty()) {
            result.error("invalid", "Bildirim bilgisi eksik", null);
            return;
        }
        if (!notificationsAllowed()) {
            result.success(false);
            return;
        }
        try {
            NotificationManager manager = getSystemService(NotificationManager.class);
            if (Build.VERSION.SDK_INT >= 26) {
                manager.createNotificationChannel(new NotificationChannel(RESERVATION_CHANNEL,
                        "Hazır rezervasyonlar", NotificationManager.IMPORTANCE_DEFAULT));
            }
            Intent open = new Intent(this, MainActivity.class)
                    .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
            PendingIntent pi = PendingIntent.getActivity(this, 0, open, PI_FLAGS);
            Notification.Builder b = Build.VERSION.SDK_INT >= 26
                    ? new Notification.Builder(this, RESERVATION_CHANNEL)
                    : new Notification.Builder(this);
            if (expires != null) {
                long remaining = expires.longValue() - System.currentTimeMillis();
                if (remaining <= 0) {
                    // Süresi dolmuş rezervasyon için bildirim gösterilmez.
                    manager.cancel("reservation:" + id, 1);
                    result.success(false);
                    return;
                }
                if (Build.VERSION.SDK_INT >= 26) b.setTimeoutAfter(remaining);
            }
            Notification n = b.setSmallIcon(android.R.drawable.ic_dialog_info)
                    .setContentTitle("Rezervasyon hazır")
                    .setContentText(title + " · " + person)
                    .setVisibility(Notification.VISIBILITY_PRIVATE)
                    .setAutoCancel(true)
                    .setContentIntent(pi)
                    .build();
            manager.notify("reservation:" + id, 1, n);
            result.success(true);
        } catch (Exception e) {
            result.error("notify", "Bildirim gösterilemedi", null);
        }
    }

    // ---- kitapbul/files (SAF dosya seçici ile içe/dışa aktarma) ---------------------------

    private static boolean isPdf(String method) {
        return "exportPdf".equals(method) || "exportInventoryPdf".equals(method)
                || "exportTextbookPdf".equals(method) || "exportCertificatePdf".equals(method)
                || "exportStudentCardsPdf".equals(method) || "exportSpineLabelsPdf".equals(method)
                || "exportOfficialReportPdf".equals(method);
    }

    private static boolean isRead(String method) {
        return "import".equals(method) || "inspectIphone".equals(method) || "importZip".equals(method)
                || "pickCover".equals(method) || "pickMultipleImages".equals(method)
                || "pickStudentsCsv".equals(method) || "pickXlsx".equals(method);
    }

    /** exportZip yalnız uygulamanın önbelleğindeki gerçek bir dosyayı kopyalayabilir. */
    private boolean guvenliOnbellekYolu(String path) {
        if (path == null) return false;
        try {
            File f = new File(path);
            return f.getCanonicalPath().startsWith(getCacheDir().getCanonicalPath() + "/") && f.isFile();
        } catch (Exception e) {
            return false;
        }
    }

    private void onFiles(MethodCall call, MethodChannel.Result result) {
        String method = call.method;
        if (method == null || !FILE_METHODS.contains(method)) {
            result.notImplemented();
            return;
        }
        if (pending != null || cameraResult != null) {
            result.error("busy", "Dosya seçimi zaten açık", null);
            return;
        }
        String payload = call.argument("data");
        byte[] binary = call.argument("bytes");
        String path = "exportZip".equals(method) ? call.argument("path") : null;
        boolean gecerli = (!PAYLOAD_METHODS.contains(method) || payload != null)
                && (!"exportXlsx".equals(method) || (binary != null && binary.length <= 25 * 1024 * 1024))
                && (!"exportZip".equals(method) || guvenliOnbellekYolu(path));
        if (!gecerli) {
            result.error("invalid", "Yedek verisi eksik", null);
            return;
        }
        pending = result;
        pendingMethod = method;
        exportData = payload;
        exportBytes = binary;
        exportPath = path;
        boolean read = isRead(method);
        try {
            Intent intent = new Intent(read ? Intent.ACTION_OPEN_DOCUMENT : Intent.ACTION_CREATE_DOCUMENT);
            intent.addCategory(Intent.CATEGORY_OPENABLE);
            String type;
            String name;
            if ("inspectIphone".equals(method) || "importZip".equals(method) || "exportZip".equals(method)) {
                type = "application/zip";
            } else if ("pickCover".equals(method)) {
                type = "image/*";
            } else if ("pickMultipleImages".equals(method)) {
                type = "image/*";
                intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true);
            } else if ("pickStudentsCsv".equals(method)) {
                type = "*/*";
                intent.putExtra(Intent.EXTRA_MIME_TYPES, new String[] {
                        "text/csv", "text/plain", "application/vnd.ms-excel", "text/tab-separated-values"});
            } else if ("pickXlsx".equals(method)) {
                type = "*/*";
                intent.putExtra(Intent.EXTRA_MIME_TYPES, new String[] {
                        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                        "application/vnd.ms-excel"});
            } else if ("exportCsv".equals(method)) {
                type = "text/csv";
            } else if (isPdf(method)) {
                type = "application/pdf";
            } else if ("exportXlsx".equals(method)) {
                type = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
            } else {
                type = "application/json";
            }
            intent.setType(type);
            if (!read) {
                String given = call.argument("filename");
                if ("exportCsv".equals(method)) name = given != null ? given : "KitapListesi.csv";
                else if (isPdf(method)) name = given != null ? given : "KitapListesi.pdf";
                else if ("exportXlsx".equals(method)) name = given != null ? given : "DersKitabiCizelgesi.xlsx";
                else if ("exportZip".equals(method)) name = given != null ? given : "kitap-bul-yedek.zip";
                else name = "kitap-bul-yedek.json";
                intent.putExtra(Intent.EXTRA_TITLE, name);
            }
            startActivityForResult(intent, FILE_REQUEST);
        } catch (Exception e) {
            clearPending();
            result.error("picker", "Dosya seçici açılamadı", null);
        }
    }

    private void clearPending() {
        pending = null;
        pendingMethod = null;
        exportData = null;
        exportBytes = null;
        exportPath = null;
    }

    // ---- Sonuçlar --------------------------------------------------------------------------

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == NOTIFICATION_PERMISSION_REQUEST) {
            MethodChannel.Result callback = notificationPermissionResult;
            notificationPermissionResult = null;
            if (callback != null) {
                callback.success(requestingLoanPermission ? LoanReminders.allowed(this) : notificationsAllowed());
            }
            requestingLoanPermission = false;
        } else if (requestCode == CAMERA_PERMISSION_REQUEST) {
            if (grantResults.length == 0 || grantResults[0] != 0) {
                MethodChannel.Result callback = cameraResult;
                cameraResult = null;
                if (callback != null) callback.error("permission", "Kamera izni verilmedi", null);
            } else {
                openCamera();
            }
        } else if (requestCode == AUDIO_PERMISSION_REQUEST) {
            MethodChannel.Result callback = audioPermissionResult;
            String locale = pendingVoiceLocale;
            audioPermissionResult = null;
            pendingVoiceLocale = null;
            if (grantResults.length == 0 || grantResults[0] != 0) {
                if (callback != null) callback.error("permission", "Mikrofon izni verilmedi", null);
            } else if (callback != null && voiceBridge != null) {
                voiceBridge.startListening(locale, callback);
            }
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == CAMERA_CAPTURE_REQUEST) {
            onCameraResult(resultCode);
            return;
        }
        if (requestCode != FILE_REQUEST || pending == null) return;
        final MethodChannel.Result callback = pending;
        final String method = pendingMethod;
        final String payload = exportData;
        final byte[] binary = exportBytes;
        final String zipSource = exportPath;
        clearPending();
        if ("pickMultipleImages".equals(method)) {
            if (resultCode != RESULT_OK || data == null) {
                callback.success(null);
                return;
            }
            final ClipData clip = data.getClipData();
            final Uri singleUri = data.getData();
            if (clip == null && singleUri == null) {
                callback.success(null);
                return;
            }
            new Thread(() -> cokluGorselOku(clip, singleUri, callback), "kitapbul-multi-img").start();
            return;
        }
        final Uri uri = data != null ? data.getData() : null;
        if (resultCode != RESULT_OK || uri == null) {
            // İptal: okuma işlemlerinde null, yazma işlemlerinde false (1.0.0 davranışı).
            callback.success(isRead(method) ? null : Boolean.FALSE);
            return;
        }
        new Thread(() -> {
            if ("exportZip".equals(method)) zipKopyala(uri, zipSource, callback);
            else if (isPdf(method)) pdfYaz(method, payload, uri, callback);
            else if ("inspectIphone".equals(method) || "importZip".equals(method)) zipIceAl(uri, callback);
            else if (isRead(method)) dosyaOku(uri, method, callback);
            else baytYaz(uri, payload, binary, callback);
        }, "kitapbul-files").start();
    }

    private void baytYaz(Uri uri, String payload, byte[] binary, MethodChannel.Result callback) {
        try (OutputStream out = getContentResolver().openOutputStream(uri, "wt")) {
            if (out == null) throw new IllegalStateException("Dosya açılamadı");
            byte[] bytes = binary != null ? binary : payload.getBytes(StandardCharsets.UTF_8);
            out.write(bytes);
            ui(() -> callback.success(true));
        } catch (Exception e) {
            ui(() -> callback.error("file", "Yedek dosyası kaydedilemedi", null));
        }
    }

    private void zipKopyala(Uri uri, String source, MethodChannel.Result callback) {
        try (OutputStream out = getContentResolver().openOutputStream(uri, "wt");
             InputStream in = new FileInputStream(source)) {
            if (out == null) throw new IllegalStateException("Dosya açılamadı");
            byte[] buf = new byte[65536];
            int n;
            while ((n = in.read(buf)) >= 0) out.write(buf, 0, n);
            ui(() -> callback.success(true));
        } catch (Exception e) {
            ui(() -> callback.error("file", "Yedek dosyası kaydedilemedi", null));
        }
    }

    private void pdfYaz(String method, String payload, Uri uri, MethodChannel.Result callback) {
        try {
            if (payload == null) throw new IllegalStateException("PDF verisi eksik");
            byte[] pdf;
            switch (method) {
                case "exportInventoryPdf": pdf = InventoryPdf.generate(payload); break;
                case "exportStudentCardsPdf": pdf = StudentCardsPdf.generate(payload); break;
                case "exportCertificatePdf": pdf = CertificatePdf.generate(payload); break;
                case "exportTextbookPdf": pdf = TextbookReportPdf.generate(payload); break;
                case "exportSpineLabelsPdf": pdf = SpineLabelsPdf.generate(payload); break;
                case "exportOfficialReportPdf": pdf = OfficialReportPdf.generate(payload); break;
                default: pdf = CatalogPdf.generate(payload); break;
            }
            try (OutputStream out = getContentResolver().openOutputStream(uri, "wt")) {
                if (out == null) throw new IllegalStateException("Dosya açılamadı");
                out.write(pdf);
            }
            ui(() -> callback.success(true));
        } catch (Exception | OutOfMemoryError e) {
            ui(() -> callback.error("file", "PDF kaydedilemedi", null));
        }
    }

    /** ZIP yedeğini (iPhone arşivi veya Android yedeği) önbelleğe kopyalar; yolu Dart'a döner. */
    private void zipIceAl(Uri uri, MethodChannel.Result callback) {
        File dir = new File(getCacheDir(), "iphone-import");
        String stamp = System.currentTimeMillis() + "-" + UUID.randomUUID();
        File target = new File(dir, "import-" + stamp + ".zip");
        File temp = new File(dir, "import-" + stamp + ".zip.part");
        try {
            dir.mkdirs();
            File[] old = dir.listFiles();
            if (old != null) {
                for (File f : old) if (f.getName().startsWith("import") && !f.equals(target)) f.delete();
            }
            long limit = 512L * 1024 * 1024;
            try (InputStream in = getContentResolver().openInputStream(uri);
                 FileOutputStream out = new FileOutputStream(temp)) {
                if (in == null) throw new IllegalStateException("Dosya açılamadı");
                byte[] buf = new byte[65536];
                long total = 0;
                int n;
                while ((n = in.read(buf)) >= 0) {
                    total += n;
                    if (total > limit) throw new IllegalArgumentException("Dosya çok büyük");
                    out.write(buf, 0, n);
                }
                out.getFD().sync();
            }
            if (!temp.renameTo(target)) throw new IllegalStateException("Dosya taşınamadı");
            final String path = target.getAbsolutePath();
            ui(() -> callback.success(path));
        } catch (Exception e) {
            temp.delete();
            ui(() -> callback.error("file", "Dosya okunamadı veya izin verilen boyutu aşıyor", null));
        }
    }

    /** JSON yedeği metin olarak, kapak, öğrenci CSV'si ve Excel dosyası bayt olarak döner. */
    private void dosyaOku(Uri uri, String method, MethodChannel.Result callback) {
        boolean cover = "pickCover".equals(method);
        boolean csv = "pickStudentsCsv".equals(method);
        boolean xlsx = "pickXlsx".equals(method);
        int limit = cover ? 4 * 1024 * 1024 : csv ? 5 * 1024 * 1024 : xlsx ? 25 * 1024 * 1024 : 50 * 1024 * 1024;
        try (InputStream in = getContentResolver().openInputStream(uri)) {
            if (in == null) throw new IllegalStateException("Dosya açılamadı");
            ByteArrayOutputStream buf = new ByteArrayOutputStream();
            byte[] chunk = new byte[8192];
            int n;
            while ((n = in.read(chunk)) >= 0) {
                if (buf.size() + n > limit) throw new IllegalArgumentException("Dosya çok büyük");
                buf.write(chunk, 0, n);
            }
            final Object value = (cover || csv || xlsx)
                    ? buf.toByteArray()
                    : new String(buf.toByteArray(), StandardCharsets.UTF_8);
            ui(() -> callback.success(value));
        } catch (Exception e) {
            ui(() -> callback.error("file", "Dosya okunamadı veya izin verilen boyutu aşıyor", null));
        }
    }

    /** Çoklu görsel seçimini (en fazla 16 fotoğraf) sıkıştırılmış JPEG listesi olarak döner. */
    private void cokluGorselOku(ClipData clip, Uri singleUri, MethodChannel.Result callback) {
        try {
            java.util.ArrayList<byte[]> outList = new java.util.ArrayList<>();
            java.util.ArrayList<Uri> uris = new java.util.ArrayList<>();
            if (clip != null && clip.getItemCount() > 0) {
                int max = Math.min(clip.getItemCount(), 16);
                for (int i = 0; i < max; i++) {
                    Uri u = clip.getItemAt(i).getUri();
                    if (u != null) uris.add(u);
                }
            } else if (singleUri != null) {
                uris.add(singleUri);
            }
            for (Uri u : uris) {
                try (InputStream in = getContentResolver().openInputStream(u)) {
                    if (in == null) continue;
                    ByteArrayOutputStream buf = new ByteArrayOutputStream();
                    byte[] chunk = new byte[16384];
                    int n;
                    while ((n = in.read(chunk)) >= 0) {
                        if (buf.size() + n > 30 * 1024 * 1024) {
                            throw new IllegalArgumentException("Fotoğraf çok büyük");
                        }
                        buf.write(chunk, 0, n);
                    }
                    outList.add(GorselHazirla.bellekFotografi(buf.toByteArray()));
                } catch (Exception ignored) {
                    // Tek bir bozuk görsel diğerlerini iptal etmesin
                }
            }
            ui(() -> callback.success(outList));
        } catch (Exception | OutOfMemoryError e) {
            ui(() -> callback.error("file", "Seçilen fotoğraflar okunamadı", null));
        }
    }
}
