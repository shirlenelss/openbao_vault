package com.openbaovault.pkiclient;

import com.openbaovault.pkiclient.config.OpenBaoProperties;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;

@SpringBootApplication
@EnableConfigurationProperties(OpenBaoProperties.class)
public class PkiCertClientApplication {

    public static void main(String[] args) {
        SpringApplication.run(PkiCertClientApplication.class, args);
    }
}
