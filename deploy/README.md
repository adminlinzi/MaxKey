# MaxKey 部署指南（deploy/）

## 一、说明

本目录集中存放经过 CI 实测的部署文件，与上游 `deployment/` 互不干扰。支持两种部署形态：

- **Docker Compose**：单机/单节点快速部署，适合开发、测试、小规模生产。
- **Kubernetes（kustomize）**：多节点、可声明式管理，适合生产或需要编排的场景。

### 1.1 目录结构

```
deploy/
├── docker/                    # Docker 单机编排
│   ├── docker-compose.yml            # 生产/测试通用编排（镜像来自 GHCR）
│   ├── docker-compose.local.yml      # CI 本地冒烟覆盖（使用本地构建的 :ci 镜像）
│   ├── mysql/                        # MySQL 8.4.2 初始化 SQL 与配置
│   │   ├── conf.d/mysqld.cnf
│   │   ├── docker-entrypoint-initdb.d/init.sql
│   │   └── docker-entrypoint-initdb.d/latest/maxkey.sql
│   ├── nginx/default.conf            # 网关反向代理配置
│   ├── frontend/                     # 认证前端镜像上下文（nginx-only）
│   └── mgt-frontend/                 # 管理前端镜像上下文（nginx-only）
└── k8s/                       # Kubernetes 编排（kustomize）
    ├── base/                          # 通用资源
    │   ├── namespace.yaml
    │   ├── secrets.yaml
    │   ├── mysql/
    │   ├── maxkey/
    │   ├── maxkey-mgt/
    │   ├── maxkey-openapi/
    │   ├── frontend/
    │   ├── mgt-frontend/
    │   └── nginx/
    ├── overlays/dev/                  # 开发/测试覆盖（固定镜像标签）
    └── kind/kind.yaml                 # 本地 kind 集群配置（CI 实部署验证用）
```

### 1.2 镜像清单（GitHub Container Registry，GHCR）

| 镜像 | 端口 | 上下文路径 | 说明 |
| --- | --- | --- | --- |
| `ghcr.io/<owner>/maxkey` | 9527 (`/sign/`) | `maxkey-webs/maxkey-web-maxkey` | 认证服务端 |
| `ghcr.io/<owner>/maxkey-mgt` | 9526 (`/maxkey-mgt-api/`) | `maxkey-webs/maxkey-web-mgt` | 管理端 API |
| `ghcr.io/<owner>/maxkey-openapi` | 9525 (`/maxkey-openapi/`) | `maxkey-webs/maxkey-web-openapi` | OpenAPI |
| `ghcr.io/<owner>/maxkey-frontend` | 8527 (`/maxkey/`) | `deploy/docker/frontend` | 认证前端（静态） |
| `ghcr.io/<owner>/maxkey-mgt-frontend` | 8526 (`/maxkey-mgt/`) | `deploy/docker/mgt-frontend` | 管理前端（静态） |

`<owner>` 为 GitHub 仓库所有者（本仓库为 `adminlinzi`）。

> 注：`maxkey-gateway` 模块在当前源码中为未完成 stub（无 bootJar、网关依赖已注释），**不提供镜像**。

### 1.3 前置条件

| 方案 | 必需工具 | 说明 |
| --- | --- | --- |
| Docker Compose | Docker Engine ≥ 20.10、Docker Compose v2 | 单机部署 |
| Kubernetes | kubectl ≥ 1.25、kustomize ≥ 5.0 | K8s 部署 |
| kind（可选） | kind ≥ 0.20 | 本地实部署验证，模拟 CI 环境 |

> 所有后端镜像基于 `eclipse-temurin:21-jre`，需 JDK 21 构建产物；前端镜像基于 `nginx:stable-alpine`。

---

## 二、配置

### 2.1 镜像标签

CI 推送的标签规则：

| 触发方式 | 标签 | 用途 |
| --- | --- | --- |
| Release tag（如 `4.2.0`，**不带 `v` 前缀**） | `<version>`、`latest`、`sha-<commit>` | 正式发版，同时创建 GitHub Release |
| Manual Build | `dev-<分支>-<短sha>`、`sha-<commit>` | 临时验证/小规模改动，**不创建 Release** |

### 2.2 环境变量

Docker Compose 通过环境变量注入镜像前缀与版本：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `GHCR` | `ghcr.io/adminlinzi` | 镜像仓库前缀 |
| `MXK_VERSION` | `4.2.0`（与 `gradle.properties` 一致） | 镜像标签 |

使用示例：

```bash
export MXK_VERSION=4.2.0
# 或拉取手动构建的镜像
export MXK_VERSION=dev-main-a1b2c3d
docker compose -f deploy/docker/docker-compose.yml up -d
```

### 2.3 数据库凭据

- **Docker Compose**：在 `deploy/docker/docker-compose.yml` 中通过环境变量 `MYSQL_ROOT_PASSWORD`、`DATABASE_PWD` 配置。
- **Kubernetes**：在 `deploy/k8s/base/secrets.yaml` 中配置。

> **警告**：默认凭据为 `root / maxkey`，**仅用于本地/测试**。生产环境务必修改，并使用 Sealed Secrets / External Secrets / CSI 驱动管理密钥，不要将明文密钥提交到仓库。

### 2.4 MySQL 初始化

首次启动 MySQL 时会自动执行 `deploy/docker/mysql/docker-entrypoint-initdb.d/` 下的 SQL：

1. `init.sql`：创建 `maxkey` 数据库。
2. `latest/maxkey.sql`：导入 MaxKey 初始表结构与数据（约 11MB）。

MySQL 版本为 **8.4.2**，已适配：

- 使用 `caching_sha2_password` 作为默认认证插件。
- 后端 JDBC URL 已包含 `allowPublicKeyRetrieval=true`，确保本地/测试环境可连接。
- 不再使用 MySQL 8.4 已删除的 `default-authentication-plugin` 变量。
- **K8s 中不覆盖 `command`**：保留官方镜像的 `docker-entrypoint.sh` entrypoint，确保数据目录初始化与 SQL 导入正常执行；运行参数通过 `conf.d/mysqld.cnf` 注入。
- **资源配置**：K8s 中 MySQL requests 2Gi/1CPU、limits 4Gi/2CPU；若初始化 11MB SQL 仍 OOM，可继续上调 `limits.memory`。

> **K8s 注意**：`base/mysql/mysql-deployment.yaml` 使用 `hostPath` 挂载初始化 SQL，**仅适用于 kind/单机测试**。生产环境请改用托管数据库，或通过 db-init Job 加载初始化 SQL。

---

## 三、部署

### 3.1 Docker 单机部署

```bash
cd deploy/docker

# 使用默认版本（MXK_VERSION 默认 4.2.0，可覆盖）
export MXK_VERSION=4.2.0
docker compose up -d

# 查看状态
docker compose ps
docker compose logs -f maxkey

# 停止并清理
docker compose down -v
```

### 3.2 Kubernetes 部署

#### 3.2.1 直接部署开发覆盖

```bash
# 开发环境（固定标签 4.2.0）
kubectl apply -k deploy/k8s/overlays/dev

# 查看
kubectl -n maxkey get all
kubectl -n maxkey rollout status deploy/mysql --timeout=600s
```

#### 3.2.2 指定版本部署

```bash
cd deploy/k8s/overlays/dev

# 替换为需要的版本
kustomize edit set image maxkey=ghcr.io/adminlinzi/maxkey:4.2.0
kustomize edit set image maxkey-mgt=ghcr.io/adminlinzi/maxkey-mgt:4.2.0
kustomize edit set image maxkey-openapi=ghcr.io/adminlinzi/maxkey-openapi:4.2.0
kustomize edit set image maxkey-frontend=ghcr.io/adminlinzi/maxkey-frontend:4.2.0
kustomize edit set image maxkey-mgt-frontend=ghcr.io/adminlinzi/maxkey-mgt-frontend:4.2.0

kubectl apply -k .
```

> 若 GHCR 包为私有，需先创建 imagePullSecret：
>
> ```bash
> kubectl -n maxkey create secret docker-registry ghcr-pull \
>   --docker-server=ghcr.io \
>   --docker-username=<你的 GitHub 用户名> \
>   --docker-password=<GHCR PAT 或 GITHUB_TOKEN>
> kubectl -n maxkey patch serviceaccount default -p '{"imagePullSecrets":[{"name":"ghcr-pull"}]}'
> ```

### 3.3 本地 kind 实部署验证

```bash
# 1. 创建 kind 集群（自动挂载 MySQL 初始化 SQL 与配置）
kind create cluster --config deploy/k8s/kind/kind.yaml

# 2. 设置镜像标签并部署
cd deploy/k8s/overlays/dev
for s in maxkey maxkey-mgt maxkey-openapi maxkey-frontend maxkey-mgt-frontend; do
  kustomize edit set image "$s=ghcr.io/adminlinzi/$s:4.2.0"
done
kubectl apply -k .

# 3. 等待全部 rollout 完成（MySQL 初始化约需 1-3 分钟）
for d in mysql maxkey maxkey-mgt maxkey-openapi maxkey-frontend maxkey-mgt-frontend maxkey-nginx; do
  kubectl -n maxkey rollout status "deploy/$d" --timeout=600s
done

# 4. 访问测试
curl -f http://localhost/sign/
curl -f http://localhost/maxkey/
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

通过 nginx 网关访问（默认 80 端口）：

```bash
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
| `.github/workflows/ci.yml` | PR / push main / 手动 | 构建产物 → 本地构建镜像 → `docker-compose` 冒烟 → `kustomize build \| kubectl apply --dry-run=client` 校验 k8s 清单 |
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

---

## 五、常见问题排查

### 5.1 Release 没有创建

`release.yml` 的 `release` job 依赖 `deploy-test`：

```yaml
release:
  needs: [prepare, build, images, deploy-test]
```

如果 `deploy-test`（kind 实部署验证）失败，`release` 会被跳过，GitHub Release 也就不会创建。**必须先解决 kind 部署问题**。

### 5.2 kind 中 mysql rollout 超时

常见原因：

1. **K8s 中覆盖了 MySQL `command`**：MySQL 官方镜像依赖 `docker-entrypoint.sh` 初始化数据目录并执行 `/docker-entrypoint-initdb.d/` 下的 SQL。K8s 中若用 `command: [mysqld, ...]` 会覆盖 entrypoint，导致以 root 启动 mysqld 直接崩溃。当前配置已改用默认 entrypoint + `conf.d/mysqld.cnf` 传参。
2. **MySQL 配置不兼容**：检查是否使用了 MySQL 8.4 已删除的变量（如 `default-authentication-plugin`）。
3. **初始化 SQL 执行慢**：`maxkey.sql` 约 11MB，首次启动需要 1-3 分钟；`startupProbe` 已留出足够时间。
4. **hostPath 挂载失败**：确认 kind 节点上 `/mnt/maxkey-mysql-init` 存在且包含 `init.sql` 与 `latest/maxkey.sql`。
5. **资源不足**：kind 单节点默认资源有限，当前已给 MySQL 分配 requests 2Gi/1CPU、limits 4Gi/2CPU。若日志出现 `OOMKilled`，继续上调 `limits.memory`。

排查命令：

```bash
kubectl -n maxkey get pods -o wide
kubectl -n maxkey describe deploy/mysql
kubectl -n maxkey logs -l app=mysql --tail=300
kubectl -n maxkey get events --sort-by=.lastTimestamp
```

### 5.3 GHCR 镜像拉取失败（ImagePullBackOff）

GitHub Packages 默认**私有**，即使仓库是公开的。需要在 GitHub 仓库页面 **Settings → Packages → Package settings** 中将每个包设置为 **Public**，或在目标集群创建 imagePullSecret。

### 5.4 CI dry-run 报错 `connection refused`

旧版使用 `kubectl apply -k ... --dry-run=client`，会尝试连接 API server。已修复为：

```bash
kustomize build deploy/k8s/overlays/dev | kubectl apply --dry-run=client --validate=false -f -
```

---

## 六、提交约定

建议遵循 Conventional Commits（`feat:` / `fix:` / `docs:` …），便于 git-cliff 自动归类生成 `CHANGELOG.md`。

> 说明文档一致性由 `scripts/check-docs.sh` 保证：`gradle.properties` 的版本必须为纯语义化版本，且 `README.md` 需同步提及该版本，否则 CI 失败。
