package com.openbaovault.pkiclient.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

import java.util.Map;

@ConfigurationProperties(prefix = "openbao")
public record OpenBaoProperties(
        String baseUrl,
        String token,
        String defaultRole,
        String encryptionRole,
        Map<String, String> pkiMounts
) {
}
