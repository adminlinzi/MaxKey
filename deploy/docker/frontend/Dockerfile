# MaxKey 前端镜像（nginx-only）
# 说明：Angular 13 必须在 Node 16 环境构建，无法在 buildx 多架构（arm64）中
# 直接构建。因此 CI 先在 Node 16 中执行 `ng build` 产出 dist，
# 本 Dockerfile 仅把 dist 拷入多架构 nginx 基础镜像，规避多架构构建问题。
FROM nginx:stable-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY dist /usr/share/nginx/html/maxkey

EXPOSE 8527
