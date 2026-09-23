package com.openbaovault.pkiclient.dto;

import java.util.List;

public record IssuedCertificate(
        String certificate,
        String privateKey,
        String serialNumber,
        String issuingCa,
        List<String> caChain
) {
}
