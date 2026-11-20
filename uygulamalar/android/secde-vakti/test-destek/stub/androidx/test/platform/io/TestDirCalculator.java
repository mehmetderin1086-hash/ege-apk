package androidx.test.platform.io;
import java.io.File; import androidx.test.platform.app.InstrumentationRegistry;
public class TestDirCalculator {
  private File kok() { return InstrumentationRegistry.getInstrumentation().getTargetContext().getCacheDir(); }
  public File getOutputDir() { String d = InstrumentationRegistry.getArguments().getString("additionalTestOutputDir"); return d != null ? new File(d) : new File(kok(), "additionalTestOutputDir"); }
  public File getInputDir() { String d = InstrumentationRegistry.getArguments().getString("testInputDir"); return d != null ? new File(d) : new File(kok(), "testInputDir"); }
}
