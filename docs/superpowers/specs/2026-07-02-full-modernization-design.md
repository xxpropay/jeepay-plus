# Jeepay 全面现代化与完整性修复设计

## 目标

在保持现有支付产品边界和渠道协议兼容性的前提下，修复部署阻断、安全风险、业务完整性与仓库管理问题，并将后端全面迁移到 Java 17 与 Spring Boot 3。

## 实施策略

采用分阶段迁移。每个阶段建立独立验证点，避免把部署、框架、资金状态和前端问题混为一次不可诊断的大改。

## 技术基线

- Java 17。
- Spring Boot 3.5.x 与 Spring Security 6.5.x。
- Jakarta Servlet 6；所有受影响的 `javax.*` API 迁移到 `jakarta.*`。
- MyBatis-Plus 使用 `mybatis-plus-spring-boot3-starter:3.5.16`。
- JJWT 使用 0.13.x，并拆分为 API、运行时实现和 Jackson 模块。
- Node.js 20，用于三个 Vue 3 前端的统一构建。
- Maven Wrapper 固化 Maven 构建版本。

## 部署架构

Docker Compose 只包含以下基础服务和应用：

- MySQL：服务名 `mysql`，容器端口 `3306`。
- Redis：服务名 `redis`，容器端口 `6379`。
- ActiveMQ：服务名 `activemq`，容器端口 `61616`。
- Payment、Manager、Merchant 三个后端。
- Cashier、Manager、Merchant 三个独立前端容器。

删除 RabbitMQ、RocketMQ 及其卷配置。后端使用各模块自己的 Dockerfile。前端构建上下文固定为仓库内 `./jeepay-ui`。删除当前依赖缺失 `nginx.tar.gz` 的总 Nginx 服务；三个前端容器继续通过各自 Nginx 提供服务。

## 配置与密钥

- 数据库、Redis、ActiveMQ 地址全部使用 Compose 服务名，不使用静态 IP 或旧安装脚本容器名。
- 数据库密码、ActiveMQ 密码、JWT 密钥与其他敏感配置通过环境变量注入。
- 仓库提交 `.env.example`，真实 `.env` 加入 `.gitignore`。
- JWT 密钥缺失或少于 32 字节时应用拒绝启动。
- CORS 来源通过 `JEEPAY_CORS_ALLOWED_ORIGINS` 配置；默认只包含本地三个前端地址。
- 不再使用允许任意来源并携带凭据的 CORS 配置。

## 框架迁移

- Spring Security 从 `WebSecurityConfigurerAdapter` 迁移到 `SecurityFilterChain`、`WebSecurityCustomizer` 和 Lambda DSL。
- 使用 Spring Security 6 的 `requestMatchers`、方法安全与认证管理方式。
- 将 Servlet、Validation、Annotation 等 API 迁移到 Jakarta 命名空间。
- 统一由 Spring Boot BOM 管理 Spring 家族及常用依赖，删除不必要的显式覆盖。
- Jeepay SDK 版本由父 POM 单点管理，消除 Payment 模块的版本分叉。
- 升级或隔离不兼容 Jakarta 的第三方支付 SDK，不回退整体框架版本。

## 安全修复

- 移除 `printStackTrace()` 和仅记录异常消息的日志写法，统一记录上下文及异常堆栈，同时避免输出密钥和完整支付报文。
- MD5 只允许存在于上游渠道明确要求的协议适配器中，并加协议兼容说明和回归测试。
- 通用工具不再暴露可供密码或内部签名误用的 MD5 方法。
- 内部密码使用 BCrypt；内部消息鉴权或签名使用 HMAC-SHA256 或更强算法。
- 增加敏感信息扫描，防止 JWT 密钥、数据库密码和渠道私钥重新进入版本库。

## 业务完整性

### 云闪付终端号

在 `YsfpayIsvsubMchParams` 中增加必填 `termId`。每个特约商户独立配置终端号。条码支付缺少 `termId` 时直接返回明确配置错误，不再回退到硬编码值。

### 补单自动撤销

- 抽取共用关单服务，供手工关单 API 与 MQ 补单共同调用。
- 补单达到查询上限且仍为 `WAITING` 时调用渠道 `IPayOrderCloseService`。
- 只有渠道明确返回关闭成功，才使用带旧状态条件的更新将本地订单从“支付中”改为“已关闭”。
- 渠道不支持关单、返回失败、超时或异常时，订单保持“支付中”，记录结构化告警，并由定时查单继续核实。
- 不把未知渠道状态误标为支付失败或已关闭。

### 幂等与状态保护

- 支付回调、退款回调、MQ 重复消费和关单都使用条件状态迁移。
- 重复成功通知只触发一次成功后置业务与商户通知。
- 增加并发状态更新、重复回调、重复消息和关单异常测试。

## 前端与仓库治理

- 移除 `jeepay-ui/.git`，将前端源码直接纳入主仓库。
- 统一 workspace、lockfile 和 Node 20 构建入口。
- 三个前端分别执行生产构建，修复 Vite、Vue、Axios、Pinia 与 TypeScript 的版本冲突。
- 忽略 `node_modules`、`dist` 和本机环境文件，不提交生成物。

## 实施阶段

1. 建立 Maven Wrapper、Java 17 构建基线和部署配置静态测试。
2. 修复 Compose 与环境变量体系，只保留 ActiveMQ。
3. 迁移 Spring Boot 3.5、Jakarta、Spring Security 6、MyBatis-Plus、JJWT 和相关依赖。
4. 修复 JWT、CORS、异常日志和 MD5 使用边界。
5. 实现共用关单服务、补单自动撤销与云闪付 `termId`。
6. 将前端纳入主仓库，统一 Node 20 构建。
7. 补充支付状态、通知幂等、MQ 重复消费、关单失败和配置校验测试。
8. 完成全量验证和敏感信息扫描。

## 验收标准

- Compose 只包含 ActiveMQ，不包含 RabbitMQ/RocketMQ，且不存在重复静态 IP。
- Compose 中引用的 Dockerfile、构建上下文和挂载文件全部存在。
- 三个后端在 Java 17 下完成编译和测试。
- 三个后端可以基于 Spring Boot 3.5 启动，健康检查通过。
- 三个前端完成生产构建。
- JWT、CORS、数据库和 MQ 配置均来自受控环境变量。
- 补单撤销和云闪付终端号测试通过。
- 重复回调和 MQ 重复消费不会重复执行资金后置业务。
- 仓库不再包含嵌套 Git 元数据、明文密钥或构建产物。

## 非目标

- 不改变支付渠道既有业务报文格式。
- 不在缺少渠道协议依据时更改上游要求的签名算法。
- 不增加新的支付产品、结算模型或数据库业务实体。
