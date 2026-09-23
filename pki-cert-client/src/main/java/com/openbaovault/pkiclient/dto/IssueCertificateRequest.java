package com.openbaovault.pkiclient.dto;

public record IssueCertificateRequest(String commonName, String ttl, String password) {
}
