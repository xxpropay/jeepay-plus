# Jeepay Full Modernization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复全部部署阻断、高风险、业务完整性和仓库管理问题，并把项目迁移到 Java 17、Spring Boot 3.5 与 Jakarta。

**Architecture:** 采用分阶段迁移：先建立可重复的配置测试与构建工具，再修复部署拓扑，之后完成框架和安全迁移，最后实现资金状态保护与前端单仓治理。每个阶段单独提交并保持静态验证或自动化测试可运行。

**Tech Stack:** Java 17, Maven Wrapper, Spring Boot 3.5.x, Spring Security 6.5.x, Jakarta Servlet 6, MyBatis-Plus 3.5.16, JJWT 0.13.x, ActiveMQ, MySQL 8, Redis, Vue 3, Vite, Node.js 20, Docker Compose, PowerShell.

---

## 文件结构与职责

- `scripts/verify-deployment.ps1`：验证 Compose 服务、文件引用、配置主机名和敏感信息。
- `docker-compose.yml`：唯一容器部署拓扑，只保留 ActiveMQ。
- `.env.example`：可提交的环境变量模板；`.env` 仅保存本机值。
- `pom.xml`：Java 17、Boot 3.5、统一依赖与插件版本。
- `jeepay-*/pom.xml`：模块依赖迁移，不再覆盖父 POM 中的统一版本。
- `jeepay-*/src/test/**`：配置、安全和支付状态回归测试。
- `SecurityYmlConfig` / `SystemYmlConfig`：JWT 和 CORS 配置入口。
- `PayOrderCloseService`：手工关单与补单撤销共用的领域服务。
- `YsfpayIsvsubMchParams`：特约商户云闪付终端号。
- `jeepay-ui/package.json` 与根 lockfile：三个前端的统一 workspace。
- `.github/workflows/ci.yml`：Java、前端、配置验证流水线。

### Task 1: 建立部署配置回归测试

**Files:**
- Create: `scripts/verify-deployment.ps1`
- Test: `scripts/verify-deployment.ps1`

- [ ] **Step 1: 写入会对当前配置失败的验证脚本**

脚本读取 YAML 文本并断言：只存在 ActiveMQ、没有重复 IP、Compose 引用文件存在、后端连接主机名一致、没有明文 JWT。

```powershell
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$composePath = Join-Path $root 'docker-compose.yml'
$compose = Get-Content -Raw -Encoding UTF8 $composePath

function Assert-True([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

Assert-True ($compose -match '(?m)^  activemq:') 'ActiveMQ service is required'
Assert-True ($compose -notmatch '(?m)^  (rabbitmq|rocketmq-namesrv|rocketmq-broker):') 'Only ActiveMQ is allowed'

$ips = [regex]::Matches($compose, 'ipv4_address:\s*([^\r\n]+)') | ForEach-Object { $_.Groups[1].Value.Trim() }
Assert-True (($ips | Group-Object | Where-Object Count -gt 1).Count -eq 0) 'Duplicate static IP found'

@('jeepay-payment/Dockerfile','jeepay-manager/Dockerfile','jeepay-merchant/Dockerfile','jeepay-ui/Dockerfile') |
    ForEach-Object { Assert-True (Test-Path (Join-Path $root $_)) "Missing $_" }

Get-ChildItem (Join-Path $root 'conf') -Filter application.yml -Recurse |
    Where-Object FullName -notmatch 'devCommons' |
    ForEach-Object {
        $yaml = Get-Content -Raw -Encoding UTF8 $_.FullName
        Assert-True ($yaml -notmatch 'mysql8|redis6|activemq5') "Legacy hostname in $($_.FullName)"
        Assert-True ($yaml -notmatch '(?m)^\s+jwt-secret:\s*\S+') "Plain JWT secret in $($_.FullName)"
    }

Write-Host 'Deployment verification passed.'
```

- [ ] **Step 2: 运行测试并确认按预期失败**

Run: `powershell -ExecutionPolicy Bypass -File scripts/verify-deployment.ps1`

Expected: FAIL，首先报告 `Only ActiveMQ is allowed` 或 `Duplicate static IP found`。

- [ ] **Step 3: 提交测试基线**

```powershell
git add scripts/verify-deployment.ps1
git commit -m "test: add deployment configuration checks"
```

### Task 2: 修复 Compose、环境变量与 Docker 构建路径

**Files:**
- Modify: `docker-compose.yml`
- Modify: `.gitignore`
- Create: `.env.example`
- Modify: `conf/payment/application.yml`
- Modify: `conf/manager/application.yml`
- Modify: `conf/merchant/application.yml`

- [ ] **Step 1: 将 Compose 缩减为单 ActiveMQ 拓扑**

删除 RabbitMQ、RocketMQ 和总 Nginx 服务及相关卷。三个后端分别使用：

```yaml
payment:
  build:
    context: .
    dockerfile: jeepay-payment/Dockerfile
manager:
  build:
    context: .
    dockerfile: jeepay-manager/Dockerfile
merchant:
  build:
    context: .
    dockerfile: jeepay-merchant/Dockerfile
```

三个前端统一使用：

```yaml
build:
  context: ./jeepay-ui
  dockerfile: Dockerfile
```

MySQL 与 ActiveMQ 密码由环境变量传入：

```yaml
MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
MYSQL_DATABASE: ${MYSQL_DATABASE:-jeepaydb}
MYSQL_USER: ${MYSQL_USER:-jeepay}
MYSQL_PASSWORD: ${MYSQL_PASSWORD}
```

- [ ] **Step 2: 创建安全环境模板并忽略真实文件**

`.env.example`：

```dotenv
MYSQL_ROOT_PASSWORD=change-me-root
MYSQL_DATABASE=jeepaydb
MYSQL_USER=jeepay
MYSQL_PASSWORD=change-me-app
ACTIVEMQ_USER=system
ACTIVEMQ_PASSWORD=change-me-mq
MANAGER_JWT_SECRET=replace-with-at-least-32-random-bytes
MERCHANT_JWT_SECRET=replace-with-at-least-32-random-bytes
JEEPAY_CORS_ALLOWED_ORIGINS=http://localhost:9226,http://localhost:9227,http://localhost:9228
```

在 `.gitignore` 加入：

```gitignore
.env
!.env.example
```

- [ ] **Step 3: 统一三个后端的连接配置**

每份部署配置采用相同模式：

```yaml
spring:
  datasource:
    url: jdbc:mysql://${MYSQL_HOST:mysql}:3306/${MYSQL_DATABASE:jeepaydb}?zeroDateTimeBehavior=convertToNull&useUnicode=true&characterEncoding=utf-8&useSSL=false&allowPublicKeyRetrieval=true
    username: ${MYSQL_USER:jeepay}
    password: ${MYSQL_PASSWORD}
  redis:
    host: ${REDIS_HOST:redis}
    port: ${REDIS_PORT:6379}
  activemq:
    broker-url: failover:(tcp://${ACTIVEMQ_HOST:activemq}:61616?wireFormat.maxInactivityDuration=0)
    user: ${ACTIVEMQ_USER:system}
    password: ${ACTIVEMQ_PASSWORD}
```

- [ ] **Step 4: 运行部署测试确认通过**

Run: `powershell -ExecutionPolicy Bypass -File scripts/verify-deployment.ps1`

Expected: `Deployment verification passed.`

- [ ] **Step 5: 提交部署修复**

```powershell
git add docker-compose.yml .gitignore .env.example conf scripts/verify-deployment.ps1
git commit -m "fix: make ActiveMQ compose deployment self contained"
```

### Task 3: 将前端正式纳入主仓库

**Files:**
- Remove: `jeepay-ui/.git/`
- Add: `jeepay-ui/**`
- Modify: `jeepay-ui/.gitignore`

- [ ] **Step 1: 记录嵌套仓库当前提交并确认工作区干净**

Run: `git -C jeepay-ui rev-parse HEAD; git -C jeepay-ui status --short`

Expected: 输出提交 `11c8933...`，状态无未提交文件；如不为空则先停止并保护用户改动。

- [ ] **Step 2: 删除嵌套 Git 元数据**

在 PowerShell 中先验证目标路径：

```powershell
$target = (Resolve-Path 'jeepay-ui/.git').Path
$root = (Resolve-Path '.').Path
if (-not $target.StartsWith((Join-Path $root 'jeepay-ui'))) { throw 'Unsafe nested git path' }
Remove-Item -LiteralPath $target -Recurse -Force
```

- [ ] **Step 3: 验证前端成为主仓库普通文件**

Run: `git status --short -- jeepay-ui | Select-Object -First 20`

Expected: 前端文件显示为主仓库新增文件，且不包含 `node_modules`、`dist`。

- [ ] **Step 4: 提交前端源码**

```powershell
git add jeepay-ui
git commit -m "chore: integrate frontend into monorepo"
```

### Task 4: 建立 Java 17 与 Spring Boot 3.5 依赖基线

**Files:**
- Modify: `pom.xml`
- Modify: `jeepay-core/pom.xml`
- Modify: `jeepay-service/pom.xml`
- Modify: `jeepay-components/jeepay-components-mq/pom.xml`
- Modify: `jeepay-components/jeepay-components-oss/pom.xml`
- Modify: `jeepay-manager/pom.xml`
- Modify: `jeepay-merchant/pom.xml`
- Modify: `jeepay-payment/pom.xml`
- Create: `.mvn/wrapper/maven-wrapper.properties`
- Create: `mvnw`
- Create: `mvnw.cmd`

- [ ] **Step 1: 添加 Maven Wrapper 并验证旧基线编译失败点**

使用 Maven Wrapper 3.3.2、Maven 3.9.x。运行：

`./mvnw.cmd -DskipTests compile`

Expected: 当前环境或旧依赖在 Java 17/Boot 3 迁移前失败，保存首个真实编译错误作为迁移入口。

- [ ] **Step 2: 更新父 POM 基线**

```xml
<parent>
  <groupId>org.springframework.boot</groupId>
  <artifactId>spring-boot-starter-parent</artifactId>
  <version>3.5.11</version>
</parent>
<properties>
  <java.version>17</java.version>
  <maven.compiler.parameters>true</maven.compiler.parameters>
  <mybatis-plus.version>3.5.16</mybatis-plus.version>
  <jjwt.version>0.13.0</jjwt.version>
</properties>
```

父 POM 使用 MyBatis-Plus Boot 3 starter，并统一 Jeepay SDK 版本；Payment 删除 `pls-1.3.0` 覆盖。

- [ ] **Step 3: 更新 JJWT 模块依赖**

```xml
<dependency>
  <groupId>io.jsonwebtoken</groupId><artifactId>jjwt-api</artifactId><version>${jjwt.version}</version>
</dependency>
<dependency>
  <groupId>io.jsonwebtoken</groupId><artifactId>jjwt-impl</artifactId><version>${jjwt.version}</version><scope>runtime</scope>
</dependency>
<dependency>
  <groupId>io.jsonwebtoken</groupId><artifactId>jjwt-jackson</artifactId><version>${jjwt.version}</version><scope>runtime</scope>
</dependency>
```

- [ ] **Step 4: 运行依赖解析和编译收集 Jakarta 错误**

Run: `./mvnw.cmd -DskipTests compile`

Expected: 依赖解析成功；编译仅剩 Jakarta、Security API 或第三方 SDK 兼容错误。

- [ ] **Step 5: 提交构建基线**

```powershell
git add pom.xml */pom.xml jeepay-components/*/pom.xml .mvn mvnw mvnw.cmd
git commit -m "build: migrate baseline to Java 17 and Spring Boot 3"
```

### Task 5: 迁移 Jakarta 与框架 API

**Files:**
- Modify: all Java files importing `javax.servlet.*`, `javax.validation.*`, `javax.annotation.*`
- Modify: Spring Boot 3 不兼容的配置类
- Test: `jeepay-core/src/test/java/**`

- [ ] **Step 1: 添加 Jakarta 编译守卫测试**

创建 PowerShell 检查，禁止受影响的旧命名空间：

```powershell
$hits = rg -n 'import javax\.(servlet|validation|annotation)' jeepay-core jeepay-service jeepay-components jeepay-manager jeepay-merchant jeepay-payment
if ($LASTEXITCODE -eq 0) { throw "Legacy javax imports remain:`n$hits" }
```

首次运行应因现有 `javax.*` 导入失败。

- [ ] **Step 2: 机械迁移到 Jakarta 命名空间**

映射固定为：

```text
javax.servlet.*   -> jakarta.servlet.*
javax.validation.* -> jakarta.validation.*
javax.annotation.* -> jakarta.annotation.*
```

不要迁移仍属于 Java SE 的 `javax.crypto`、`javax.net`、`javax.xml`。

- [ ] **Step 3: 修复 Boot 3 配置属性和移除的常量**

将 `MediaType.APPLICATION_JSON_UTF8_VALUE` 改为 `MediaType.APPLICATION_JSON_VALUE`；根据编译错误逐一迁移，不做无关重构。

- [ ] **Step 4: 验证 Jakarta 守卫与模块编译**

Run: `./mvnw.cmd -DskipTests compile`

Expected: Jakarta 相关错误清零。

- [ ] **Step 5: 提交 Jakarta 迁移**

```powershell
git add jeepay-core jeepay-service jeepay-components jeepay-manager jeepay-merchant jeepay-payment
git commit -m "refactor: migrate application APIs to Jakarta"
```

### Task 6: 迁移 Spring Security、JWT 与 CORS

**Files:**
- Modify: `jeepay-manager/src/main/java/com/jeequan/jeepay/mgr/secruity/WebSecurityConfig.java`
- Modify: `jeepay-merchant/src/main/java/com/jeequan/jeepay/mch/secruity/WebSecurityConfig.java`
- Modify: both `JeeAuthenticationTokenFilter.java`
- Modify: `jeepay-core/src/main/java/com/jeequan/jeepay/core/jwt/JWTUtils.java`
- Modify: manager/merchant `SystemYmlConfig.java`
- Test: manager/merchant security tests
- Test: `jeepay-core/src/test/java/com/jeequan/jeepay/core/jwt/JWTUtilsTest.java`

- [ ] **Step 1: 写 JWT 弱密钥失败测试**

```java
@Test
void rejectsSecretShorterThan32Bytes() {
    assertThrows(IllegalArgumentException.class,
        () -> JWTUtils.generateToken(new JWTPayload(), "short"));
}
```

运行测试，Expected: FAIL，因为旧实现接受短密钥或方法签名尚未迁移。

- [ ] **Step 2: 使用 JJWT 0.13 密钥 API**

```java
private static SecretKey signingKey(String secret) {
    byte[] bytes = secret.getBytes(StandardCharsets.UTF_8);
    if (bytes.length < 32) {
        throw new IllegalArgumentException("JWT secret must contain at least 32 UTF-8 bytes");
    }
    return Keys.hmacShaKeyFor(bytes);
}
```

构建使用 `Jwts.builder().subject(...).signWith(signingKey(secret)).compact()`，解析使用 `Jwts.parser().verifyWith(key).build().parseSignedClaims(token)`。

- [ ] **Step 3: 写 CORS 白名单测试**

使用 `MockMvc` 验证允许来源返回 CORS header，未知来源不返回该 header。首次运行应因当前 `*` 配置失败。

- [ ] **Step 4: 迁移 SecurityFilterChain**

核心结构：

```java
@Bean
SecurityFilterChain securityFilterChain(HttpSecurity http,
                                        JeeAuthenticationTokenFilter tokenFilter) throws Exception {
    http.csrf(AbstractHttpConfigurer::disable)
        .cors(Customizer.withDefaults())
        .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
        .exceptionHandling(e -> e.authenticationEntryPoint(unauthorizedHandler))
        .authorizeHttpRequests(a -> a.anyRequest().authenticated())
        .addFilterBefore(tokenFilter, UsernamePasswordAuthenticationFilter.class);
    return http.build();
}
```

静态资源与匿名接口通过 `WebSecurityCustomizer` 或 `requestMatchers(...).permitAll()` 配置；过滤器改为 Spring Bean，不再 `new`。

- [ ] **Step 5: 从配置生成 CORS 白名单**

解析 `${JEEPAY_CORS_ALLOWED_ORIGINS:http://localhost:9226,http://localhost:9227,http://localhost:9228}`，调用 `setAllowedOrigins`，保留 credentials，不使用通配符。

- [ ] **Step 6: 运行安全测试**

Run: `./mvnw.cmd -pl jeepay-core,jeepay-manager,jeepay-merchant -am test`

Expected: JWT 与 CORS 测试全部 PASS。

- [ ] **Step 7: 提交安全迁移**

```powershell
git add jeepay-core jeepay-manager jeepay-merchant conf
git commit -m "security: migrate JWT CORS and filter chain"
```

### Task 7: 修复异常日志与 MD5 边界

**Files:**
- Modify: Java files containing `printStackTrace()`
- Modify: `jeepay-core/src/main/java/com/jeequan/jeepay/core/utils/JeepayKit.java`
- Modify: channel MD5 implementations
- Test: `scripts/verify-security.ps1`

- [ ] **Step 1: 写安全静态测试并确认失败**

```powershell
$prints = rg -n 'printStackTrace\(' jeepay-core jeepay-service jeepay-components jeepay-manager jeepay-merchant jeepay-payment
if ($LASTEXITCODE -eq 0) { throw "printStackTrace remains:`n$prints" }
$weakLogs = rg -n 'log\.error\(e\.getMessage\(\)\)' jeepay-*
if ($LASTEXITCODE -eq 0) { throw "Stack trace is discarded:`n$weakLogs" }
```

- [ ] **Step 2: 将异常处理改为结构化日志**

使用 `log.error("operation failed, payOrderId={}", payOrderId, e)`；工具类无法使用 Lombok 时增加 SLF4J logger。日志中不得输出私钥、密码和完整授权码。

- [ ] **Step 3: 收紧 MD5 API**

删除通用 `JeepayKit.md5` 的内部调用；渠道协议所需实现移动或保留在对应 channel 包，并命名为 `channelProtocolMd5Sign`，附注上游协议约束。密码与内部签名不得引用该方法。

- [ ] **Step 4: 运行静态测试和相关单元测试**

Run: `powershell -ExecutionPolicy Bypass -File scripts/verify-security.ps1`

Expected: PASS。

- [ ] **Step 5: 提交日志和算法边界修复**

```powershell
git add scripts/verify-security.ps1 jeepay-core jeepay-payment
git commit -m "security: harden exception logging and MD5 boundaries"
```

### Task 8: 抽取共用关单服务并补齐自动撤销

**Files:**
- Create: `jeepay-payment/src/main/java/com/jeequan/jeepay/pay/service/PayOrderCloseService.java`
- Modify: `jeepay-payment/src/main/java/com/jeequan/jeepay/pay/ctrl/payorder/CloseOrderController.java`
- Modify: `jeepay-payment/src/main/java/com/jeequan/jeepay/pay/mq/PayOrderReissueMQReceiver.java`
- Test: `jeepay-payment/src/test/java/com/jeequan/jeepay/pay/service/PayOrderCloseServiceTest.java`
- Test: `jeepay-payment/src/test/java/com/jeequan/jeepay/pay/mq/PayOrderReissueMQReceiverTest.java`

- [ ] **Step 1: 写“明确关闭成功才更新本地状态”测试**

```java
@Test
void closesLocalOrderOnlyWhenChannelConfirmsSuccess() {
    when(channelCloseService.close(order, context))
        .thenReturn(ChannelRetMsg.confirmSuccess(null));
    assertEquals(CloseResult.CLOSED, service.close(order));
    verify(payOrderService).updateIng2Close(order.getPayOrderId());
}

@Test
void keepsOrderPendingWhenChannelResultIsUnknown() {
    when(channelCloseService.close(order, context)).thenReturn(null);
    assertEquals(CloseResult.UNKNOWN, service.close(order));
    verify(payOrderService, never()).updateIng2Close(anyString());
}
```

Expected: FAIL，因为共用服务不存在。

- [ ] **Step 2: 实现关单结果模型与服务**

```java
public enum CloseResult { CLOSED, REJECTED, UNSUPPORTED, UNKNOWN }

@Transactional
public CloseResult close(PayOrder order) {
    IPayOrderCloseService channel = beanProvider.getIfAvailable();
    if (channel == null) return CloseResult.UNSUPPORTED;
    ChannelRetMsg result = channel.close(order, queryContext(order));
    if (result == null || result.getChannelState() == null) return CloseResult.UNKNOWN;
    if (result.getChannelState() != ChannelRetMsg.ChannelState.CONFIRM_SUCCESS) return CloseResult.REJECTED;
    return payOrderService.updateIng2Close(order.getPayOrderId())
        ? CloseResult.CLOSED : CloseResult.UNKNOWN;
}
```

实际 Bean 查找沿用现有 `ifCode + "PayOrderCloseService"` 规则，但封装在服务内。

- [ ] **Step 3: 让 Controller 使用共用服务**

Controller 只负责验签、订单查询、状态前置校验和响应映射，不再直接查找渠道 Bean。

- [ ] **Step 4: 写第 6 次 WAITING 自动关单测试**

```java
@Test
void attemptsCloseAfterLastWaitingQuery() {
    when(reissueService.processPayOrder(order)).thenReturn(ChannelRetMsg.waiting());
    receiver.receive(PayOrderReissueMQ.build(order.getPayOrderId(), 6));
    verify(closeService).close(order);
    verify(mqSender, never()).send(any(), anyInt());
}
```

- [ ] **Step 5: 实现补单撤销并保留未知状态**

达到上限时调用 `closeService.close(payOrder)`；非 `CLOSED` 只记录包含订单号、渠道和结果的告警，不更新为失败。

- [ ] **Step 6: 运行支付模块测试**

Run: `./mvnw.cmd -pl jeepay-payment -am test`

Expected: 关单与补单测试 PASS。

- [ ] **Step 7: 提交业务完整性修复**

```powershell
git add jeepay-payment
git commit -m "fix: close unresolved pay orders safely"
```

### Task 9: 将云闪付终端号迁移到特约商户配置

**Files:**
- Modify: `jeepay-core/src/main/java/com/jeequan/jeepay/core/model/params/ysf/YsfpayIsvsubMchParams.java`
- Modify: `jeepay-payment/src/main/java/com/jeequan/jeepay/pay/channel/ysfpay/YsfpayPaymentService.java`
- Modify: manager/merchant payment interface configuration UI files
- Test: `jeepay-payment/src/test/java/com/jeequan/jeepay/pay/channel/ysfpay/YsfpayPaymentServiceTest.java`

- [ ] **Step 1: 写缺失 termId 时失败的测试**

```java
@Test
void rejectsBarPaymentWithoutConfiguredTerminalId() {
    YsfpayIsvsubMchParams params = new YsfpayIsvsubMchParams();
    BizException ex = assertThrows(BizException.class,
        () -> YsfpayPaymentService.barParamsSet(request, order, params));
    assertEquals("云闪付终端号未配置", ex.getMessage());
}
```

Expected: FAIL，旧代码仍写死 `01727367`。

- [ ] **Step 2: 增加特约商户 termId 字段**

```java
/** 云闪付分配给特约商户的终端号。 */
private String termId;
```

- [ ] **Step 3: 从配置生成条码支付参数**

```java
if (StringUtils.isBlank(params.getTermId())) {
    throw new BizException("云闪付终端号未配置");
}
reqParams.put("termId", params.getTermId().trim());
```

调用方通过 `ConfigContextQueryService.queryIsvsubMchParams` 取得配置，不设置默认值。

- [ ] **Step 4: 在运营端和商户端配置表单增加必填项**

字段 key 固定为 `termId`，标签“终端编号”，只在云闪付特约商户配置中显示并校验非空。

- [ ] **Step 5: 运行后端测试和两个前端构建**

Run: `./mvnw.cmd -pl jeepay-payment -am test`

Run: `npm --prefix jeepay-ui run build:manager; npm --prefix jeepay-ui run build:merchant`

Expected: 全部 PASS。

- [ ] **Step 6: 提交终端号配置修复**

```powershell
git add jeepay-core jeepay-payment jeepay-ui
git commit -m "fix: configure YSF terminal per sub merchant"
```

### Task 10: 补充回调与 MQ 幂等测试

**Files:**
- Test: `jeepay-payment/src/test/java/com/jeequan/jeepay/pay/ctrl/payorder/ChannelNoticeControllerTest.java`
- Test: `jeepay-payment/src/test/java/com/jeequan/jeepay/pay/mq/PayOrderMchNotifyMQReceiverTest.java`
- Modify: relevant process/service classes only if tests reveal duplicate side effects

- [ ] **Step 1: 写重复成功通知测试**

构造同一订单两次成功通知，断言 `updateIng2Success` 的条件更新只有第一次返回 true，`payOrderProcessService.confirmSuccess` 只执行一次。

- [ ] **Step 2: 运行测试并确认当前行为**

Run: `./mvnw.cmd -pl jeepay-payment -Dtest=ChannelNoticeControllerTest test`

Expected: 若存在重复后置业务则 FAIL；若现有条件更新已保护则 PASS 并作为回归测试保留。

- [ ] **Step 3: 写 MQ 重复消息测试**

同一 notify record 连续消费两次，断言第二次因记录不再为 `STATE_ING` 而不发送 HTTP 通知。

- [ ] **Step 4: 最小化修复重复副作用**

所有后置业务必须位于成功的条件更新之后；不得先通知再更新状态。

- [ ] **Step 5: 运行支付模块全量测试并提交**

Run: `./mvnw.cmd -pl jeepay-payment -am test`

```powershell
git add jeepay-payment
git commit -m "test: protect payment callbacks and MQ idempotency"
```

### Task 11: 统一前端 workspace 与生产构建

**Files:**
- Modify: `jeepay-ui/package.json`
- Create: `jeepay-ui/package-lock.json`
- Remove: child `package-lock.json` files after root lockfile is generated
- Modify: child `package.json` files as required by clean install/build

- [ ] **Step 1: 清理依赖目录并执行根 workspace 干净安装**

在确认路径位于 `jeepay-ui` 后删除三个子项目 `node_modules`，然后运行：

`npm --prefix jeepay-ui install --package-lock-only`

Expected: 生成唯一根 lockfile。

- [ ] **Step 2: 添加统一验证脚本**

```json
{
  "scripts": {
    "build": "npm run build:cashier && npm run build:manager && npm run build:merchant",
    "check": "npm run build"
  },
  "engines": { "node": ">=20 <23" }
}
```

- [ ] **Step 3: 安装并构建三个前端**

Run: `npm --prefix jeepay-ui ci`

Run: `npm --prefix jeepay-ui run build`

Expected: 三个 Vite production build 均成功。

- [ ] **Step 4: 修复依赖冲突而不改变业务 UI**

统一 Vue 与 `@vue/compiler-sfc` 小版本；Pinia 使用稳定版；Vite/plugin-vue 使用彼此兼容版本；Axios 升级后修复废弃 API。每次只调整一个依赖组并重跑受影响前端构建。

- [ ] **Step 5: 提交前端构建治理**

```powershell
git add jeepay-ui
git commit -m "build: unify frontend workspace and lockfile"
```

### Task 12: 增加 CI 与最终验证

**Files:**
- Create: `.github/workflows/ci.yml`
- Modify: `README.md`
- Modify: `jeepay-ui/README.md`

- [ ] **Step 1: 创建 CI 流水线**

CI 使用 Java 17、Node 20，依次执行：

```yaml
- run: powershell -ExecutionPolicy Bypass -File scripts/verify-deployment.ps1
- run: powershell -ExecutionPolicy Bypass -File scripts/verify-security.ps1
- run: ./mvnw -B test
- run: npm ci
  working-directory: jeepay-ui
- run: npm run build
  working-directory: jeepay-ui
- run: docker compose --env-file .env.example config --quiet
```

- [ ] **Step 2: 更新运行文档**

README 明确：安装 Java 17、Docker、Node 20；复制 `.env.example` 为 `.env` 并替换密钥；运行 `docker compose up --build`。删除 submodule 和多 MQ 说明。

- [ ] **Step 3: 运行后端全量验证**

Run: `./mvnw.cmd clean test`

Expected: 所有模块 BUILD SUCCESS。

- [ ] **Step 4: 运行前端全量验证**

Run: `npm --prefix jeepay-ui ci; npm --prefix jeepay-ui run build`

Expected: 三个前端构建成功。

- [ ] **Step 5: 运行部署和安全验证**

Run: `powershell -ExecutionPolicy Bypass -File scripts/verify-deployment.ps1`

Run: `powershell -ExecutionPolicy Bypass -File scripts/verify-security.ps1`

Run: `docker compose --env-file .env.example config --quiet`

Expected: 三项均成功，无输出错误。

- [ ] **Step 6: 检查仓库状态和敏感信息**

```powershell
git status --short
rg -n 'jwt-secret:\s*[^$]|jeepaydb123456|BEGIN (RSA |EC )?PRIVATE KEY' --glob '!docs/superpowers/**' .
Get-ChildItem jeepay-ui -Force -Directory -Filter .git -Recurse
```

Expected: 只有计划内变更；敏感信息和嵌套 `.git` 均无命中。

- [ ] **Step 7: 提交 CI 与文档**

```powershell
git add .github README.md jeepay-ui/README.md
git commit -m "ci: verify modernized backend frontend and deployment"
```

## 最终完成条件

- 所有 12 个任务均有对应提交。
- Maven 全量测试、三个前端构建、Compose 解析、部署静态检查和安全扫描全部通过。
- 不以“环境缺工具”为完成依据；缺少 Java/Docker 时先安装或使用可复现工具链完成验证。
- 不覆盖任务开始前用户已有的非计划改动。
