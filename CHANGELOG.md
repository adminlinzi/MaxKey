# Changelog

All notable changes to MaxKey will be documented in this file.

> 本文件由 `git-cliff` 基于 Conventional Commits 自动生成与维护，合并到 `main` 后由
> `.github/workflows/docs.yml` 回写。请勿手工大规模编辑，提交请遵循 `feat:` / `fix:` / `docs:` 规范。

## [4.2.0] - 2026-08-25

- 新增 GitHub Actions 流水线（docs / ci / release）与独立 `deploy/` 部署目录（docker + k8s kustomize）
- 修正后端运行镜像为 `eclipse-temurin:21-jre`（原 17 与 JDK 21 构建产物不兼容）
- 前端构建固定使用 Node 16（Angular 13 要求）
