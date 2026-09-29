package com.utility.ingestion.client;

import com.utility.ingestion.api.dto.BulkIngestionRequest;
import com.utility.ingestion.api.dto.TransformationResponse;
import com.utility.ingestion.configuration.IntegrationProperties;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

@Component
public class TransformationClient {

    private final RestClient restClient;

    public TransformationClient(
            RestClient.Builder restClientBuilder,
            IntegrationProperties properties) {

        this.restClient = restClientBuilder
                .baseUrl(properties.baseUrl())
                .defaultHeader("X-EAI-TOKEN", properties.authToken())
                .build();
    }

    public TransformationResponse transform(BulkIngestionRequest request) {
        return restClient.post()
                .uri("/api/v1/transform")
                .contentType(MediaType.APPLICATION_JSON)
                .body(request)
                .retrieve()
                .body(TransformationResponse.class);
    }
}
