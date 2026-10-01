package com.utility.ingestion.configuration;

import jakarta.validation.constraints.NotBlank;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

@Validated
@ConfigurationProperties(prefix = "integration.python")
public record IntegrationProperties(
        @NotBlank String baseUrl,
        @NotBlank String authToken
) {
}
