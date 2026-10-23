# 365 AI Master v2 宣传素材

2026-10-23。所有文案按「数字诚实纪律」写：用量只说「按 API 价折算」，不说「省了多少钱」；「击败全球 X%」只在参与人数 ≥20 时出现；不写用户数、不写没做出来的功能；付款通道未开通前只说「免费试用 14 天」。发出去之前，每一条都需要 Kenichi 自己过目并点发送。

## 一、定位卡

- **一句话**：每天一招，365 天成为 AI 大师。
- **English**：One AI skill a day. Master AI in 365 days.
- **是什么**：住在 Mac 菜单栏里的 AI 教练，给每天用 Claude Code 和 Codex 的开发者和创业者。
- **三个承诺**：看清你的 AI 水平；每天学一招，用了就自动点亮；看清这周用了多少、额度还剩多少。
- **信任底线**：本机计算，不调用任何 AI，0 token，默认不上传任何东西。
- **和别人的区别**：CodexBar、ccusage 告诉你用了多少；365 告诉你用得好不好、今天该练什么，并在日志里确认你真的用上了。
- **价格**：免费版永久可用；Pro $12/年创始价（约每月 $1），14 天试用不绑卡。

**三十秒介绍**：
> 我天天用 Claude Code 和 Codex，但一直不知道自己用得到底好不好。所以做了 365 AI Master：它住在 Mac 菜单栏里，读你本机已有的 AI 使用记录，给你一个分数和段位，每天挑一招你还没用过的技巧，配好提示词。你用一次，它在日志里看到了，这一招就点亮。全程在本机算，不花你一个 token。

**不能说的话**：「帮你省钱」「AI 分析你的对话」「已有 N 万用户」「支持 Intel Mac」「支持 Windows」「立即购买」（付款通道开通前）。

## 二、标语备选

| 中文 | English |
|---|---|
| 每天一招，365 天成为 AI 大师 | One AI skill a day. Master AI in 365 days. |
| 别只看用了多少，看看用得好不好 | Don't just count tokens. See how well you use them. |
| 你的 AI 段位，菜单栏里一眼看清 | Your AI rank, one click away. |
| 用一次就点亮的 AI 技巧 | AI skills that light up when you use them. |
| 0 token 的 AI 教练 | The AI coach that costs zero tokens. |

## 三、各渠道文案

### X / Twitter（英文，6 条串）

1. I use Claude Code and Codex every day, and I had no idea if I was using them well. So I built a menu-bar coach that reads my local logs and tells me. Meet 365 AI Master. 🧵
2. Click the menu bar and you get one score (0–100), a rank from Novice to Master, and four sub-scores: model choice, focus rhythm, context care and reuse. Each one shows your number, the target, and why you lost points.
3. Every day it picks one skill you haven't used yet: Plan mode, sub-agents, MCP, hooks, worktrees… with a prompt you can paste. Use it once and it lights up, because it can see it in your logs.
4. It also shows this week's usage at public API prices and how much Codex quota you have left, plus whether you're on pace.
5. Everything runs on your Mac with plain rules. It never calls an AI, never spends a token, and uploads nothing unless you opt into the global ranking.
6. Free forever for the basics. Pro is $12/year (founding price) for all 24 skills, weekly reviews and global ranks. 14-day trial, no card. Mac only for now. [link]

### Product Hunt

- **Name**：365 AI Master
- **Tagline**（≤60 字符）：A menu-bar coach that levels up your Claude Code skills
- **Description**（≤260 字符）：365 AI Master reads your local Claude Code and Codex logs, gives you an AI rank, and picks one skill to practise each day. Use it once and it lights up. Weekly usage and quota included. Runs locally, zero tokens.
- **First comment（maker 留言）**：
  > Hi Product Hunt! I'm a founder who lives in Claude Code and Codex. Quota trackers told me how much I used, but never whether I was using these tools well. 365 AI Master is my answer: a rank you can climb, one practical skill a day, and proof from your own logs that you actually used it. It's all computed on your Mac with rules (no AI calls, no tokens), and nothing is uploaded unless you join the anonymous ranking. I'd love to hear which skill you'd want on the path next.
- **图集说明**：①首页：分数、今日一招、本周 ②今日一招点亮 ③修炼路线 ④能力详情：为什么扣分、怎么补 ⑤分享卡

### Hacker News

- **标题**：Show HN: 365 AI Master – a menu-bar coach that reads your Claude Code logs
- **首条评论**：
  > I built this because I use Claude Code and Codex all day and wanted to know whether I was getting better at it, not just how many tokens I burned. It parses the JSONL logs already on disk (~/.claude, ~/.codex), scores four habits with deterministic rules (model choice, time concentration, context hygiene, reuse via skills/hooks/commands), and suggests one practice per day. Skills that leave a trace in the logs (Plan mode, sub-agents, MCP, hooks, worktrees…) are verified automatically on the next scan. No LLM calls, no network except one daily download of a public rankings file; the opt-in leaderboard uploads only five numbers. Swift menu-bar app with a bundled Python engine. Happy to answer questions about the log formats or the scoring.

### V2EX（分享创造节点）

- **标题**：做了个 Mac 菜单栏小工具：读你的 Claude Code / Codex 日志，每天教你一招
- **正文**：
  > 天天用 Claude Code 和 Codex，但一直不知道自己用得好不好。CodexBar 这类工具能看额度，看不出水平，于是自己做了一个。
  >
  > 它做三件事：
  > 1. 给你一个分数和段位（新手 → 学徒 → 熟练者 → 专家 → 大师），四项能力分别打分，每项都写清楚你的数字、目标和扣分原因。
  > 2. 每天挑一招你还没用过的技巧（Plan 模式、子代理、MCP、Hook、worktree……），配好提示词。用一次，下次刷新时在日志里看到，就自动点亮。
  > 3. 按公开 API 价折算这周的用量，Codex 额度还剩多少、几天后重置。
  >
  > 全部在本机用规则算，不调用任何 AI，不花 token，默认不上传任何东西。免费版永久可用，Pro 一年 $12（创始价），14 天试用不绑卡。
  >
  > 目前只有 Mac（Apple 芯片）。欢迎拍砖，尤其想听：你最希望路线上加哪一招？

### 即刻

> 给自己做了个 AI 教练。每天打开菜单栏，它告诉我今天练哪一招，我在 Claude Code 里用一次，它就在日志里看到、自动点亮。今天的分数 72，熟练者，再提 3 分升专家。全程本机计算，0 token。名字叫 365 AI Master：每天一招，365 天成为 AI 大师。

### 小红书

- **标题**：用 Claude Code 的人，一定要知道自己是什么段位
- **正文**：
  > 我做了一个 Mac 菜单栏小工具 🧑‍💻
  > 打开就能看到：
  > ✅ 你的 AI 段位（新手到大师，五级）
  > ✅ 今天该练哪一招，提示词直接复制
  > ✅ 用一次自动点亮，不用打卡
  > ✅ 这周用量和额度还剩多少
  > 最重要的是：本机计算，不花一个 token，不上传你的记录。
  > 免费版就够用，想走完 24 招再升级。
- **标签**：#ClaudeCode #AI编程 #效率工具 #Mac软件 #独立开发

### 微信公众号长文（提纲）

- **标题备选**：《我用 30 天，看清了自己用 AI 的四个坏习惯》《别只看 token 用了多少，你的 AI 段位是多少？》
- **结构**：
  1. 开头：一个具体的数字（自己的分数和最低的一项），以及当时的惊讶。
  2. 四项能力分别是什么，自己在哪一项最差，为什么（用自己的真实例子，发之前 Kenichi 口述）。
  3. 「每天一招」怎么帮自己改掉一个习惯，前后对比。
  4. 为什么坚持本机计算、0 token（隐私和信任）。
  5. 结尾：下载方式、免费版和 Pro 的区别、欢迎反馈。
- **纪律**：文中个人经历只用 Kenichi 口述的内容，不编。

### 朋友圈

> 做了个小东西：Mac 菜单栏里的 AI 教练。每天教你一招 Claude Code 的用法，用一次就自动点亮。本机计算，不花 token。想试的私我。

## 四、60 秒录屏脚本（不露脸，适配「不露脸录屏」IP 计划）

| 时间 | 画面 | 旁白 |
|---|---|---|
| 0–5s | 菜单栏特写，圆环图标显示 72 和一个小金点 | 你天天用 Claude Code，可你知道自己是什么段位吗？ |
| 5–15s | 点开弹窗：分数环、熟练者、击败全球 X% | 365 AI Master 读你本机的使用记录，给你一个分数和段位。 |
| 15–28s | 镜头停在「今日一招」，点「复制提示词」 | 每天挑一招你还没用过的技巧，提示词已经写好，复制就行。 |
| 28–40s | 切到终端里的 Claude Code，粘贴发送 | 在 Claude Code 里正常用一次。 |
| 40–50s | 回到弹窗点刷新，卡片变绿：今天这一招已点亮 | 它在日志里看到了，这一招自动点亮。 |
| 50–60s | 本周卡片、修炼路线一闪而过，结尾标语 | 本机计算，不花一个 token。每天一招，365 天成为 AI 大师。 |

录制前提：演示用的分数和用量必须是 Kenichi 自己愿意公开的数字，或者使用演示数据。

## 五、上线前需要 Kenichi 做的事

1. **签名与公证**：用 Apple 开发者账号签名、公证 App，打成 DMG；否则别人下载后会被系统拦截。
2. **GitHub Release**：在 `KenichiXXX/365-ai-master` 发 v2.0.0 Release 并上传 DMG（官网下载按钮指向这里）。
3. **付款**：Waffo 商户上线后，把两个付款链接填进 App；之后官网「付款通道开通后」的说明可以改掉。
4. **域名与部署**：已上线 https://724.fund/365AImaster （英文版 /365AImaster/en）。更新方式：在 724fund-research 仓库最新的 main 上运行 `python3 scripts/site_deploy.py <724仓库>/public`，提交后推送即可自动部署。
5. **联系方式**：目前反馈入口是 GitHub Issues；如需邮箱，提供一个专用地址。

## 六、发布第一周节奏（建议）

| 天 | 动作 | 看什么 |
|---|---|---|
| 第 0 天 | 发给 10 个熟人用，收集第一轮反馈 | 首次引导能不能走完、今日一招有没有人真的点亮 |
| 第 1 天 | V2EX 分享创造 + 即刻 | 下载数、评论里最常问的问题 |
| 第 2 天 | X 串 | 转发和收藏 |
| 第 3 天（周二或周三） | Product Hunt | 当日排名、留言 |
| 第 5 天 | Show HN | 技术讨论里暴露的问题 |
| 第 7 天 | 复盘：下载 → 完成引导 → 次日回访 → 开始试用 → 付费 | 每一步的人数，决定下一周修什么 |
