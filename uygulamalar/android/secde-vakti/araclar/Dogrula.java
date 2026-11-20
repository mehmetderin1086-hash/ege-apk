import com.android.apksig.ApkVerifier;
import java.io.File;
public class Dogrula {
  public static void main(String[] a) throws Exception {
    ApkVerifier.Result r = new ApkVerifier.Builder(new File(a[0])).setMinCheckedPlatformVersion(24).build().verify();
    System.out.println("geçerli=" + r.isVerified() + " v1=" + r.isVerifiedUsingV1Scheme() + " v2=" + r.isVerifiedUsingV2Scheme());
    for (Object e : r.getErrors()) System.out.println("HATA " + e);
    for (Object w : r.getWarnings()) System.out.println("UYARI " + w);
    for (ApkVerifier.Result.V2SchemeSignerInfo s : r.getV2SchemeSigners()) { for (Object e : s.getErrors()) System.out.println("V2 HATA " + e); System.out.println(s.getCertificate().getSubjectX500Principal()); }
  }
}
