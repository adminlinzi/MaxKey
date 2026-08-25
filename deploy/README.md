# MaxKey 部署指南（deploy/）

本目录集中存放经过 CI 实测的部署文件，与上游 `deployment/` 互不干扰。

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

## 一、镜像清单（GitHub 容器仓库 GHCR）

| 镜像 | 端口 | 说明 |
| --- | --- | --- |
| `ghcr.io/<owner>/maxkey` | 9527 (`/sign/`) | 认证服务端 |
| `ghcr.io/<owner>/maxkey-mgt` | 9526 (`/maxkey-mgt-api/`) | 管理端 |
| `ghcr.io/<owner>/maxkey-openapi` | 9525 (`/maxkey-openapi/`) | OpenAPI |
| `ghcr.io/<owner>/maxkey-frontend` | 8527 | 认证前端（静态） |
| `ghcr.io/<owner>/maxkey-mgt-frontend` | 8526 | 管理前端（静态） |

`<owner>` 为 GitHub 仓库所有者（本仓库为 `adminlinzi`）。CI 推送的标签：release 为 `语义版本`（如 `4.2.0`）、`latest`、`sha-<commit>`；manual-build 为 `dev-<分支>-<sha>`、`sha-<commit>`。

> 注：`maxkey-gateway` 模块在当前源码中为未完成 stub（无 bootJar、网关依赖已注释），**不提供镜像**。

## 二、Docker 单机部署

前置：Docker Engine 与 Docker Compose v2。

```bash
# 默认从 GHCR 拉取当前版本（MXK_VERSION 默认 4.2.0，可覆盖）
export MXK_VERSION=4.2.0
docker compose -f deploy/docker/docker-compose.yml up -d

# 查看状态
docker compose -f deploy/docker/docker-compose.yml ps
docker compose -f deploy/docker/docker-compose.yml logs -f maxkey

# 访问：浏览器打开 http://<宿主机>/sign/  （认证端），/maxkey/ （认证前端）
```

- 数据库：内置 MySQL 8.4.2，首次启动自动执行 `deploy/docker/mysql` 下的初始化 SQL。
- 网关：`maxkey-nginx` 在 80 端口统一代理 `/sign/`、`/maxkey/`、`/maxkey-mgt-api/`、`/maxkey-mgt/`、`/maxkey-openapi/`。
- 凭据：默认 `root / maxkey`，仅用于测试，生产请修改 `deploy/docker/docker-compose.yml` 中的环境变量与 MySQL 密码。

## 三、Kubernetes 部署（kustomize）

前置：kubectl + kustomize（或 kubectl v1.14+ 内置 kustomize）。

```bash
# 开发环境（固定标签 4.2.0）
kubectl apply -k deploy/k8s/overlays/dev

# 指定版本部署（覆盖标签后应用）
cd deploy/k8s/overlays/dev
kustomize edit set image maxkey=ghcr.io/<owner>/maxkey:9.9.9
kubectl apply -k .

# 查看
kubectl -n maxkey get all
# 网关 NodePort 30080，配合云厂商 LoadBalancer/Ingress 对外暴露
kubectl -n maxkey get svc maxkey-nginx
```

- MySQL：`base/mysql` 使用 hostPath 挂载初始化 SQL，**仅适用于 kind/单机测试**。生产请改用托管数据库或 db-init Job，并将 `hostPath` 替换为你的持久化/初始化方案。
- 密钥：`base/secrets.yaml` 为明文占位，**生产务必替换为 Sealed Secrets / External Secrets / CSI 驱动**。

### 本地 kind 实部署验证

```bash
kind create cluster --config deploy/k8s/kind/kind.yaml
cd deploy/k8s/overlays/dev
for s in maxkey maxkey-mgt maxkey-openapi maxkey-frontend maxkey-mgt-frontend; do
  kustomize edit set image "$s=ghcr.io/<owner>/$s:4.2.0"
done
kubectl apply -k .
kubectl -n maxkey rollout status deploy/maxkey --timeout=420s
curl -f http://localhost/sign/      # kind 已将 NodePort 30080 映射到本机 80
```

## 四、CI/CD 流程（GitHub Actions）

| 工作流 | 触发 | 职责 |
| --- | --- | --- |
| `.github/workflows/docs.yml` | PR / push main | 校验文档版本一致性；合并到 main 后用 git-cliff 回写 `CHANGELOG.md` |
| `.github/workflows/ci.yml` | PR / push main / 手动 | 构建产物 → 本地构建镜像 → `docker-compose` 冒烟 → `kubectl apply --dry-run` 校验 k8s 清单 |
| `.github/workflows/release.yml` | 推送语义化 tag（如 `4.2.0`） | 多架构构建并推送 GHCR → kind 实部署验证 → 创建 GitHub Release 并上传制品 |
| `.github/workflows/manual-build.yml` | 手动 `workflow_dispatch` | 少量改动未发版：构建产物 → 多架构推送 GHCR（`dev-<分支>-<sha>`，不建 Release）→ 可选 `docker-compose` 冒烟 |

### 手动构建（未发版）

少量代码修改、尚不想打版本 tag 时，可在仓库 **Actions → Manual Build → Run workflow** 手动触发：

- 默认在 `dev-<分支名>-<短sha>` 标签下多架构推送 5 个镜像到 GHCR（另打 `sha-<commit>`），**不创建 GitHub Release**。
- 支持三个输入项（均可留默认）：
  - `image_tag`：自定义镜像标签，留空则自动生成 `dev-<分支>-<短sha>`（分支名中的 `/` 会替换为 `-`）。
  - `push_images`：是否推送镜像（默认 `true`；设为 `false` 则只构建不推送）。
  - `smoke_test`：是否运行 `docker-compose` 本地冒烟（默认 `true`）。

> 拉取手动构建的镜像部署：`export MXK_VERSION=dev-<分支>-<短sha> && docker compose -f deploy/docker/docker-compose.yml up -d`

提交约定：建议遵循 Conventional Commits（`feat:` / `fix:` / `docs:` …），便于 git-cliff 自动归类生成 CHANGELOG。

> 说明文档一致性由 `scripts/check-docs.sh` 保证：`gradle.properties` 的版本必须为纯语义化版本，且 `README.md` 需同步提及该版本，否则 CI 失败。
