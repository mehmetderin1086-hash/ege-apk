import com.android.apksig.ApkSigner;
import java.io.*;
import java.security.*;
import java.security.cert.X509Certificate;
import java.util.*;

public class Sign {
  public static void main(String[] a) throws Exception {
    // a: keystore pass alias in out
    KeyStore ks = KeyStore.getInstance(new File(a[0]), a[1].toCharArray());
    PrivateKey key = (PrivateKey) ks.getKey(a[2], a[1].toCharArray());
    X509Certificate cert = (X509Certificate) ks.getCertificate(a[2]);
    ApkSigner.SignerConfig sc = new ApkSigner.SignerConfig.Builder("CERT", key, Collections.singletonList(cert)).build();
    new ApkSigner.Builder(Collections.singletonList(sc))
      .setInputApk(new File(a[3])).setOutputApk(new File(a[4]))
      .setMinSdkVersion(24).setV1SigningEnabled(false).setV2SigningEnabled(true)
      .build().sign();
    System.out.println("imzalandı: " + a[4]);
  }
}
