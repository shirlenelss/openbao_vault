package com.openbaovault.pkiclient.web;

import com.openbaovault.pkiclient.dto.IssueCertificateRequest;
import com.openbaovault.pkiclient.service.OpenBaoPkiService;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/certificates")
public class CertificateController {

    private static final MediaType PKCS12 = MediaType.valueOf("application/x-pkcs12");

    private final OpenBaoPkiService pkiService;

    public CertificateController(OpenBaoPkiService pkiService) {
        this.pkiService = pkiService;
    }

    @PostMapping("/{ca}")
    public ResponseEntity<byte[]> issue(@PathVariable String ca, @RequestBody IssueCertificateRequest request) {
        byte[] keystore = pkiService.issueKeystore(ca, request);
        return keystoreResponse(keystore, ca + ".p12");
    }

    @PostMapping("/pid-issuer/bundle")
    public ResponseEntity<byte[]> issuePidIssuerBundle(@RequestBody IssueCertificateRequest request) {
        byte[] keystore = pkiService.issuePidIssuerBundle(request);
        return keystoreResponse(keystore, "pid-issuer-bundle.p12");
    }

    @GetMapping(value = "/{ca}/ca", produces = "application/x-pem-file")
    public ResponseEntity<String> getCaCertificate(@PathVariable String ca) {
        String pem = pkiService.getCaCertificatePem(ca);
        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType("application/x-pem-file"))
                .body(pem);
    }

    @GetMapping("/{ca}/truststore")
    public ResponseEntity<byte[]> getTrustStore(@PathVariable String ca,
                                                 @RequestParam(required = false) String password) {
        byte[] trustStore = pkiService.issueTrustStore(ca, password);
        return keystoreResponse(trustStore, ca + "-truststore.p12");
    }

    private ResponseEntity<byte[]> keystoreResponse(byte[] keystore, String filename) {
        return ResponseEntity.ok()
                .contentType(PKCS12)
                .header(HttpHeaders.CONTENT_DISPOSITION,
                        ContentDisposition.attachment().filename(filename).build().toString())
                .body(keystore);
    }
}
