resource "azurerm_cdn_frontdoor_profile" "poc" {
  name                = "poc-eai-afd"
  resource_group_name = azurerm_resource_group.poc_aca.name
  sku_name            = "Standard_AzureFrontDoor"
}

resource "azurerm_cdn_frontdoor_endpoint" "poc" {
  name                     = "poc-eai-afd-endpoint"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.poc.id
}

resource "azurerm_cdn_frontdoor_origin_group" "react_readings" {
  name                     = "react-readings-origin-group"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.poc.id

  health_probe {
    path                = "/"
    protocol            = "Https"
    request_type        = "GET"
    interval_in_seconds = 60
  }

  load_balancing {}
}

resource "azurerm_cdn_frontdoor_origin" "react_readings" {
  name                          = "react-readings-origin"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.react_readings.id
  host_name                     = azurerm_container_app.react_readings.latest_revision_fqdn
  origin_host_header            = azurerm_container_app.react_readings.latest_revision_fqdn
  certificate_name_check_enabled = true
}

# Static assets: cached at the edge.
resource "azurerm_cdn_frontdoor_route" "static" {
  name                          = "static-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.poc.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.react_readings.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.react_readings.id]
  patterns_to_match             = ["/*"]
  supported_protocols            = ["Https"]
  https_redirect_enabled        = true
  forwarding_protocol            = "HttpsOnly"

  cache {
    query_string_caching_behavior = "IgnoreQueryString"
  }
}

# API calls: never cached — a separate route, same origin, no cache block.
resource "azurerm_cdn_frontdoor_route" "api" {
  name                          = "api-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.poc.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.react_readings.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.react_readings.id]
  patterns_to_match             = ["/api/*"]
  supported_protocols            = ["Https"]
  https_redirect_enabled        = true
  forwarding_protocol            = "HttpsOnly"
  # No cache{} block — caching is off by default for this route.
}

output "front_door_endpoint_hostname" { value = azurerm_cdn_frontdoor_endpoint.poc.host_name }
