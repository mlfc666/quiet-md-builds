# 构建与下载 · Builds

这个仓库是 [s1dashu/quiet-md](https://github.com/s1dashu/quiet-md) 的自动构建镜像，同时提供两种构建：

| 渠道 | 什么时候出 | 版本号 | GitHub 标记 |
| --- | --- | --- | --- |
| 正式版 | 上游打 `v0.1.x` tag 后 | `0.1.15` | Latest |
| 每日构建 | 每天 04:17（Asia/Shanghai），上游有动静与否都出 | `0.1.15-daily.20261126` | Pre-release |

## 分支是怎么分工的

| 分支 | 内容 | 谁在推 |
| --- | --- | --- |
| `main` | 只跟**上游的正式发布**：每个上游 tag 合并一次，正式版从这里构建 | `.github/workflows/sync-upstream.yml` |
| `upstream-main` | 跟上游 `main` 的**所有提交**，每小时同步一次；每日构建从它的顶端打 tag | 同上 |

所以：想看上游最新代码 → 每日构建；想要上游发过的版本 → 正式版。

## 下载

在 [Releases](../../releases) 页面：

- 正式版是标着 **Latest** 的那个；
- 每日构建标着 **Pre-release**，只保留最近 14 天，更早的会被删掉。

每个平台都有对应的包（macOS `.zip`、Windows `setup.exe`、Linux `.deb` / `.tar.gz` / `.AppImage` / Arch 包），旁边的 `.sha256` 是校验文件：

```bash
sha256sum -c quiet-md-0.1.15-linux-x86_64.tar.gz.sha256
```

## 请注意

- **都没有签名、没有公证。** 这些包由 CI 构建，没有 Developer ID 证书，也没有 Windows 代码签名证书。
  macOS 首次打开请右键 →「打开」；Windows 可能弹出 SmartScreen。
- **不支持应用内自动更新。** 更新信息由上游的服务器提供，这里的构建不在其中；升级请直接下载新版覆盖安装。
- **每日构建是预览版。** 它跟的是上游 `main`，可能有未发布的改动和未修复的问题；在意稳定就用正式版。
- 构建日志都在 Actions 页面，每日构建会在最后一个 job 里汇总三个平台的构建结果。

## 工作流在这里

| 文件 | 作用 |
| --- | --- |
| `.github/workflows/sync-upstream.yml` | 每小时同步 `upstream-main`；上游发新版时合并 tag 到 `main` 并触发正式构建 |
| `.github/workflows/daily-build.yml` | 每天把 `upstream-main` 顶端做成带日期的 Pre-release 并触发三个平台构建，之后等构建结果、重试没抢到机器的 macOS、清理过期的每日构建 |
| `.github/workflows/build-{linux,macos,windows}.yml` | 真正的编译与打包 |
| `scripts/ci-merge-upstream.sh` | 两个同步共用的合并逻辑（上游只被合并，从未被改写） |
