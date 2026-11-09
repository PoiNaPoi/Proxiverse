import java.io.File;
import java.io.FileInputStream;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;

public final class InstallCertificate {
    public static void main(String[] args) throws Exception {
        if (args.length != 2 || !args[1].matches("[0-9]+")) {
            throw new IllegalArgumentException("Expected public CA path and Android user ID");
        }
        X509Certificate cert;
        try (FileInputStream input = new FileInputStream(args[0])) {
            cert = (X509Certificate) CertificateFactory.getInstance("X.509").generateCertificate(input);
        }
        cert.checkValidity();
        if (cert.getBasicConstraints() < 0) throw new IllegalArgumentException("Certificate is not a CA");
        Class<?> type = Class.forName("com.android.org.conscrypt.TrustedCertificateStore");
        File userDirectory = new File("/data/misc/user/" + args[1]);
        File addedDirectory = new File(userDirectory, "cacerts-added");
        boolean directoryExisted = addedDirectory.exists();
        type.getMethod("setDefaultUserDirectory", File.class).invoke(null, userDirectory);
        Object store = type.getConstructor().newInstance();
        type.getMethod("installCertificate", X509Certificate.class).invoke(store, cert);
        String alias = (String) type.getMethod("getCertificateAlias", java.security.cert.Certificate.class).invoke(store, cert);
        if (alias == null || !cert.equals(type.getMethod("getCertificate", String.class).invoke(store, alias))) {
            throw new IllegalStateException("Installed CA could not be read from Android trust store");
        }
        if (alias.startsWith("user:")) {
            File installed = new File(addedDirectory, alias.substring(5));
            Class<?> os = Class.forName("android.system.Os");
            // Keep the CA removable by Android's Settings / KeyChain service.
            os.getMethod("chown", String.class, int.class, int.class).invoke(null, installed.getPath(), 1000, 1000);
            os.getMethod("chmod", String.class, int.class).invoke(null, installed.getPath(), 0644);
            if (!directoryExisted) {
                os.getMethod("chown", String.class, int.class, int.class).invoke(null, addedDirectory.getPath(), 1000, 1000);
                os.getMethod("chmod", String.class, int.class).invoke(null, addedDirectory.getPath(), 0755);
            }
            Object restored = Class.forName("android.os.SELinux").getMethod("restorecon", File.class).invoke(null, installed);
            if (!Boolean.TRUE.equals(restored)) throw new IllegalStateException("Cannot restore CA security context");
        }
        System.out.println("PROXIVERSE_CA_INSTALLED:" + alias);
    }
}
