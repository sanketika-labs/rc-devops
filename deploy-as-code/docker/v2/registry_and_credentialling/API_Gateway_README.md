# API Security Using Kong Gateway

## Overview

Currently, our backend APIs are publicly accessible. To improve security
and centralize API management, we will deploy **Kong Gateway** as the
single entry point for all API requests.

Kong Gateway is built on top of **NGINX**, so a separate NGINX reverse
proxy is **not required**. Kong provides routing, authentication,
authorization, rate limiting, logging, and API security features out of
the box.

------------------------------------------------------------------------

## Architecture

``` text
                Client
                   |
                   v
            Kong Gateway
      +--------------------------+
      | Authentication           |
      | Authorization            |
      | JWT Validation           |
      | API Key Authentication   |
      | Rate Limiting            |
      | CORS                     |
      | Request Logging          |
      +--------------------------+
                   |
                   v
           Backend REST APIs
```

------------------------------------------------------------------------

## Objectives

-   Secure all public APIs
-   Centralize API access through Kong Gateway
-   Prevent direct access to backend services
-   Apply common security policies
-   Simplify API management

------------------------------------------------------------------------

## Key Features

-   API Routing
-   JWT Authentication
-   API Key Authentication
-   Authorization
-   Rate Limiting
-   CORS Management
-   Request & Response Logging
-   SSL/TLS Support
-   Plugin-based architecture

------------------------------------------------------------------------

## Deployment

Kong Gateway will run as a Docker container.

``` text
Docker
├── Kong Gateway
└── Backend APIs
```

Only Kong Gateway will be exposed externally.

------------------------------------------------------------------------

## Request Flow

``` text
Client
   |
   v
Kong Gateway
   |
   +-- Authenticate Request
   +-- Apply Security Policies
   +-- Route Request
   |
   v
Backend API
```

------------------------------------------------------------------------

## Implementation Steps

1.  Deploy Kong Gateway using Docker.
2.  Configure Services and Routes.
3.  Enable JWT or API Key authentication.
4.  Configure Rate Limiting and CORS.
5.  Validate API access through Kong.
6.  Expose only Kong Gateway publicly.

------------------------------------------------------------------------

## Official Documentation

-   Kong Gateway: https://developer.konghq.com/gateway/
-   Install with Docker:
    https://developer.konghq.com/gateway/install/docker/
-   Getting Started: https://developer.konghq.com/gateway/get-started/
-   Plugin Hub: https://developer.konghq.com/plugins/
-   JWT Plugin: https://developer.konghq.com/plugins/jwt/
-   Rate Limiting Plugin:
    https://developer.konghq.com/plugins/rate-limiting/
