$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$composePath = Join-Path $root 'docker-compose.yml'
$compose = Get-Content -Raw -Encoding UTF8 $composePath

function Assert-True([bool]$condition, [string]$message) {
    if (-not $condition) {
        throw $message
    }
}

$coolifyCompose = $compose

Write-Host "=== Checking Coolify Production Topology ==="
Assert-True ($coolifyCompose -notmatch '(?m)^\s+container_name:') 'Coolify services must not set container_name'
Assert-True ($coolifyCompose -notmatch '(?m)^\s+ports:') 'Coolify stack must not publish host ports'
Assert-True ($coolifyCompose -notmatch '(?m)^networks:') 'Coolify stack must use the default network'
Assert-True ($coolifyCompose -notmatch 'condition:\s*service_healthy') 'Coolify deployment must not block compose up on dependency health'
Assert-True ($coolifyCompose -notmatch '\./(logs|conf)/') 'Coolify stack must not bind deployment checkout paths'
Assert-True ($coolifyCompose -notmatch '(?m)^\s+-\s+\./') 'Coolify stack must not use relative host bind mounts'
@('MYSQL_ROOT_PASSWORD','MYSQL_PASSWORD','ACTIVEMQ_USER','ACTIVEMQ_PASSWORD','MANAGER_JWT_SECRET','MERCHANT_JWT_SECRET') |
    ForEach-Object { Assert-True ($coolifyCompose -match "\$\{$($_):\?[^}]*\}") "Coolify variable $_ must be required" }
@('mysql','redis','activemq','payment','manager','merchant','ui-payment','ui-manager','ui-merchant') |
    ForEach-Object {
        $service = $_ -replace '-', '\-'
        $block = [regex]::Match($coolifyCompose, "(?ms)^  $service`:.*?(?=^  [a-z]|^volumes:|\Z)").Value
        Assert-True ($block -match 'healthcheck:') "Coolify service $_ missing healthcheck"
    }
@('manager-uploads','merchant-uploads','payment-uploads') |
    ForEach-Object { Assert-True ($coolifyCompose -match "(?m)^  $_`:") "Missing persistent volume $_" }

Write-Host "=== Checking Compose Topology ==="
Assert-True ($compose -match '(?m)^  activemq:') 'ActiveMQ service is required'
Assert-True ($compose -notmatch '(?m)^  (rabbitmq|rocketmq-namesrv|rocketmq-broker):') 'Only ActiveMQ is allowed'

$ips = [regex]::Matches($compose, '(?m)^\s+ipv4_address:\s*([^\r\n]+)') |
    ForEach-Object { $_.Groups[1].Value.Trim() }
Assert-True (($ips | Group-Object | Where-Object Count -gt 1).Count -eq 0) 'Duplicate static IP found'

Assert-True ($compose -notmatch 'nginx\.tar\.gz') 'Compose references missing nginx.tar.gz'
Assert-True ($compose -notmatch 'container_name:') 'container_name should be removed for Coolify compatibility'
Assert-True ($compose -match 'restart:\s+unless-stopped') 'Restart policy required for production'

Write-Host "=== Checking Dockerfile References ==="
@(
    'docker/mysql/Dockerfile',
    'docker/activemq/Dockerfile',
    'jeepay-payment/Dockerfile',
    'jeepay-manager/Dockerfile',
    'jeepay-merchant/Dockerfile',
    'jeepay-ui/Dockerfile'
) | ForEach-Object {
    Assert-True (Test-Path (Join-Path $root $_)) "Missing $_"
}

Get-ChildItem $root -Filter Dockerfile -Recurse |
    Where-Object FullName -notmatch '[\\/]target[\\/]' |
    ForEach-Object {
        $dockerfile = Get-Content -Raw -Encoding UTF8 $_.FullName
        Assert-True ($dockerfile -notmatch '(?m)^COPY\s+<<') "BuildKit-incompatible heredoc COPY in $($_.FullName)"
    }

$activeMqDockerfile = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'docker/activemq/Dockerfile')
if ($compose -match 'nc -z localhost 61616') {
    Assert-True ($activeMqDockerfile -match 'netcat-openbsd') 'ActiveMQ healthcheck requires netcat-openbsd in the image'
}

$managerDockerfile = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'jeepay-manager/Dockerfile')
Assert-True ($managerDockerfile -match 'fontconfig' -and $managerDockerfile -match 'fonts-dejavu-core') 'Manager captcha image requires fontconfig and fonts-dejavu-core'

@('jeepay-manager', 'jeepay-merchant', 'jeepay-payment') | ForEach-Object {
    $modulePom = Get-Content -Raw -Encoding UTF8 (Join-Path $root "$_/pom.xml")
    Assert-True ($modulePom -match '<artifactId>spring-boot-starter-validation</artifactId>') "Module $_ must include a Bean Validation implementation at runtime"
}

@('jeepay-payment', 'jeepay-manager', 'jeepay-merchant') | ForEach-Object {
    Assert-True ($compose -match "dockerfile:\s+$_/Dockerfile") "Compose does not reference $_/Dockerfile"
}

Write-Host "=== Checking Healthchecks ==="
@('mysql', 'redis', 'activemq', 'payment', 'manager', 'merchant', 'ui-payment', 'ui-manager', 'ui-merchant') |
    Where-Object { $compose -match "(?m)^  $($_ -replace '-', '\-'):" } |
    ForEach-Object {
        $svc = $_ -replace '-', '\-'
        $pattern = "(?ms)^  $svc`:.*?(?=^  \w+:|^volumes:|^networks:|\Z)"
        $serviceBlock = [regex]::Match($compose, $pattern).Value
        Assert-True ($serviceBlock -match 'healthcheck:') "Service $_ missing healthcheck"
    }

Write-Host "=== Checking Configuration Files ==="
$serviceSources = Get-ChildItem (Join-Path $root 'jeepay-service/src/main/java') -Filter '*Service.java' -Recurse
$serviceSources | ForEach-Object {
    $source = Get-Content -Raw -Encoding UTF8 $_.FullName
    $classMatch = [regex]::Match($source, 'public\s+class\s+(\w+Service)\b')
    if ($classMatch.Success) {
        $serviceClass = [regex]::Escape($classMatch.Groups[1].Value)
        Assert-True ($source -notmatch "(?m)private\s+$serviceClass\s+\w+\s*;") "Service $($classMatch.Groups[1].Value) must not inject itself"
    }
}
$legacyRedisBindings = & rg -n 'spring\.redis\.' (Join-Path $root 'jeepay-manager/src/main/java') (Join-Path $root 'jeepay-merchant/src/main/java') (Join-Path $root 'jeepay-payment/src/main/java')
Assert-True ($LASTEXITCODE -ne 0) "Legacy Spring Boot 2 Redis bindings remain:`n$legacyRedisBindings"
@(
    'conf/payment/application.yml',
    'conf/manager/application.yml',
    'conf/merchant/application.yml',
    'docs/sql/init.sql',
    'jeepay-ui/default.conf.template',
    'jeepay-ui/docker-entrypoint.sh',
    '.env.example'
) | ForEach-Object {
    Assert-True (Test-Path (Join-Path $root $_)) "Missing $_"
}

Get-ChildItem (Join-Path $root 'conf') -Filter application.yml -Recurse |
    Where-Object FullName -notmatch 'devCommons' |
    ForEach-Object {
        $yaml = Get-Content -Raw -Encoding UTF8 $_.FullName
        Assert-True ($yaml -notmatch 'mysql8|redis6|activemq5') "Legacy hostname in $($_.FullName)"
        Assert-True ($yaml -notmatch '(?m)^\s+jwt-secret:\s*(?!\$\{)\S+') "Plain JWT secret in $($_.FullName)"
    }

Write-Host "=== Checking Maven Wrapper ==="
@(
    '.mvn/wrapper/maven-wrapper.properties',
    'mvnw',
    'mvnw.cmd'
) | ForEach-Object {
    Assert-True (Test-Path (Join-Path $root $_)) "Missing $_"
}

Write-Host "=== Checking .env.example Completeness ==="
$envExample = Get-Content -Raw -Encoding UTF8 (Join-Path $root '.env.example')
@(
    'MYSQL_ROOT_PASSWORD',
    'MYSQL_DATABASE',
    'MYSQL_USER',
    'MYSQL_PASSWORD',
    'ACTIVEMQ_USER',
    'ACTIVEMQ_PASSWORD',
    'MANAGER_JWT_SECRET',
    'MERCHANT_JWT_SECRET',
    'JEEPAY_CORS_ALLOWED_ORIGINS'
) | ForEach-Object {
    Assert-True ($envExample -match "(?m)^$_=") ".env.example missing $_"
}

Write-Host ''
Write-Host 'Deployment verification passed. Coolify compatible.' -ForegroundColor Green
