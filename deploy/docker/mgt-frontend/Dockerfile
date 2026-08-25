# MaxKey 管理端前端镜像（nginx-only）
# 构建方式同 frontend：CI 在 Node 16 执行 `ng build --base-href /maxkey-mgt/`
# 产出 dist，本 Dockerfile 仅做静态托管，兼容多架构。
FROM nginx:stable-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY dist /usr/share/nginx/html/maxkey-mgt

EXPOSE 8526
