package com.openbaovault.pkiclient.service;

import com.openbaovault.pkiclient.dto.IssuedCertificate;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.KeyFactory;
import java.security.KeyStore;
import java.security.PrivateKey;
import java.security.cert.CertificateException;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.security.spec.PKCS8EncodedKeySpec;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;

/**
 * Packages OpenBao-issued PEM certificates/keys into a PKCS12 keystore, matching
 * the format the actual wallet-ecosystem services (pid-issuer, verifier, etc.)
 * load at startup rather than raw PEM.
 */
final class Pkcs12KeystoreBuilder {

    private Pkcs12KeystoreBuilder() {
    }

    record Entry(String alias, IssuedCertificate certificate) {
    }

    static byte[] build(String password, List<Entry> entries) throws GeneralSecurityException, IOException {
        KeyStore keyStore = KeyStore.getInstance("PKCS12");
        keyStore.load(null, null);

        for (Entry entry : entries) {
            IssuedCertificate cert = entry.certificate();
            X509Certificate leaf = parseCertificate(cert.certificate());
            PrivateKey privateKey = parsePkcs8PrivateKey(cert.privateKey());

            List<X509Certificate> chain = new ArrayList<>();
            chain.add(leaf);
            for (String chainPem : cert.caChain()) {
                chain.add(parseCertificate(chainPem));
            }

            keyStore.setKeyEntry(entry.alias(), privateKey, password.toCharArray(),
                    chain.toArray(new X509Certificate[0]));
        }

        ByteArrayOutputStream out = new ByteArrayOutputStream();
        keyStore.store(out, password.toCharArray());
        return out.toByteArray();
    }

    static byte[] buildTrustStore(String password, String alias, String caCertificatePem)
            throws GeneralSecurityException, IOException {
        KeyStore keyStore = KeyStore.getInstance("PKCS12");
        keyStore.load(null, null);
        keyStore.setCertificateEntry(alias, parseCertificate(caCertificatePem));

        ByteArrayOutputStream out = new ByteArrayOutputStream();
        keyStore.store(out, password.toCharArray());
        return out.toByteArray();
    }

    private static X509Certificate parseCertificate(String pem) throws CertificateException {
        CertificateFactory factory = CertificateFactory.getInstance("X.509");
        return (X509Certificate) factory.generateCertificate(
                new ByteArrayInputStream(pem.getBytes(StandardCharsets.UTF_8)));
    }

    private static PrivateKey parsePkcs8PrivateKey(String pem) throws GeneralSecurityException {
        String base64 = pem
                .replaceAll("-----BEGIN [^-]+-----", "")
                .replaceAll("-----END [^-]+-----", "")
                .replaceAll("\\s", "");
        byte[] der = Base64.getDecoder().decode(base64);
        KeyFactory keyFactory = KeyFactory.getInstance("EC");
        return keyFactory.generatePrivate(new PKCS8EncodedKeySpec(der));
    }
}
