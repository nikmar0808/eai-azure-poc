package com.utility.ingestion.api.dto;

import com.fasterxml.jackson.annotation.JsonProperty;

public record TransformationResponse(
        String message,
        Metadata metadata,
        @JsonProperty("analytics_summary") AnalyticsSummary analyticsSummary
) {
    public record Metadata(
            @JsonProperty("processed_asset") String processedAsset,
            @JsonProperty("regional_zone") String regionalZone,
            @JsonProperty("intervals_saved") int intervalsSaved
    ) {
    }

    public record AnalyticsSummary(
            @JsonProperty("cumulative_kwh") double cumulativeKwh,
            @JsonProperty("average_load_per_interval") double averageLoadPerInterval
    ) {
    }
}
