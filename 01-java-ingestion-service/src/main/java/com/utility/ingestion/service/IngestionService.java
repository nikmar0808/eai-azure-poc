package com.utility.ingestion.service;

import com.utility.ingestion.api.dto.BulkIngestionRequest;
import com.utility.ingestion.api.dto.TransformationResponse;
import com.utility.ingestion.client.TransformationClient;
import org.springframework.stereotype.Service;

@Service
public class IngestionService {

    private final TransformationClient transformationClient;

    public IngestionService(TransformationClient transformationClient) {
        this.transformationClient = transformationClient;
    }

    public TransformationResponse ingest(BulkIngestionRequest request) {
        return transformationClient.transform(request);
    }
}
