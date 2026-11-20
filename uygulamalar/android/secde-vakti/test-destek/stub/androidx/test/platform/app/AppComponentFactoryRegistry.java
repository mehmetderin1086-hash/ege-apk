package androidx.test.platform.app;
import android.app.Activity; import android.app.AppComponentFactory; import android.app.Application; import android.content.Intent; import android.os.Build;
public final class AppComponentFactoryRegistry {
  private static volatile AppComponentFactory factory;
  public static AppComponentFactory getAppComponentFactory() { return factory; }
  public static void setAppComponentFactory(AppComponentFactory f) { factory = f; }
  public static Application instantiateApplication(ClassLoader cl, String n) {
    try { return Build.VERSION.SDK_INT >= 28 && factory != null ? factory.instantiateApplication(cl, n) : null; } catch (Exception e) { throw new RuntimeException(e); } }
  public static Activity instantiateActivity(ClassLoader cl, String n, Intent i) {
    try { return Build.VERSION.SDK_INT >= 28 && factory != null ? factory.instantiateActivity(cl, n, i) : null; } catch (Exception e) { throw new RuntimeException(e); } }
  public static Activity instantiateActivity(ClassLoader cl, String n) { return instantiateActivity(cl, n, null); }
}
