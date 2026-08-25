# MaxKey 部署指南（deploy/）

## 一、说明

本目录集中存放经过 CI 实测的部署文件，与上游 `deployment/` 互不干扰。

### 1.1 目录结构

```
deploy/
├── docker/                  # Docker 单机编排
│   ├── docker-compose.yml          # 生产/测试通用编排（镜像来自 GHCR）
│   ├── docker-compose.local.yml    # 本地冒烟覆盖（使用 CI 本地构建的镜像）
│   ├── mysql/                      # MySQL 初始化 SQL 与配置（含 maxkey.sql）
│   ├── nginx/default.conf          # 网关反向代理配置
│   ├── frontend/                   # 认证前端镜像（nginx-only，COPY 预构建 dist）
│   └── mgt-frontend/               # 管理前端镜像
└── k8s/                    # Kubernetes 编排（kustomize）
    ├── base/                       # 通用资源（namespace/secret/mysql/各服务/nginx）
    ├── overlays/dev/               # 开发覆盖（固定镜像标签）
    └── kind/kind.yaml              # 本地 kind 集群配置（CI 实部署验证用）
```

### 1.2 镜像清单（GitHub 容器仓库 GHCR）

| 镜像 | 端口 | 说明 |
| --- | --- | --- |
| `ghcr.io/<owner>/maxkey` | 9527 (`/sign/`) | 认证服务端 |
| `ghcr.io/<owner>/maxkey-mgt` | 9526 (`/maxkey-mgt-api/`) | 管理端 |
| `ghcr.io/<owner>/maxkey-openapi` | 9525 (`/maxkey-openapi/`) | OpenAPI |
| `ghcr.io/<owner>/maxkey-frontend` | 8527 | 认证前端（静态） |
| `ghcr.io/<owner>/maxkey-mgt-frontend` | 8526 | 管理前端（静态） |

`<owner>` 为 GitHub 仓库所有者（本仓库为 `adminlinzi`）。

> 注：`maxkey-gateway` 模块在当前源码中为未完成 stub（无 bootJar、网关依赖已注释），**不提供镜像**。

### 1.3 前置条件

- Docker Engine + Docker Compose v2（Docker 单机方案）
- kubectl + kustomize（Kubernetes 方案）
- kind（可选，本地 kind 实部署验证）

---

## 二、配置

### 2.1 镜像标签

CI 推送的标签规则：

| 触发方式 | 标签 | 用途 |
| --- | --- | --- |
| Release tag（如 `4.2.0`） | `<version>`、`latest`、`sha-<commit>` | 正式发版 |
| Manual Build（未发版） | `dev-<分支>-<短sha>`、`sha-<commit>` | 临时验证/小规模改动 |

### 2.2 环境变量

Docker Compose 通过环境变量注入镜像前缀与版本：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `GHCR` | `ghcr.io/adminlinzi` | 镜像仓库前缀 |
| `MXK_VERSION` | `4.2.0`（取自 `gradle.properties`） | 镜像标签 |

### 2.3 数据库凭据

- **Docker Compose**：在 `deploy/docker/docker-compose.yml` 中通过环境变量 `MYSQL_ROOT_PASSWORD`、`DATABASE_PWD` 配置。
- **Kubernetes**：在 `deploy/k8s/base/secrets.yaml` 中配置。

> **警告**：默认凭据为 `root / maxkey`，**仅用于本地/测试**。生产环境务必修改，并使用 Sealed Secrets / External Secrets / CSI 驱动管理密钥，不要将明文密钥提交到仓库。

### 2.4 MySQL 初始化

首次启动 MySQL 时会自动执行 `deploy/docker/mysql/docker-entrypoint-initdb.d/` 下的 SQL：

1. `init.sql`：创建 `maxkey` 数据库。
2. `latest/maxkey.sql`：导入 MaxKey 初始表结构与数据（约 11MB）。

> **K8s 注意**：`base/mysql/mysql-deployment.yaml` 使用 `hostPath` 挂载初始化 SQL，**仅适用于 kind/单机测试**。生产环境请改用托管数据库，或通过 db-init Job 加载初始化 SQL。

---

## 三、部署

### 3.1 Docker 单机部署

```bash
# 使用默认版本（MXK_VERSION 默认 4.2.0，可覆盖）
export MXK_VERSION=4.2.0
docker compose -f deploy/docker/docker-compose.yml up -d

# 查看状态
docker compose -f deploy/docker/docker-compose.yml ps
docker compose -f deploy/docker/docker-compose.yml logs -f maxkey
```

### 3.2 Kubernetes 部署

```bash
# 开发环境（固定标签 4.2.0）
kubectl apply -k deploy/k8s/overlays/dev

# 指定版本部署（覆盖标签后应用）
cd deploy/k8s/overlays/dev
kustomize edit set image maxkey=ghcr.io/<owner>/maxkey:9.9.9
kubectl apply -k .

# 查看
kubectl -n maxkey get all
```

### 3.3 本地 kind 实部署验证

```bash
# 创建 kind 集群（自动挂载 MySQL 初始化 SQL 与配置）
kind create cluster --config deploy/k8s/kind/kind.yaml

# 设置镜像标签并部署
cd deploy/k8s/overlays/dev
for s in maxkey maxkey-mgt maxkey-openapi maxkey-frontend maxkey-mgt-frontend; do
  kustomize edit set image "$s=ghcr.io/<owner>/$s:4.2.0"
done
kubectl apply -k .

# 等待全部 rollout 完成
kubectl -n maxkey rollout status deploy/mysql --timeout=600s
kubectl -n maxkey rollout status deploy/maxkey --timeout=600s
```

---

## 四、访问测试

### 4.1 服务入口

| 入口 | 路径 | 后端服务 |
| --- | --- | --- |
| 认证端 | `/sign/` | maxkey:9527 |
| 认证前端 | `/maxkey/` | maxkey-frontend:8527 |
| 管理端 API | `/maxkey-mgt-api/` | maxkey-mgt:9526 |
| 管理前端 | `/maxkey-mgt/` | maxkey-mgt-frontend:8526 |
| OpenAPI | `/maxkey-openapi/` | maxkey-openapi:9525 |

### 4.2 Docker 单机访问测试

```bash
# 通过 nginx 网关访问（默认 80 端口）
curl -f http://localhost/sign/
curl -f http://localhost/maxkey/
curl -f http://localhost/maxkey-mgt/
```

### 4.3 Kubernetes / kind 访问测试

`maxkey-nginx` Service 使用 NodePort 30080，kind 已将其映射到本机 80：

```bash
kubectl -n maxkey get svc maxkey-nginx

# 本机直接访问
curl -f http://localhost/sign/
curl -f http://localhost/maxkey/
curl -f http://localhost/maxkey-mgt/
```

### 4.4 各服务健康检查

| 服务 | 检查方式 | 预期结果 |
| --- | --- | --- |
| mysql | `mysqladmin ping` | `mysqld is alive` |
| maxkey | TCP 9527 | 端口可连接 |
| maxkey-mgt | TCP 9526 | 端口可连接 |
| maxkey-openapi | TCP 9525 | 端口可连接 |
| maxkey-frontend | HTTP 8527 | 200 |
| maxkey-mgt-frontend | HTTP 8526 | 200 |
| maxkey-nginx | HTTP 80 | 200 / 302 |

### 4.5 CI/CD 流程

| 工作流 | 触发 | 职责 |
| --- | --- | --- |
| `.github/workflows/docs.yml` | PR / push main | 校验文档版本一致性；合并到 main 后用 git-cliff 回写 `CHANGELOG.md` |
| `.github/workflows/ci.yml` | PR / push main / 手动 | 构建产物 → 本地构建镜像 → `docker-compose` 冒烟 → `kustomize build | kubectl apply --dry-run=client` 校验 k8s 清单 |
| `.github/workflows/release.yml` | 推送语义化 tag（如 `4.2.0`） | 多架构构建并推送 GHCR → kind 实部署验证 → 创建 GitHub Release 并上传制品 |
| `.github/workflows/manual-build.yml` | 手动 `workflow_dispatch` | 少量改动未发版：构建产物 → 多架构推送 GHCR（`dev-<分支>-<sha>`，不建 Release）→ 可选 `docker-compose` 冒烟 |

### 4.6 手动构建（未发版）

少量代码修改、尚不想打版本 tag 时，可在仓库 **Actions → Manual Build → Run workflow** 手动触发：

- 默认在 `dev-<分支名>-<短sha>` 标签下多架构推送 5 个镜像到 GHCR（另打 `sha-<commit>`），**不创建 GitHub Release**。
- 支持三个输入项（均可留默认）：
  - `image_tag`：自定义镜像标签，留空则自动生成 `dev-<分支>-<短sha>`。
  - `push_images`：是否推送镜像（默认 `true`；设为 `false` 则只构建不推送）。
  - `smoke_test`：是否运行 `docker-compose` 本地冒烟（默认 `true`）。

> 拉取手动构建的镜像部署：`export MXK_VERSION=dev-<分支>-<短sha> && docker compose -f deploy/docker/docker-compose.yml up -d`

提交约定：建议遵循 Conventional Commits（`feat:` / `fix:` / `docs:` …），便于 git-cliff 自动归类生成 CHANGELOG。

> 说明文档一致性由 `scripts/check-docs.sh` 保证：`gradle.properties` 的版本必须为纯语义化版本，且 `README.md` 需同步提及该版本，否则 CI 失败。
