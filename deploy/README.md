# MaxKey 部署指南（deploy/）

本目录集中存放经过 CI 实测的部署文件，与上游 `deployment/` 互不干扰。支持两种部署形态：

- **Docker Compose**：单机 / 单节点快速部署，适合开发、测试、小规模生产。
- **Kubernetes（kustomize）**：多节点、可声明式管理，适合生产或需要编排的场景。

> 本文档面向「把 `deploy/` 目录复制到本地环境、自行部署到生产」的用户。所有文件均可直接复制使用，仅少量配置项需要按你的环境调整（详见「二、配置」）。

---

## 一、说明

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

### 1.2 适用部署环境

| 部署方式 | 适用场景 | 复杂度 | 生产就绪度 |
| --- | --- | --- | --- |
| **Docker Compose** | 单机 / 单节点；开发、测试、边缘或小规模生产 | 低，一条命令起全部 | 可用于生产（需改默认密码、持久化数据、做好备份） |
| **Kubernetes** | 多节点集群；需要弹性、高可用、声明式运维的生产环境 | 中，需 kubectl/kustomize | 生产推荐，配合持久卷、密钥管理、Ingress 更佳 |

两种方式的**服务组成完全一致**：MySQL 8.4.2 + 认证后端（maxkey）+ 管理端 API（maxkey-mgt）+ OpenAPI（maxkey-openapi）+ 认证前端（maxkey-frontend）+ 管理前端（maxkey-mgt-frontend）+ nginx 网关（maxkey-nginx）。nginx 网关统一对外暴露 80 端口，按路径路由到各服务。

### 1.3 镜像清单（GitHub Container Registry，GHCR）

| 镜像 | 端口 | 上下文路径 | 说明 |
| --- | --- | --- | --- |
| `ghcr.io/<owner>/maxkey` | 9527 (`/sign/`) | `maxkey-webs/maxkey-web-maxkey` | 认证服务端 |
| `ghcr.io/<owner>/maxkey-mgt` | 9526 (`/maxkey-mgt-api/`) | `maxkey-webs/maxkey-web-mgt` | 管理端 API |
| `ghcr.io/<owner>/maxkey-openapi` | 9525 (`/maxkey-openapi/`) | `maxkey-webs/maxkey-web-openapi` | OpenAPI |
| `ghcr.io/<owner>/maxkey-frontend` | 8527 (`/maxkey/`) | `deploy/docker/frontend` | 认证前端（静态） |
| `ghcr.io/<owner>/maxkey-mgt-frontend` | 8526 (`/maxkey-mgt/`) | `deploy/docker/mgt-frontend` | 管理前端（静态） |

`<owner>` 为 GitHub 仓库所有者（本仓库为 `adminlinzi`）。除 5 个 MaxKey 镜像外，MySQL 使用官方 `mysql:8.4.2`，nginx 网关使用官方 `nginx:stable`，这两个镜像直接从 Docker Hub 拉取，无需 GHCR 凭据。

> 注：`maxkey-gateway` 模块在当前源码中为未完成 stub（无 bootJar、网关依赖已注释），**不提供镜像**。

**镜像来源**：上面的镜像由本仓库 CI 构建并推送到 GHCR（`release.yml` 在推送语义化 tag 时构建，`manual-build.yml` 可手动构建）。若你复用了本仓库的 GHCR 包，直接拉取即可；若使用自己的仓库，需先把镜像推送到你自己的 GHCR / 私有仓库，再在配置里改 `GHCR` 前缀或镜像地址（见 2.1、2.2）。

### 1.4 前置条件

| 方案 | 必需工具 | 说明 |
| --- | --- | --- |
| **Docker Compose** | Docker Engine ≥ 20.10、Docker Compose v2（`docker compose` 子命令） | 单机部署；`git clone` 或复制 `deploy/docker/` 目录到目标机即可 |
| **Kubernetes** | kubectl ≥ 1.25、kustomize ≥ 5.0（或 `kubectl kustomize`） | 已有一个可用的 K8s 集群（kubeadm / 云厂商托管 / kind 均可） |

> 所有后端镜像基于 `eclipse-temurin:21-jre`；前端镜像基于 `nginx:stable-alpine`。运行环境本身只需能拉取镜像并启动容器，无需在目标机安装 JDK 或 Node。
> `kind`（≥ 0.20）为可选工具，仅用于在本地一键拉起临时集群做验证（见 `deploy/k8s/kind/kind.yaml`），生产部署不依赖它。

---

## 二、配置

下面按部署环境，把配置项分成三类：

- **必须配置**：不改就无法在生产环境安全 / 正确运行（主要是密码、镜像来源、集群凭据）。
- **可配置**：有合理默认值，按需调优（端口、资源、存储等）。
- **无需配置**：开箱即用，一般不用动。

### 2.1 Docker Compose 配置

文件：`deploy/docker/docker-compose.yml`（通过环境变量注入配置；`docker-compose.local.yml` 仅 CI 本地冒烟用，部署时不需它）。

#### 必须配置（生产必改）

| 配置项 | 当前默认 | 怎么改 | 说明 |
| --- | --- | --- | --- |
| `MYSQL_ROOT_PASSWORD` | `maxkey` | `docker-compose.yml` 第 30 行，或 `export MYSQL_ROOT_PASSWORD=...` | **生产必须改**，否则数据库裸奔 |
| `DATABASE_PWD` | `maxkey` | `x-maxkey-backend` 锚点里的 `DATABASE_PWD`，或环境变量 | 后端连接 MySQL 的密码，**必须与 `MYSQL_ROOT_PASSWORD` 一致**（默认用 root 账户） |
| `MXK_VERSION` | `4.2.0` | `export MXK_VERSION=你的版本` | 镜像标签；要拉取你实际构建/需要的版本 |
| `GHCR` | `ghcr.io/adminlinzi` | `export GHCR=你的仓库前缀` | 仅当你把镜像推到了自己的仓库才需要改 |

> 默认凭据 `root / maxkey` 仅用于本地 / 测试。**生产务必修改**，并且不要将明文密码提交到公开仓库。最简单的做法是用环境变量在启动前注入，而不写死在文件里。

#### 可配置（按需调整）

| 配置项 | 位置 | 说明 |
| --- | --- | --- |
| 主机端口映射 | 各 service 的 `ports:`（如 `"9527:9527"`） | 冒号左侧是宿主机端口，按需改；改了之后外部访问用新端口 |
| 时区 `TZ` | `x-maxkey-backend` 锚点、`mysql`、`frontend` 等 | 默认 `Asia/Shanghai` |
| MySQL 运行参数 | `mysql/conf.d/mysqld.cnf` | 字符集、排序规则、慢查询日志等；已适配 MySQL 8.4.2 |
| MySQL 数据持久化 | 命名卷 `mysql-data`（默认） | 数据已落在卷里，升级 / 重启不丢；要换主机路径可改 `volumes` 为 `bind` 挂载 |
| 后端 JVM / 连接参数 | 镜像内默认；如需调可通过环境变量或覆盖镜像 | 一般无需动 |

#### 无需配置（开箱即用）

- 网络 `maxkey`（bridge）自动创建；服务间用服务名互访（如 `maxkey` 访问 `maxkey-mysql:3306`）。
- 启动顺序：后端 `depends_on` MySQL 健康检查，MySQL 就绪后后端才启动。
- 各服务 `healthcheck` 已定义（`mysqladmin ping` / TCP 端口探测）。
- nginx 网关路由（`/sign/`、`/maxkey/`、`/maxkey-mgt-api/`、`/maxkey-mgt/`）已写好，见 `nginx/default.conf`。

### 2.2 Kubernetes 配置

文件：`deploy/k8s/base/`（通用资源）+ `deploy/k8s/overlays/dev/`（开发 / 测试覆盖，含镜像地址映射）。

#### 必须配置（生产必改）

| 配置项 | 当前默认 | 怎么改 | 说明 |
| --- | --- | --- | --- |
| 密钥 `secrets.yaml` | `MYSQL_ROOT_PASSWORD: maxkey`、`DATABASE_PWD: maxkey` 明文 | 改 `deploy/k8s/base/secrets.yaml` 的 `stringData`；生产建议改用 **Sealed Secrets / External Secrets / CSI 驱动**，不要提交明文 | **生产必须改密码** |
| 镜像拉取凭据 | 无（假设 GHCR 公开） | 若 GHCR 包为私有，创建 `imagePullSecret` 并 patch 到 `maxkey` 命名空间的 default ServiceAccount（命令见 3.2） | 否则 Pod `ImagePullBackOff` |
| 镜像标签 | overlay 默认 `:latest`（浮动别名） | 生产建议固定到具体版本号：`kustomize edit set image ...:<版本>`（命令见 3.2） | `latest` 会随新构建漂移，生产应锁版本 |
| `GHCR` 仓库前缀 | `ghcr.io/adminlinzi` | 改 `overlays/dev/kustomization.yaml` 里 5 个 `newName` | 仅当使用自己的仓库时 |

#### 可配置（按需调整）

| 配置项 | 位置 | 说明 |
| --- | --- | --- |
| 命名空间 | `base/namespace.yaml`（默认 `maxkey`） | 一般不必改 |
| 资源 requests / limits | 各 Deployment（MySQL 默认 2Gi/1CPU ~ 4Gi/2CPU） | 按节点规模调整；OOM 时上调 `limits.memory` |
| MySQL 存储 | `base/mysql/mysql-pvc.yaml` | 默认 `storageClassName` 空（用集群默认）；生产指定可靠的 StorageClass |
| nginx NodePort | `base/nginx/service.yaml`（默认 `30080`） | 已映射到节点 30080 → 容器 80；可用 Ingress / LoadBalancer 替代 |
| 副本数 | 各 Deployment `replicas` | 默认 1；无状态前端 / 后端可扩副本，MySQL 不建议简单扩副本 |

#### 无需配置 / 特别注意

- **MySQL 初始化**：`base/mysql/mysql-deployment.yaml` 用 `hostPath` 挂载初始化 SQL 与配置（`/mnt/maxkey-mysql-init`、`/mnt/maxkey-mysql-conf`），**仅适用于 kind / 单机测试**。生产环境请改用托管数据库（如 RDS），或通过 **db-init Job** 加载 `deploy/docker/mysql` 下的 `init.sql` + `latest/maxkey.sql`，再让 MySQL 连托管库。
- MySQL 官方镜像的 `docker-entrypoint.sh` 入口**未被覆盖**，确保数据目录初始化与 SQL 导入正常；运行参数通过 `conf.d/mysqld.cnf` 注入（已适配 MySQL 8.4.2 的 `lc-messages-dir` 等）。
- `base/kustomization.yaml` **不定义** `images` 转换器，由 overlay 统一改写镜像地址与标签，避免同名转换器叠加导致覆盖不生效。

---

## 三、部署

下面分别给出两种环境的部署步骤。复制文件时，把整个 `deploy/docker/` 或 `deploy/k8s/` 目录拷到目标机即可。

### 3.1 Docker Compose 部署

```bash
# 1. 进入编排目录（已复制到本地）
cd deploy/docker

# 2. （生产必做）注入真实密码与版本，避免用默认 maxkey
export MYSQL_ROOT_PASSWORD='换成强密码'
export DATABASE_PWD='换成强密码'      # 需与 MYSQL_ROOT_PASSWORD 一致（默认用 root 账户）
export MXK_VERSION=4.2.0             # 你要部署的镜像版本
# export GHCR=ghcr.io/你的仓库        # 仅当镜像在自己仓库时

# 3. 启动全套
docker compose up -d

# 4. 查看状态（STATUS 应全为 running/healthy）
docker compose ps

# 5. 跟踪日志
docker compose logs -f maxkey
```

**停止并清理**（会一并删除命名卷，数据会丢，谨慎）：

```bash
docker compose down -v
```

### 3.2 Kubernetes 部署

#### 方式 A：开发 / 测试覆盖（默认 `:latest` 标签）

```bash
# 直接应用 dev overlay（镜像为 ghcr.io/adminlinzi/<name>:latest）
kubectl apply -k deploy/k8s/overlays/dev

# 查看
kubectl -n maxkey get all
kubectl -n maxkey rollout status deploy/mysql --timeout=600s
```

#### 方式 B：生产固定版本号（推荐）

```bash
cd deploy/k8s/overlays/dev

# 把 5 个组件锁定到具体版本（与你要部署的 tag 一致）
VERSION=4.2.0
OWNER=adminlinzi
for s in maxkey maxkey-mgt maxkey-openapi maxkey-frontend maxkey-mgt-frontend; do
  kustomize edit set image "$s=ghcr.io/${OWNER}/$s:${VERSION}"
done

kubectl apply -k .
```

#### 若 GHCR 包为私有（需 imagePullSecret）

```bash
kubectl -n maxkey create secret docker-registry ghcr-pull \
  --docker-server=ghcr.io \
  --docker-username=<你的 GitHub 用户名> \
  --docker-password=<GHCR PAT 或 GITHUB_TOKEN>

kubectl -n maxkey patch serviceaccount default \
  -p '{"imagePullSecrets":[{"name":"ghcr-pull"}]}'
```

> 也可直接 `kubectl apply -k deploy/k8s/base` 应用基础资源（不含 overlay 的镜像映射），但 base 中 Deployment 使用裸镜像名，必须经 overlay 或手动 `kustomize edit set image` 指定完整地址后才可拉取，因此**推荐始终经 `overlays/dev` 部署**。

### 3.3 部署后访问使用

所有用户入口都经 nginx 网关，对外统一端口：

| 部署方式 | 访问地址（浏览器） | 网关端口 |
| --- | --- | --- |
| Docker Compose | `http://<宿主机IP>/sign/` 等 | 宿主机 `80` |
| Kubernetes | `http://<任意节点IP>:30080/sign/` 等 | 节点 `30080`（NodePort） |

各路径对照：

| 入口 | 路径 | 对应服务 |
| --- | --- | --- |
| 认证端 | `/sign/` | maxkey:9527 |
| 认证前端 | `/maxkey/` | maxkey-frontend:8527 |
| 管理端 API | `/maxkey-mgt-api/` | maxkey-mgt:9526 |
| 管理前端 | `/maxkey-mgt/` | maxkey-mgt-frontend:8526 |
| OpenAPI | `/maxkey-openapi/` | maxkey-openapi:9525 |

- **Docker Compose**：浏览器打开 `http://<宿主机IP>/sign/` 即可看到登录页；管理后台 `http://<宿主机IP>/maxkey-mgt/`。
- **Kubernetes**：浏览器打开 `http://<节点IP>:30080/sign/`。若集群在外网，建议在前面再加一层 Ingress / 负载均衡 / WAF。

### 3.4 部署后健康状态检查与验证

**目标**：确认「真的部署成功」——不只是容器起来了，而是服务能正常响应、数据库可用、网关能路由。

#### Docker Compose

```bash
# 1. 容器状态（STATUS 列应为 Up / healthy）
docker compose ps

# 2. 各服务健康检查明细
docker inspect -f '{{.State.Health.Status}}' maxkey-mysql
docker inspect -f '{{.State.Health.Status}}' maxkey
docker inspect -f '{{.State.Health.Status}}' maxkey-mgt

# 3. 业务连通性（经 nginx 网关 80 端口）
curl -f http://localhost/sign/        && echo "认证端 OK"
curl -f http://localhost/maxkey/      && echo "认证前端 OK"
curl -f http://localhost/maxkey-mgt/  && echo "管理前端 OK"

# 4. 数据库可用性
docker exec maxkey-mysql mysqladmin ping -p"$MYSQL_ROOT_PASSWORD"
```

预期：`docker compose ps` 全部 `healthy`；3 个 `curl` 均返回 200/302；`mysqladmin ping` 返回 `mysqld is alive`。

#### Kubernetes

```bash
# 1. 所有 Pod 状态（STATUS 应为 Running，READY 1/1）
kubectl -n maxkey get pods -o wide

# 2. 等待各 Deployment 滚动完成（MySQL 初始化约 1-3 分钟）
for d in mysql maxkey maxkey-mgt maxkey-openapi maxkey-frontend maxkey-mgt-frontend maxkey-nginx; do
  kubectl -n maxkey rollout status "deploy/$d" --timeout=600s
done

# 3. 业务连通性（NodePort 30080）
curl -f http://<节点IP>:30080/sign/        && echo "认证端 OK"
curl -f http://<节点IP>:30080/maxkey/      && echo "认证前端 OK"
curl -f http://<节点IP>:30080/maxkey-mgt/  && echo "管理前端 OK"

# 4. 数据库可用性
kubectl -n maxkey exec deploy/mysql -- mysqladmin ping -uroot -p"$MYSQL_ROOT_PASSWORD"
```

**失败排查（常用三连）**：

```bash
kubectl -n maxkey get pods                       # 看哪个 Pod 不是 Running
kubectl -n maxkey describe deploy/<名称>         # 看 Events / 拉镜像失败原因
kubectl -n maxkey logs -l app=<名称> --tail=300  # 看容器日志
```

| 现象 | 常见原因 | 处理 |
| --- | --- | --- |
| `ImagePullBackOff` | GHCR 私有且无 imagePullSecret；或镜像标签不存在 | 建 `ghcr-pull` 密钥并 patch SA；确认 `MXK_VERSION` / overlay 标签真实存在 |
| mysql Pod 一直 `CrashLoopBackOff` | 覆盖了 MySQL `command`；或配置不兼容 | 不要覆盖 `command`，保留官方 entrypoint；检查 `mysqld.cnf` 无 8.4 已删变量 |
| mysql 初始化超时 | hostPath 未挂载 / 资源不足 | kind 下确认 `/mnt/maxkey-mysql-init` 含 SQL；OOM 则上调 `limits.memory` |
| 网关 404 / 502 | 后端未就绪就被访问 | 等 `rollout status` 全绿再访问；检查 `nginx/default.conf` 路由 |

---

## 四、常见问题

### 4.1 镜像从哪里来 / 如何自己构建

- 本仓库 CI 在推送语义化 tag（如 `4.2.0`，不带 `v` 前缀）时，由 `release.yml` 多架构构建并推送 5 个镜像到 GHCR（`ghcr.io/<owner>/<name>:<version>` 与 `:latest`）。
- 少量改动未发版时，可在 **Actions → Manual Build → Run workflow** 手动触发 `manual-build.yml`，推送到 `dev-<分支>-<短sha>` 标签（不创建 Release）。
- 若你使用自己的仓库，先把镜像推到你的 GHCR / 私有仓库，再按 2.1 / 2.2 修改 `GHCR` 前缀或镜像地址。

### 4.2 生产部署检查清单

- [ ] 已修改数据库密码（Docker：`MYSQL_ROOT_PASSWORD`/`DATABASE_PWD`；K8s：`secrets.yaml`），未使用默认 `maxkey`
- [ ] 镜像来源正确（GHCR 前缀 / 私有仓库 imagePullSecret）
- [ ] 生产环境锁定具体镜像版本号（K8s 用 `kustomize edit set image`，不用浮动 `latest`）
- [ ] 数据已持久化（Docker：命名卷 `mysql-data`；K8s：可靠 StorageClass 的 PVC）
- [ ] MySQL 不使用 kind 专用 `hostPath`（生产改托管库或 db-init Job）
- [ ] 已验证健康状态：容器/Pod 全 healthy、网关各路径 curl 通过、数据库 `ping` 正常

### 4.3 kind 本地验证（可选）

```bash
kind create cluster --config deploy/k8s/kind/kind.yaml
cd deploy/k8s/overlays/dev
for s in maxkey maxkey-mgt maxkey-openapi maxkey-frontend maxkey-mgt-frontend; do
  kustomize edit set image "$s=ghcr.io/adminlinzi/$s:4.2.0"
done
kubectl apply -k .
# 等待 rollout 后访问 http://localhost/sign/
```

> kind 通过 `kind.yaml` 把 MySQL 初始化 SQL 与配置挂载进节点，仅用于本地实部署验证，不等同于生产配置。
