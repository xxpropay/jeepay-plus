# Coolify Production Deployment Design

## Goal

Make `codex/full-modernization` deployable from a clean Git checkout through Coolify's Docker Compose build pack, without relying on locally generated JARs or exposing internal services.

## Architecture

Use `docker-compose.yml` directly as the Coolify production source of truth. The stack contains MySQL, Redis, ActiveMQ, three Spring Boot services, and three Nginx UI services. Only the UI services receive Coolify domains; API and WebSocket traffic reaches the backend through each UI's same-origin Nginx proxy.

## Build

- Replace the three backend Dockerfiles with Java 17 Maven multi-stage builds that work from a clean clone.
- Add a root `.dockerignore` to exclude Git metadata, IDE files, logs, frontend generated files, and unrelated build output while retaining Maven sources.
- Build each frontend workspace with Node 20 and its committed lockfile using `npm ci`; make the npm registry configurable instead of hard-coding a mirror.
- Preserve runtime images as Java 17 JRE and Nginx Alpine images.

## Runtime and Networking

- Remove `container_name`, host port mappings, and custom networks from the Coolify Compose file.
- Use service names (`mysql`, `redis`, `activemq`, `payment`, `manager`, `merchant`) for internal communication.
- Expose container ports only through metadata; assign public domains only to `ui-payment`, `ui-manager`, and `ui-merchant` in Coolify.
- Mark all passwords and JWT secrets required with `${VAR:?}`. CORS accepts exact HTTPS production origins.

## Readiness and Recovery

- Add health checks for MySQL, Redis, ActiveMQ, all backends, and all UIs.
- Add Spring Boot Actuator health endpoints with only health information exposed.
- Gate dependent service startup with `condition: service_healthy` and use `restart: unless-stopped`.
- A backend is considered ready only after its database, Redis, and broker connections have initialized.

## Persistence

- Use named volumes for MySQL, Redis, ActiveMQ, service logs, and uploaded files.
- Do not bind deployment checkout paths for logs or configuration.
- Bake non-secret application configuration into backend images; inject all secrets at runtime.
- Document that database backups must be configured independently in Coolify or at the storage layer.

## Security

- Do not publish MySQL, Redis, ActiveMQ transport/admin ports, or backend ports on the host.
- Keep the ActiveMQ console inaccessible from the public proxy.
- Run backend containers as a non-root application user.
- Retain exact CORS origin configuration and same-origin `/api/` proxying.

## Verification

Extend `scripts/verify-deployment.ps1` to assert that `docker-compose.yml`:

- performs clean-clone backend builds;
- has no `container_name` or public internal-service port mappings;
- marks secrets required;
- defines health checks and persistent volumes;
- exposes only ActiveMQ as the MQ implementation.

Run Maven tests, frontend clean builds, Compose parsing, deployment/security checks, and Docker image builds where Docker is available. CI performs the same checks on every push.

## Deployment Procedure

Create a Coolify application using the Docker Compose build pack and the default `/docker-compose.yml` path, configure the required runtime variables, and assign HTTPS domains to the three UI services on container port 80. No public domains are assigned to infrastructure or backend services.
