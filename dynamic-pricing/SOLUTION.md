# Dynamic Pricing - Caching Proxy

A Rails API that acts as a caching proxy for an upstream hotel pricing service. It reduces load on the expensive external API by maintaining an in-memory cache of all pricing combinations, refreshed automatically in the background.

## Quick Start

```bash
docker compose up --build
```

- **Our API**: http://localhost:3000/api/v1/pricing
- **Upstream API** (rate-api): http://localhost:8080 (internal, not called directly)

### Example Request

```bash
GET /api/v1/pricing?period=Summer&hotel=FloatingPointResort&room=SingletonRoom
```

```json
{ "rate": 69000.0 }
```

### Valid Parameters

| Parameter | Values |
|-----------|--------|
| `period` | `Summer`, `Autumn`, `Winter`, `Spring` |
| `hotel` | `FloatingPointResort`, `GitawayHotel`, `RecursionRetreat` |
| `room` | `SingletonRoom`, `BooleanTwin`, `RestfulKing` |

4 periods x 3 hotels x 3 rooms = **36 combinations** total.

## Architecture

```
Client  -->  PricingController  -->  PricingService  -->  Rails.cache (memory_store)
                                          |                      ^
                                          | (cache miss)         |
                                          v                      |
                                     RateApiClient          PricingCacheRefreshJob
                                          |                 (every 4 min, background)
                                          v
                                     rate-api:8080
```

### Request Flow

1. **Cache hit** - return cached rate immediately, no API call
2. **Cache miss** - check quota, call upstream API, validate response, cache result, return rate
3. **Background refresh** - every 4 minutes, a background job fetches all 36 combinations in a single API call and populates the cache

In practice, cache misses should be rare due to proactive refresh. The per-request fallback primarily handles cold starts or partial refresh failures.

### Why This Design

The upstream API is expensive and rate-limited (~1000 calls/day). With only 36 valid combinations, we can:
- **Batch-fetch everything** in one API call instead of fetching per-request
- **Refresh proactively** so users almost always hit cache
- Keep the entire cache in memory (no Redis needed for 36 entries)

## Caching Strategy

| Setting | Value | Rationale |
|---------|-------|-----------|
| **Cache store** | `memory_store` | 36 entries fit trivially in memory; no Redis dependency needed |
| **TTL** | 5 minutes | Per assignment requirement |
| **Refresh interval** | 4 minutes | Creates 1-minute overlap before TTL expires, minimizing cache misses |
| **Retry on failure** | 3 attempts, 20s apart | Fits within the 1-minute overlap window (~60s total) |

### Cache Lifecycle

```
t=0min    Refresh job runs, caches all 36 rates (TTL=5min)
t=4min    Next refresh runs, overwrites cache (new TTL=5min)
t=5min    Old entries would expire, but they were already refreshed at t=4min
```

The 1-minute overlap ensures that even if a refresh fails and retries 3 times (3 x 20s = 60s), the cache remains warm.

## Upstream Quota Budget

The upstream API allows ~1000 calls/day. Enforce a **950 call/day budget** as a safety margin:

- **`check_quota!`** - read-only check before making an API call
- **`consume!`** - atomic increment **after** a successful API response
- Failed API calls (500s, timeouts) do **not** count against the budget
- Budget resets daily (key expires at end of day + 1 hour buffer). The quota key uses `Date.current` in the configured Rails time zone. In production, this should align with the upstream provider's quota reset timezone (typically UTC).

With a 4-minute refresh interval: ~360 calls/day for the background job, leaving ~590 for individual cache-miss requests.

## Error Handling

### HTTP Status Codes

| Status | When |
|--------|------|
| `200` | Rate found (from cache or API) |
| `400` | Missing or invalid parameters |
| `404` | Unknown route |
| `405` | Wrong HTTP method (e.g. POST to /pricing) |
| `500` | Unhandled internal error |
| `502` | Upstream API returned error, invalid data, or missing rate |
| `504` | Upstream API timed out |
| `503` | Quota exhausted or unexpected upstream error |

### Response Format

All responses are JSON. Errors follow a consistent format:

```json
{ "error": "Human-readable error message" }
```

No stack traces, exception classes, or internal details are ever exposed to clients. A global `rescue_from StandardError` in `ApplicationController` acts as a safety net for any unhandled exceptions, logging the details server-side via `AppLog` and returning a clean `500` to the client.

### Upstream API Failures

| Scenario | Behavior |
|----------|----------|
| API returns HTTP error | Background job raises `UpstreamError`, triggers `retry_on` (3 attempts) |
| API times out | `Net::ReadTimeout` / `Net::OpenTimeout` caught, returns 504 |
| API returns null rate | Skipped (not cached), returns 502 for direct requests |
| API returns non-numeric rate (e.g. `"N/A"`) | Skipped (not cached), returns 502 for direct requests |
| API returns string number (e.g. `"15000"`) | Normalized to float (`15000.0`) and cached |
| Quota exhausted | API call skipped entirely, returns 503 |

### Design Decision: Fail Fast vs. Serve Stale

Chose to **return an error** rather than serve stale data when the upstream API fails. Rationale:

- **Pricing data is business-critical** - serving outdated rates could lead to incorrect bookings or financial discrepancies 
(but this would depend on business needs and stakeholder agreements, if needed we could serve slightly stale data rather than nothing) 
- **The client should know** when data is unreliable, rather than silently receiving stale prices
- **The 1-minute overlap** and 3 retry attempts make actual cache misses very rare
- In a real production system, a circuit breaker pattern could be layered on top if stale-serving becomes necessary

## Logging

All logs are structured JSON for easy parsing by log aggregation tools.

### Application Logs (AppLog)

```json
{
  "timestamp": "2026-02-23T05:34:11.613Z",
  "source": "PricingCacheRefreshJob",
  "event": "quota_consumed",
  "usage_today": 42
}
```

Events logged: `cache_hit`, `cache_miss`, `start`, `success`, `quota_consumed`, `quota_exceeded`, `crash`, `invalid_payload`

### Request Logs (Lograge)

```json
{
  "method": "GET",
  "path": "/api/v1/pricing",
  "controller": "Api::V1::PricingController",
  "action": "index",
  "status": 200,
  "duration": 5.74,
  "timestamp": "2026-02-23T05:36:12.940Z",
  "request_id": "a99afd67-318b-438a-83e7-1aceb55535b0"
}
```

## Health Endpoint

```bash
GET /api/v1/health
```

```json
{
  "status": "ok",
  "cache": {
    "total_combinations": 36,
    "cached_entries": 36,
    "coverage": "100.0%"
  },
  "upstream_budget": {
    "calls_today": 42,
    "limit": 950
  }
}
```

Useful for monitoring cache warmth and quota consumption without external tooling.

## Input Validation

All incoming parameters are validated against a **strict whitelist** before reaching the service layer:

- Missing or blank parameters -> `400`
- Values not in the allowed list -> `400` with message showing valid options
- Extra/unknown parameters -> accepted but logged as a warning (helps identify misconfigured clients)
- SQL injection, XSS, etc. -> impossible (whitelist rejects anything that's not an exact match)

## Security

### Current

- **No stack trace leakage** — all exceptions return clean JSON errors, details logged server-side only
- **Input whitelist** — params validated against a strict allowlist, preventing injection attacks
- **No user input in cache keys** — cache keys are built from validated values only

### What We'd Change in Production

- **Upstream API token** — currently hardcoded in `RateApiClient`. Should be moved to an environment variable (`ENV['RATE_API_TOKEN']`), secret manager or kubernetes secrets so it's not in source control
- **Client authentication** — our API is currently open. In production, require an API key or JWT token to prevent unauthorized access and enable per-client rate limiting
- **HTTPS** — enforce TLS in production for both inbound (client -> our API) and outbound (our API -> upstream) traffic
- **Rate limiting** — add middleware to throttle abusive clients before they reach the application layer

## Rate Handling

Rates are stored and returned as **floats** (`69000.0`). This handles:
- Integer rates from the API (`15000` -> `15000.0`)
- String rates (`"15000"` -> `15000.0`)
- Decimal rates (`"150.50"` -> `150.5`)

**Currency assumption**: Rates are assumed to be in **Japanese Yen (JPY)**. JPY does not use decimals, so decimal values from the API are preserved but are not expected in practice. If multi-currency support is needed in the future, the response format should include a `currency` field.

## Testing

```bash
# Run all tests
ruby -Itest -e "Dir.glob('test/**/*_test.rb').each { |f| require_relative f }"
```

**49 tests, 272 assertions** covering:

| Test File | Tests | Covers |
|-----------|-------|--------|
| `pricing_controller_test.rb` | 18 | Params validation, HTTP status codes, cache hit, extra params, routing (405/404), unhandled exceptions |
| `pricing_service_test.rb` | 14 | Cache hit/miss, rate normalization, null/non-numeric rates, timeout, quota, errors |
| `pricing_cache_refresh_job_test.rb` | 9 | Batch caching, rate validation, API errors with retry, quota exceeded |
| `pricing_upstream_budget_test.rb` | 6 | Increment, quota check, exceed handling |
| `health_controller_test.rb` | 2 | Empty cache, partial cache coverage |

All tests use mocks at the `RateApiClient` boundary - no Docker or network calls required.

### Integration Tests?

The upstream rate-api is unreliable, which would make integration tests non-deterministic. In production, we would add a smoke test suite that runs post-deploy against the real stack.

## Project Structure

```
app/
├── controllers/
│   ├── application_controller.rb      # request_id, rescue_from, 404/405 handlers
│   └── api/v1/
│       ├── pricing_controller.rb      # param validation, delegates to service
│       └── health_controller.rb       # cache & quota monitoring
├── jobs/
│   └── pricing_cache_refresh_job.rb   # background batch refresh, retry logic
├── models/
│   ├── app_log.rb                     # structured JSON logging
│   └── pricing_constants.rb           # valid combos, cache key format
└── services/
    ├── base_service.rb                # shared result/error pattern
    ├── pricing_upstream_budget.rb     # daily quota management
    └── api/v1/
        └── pricing_service.rb         # cache -> quota -> API -> validate -> cache

config/
├── initializers/
│   ├── lograge.rb                     # JSON request logging with timestamps
│   └── pricing_refresh.rb            # background refresh thread (4min loop)
└── routes.rb                          # GET endpoints + 405/404 catch-all

lib/
└── rate_api_client.rb                 # HTTParty client with timeouts
```

## Trade-offs & Future Considerations

### What We could Add in Production

- **Circuit breaker** - after N consecutive upstream failures, stop calling the API for a cooldown period and serve cached data. Prevents hammering a struggling service.
- **Redis cache** - `memory_store` doesn't survive server restarts and isn't shared across processes. Redis would provide persistence and work across multiple app instances.
- **Configurable combinations** - currently hardcoded in `PricingConstants`. If hotels/rooms/periods change frequently, extract to YAML config or a database table so changes don't require a code deploy.
- **Distributed locking** - the current single-process refresh thread works for a monolith, but a multi-instance deployment would need Redis-based locking to prevent duplicate refresh calls.
- **Metrics & alerting** - track cache hit ratio, upstream latency percentiles, quota burn rate. Alert when cache coverage drops below threshold.
- **Client identification** - accept an `X-Client-Id` header to identify which service or team is calling the API. This enables per-client quota tracking, usage analytics, and makes it easier to trace misconfigured clients from the warning logs.

### Monolith Considerations

On a monolithic architecture. The current solution is designed to work within that constraint:
- Uses `memory_store` (in-process, no external dependencies)
- Background refresh runs in a thread within the same process
- No Redis dependency required
- The `ApplicationJob` with `Async` adapter runs jobs in-process
