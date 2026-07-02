package demo;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

import javax.net.ssl.*;
import java.net.Socket;
import java.security.SecureRandom;
import java.security.cert.X509Certificate;

@SpringBootApplication
public class PingFedDemoApplication {

    // PingFederate has a self-signed cert in when running in a Docker container (development mode).
    // It runs at HTTPS://localhost:9031 and 9999 (HTTP Secure). In dev mode, Java will decline the app access to these hostnames throwing SSL Exception.

    // X509ExtendedTrustManager avoids the JVM wrapping it with
    // AbstractTrustManagerWrapper (which would add hostname checks on top).
    // THIS BLOCK SHOULD BE REMOVED IN PROD ENVIRONMENTS, otherwise an attacker will be able to access all data being sent from this app, by presenting any certificate.
    static {

        try {
            TrustManager[] trustAll = new TrustManager[]{new X509ExtendedTrustManager() {
                public X509Certificate[] getAcceptedIssuers() { return new X509Certificate[0]; }
                public void checkClientTrusted(X509Certificate[] c, String a) {}
                public void checkServerTrusted(X509Certificate[] c, String a) {}
                public void checkClientTrusted(X509Certificate[] c, String a, Socket s) {}
                public void checkServerTrusted(X509Certificate[] c, String a, Socket s) {}
                public void checkClientTrusted(X509Certificate[] c, String a, SSLEngine e) {}
                public void checkServerTrusted(X509Certificate[] c, String a, SSLEngine e) {}
            }};
            SSLContext sc = SSLContext.getInstance("TLS");
            sc.init(null, trustAll, new SecureRandom());
            SSLContext.setDefault(sc);
            HttpsURLConnection.setDefaultSSLSocketFactory(sc.getSocketFactory());
            HttpsURLConnection.setDefaultHostnameVerifier((host, session) -> true);
        } catch (Exception e) {
            throw new RuntimeException("Failed to configure trust-all SSL context", e);
        }
    }

    public static void main(String[] args) {
        SpringApplication.run(PingFedDemoApplication.class, args);
    }
}
