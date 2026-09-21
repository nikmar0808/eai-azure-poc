package com.utility.ingest;

import java.util.Objects;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

@Component
public class IntegrationClient {

    private static final Logger log = LoggerFactory.getLogger(IntegrationClient.class);
    private final RestClient restClient;

    public IntegrationClient(
            RestClient.Builder restClientBuilder,
            @Value("${integration.python.base-url}") String baseUrl,
            @Value("${integration.python.auth-token}") String authToken) {
        
        // Explicitly assert non-null bounds to clear compiler null-safety warnings
        String cleanBaseUrl = Objects.requireNonNull(baseUrl, "Downstream base URL configuration property cannot be null");
        String cleanAuthToken = Objects.requireNonNull(authToken, "Downstream authorization token property cannot be null");
        
        this.restClient = restClientBuilder
                .baseUrl(cleanBaseUrl)
                .defaultHeader("X-EAI-Token", cleanAuthToken)
                .defaultHeader("Content-Type", MediaType.APPLICATION_JSON_VALUE)
                .build();
    }

    public String forwardPayloadToTransformer(SmartMeterPayload payload) {
        int maxAttempts = 3;
        int attempt = 0;
        
        while (attempt < maxAttempts) {
            try {
                attempt++;
                log.info("Dispatching ingestion transaction for meter: {} to Python target. Attempt {}/{}", 
                        payload.meterId(), attempt, maxAttempts);

                return restClient.post()
                        .uri("/api/v1/transform")
                        .body(payload)
                        .retrieve()
                        .onStatus(status -> status.is4xxClientError(), (request, response) -> {
                            log.error("Client side exception hit validation barrier: Code {}", response.getStatusCode());
                            throw new RuntimeException("Downstream boundary failure: Ingestion aborted.");
                        })
                        .onStatus(status -> status.is5xxServerError(), (request, response) -> {
                            log.error("Server side exception on Python validation engine: Code {}", response.getStatusCode());
                            throw new RuntimeException("Downstream runtime failure: Target system unstable.");
                        })
                        .body(String.class);

            } catch (Exception e) {
                log.warn("Network path exception caught during transaction delivery: {}", e.getMessage());
                if (attempt >= maxAttempts) {
                    throw new RuntimeException("System retry thresholds exhausted. Processing halted for meter: " + payload.meterId(), e);
                }
                try {
                    Thread.sleep(1000L * attempt); 
                } catch (InterruptedException ie) {
                    Thread.currentThread().interrupt();
                    throw new RuntimeException("System transaction retry loop interrupted structurally.", ie);
                }
            }
        }
        throw new RuntimeException("Transaction pipeline dropped due to unforeseen scheduling errors.");
    }
}
