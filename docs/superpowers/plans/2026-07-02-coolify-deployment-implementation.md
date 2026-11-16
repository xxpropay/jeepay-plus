# Coolify Production Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Jeepay deploy reliably and securely from a clean Git checkout using Coolify's Docker Compose build pack.

**Architecture:** Use `docker-compose.yml` directly for Coolify, convert backend images to Maven multi-stage builds, and expose only three Nginx UI services. Infrastructure and APIs remain on the Compose private network with required secrets, health-gated startup, and named storage.

**Tech Stack:** Docker Compose, Coolify, Java 17, Maven 3.9, Spring Boot Actuator, Node.js 20, npm workspaces, Nginx, MySQL 8.4, Redis 7.4, ActiveMQ.

---

### Task 1: Add Coolify deployment regression checks

**Files:**
- Modify: `scripts/verify-deployment.ps1`
- Test: `scripts/verify-deployment.ps1`

- [ ] Add assertions requiring health checks, required-variable syntax, named upload volumes, and no `container_name`, custom network, or host `ports` entries in `docker-compose.yml`.
- [ ] Run `./scripts/verify-deployment.ps1` and confirm it fails because the existing Compose topology is not Coolify-safe.
- [ ] Commit as `test: define Coolify deployment invariants`.

### Task 2: Make backend images build from a clean checkout

**Files:**
- Modify: `jeepay-payment/Dockerfile`
- Modify: `jeepay-manager/Dockerfile`
- Modify: `jeepay-merchant/Dockerfile`
- Create: `.dockerignore`

- [ ] Convert each Dockerfile to a `maven:3.9-eclipse-temurin-17` build stage running `mvn -pl <module> -am package -DskipTests`.
- [ ] Copy only the generated module JAR into an `eclipse-temurin:17-jre-jammy` runtime stage.
- [ ] Create a non-root `jeepay` user, copy the service configuration into the image, install `curl`, and add an Actuator health check.
- [ ] Add `.dockerignore` exclusions for `.git`, `.idea`, `.worktrees`, logs, frontend `node_modules`/`dist`, and all `target` directories.
- [ ] Run Maven package and the deployment regression test.
- [ ] Commit as `build: make backend images self contained`.

### Task 3: Add backend health endpoints

**Files:**
- Modify: `pom.xml`
- Modify: `jeepay-manager/pom.xml`
- Modify: `jeepay-merchant/pom.xml`
- Modify: `jeepay-payment/pom.xml`
- Modify: `conf/manager/application.yml`
- Modify: `conf/merchant/application.yml`
- Modify: `conf/payment/application.yml`
- Modify: manager and merchant `WebSecurityConfig.java`

- [ ] Add `spring-boot-starter-actuator` and expose only `health` with probe details hidden.
- [ ] Permit unauthenticated `GET /actuator/health` in both Spring Security filter chains.
- [ ] Run the full Maven test suite and verify `/actuator/health` configuration statically.
- [ ] Commit as `feat: expose deployment health endpoints`.

### Task 4: Create the production Coolify stack

**Files:**
- Modify: `docker-compose.yml`

- [ ] Define MySQL, Redis, and ActiveMQ health checks with named data volumes and `${VAR:?}` secrets.
- [ ] Define the three backend builds, environment variables, health checks, named log/upload volumes, health-gated dependencies, and `restart: unless-stopped`.
- [ ] Define the three UI builds on port 80 with internal backend hostnames and no host port mappings.
- [ ] Omit `container_name`, custom networks, and all `ports` keys.
- [ ] Run deployment regression checks and `docker compose config --quiet` where Docker is available.
- [ ] Commit as `deploy: add secure Coolify compose stack`.

### Task 5: Make frontend builds reproducible

**Files:**
- Modify: `jeepay-ui/Dockerfile`
- Modify: `jeepay-ui/package.json`
- Verify: child workspace `package-lock.json` files

- [ ] Verify each child lock matches its package manifest.
- [ ] Change the image build to run `npm ci` in the selected child workspace and make `NPM_REGISTRY` a build argument.
- [ ] Build cashier, manager, and merchant production assets.
- [ ] Commit as `build: make Coolify frontend builds reproducible`.

### Task 6: Document and verify Coolify deployment

**Files:**
- Create: `docs/deploy/coolify.md`
- Modify: `README.md`
- Modify: `.github/workflows/ci.yml`

- [ ] Document the Compose path, required variables, three domain mappings, persistence, first-run SQL behavior, backups, and upgrade procedure.
- [ ] Add CI validation for the Coolify Compose file and deployment regression script.
- [ ] Run Maven tests, frontend builds, all PowerShell verification scripts, secret scans, and `git diff --check`.
- [ ] Commit as `docs: add Coolify production deployment guide`.
