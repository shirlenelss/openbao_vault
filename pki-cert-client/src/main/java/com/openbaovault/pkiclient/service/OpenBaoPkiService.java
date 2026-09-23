package com.openbaovault.pkiclient.service;

import com.openbaovault.pkiclient.config.OpenBaoProperties;
import com.openbaovault.pkiclient.dto.IssueCertificateRequest;
import com.openbaovault.pkiclient.dto.IssuedCertificate;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientResponseException;
import org.springframework.web.server.ResponseStatusException;

import java.io.IOException;
import java.security.GeneralSecurityException;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

@Service
public class OpenBaoPkiService {

    private static final String DEFAULT_KEYSTORE_PASSWORD = "changeit";

    private final RestClient restClient;
    private final OpenBaoProperties properties;

    public OpenBaoPkiService(OpenBaoProperties properties) {
        this.properties = properties;
        this.restClient = RestClient.builder()
                .baseUrl(properties.baseUrl())
                .defaultHeader("X-Vault-Token", properties.token())
                .build();
    }

    /** Single-key PKCS12 keystore containing just this CA's leaf certificate. */
    public byte[] issueKeystore(String ca, IssueCertificateRequest request) {
        String mount = resolveMount(ca);
        IssuedCertificate cert = issue(mount, properties.defaultRole(), request.commonName(), request.ttl());
        String password = resolvePassword(request.password());

        try {
            return Pkcs12KeystoreBuilder.build(password,
                    List.of(new Pkcs12KeystoreBuilder.Entry(ca, cert)));
        } catch (GeneralSecurityException | IOException e) {
            throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR,
                    "Failed to build PKCS12 keystore: " + e.getMessage(), e);
        }
    }

    /**
     * pid-issuer's keystore bundles three key pairs - the main service cert plus
     * nonce-encryption and request-encryption keys - matching the ecosystem's
     * pid_issuer.p12.
     */
    public byte[] issuePidIssuerBundle(IssueCertificateRequest request) {
        String mount = resolveMount("pid-issuer");
        String password = resolvePassword(request.password());

        IssuedCertificate main = issue(mount, properties.defaultRole(), request.commonName(), request.ttl());
        IssuedCertificate nonce = issue(mount, properties.encryptionRole(), "nonce-encryption", null);
        IssuedCertificate requestEnc = issue(mount, properties.encryptionRole(), "request-encryption", null);

        try {
            return Pkcs12KeystoreBuilder.build(password, List.of(
                    new Pkcs12KeystoreBuilder.Entry("pid_issuer", main),
                    new Pkcs12KeystoreBuilder.Entry("nonce-encryption", nonce),
                    new Pkcs12KeystoreBuilder.Entry("request-encryption", requestEnc)));
        } catch (GeneralSecurityException | IOException e) {
            throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR,
                    "Failed to build PKCS12 keystore: " + e.getMessage(), e);
        }
    }

    /** Truststore containing just this CA's root certificate, for peers that need to trust it. */
    public byte[] issueTrustStore(String ca, String password) {
        String mount = resolveMount(ca);
        String pem = getCaCertificatePem(ca);
        String resolvedPassword = resolvePassword(password);

        try {
            return Pkcs12KeystoreBuilder.buildTrustStore(resolvedPassword, "root_ca", pem);
        } catch (GeneralSecurityException | IOException e) {
            throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR,
                    "Failed to build PKCS12 truststore: " + e.getMessage(), e);
        }
    }

    public String getCaCertificatePem(String ca) {
        String mount = resolveMount(ca);
        return callOpenBao(() -> restClient.get()
                .uri("/v1/{mount}/ca/pem", mount)
                .retrieve()
                .body(String.class));
    }

    private IssuedCertificate issue(String mount, String role, String commonName, String ttl) {
        Map<String, Object> body = new HashMap<>();
        body.put("common_name", commonName);
        body.put("private_key_format", "pkcs8");
        if (ttl != null && !ttl.isBlank()) {
            body.put("ttl", ttl);
        }

        Map<String, Object> response = callOpenBao(() -> restClient.post()
                .uri("/v1/{mount}/issue/{role}", mount, role)
                .body(body)
                .retrieve()
                .body(new ParameterizedTypeReference<Map<String, Object>>() {
                }));

        @SuppressWarnings("unchecked")
        Map<String, Object> data = (Map<String, Object>) response.get("data");
        if (data == null) {
            throw new ResponseStatusException(HttpStatus.BAD_GATEWAY, "OpenBao response had no data field");
        }

        @SuppressWarnings("unchecked")
        List<String> caChain = (List<String>) data.getOrDefault("ca_chain", List.of());

        return new IssuedCertificate(
                (String) data.get("certificate"),
                (String) data.get("private_key"),
                (String) data.get("serial_number"),
                (String) data.get("issuing_ca"),
                caChain
        );
    }

    private String resolvePassword(String requested) {
        return (requested == null || requested.isBlank()) ? DEFAULT_KEYSTORE_PASSWORD : requested;
    }

    private String resolveMount(String ca) {
        String mount = properties.pkiMounts().get(ca);
        if (mount == null) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND,
                    "Unknown CA '" + ca + "'. Known values: " + properties.pkiMounts().keySet());
        }
        return mount;
    }

    private <T> T callOpenBao(java.util.function.Supplier<T> call) {
        try {
            return call.get();
        } catch (RestClientResponseException e) {
            throw new ResponseStatusException(HttpStatus.BAD_GATEWAY,
                    "OpenBao request failed (" + e.getStatusCode() + "): " + e.getResponseBodyAsString(), e);
        }
    }
}
