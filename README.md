# LoL Calendar Generator

用 Swift 从 Cito API 获取 LPL 赛程，并生成可以订阅的 iCalendar (`.ics`) 文件。GitHub Actions 每天在北京时间 16:00 自动更新当年赛程。

## 输出

- `docs/lpl.ics`：当年全部 LPL 比赛。
- `docs/teams/<TEAM>.ics`：使用 `--split-teams` 时生成的战队日历。

旧版 Python 生成的 `games/` 和 `teams/` 目录作为历史产物保留，但不再由自动任务更新。

## 环境要求

- Swift 6.3
- Cito API Key

API Key 必须通过环境变量提供，不应写入源码或提交到 Git：

```bash
export CITO_API_KEY="your-api-key"
```

## 使用方法

生成当前 UTC 年份的 LPL 总日历：

```bash
swift run LoLCalendar
```

指定年份和输出目录：

```bash
swift run LoLCalendar --year 2026 --output docs
```

同时生成全部战队日历：

```bash
swift run LoLCalendar --split-teams
```

只生成某一战队的独立日历（LPL 总日历仍会生成）：

```bash
swift run LoLCalendar --split-teams --team EDG
```

完整参数：

```text
--year YYYY          UTC 年份，默认当前年份
--output PATH        输出目录，默认 docs
--leagues LIST       联赛列表，首版仅支持 lpl
--split-teams        额外生成战队日历
--team CODE          只生成指定 code 或 slug 的战队日历
-h, --help           显示帮助
```

## 测试

```bash
swift build
swift test
```

## GitHub Actions

在仓库的 **Settings → Secrets and variables → Actions** 中创建名为 `CITO_API_KEY` 的 Repository Secret。`Update Calendar` 工作流会：

1. 安装 Swift 6.3 并运行测试。
2. 生成 `docs/lpl.ics`。
3. 仅在日历内容变化时提交 `docs/`。

日历时间以 UTC `Z` 格式写入，订阅客户端会自动转换为用户的本地时区。

## License

MIT
