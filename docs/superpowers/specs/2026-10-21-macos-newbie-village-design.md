# 365 AI Master for macOS — 新手村 v1 设计

- 日期：2026-10-21
- 状态：设计已逐段确认（Kenichi），待审本文档
- 背景：`~/Documents/我的商业版图/365-AI-Master-新手村整体规划-2026-10-21.md`

## 1. 目标与范围

一个常驻 macOS 菜单栏的工具。它读取本机 AI 编程工具的日志和配置，告诉新手三件事：现在用得怎么样、卡在哪、今天学哪一招；并通过「新手村」任务线带新手进阶，每一关是否完成都由日志自动验收。

**v1 包含**

- Swift 菜单栏 App 和内嵌的 Python 引擎
- Claude Code、Codex 深度支持（用量、行为、环境三层）
- Gemini CLI、OpenCode、Qwen Code 只采用量
- 新手村 9 关、今日一招、四维分、用量与 Codex 额度
- 界面语言跟随系统：系统语言为中文时显示中文，其余显示英文

**v1 不包含**

账号、收费、云端排名与分享、自动更新、Claude 额度、Cursor 等需要联网或读取登录态的工具、Windows 版、Claude Code 插件。

**底线**

- 零网络请求
- 不读取任何凭据（钥匙串、`auth.json`、token）
- 对用户的文件只读不写
- 提示词与回复正文不进入快照

## 2. 架构

```
365 AI Master.app (Swift, LSUIElement 菜单栏应用)
  └─ 每 60s（可设）调用 Contents/Resources/engine/365engine snapshot --json
       └─ 引擎（PyInstaller 打包的 agentfit 包）
            collectors → profile → master → snapshot.json (stdout)
  读取（只读）: ~/.claude ~/.codex ~/.gemini ~/.local/share/opencode ~/.qwen
  状态/缓存:    ~/Library/Application Support/365AIMaster/
```

- App 与引擎之间的唯一契约是 `snapshot` 命令输出的 JSON（schema 见 §6）。App 只负责显示，不做任何计算。
- 引擎在仓库 `agentfit/` 上扩展，复用现有采集器、`cloud/coach.py` 的四维评分逻辑（迁入本地可用的模块，见 §7）以及现有测试。
- Swift 雏形从 `~/Documents/724.fund-research/macos-app/` 迁入本仓库 `macos/`。迁入后此处为唯一代码源。

## 3. 采集层

### 3.1 采集器接口

```python
class Collector(Protocol):
    tool: str                      # "claude_code" | "codex" | "gemini_cli" | "opencode" | "qwen_code"
    tier: Literal["deep", "usage"]
    def detect(self) -> bool: ...                    # 日志目录是否存在
    def scan(self, state: ScanState) -> list[Event]: ...   # 增量：按文件记录偏移/指纹
    def inventory(self) -> Inventory | None: ...     # deep 档才实现
```

- 增量状态：每个文件记录 `(size, mtime, offset, head_fingerprint)`，持久化到 `Application Support/365AIMaster/scan_state.json`。文件被截断或被替换时，从头重新读。
- 去重：Claude 按 `message.id` + `requestId` 去重；Codex 处理分叉会话的重复累计（参照 Tokei 的修复）。
- 容错：单个采集器抛出异常时，记入快照的 `tools[i].error`，其他采集器照常运行。

### 3.2 统一事件（在现有 `UsageEvent` 上扩展）

新增字段（均可选）：`tool_calls: dict[str, int]`、`is_sidechain: bool`、`effort: str | None`、`aborted: bool`、`compacted: bool`、`entrypoint: str | None`、`client_version: str | None`、`task_type: str | None`（在本机对正文分类后只保留类别，正文本身丢弃）、`rate_limits: RateLimits | None`（Codex 专用）。

### 3.3 环境盘点（deep 档）

| 字段 | Claude Code | Codex |
|---|---|---|
| `skills_installed` | `~/.claude/skills/*` 加插件内的 skill 名称 | `~/.codex/skills/*` |
| `skills_used_14d` | 日志中 `Skill` 工具调用涉及的 skill 名称 | 日志中的 skill 调用 |
| `instructions_file` | `~/.claude/CLAUDE.md`，以及各项目的 CLAUDE.md 是否存在、大小 | `~/.codex/AGENTS.md` |
| `hooks` | `settings.json.hooks` 中的事件类型数 | — |
| `mcp_servers` | `~/.claude.json` 的 `mcpServers` 数 | `config.toml` 的 mcp 段数 |
| `subagents` / `plugins` | `~/.claude/agents/*.md` / `enabledPlugins` 数 | — |

只记录名称和计数，不读取文件内容（instructions 文件只看大小）。

### 3.4 日志路径

| 工具 | 档位 | 路径 |
|---|---|---|
| Claude Code | deep | `~/.claude/projects/**/*.jsonl` |
| Codex | deep | `~/.codex/sessions/**/*.jsonl` |
| Gemini CLI | usage | `~/.gemini/**/conversations/*`（以 Tokei 实现为准） |
| OpenCode | usage | `~/.local/share/opencode/opencode.db` |
| Qwen Code | usage | `~/.qwen/usage/token-usage-*.jsonl` |

usage 档的解析逻辑参考 Tokei（README 标为 MIT；借用代码前核对其 LICENSE 文件，并在源码中注明出处）。

## 4. 大师层

### 4.1 新手村 9 关（检查窗口为最近 14 天）

| # | key | 名称 | 验收函数（纯函数，输入为画像） |
|---|---|---|---|
| 1 | `first_edit` | 出生点 | `tool_calls` 中 Edit 与 Write 的合计 ≥1 |
| 2 | `rules_file` | 立规矩 | 任一 instructions 文件 >200 字节 |
| 3 | `light_model` | 会分工 | 轻量档模型 token 占比 >5%（使用 `agentfit.pricing.classify_model`） |
| 4 | `first_skill` | 第一件装备 | 存在某个 skill 调用 ≥3 次 |
| 5 | `parallel` | 会并行 | `is_sidechain` 事件 ≥1，或 Codex 多代理事件 ≥1 |
| 6 | `less_rework` | 少返工 | 中断回合占比 <10%，且未命中 `RULE_ERROR_RETRY_LOOP` |
| 7 | `automation` | 自动化 | hooks ≥1，且日志中出现 `hook_success` |
| 8 | `declutter` | 断舍离 | 安装了 skill 且 `skills_used_14d / skills_installed` ≥0.5；未安装任何 skill 时算通过 |
| 9 | `graduate` | 出师 | 四维分全部 ≥85 |

- 按顺序解锁：只有前一关通过后，才对下一关做验收。
- 通过后永久保留，记录在 `progress.json`（通过时间）。退步时只提示一次，不扣除关卡。
- 段位：1–2 关探索者 / 3–5 关熟练者 / 6–8 关大师 / 9 关宗师。

### 4.2 今日一招

选择顺序：

1. 当前关卡尚未达标 → 给出该关对应的招式
2. 当前关卡已达标 → 给出四维中最低一维对应的招式
3. 9 关全部通关 → 从内容池中按日期轮换取一条

同一天内结果固定（以本地日期为种子）。用户点击「做完了，帮我检查」后会重新扫描；若当前关卡因此通过，则当天换一招。

每一招包含：`title`、`why`、`steps[]`、`prompt_for_claude`（可直接粘贴给 Claude Code 的指令）、`quest_key | dimension | pool_id`。

### 4.3 文案与诚实

- 招式与关卡文案中英各一份，放在 `agentfit/master_content/`，走代码审查和测试。
- 不联网，不实时调用大模型。
- 沿用钱的表述纪律：订阅模式不说"省了多少美元"，成本一律标注为"折算"。

## 5. 界面（SwiftUI）

- **菜单栏**：圆环 + 关卡数字；今日一招未完成时显示角标；可切换为显示 Codex 额度百分比。
- **弹出面板（约 360pt 宽）**，从上到下：
  1. 今日一招（复制指令按钮、「帮我检查」按钮）
  2. 新手村 9 格与段位
  3. 四维小圆环
  4. 用量：今日与 7 日，按工具、模型拆分，折算成本，Codex 额度条
  5. 底部：上次扫描时间、设置、退出
- **设置**：各工具开关、刷新间隔、开机自启（SMAppService）、「查看我的快照」（显示原始 JSON），以及"本应用不联网"的说明。
- **状态**：首次运行且未检测到任何工具 → 显示安装引导；某工具出错 → 对应卡片显示"暂不可用"；引擎失败 → 显示上一次的快照并标注时间。

## 6. 快照 schema（v1，引擎 stdout）

```json
{
  "schema": 1,
  "generated_at": "ISO8601",
  "locale": "zh|en",
  "tools": [{"tool": "claude_code", "tier": "deep", "detected": true, "error": null,
             "usage_today": {"tokens": 0, "cost_usd": 0.0}, "usage_7d": {"tokens": 0, "cost_usd": 0.0},
             "by_model": [{"model": "", "tokens": 0, "cost_usd": 0.0}]}],
  "quota": {"codex": {"primary_pct": 0, "primary_resets_at": "", "weekly_pct": 0, "weekly_resets_at": ""}},
  "dimensions": [{"key": "routing", "label": "", "score": 0}],
  "overall": {"score": 0, "tier": "S|A|B|C"},
  "village": {"current": 3, "rank_title": "", "quests": [{"key": "", "title": "", "status": "passed|current|locked", "passed_at": null, "progress_hint": ""}]},
  "today_tip": {"title": "", "why": "", "steps": [], "prompt_for_claude": "", "source": {"kind": "quest|dimension|pool", "ref": ""}},
  "inventory": {"claude_code": {"skills_installed": 0, "skills_used_14d": 0, "instructions_bytes": 0, "hooks": 0, "mcp_servers": 0}},
  "notices": []
}
```

`quota.codex` 在读不到时为 `null`。所有面向用户的文案由引擎按 locale 生成，App 内只保留界面框架文字的本地化。

## 7. 代码组织

- `agentfit/collector/`（沿用现有目录名，不改名）：扩展 `claude.py`、`codex.py`，新增 `gemini.py`、`opencode.py`、`qwen.py`。注意：`main` 工作区的 `collector/codex.py` 上有未提交的他人改动，worktree 从 HEAD 分出不会包含这些改动；合并时需要人工对照处理
- `agentfit/inventory.py`、`agentfit/village.py`（9 关 + 今日一招）、`agentfit/snapshot.py`、`agentfit/master_content/`
- 四维评分：把 `cloud/coach.py` 中 `compute_checkup` / `overall_from_dimensions` / `tier_for_score` 及其依赖的诊断函数迁移到 `agentfit/scoring_v2.py`，`cloud/coach.py` 改为从这里导入（单一来源，保证 CLI 不依赖 cloud）
- CLI 新增 `365aimaster snapshot --json`
- `macos/`：Swift Package / Xcode 工程，含 `EngineRunner`（只调用打包内的引擎，不再依赖登录 shell 的 PATH）、`SnapshotStore`、各个 View
- `scripts/build_engine.sh`（PyInstaller）、`scripts/package_app.sh`

## 8. 测试与验收

- **引擎**：现有测试全部通过；每个采集器一份去敏 fixture；9 个验收函数各自配正例和反例；今日一招的选择逻辑与"当天固定"；快照符合 schema
- **隐私**：测试扫描引擎与 App 源码，确认不存在网络调用（`urllib`/`requests`/`socket`/`URLSession`/`http`）；测试确认快照中不出现任何正文与路径明文
- **App**：`swift build` 通过；在 Kenichi 本机运行并截图；用空的 HOME 验证安装引导
- **打包**：在不含 Python 的干净环境中运行 `365engine snapshot --json` 并成功输出
- **完成定义**：在 Kenichi 本机，菜单栏常驻，面板显示真实关卡、今日一招和用量，各项数字与 `365aimaster snapshot` 的输出一致

## 9. 开发方式

由 Codex CLI 在独立 git worktree 分支 `feat/macos-v1` 上按实施计划逐个任务开发；每个任务完成后由 Claude 跑测试、审查 diff 后再进入下一个；最终由 Kenichi 决定是否合并。仓库 `main` 上现有的未提交改动（`rules.py`、`collector/codex.py`、pilot 测试）不得被覆盖。

## 10. 分发

v1 为不签名的内测包（首次需右键「打开」）。正式对外发布前，需要 Apple Developer 账号签名并完成公证（由 Kenichi 办理）。

---

## 11. v2 改版（2026-10-21，Kenichi 试用后反馈）

**反馈**：界面像长报告，点一次就看完；省钱数字没必要细拆；重点应该是"有哪些新技能可以学"，让人每天想点开、有可交互的东西。

**定案**

1. **三页签，参照网页版**：`体检` / `今日新技能` / `修炼`。
   - 体检：大分数环 + 段位 + 四维小环 + 「今天先改这一处」（沿用 today_tip，复制给 Claude、帮我检查）+ 底部一行用量摘要（本周 tokens · 折算 $ · Codex 额度）。按工具/模型的明细全部去掉。
   - 今日新技能：今日技能卡（优先推你没点亮的）+ 今日 Skill 榜 / Agent 榜（每天轮换 Top5，标"已装 / 未装"）+ 大师一句话。
   - 修炼：新手村 9 格 + 技能图鉴（N/总数 已点亮）+ 连续天数与徽章。
2. **技能图鉴**：约 24 张 Claude Code / Codex 能力卡。能从日志判定的，用过一次自动点亮；判定不了的，用户点「试过了」自评点亮（标"自评"）。点亮永久保留。
3. **连续天数**：按日志里有 AI 使用的日期计算（不是按打开 App），徽章：连续 3 / 7 / 14 / 30 天，图鉴点亮 5 / 10 / 20 / 全部，新手村通关。
4. **每日公开内容**（底线修订）：App 每天最多一次，用 HTTPS GET 下载 `content` 分支的公开内容文件 `daily.json`（`https://raw.githubusercontent.com/KenichiXXX/365-ai-master/content/daily.json`）。**不上传任何数据**：请求不带任何用户信息（无查询参数、无自定义头、无 Cookie），只写入 `Application Support/365AIMaster/content.json`。下载失败或文件无效时使用 App 内置的同格式内容。引擎本身仍然零网络。宣传口径从"不联网"改为"不上传任何数据"。
5. 内容文件更新（每日采集并推送到公开仓库）是单独的运营流程，需 Kenichi 另行批准，不在本次开发范围；在那之前线上文件 = 内置内容。
