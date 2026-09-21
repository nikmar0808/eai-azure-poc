package com.utility.ingest;

import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Size;
import java.util.List;

public record SmartMeterPayload(
    @JsonProperty("meter_id")
    @NotBlank(message = "Meter ID cannot be blank")
    @Size(min = 5, max = 20, message = "Meter ID must be between 5 and 20 characters")
    String meterId,

    @JsonProperty("grid_zone")
    @NotBlank(message = "Grid Zone cannot be blank")
    String gridZone,
    
    @NotEmpty(message = "Readings array cannot be empty")
    @Valid 
    List<MeterReading> readings
) {}
