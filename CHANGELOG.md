# Changelog

All notable changes to MaxKey will be documented in this file.
## [Unreleased]


### Bug Fixes

- 退出重定向回登录页面问题
- 退出重定向回登录页面问题
- Https://gitee.com/dromara/MaxKey/issues/I5X10K
- Https://gitee.com/dromara/MaxKey/issues/I5X10K
- 修复判断字符串是否为YES始终为false
- 修复PasskeyRegistrationEndpoint中@PathVariable注解缺少value属性的问题
- 修复因为 ssl 配置未生效致使使用qq邮箱配置时, 选择ssl端口无法发送并报ssl异常问题
- 接口需要禁止删除组织 Organizations#ROOT_ORG_ID 否则会导致同步器工作异常
- 修复机构配置修改后缓存没有清空，导致界面上看上去 修改失败了
- Handle null version in git-cliff template for main branch changelog
- Kubectl dry-run without K8s cluster; guard null timestamp in cliff template
- Explicitly stage backend jars and frontend dist after artifact download
- Install kustomize from GitHub release instead of cargo-binstall
- Kind deploy-test mysql rollout timeout and backend startup
- K8s dry-run via kustomize build; refactor deploy README; strengthen mysql rollout
- MySQL 8.4 auth plugin for kind deploy-test; enrich deploy README
- Create maxkey namespace before GHCR pull secret in release deploy-test

### Features

- 添加Passkey WebAuthn支持模块
- 优化passkey模块配置和依赖管理
- 实现 passkey 登录注册功能前端支持

### Miscellaneous Tasks

- Add SECURITY.md (private vulnerability reporting policy)
- Enforce LF line endings

### Refactor

- 将passkey实体类迁移到正确的包路径下

### Signed-off-by

- MaxKey <shimingxy@qq.com>

### Eclipse-temurin

- 17-jdk-alpine

### IOS

- 声明摄像头权限、把应用名改成 MaxKey

### Vuln-fix

- Temporary File Information Disclosure
