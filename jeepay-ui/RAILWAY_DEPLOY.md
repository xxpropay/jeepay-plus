# Railway 部署指南

本指南将帮助您将 Jeepay UI 项目部署到 Railway 平台。

## 前置准备

1. 拥有一个 [Railway](https://railway.app) 账号
2. 项目代码已推送到 GitHub/GitLab 仓库
3. 已在 Railway 上部署了后端服务（如需要）

## 部署步骤

### 1. 连接仓库

1. 登录 Railway 控制台
2. 点击 "New Project"
3. 选择 "Deploy from GitHub repo"
4. 授权 Railway 访问您的代码仓库
5. 选择包含 jeepay-ui 的仓库

### 2. 配置环境变量

在 Railway 控制台的项目设置中，添加以下环境变量：

| 变量名 | 必需 | 说明 | 示例值 |
|--------|------|------|--------|
| `PLATFORM` | ✅ | 选择要部署的平台 | `cashier`、`manager` 或 `merchant` |
| `BACKEND_HOST` | ✅ | 后端 API 服务地址 | `your-backend-service.railway.app` |
| `PORT` | ❌ | 端口号（Railway 会自动分配） | 通常无需手动设置 |

**注意**：`BACKEND_HOST` 只需填写域名，不需要包含 `http://` 或 `https://` 前缀，也不需要包含端口号（除非后端服务使用非标准端口）。

### 3. 部署配置

Railway 会自动检测到 `railway.json` 和 `Dockerfile` 并使用 Docker 构建方式。

默认部署 `manager` 平台。如需部署其他平台，可通过修改环境变量 `PLATFORM` 来切换。

### 4. 启动部署

1. 配置完成后，Railway 会自动开始构建和部署
2. 等待部署完成（通常需要 2-5 分钟）
3. 部署成功后，Railway 会提供一个公网访问地址

## 多平台部署

如需同时部署三个平台（cashier、manager、merchant），可以：

1. 在同一个 Railway 项目中创建多个服务
2. 每个服务连接同一个代码仓库
3. 为每个服务设置不同的 `PLATFORM` 环境变量
4. 为每个服务设置对应的 `BACKEND_HOST`

## 常见问题

### 构建失败

- 检查 Node.js 版本是否符合要求（>= 18）
- 检查依赖是否能正常安装
- 查看 Railway 构建日志获取详细错误信息

### 页面无法访问

- 确认 `BACKEND_HOST` 配置正确
- 检查后端服务是否正常运行
- 查看 Nginx 日志：在 Railway 控制台的服务日志中查看

### API 请求失败

- 确认后端服务地址可访问
- 检查 CORS 配置
- 确认 API 路径是否正确

## 本地测试 Docker 构建

在部署到 Railway 之前，您可以在本地测试 Docker 构建：

```bash
# 构建 manager 平台
docker build . --build-arg PLATFORM=manager -t jeepay-ui-manager:latest

# 运行测试
docker run -d -p 8080:80 -e BACKEND_HOST=your-backend-host jeepay-ui-manager:latest

# 访问 http://localhost:8080 测试
```

## 项目结构

```
jeepay-ui/
├── jeepay-ui-cashier/   # 聚合码收银台
├── jeepay-ui-manager/   # 运营平台
├── jeepay-ui-merchant/  # 商户系统
├── Dockerfile           # Docker 构建文件
├── railway.json         # Railway 配置
├── default.conf.template # Nginx 配置模板
└── RAILWAY_DEPLOY.md    # 本文档
```
