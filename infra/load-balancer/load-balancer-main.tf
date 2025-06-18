# module: load-balancer

# Global static IP
data "google_compute_global_address" "lb_ipv6" {
  project = var.project_id
  name = "${var.environment}-lb-ipv6"
}

data "google_compute_global_address" "lb_ipv4" {
  project = var.project_id
  name = "${var.environment}-lb-ipv4"
}

# Serverless NEG for Cloud Run
resource "google_compute_region_network_endpoint_group" "neg" {
  name                  = "${var.environment}-neg"
  region                = var.gcp_region
  project               = var.project_id
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = var.cloud_run_service_name
  }
}

# Cloud Armor Security Policy (rate limiting)
resource "google_compute_security_policy" "armor" {
  project = var.project_id  
  name = "${var.environment}-rate-limit"
  description = "Rate limiting for public access"

  rule {
    priority = 2147483647
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }

    action = "rate_based_ban"
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      rate_limit_threshold {
        count        = var.rate_limit_count
        interval_sec = var.rate_limit_interval_sec
      }
      ban_duration_sec = var.ban_duration_sec
    #   ban_threshold {
    #     count        = var.ban_count
    #     interval_sec = var.ban_interval_sec
    #   }
    #   
    }
  }
}

# Backend service
resource "google_compute_backend_service" "lb_backend" {
  project = var.project_id
  name            = "${var.environment}-gbfs-api-backend"
  protocol        = "HTTP"
  port_name       = "http"
  timeout_sec     = 30
  security_policy = google_compute_security_policy.armor.id

  backend {
    group = google_compute_region_network_endpoint_group.neg.id
  }
}

# URL map
resource "google_compute_url_map" "lb_url_map" {
  project          = var.project_id    
  name            = "${var.environment}-url-map"
  default_service = google_compute_backend_service.lb_backend.id
}

# Target HTTPS proxy
resource "google_compute_target_https_proxy" "lb_https_proxy" {
  project          = var.project_id
  name             = "${var.environment}-https-proxy"
  ssl_certificates = [data.google_compute_ssl_certificate.cert.self_link]
  url_map          = google_compute_url_map.lb_url_map.id
}

# Forwarding rule
resource "google_compute_global_forwarding_rule" "https_forwarding_rule_ipv4" {
  project          = var.project_id  
  name                  = "${var.environment}-https-rule-ipv4"
  ip_address            = data.google_compute_global_address.lb_ipv4.address
  port_range            = "443"
  target                = google_compute_target_https_proxy.lb_https_proxy.id
  load_balancing_scheme = "EXTERNAL"
}
resource "google_compute_global_forwarding_rule" "https_forwarding_rule_ipv6" {
  project          = var.project_id  
  name                  = "${var.environment}-https-rule-ipv6"
  ip_address            = data.google_compute_global_address.lb_ipv6.address
  port_range            = "443"
  target                = google_compute_target_https_proxy.lb_https_proxy.id
  load_balancing_scheme = "EXTERNAL"
}

# Reference manually created SSL certificate
data "google_compute_ssl_certificate" "cert" {
  project = var.project_id  
  name = "gbfs-beta-api-mobilitydatabase-org"
}
