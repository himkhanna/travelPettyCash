# PDD Petty Cash — Backend

Java 21 + Spring Boot 3 + PostgreSQL 15 + Flyway. Vertical-slice first
implementation covering `/auth`, `/me`, `/users`, `/trips`, `/expenses`,
and `/reports/trip/{id}`. Per CLAUDE.md §3/§4.

## Running locally

```bash
# 1. Postgres + MinIO (MinIO is unused in this slice, included for the
#    receipt-pipeline that lands next).
docker compose -f ops/docker-compose.yml up -d postgres

# 2. Backend (Java 21 required, Gradle wrapper not yet checked in —
#    use a local gradle 8+ install).
cd backend
gradle bootRun
```

The first run applies `V001__init.sql` + `V002__seed.sql`, leaving you
with the same seed users (`khalid.suwaidi`, `fatima.hashimi`, …) the
Flutter `DemoStore` uses.

## Auth (demo)

```bash
curl -sX POST http://localhost:8080/api/v1/auth/login \
  -H 'content-type: application/json' \
  -d '{"username":"khalid.suwaidi"}'
```

There is **no password check** — the prototype's landing-page role-picker
is the equivalent today. UAE Pass / proper credential verification is a
follow-up tracked in CLAUDE.md §16.

## Reports

```bash
TOKEN=...  # from /auth/login
curl -OJ -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8080/api/v1/reports/trip/trip-ksa01?format=xlsx"
```
