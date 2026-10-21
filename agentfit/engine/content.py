"""Offline zh/en copy for the macOS newbie village."""

import os
from copy import deepcopy

QUESTS = [
    "first_edit",
    "rules_file",
    "light_model",
    "first_skill",
    "parallel",
    "less_rework",
    "automation",
    "declutter",
    "graduate",
]

POOL = ["fresh_session", "background_agent", "privacy_check"]

_QUEST_TEXT = {
    "zh": {
        "first_edit": {
            "title": "出生点：让 AI 动手改一次文件",
            "why": "让 AI 真正改动文件，才算开始用起来。",
            "steps": [
                "在一个项目目录里打开 Claude Code / Codex",
                "让它改一个小地方",
                "看一眼它改了什么",
            ],
            "prompt": "请在当前项目里做一个小改动：找到 README（没有就新建），在末尾加一行今天的日期和一句项目简介，改完告诉我改了哪里。",
        },
        "rules_file": {
            "title": "立规矩：写第一份 CLAUDE.md",
            "why": "CLAUDE.md / AGENTS.md 是 AI 每次开工先读的说明书，写一次长期生效。",
            "steps": [
                "让 AI 读项目结构",
                "生成 CLAUDE.md 草稿",
                "你删改后保存在项目根目录",
            ],
            "prompt": "请阅读当前项目结构，帮我写一份 CLAUDE.md：项目简介、常用命令（安装/运行/测试）、代码风格约定、不要做的事，控制在 "
            "60 行以内，写完给我看。",
        },
        "light_model": {
            "title": "会分工：机械活交给轻量模型",
            "why": "格式转换、批量提取这类活用轻量模型更快，也更省额度。",
            "steps": [
                "输入 /model 看可选模型",
                "机械任务切到最轻的一档",
                "复杂设计再切回来",
            ],
            "prompt": "接下来这个任务是机械性的（批量整理/格式转换），请用最轻量的模型完成；如果当前不是轻量模型，告诉我怎么用 /model "
            "切换。",
        },
        "first_skill": {
            "title": "第一件装备：真正用起一个 skill",
            "why": "skill 把常干的活固化成一句话就能调用的能力。",
            "steps": [
                "看看已安装的 skill",
                "挑一个最贴近你项目的",
                "用它完成一个小任务",
            ],
            "prompt": "请列出我当前已安装的 skill，挑一个最适合这个项目的，说明它能做什么，然后用它完成一个小任务。",
        },
        "parallel": {
            "title": "会并行：让子代理同时干活",
            "why": "子代理可以同时查好几处，主对话保持清爽。",
            "steps": [
                "把一个任务拆成两件互不依赖的事",
                "让 AI 用子代理并行做",
                "看汇总结果",
            ],
            "prompt": "请启动子代理并行完成两件事：A 梳理项目目录结构，B 找出所有 TODO 注释；完成后汇总给我。",
        },
        "less_rework": {
            "title": "少返工：先对齐再动手",
            "why": "中断和反复重试最浪费；先说清目标和验收标准。",
            "steps": ["开工前让 AI 复述目标", "确认验收标准", "再让它动手"],
            "prompt": "开始之前，请先用三句话复述你理解的任务目标、验收标准和打算的步骤，等我确认后再动手。",
        },
        "automation": {
            "title": "自动化：配置第一个 hook",
            "why": "hook 让固定动作自动发生，比如改完代码自动跑测试。",
            "steps": [
                "选一个每次都要做的动作",
                "让 AI 配成 hook",
                "改一次文件验证它触发",
            ],
            "prompt": "请帮我配置一个 Claude Code "
            "hook：每次你改完文件后自动运行本项目的格式化或测试命令。先告诉我要改哪个配置文件、写什么，我确认后再写入。",
        },
        "declutter": {
            "title": "断舍离：清理用不上的 skill",
            "why": "装太多 skill 会挤占上下文，用不上的就该卸掉。",
            "steps": ["列出所有 skill", "标出两周没用过的", "自己决定卸载哪些"],
            "prompt": "请列出 ~/.claude/skills 下的所有 skill，标出最近两周没用过的，给我一份建议卸载清单（只列出，不要删除）。",
        },
        "graduate": {
            "title": "出师：四维全面达标",
            "why": "模型分工、作息、上下文、复用四项都 ≥85 分，你已经出师。",
            "steps": ["看四维里最低的一项", "照今日一招练一周", "再体检"],
            "prompt": "请根据我最近的使用习惯，指出我在模型选择、作息、上下文管理、复用沉淀四方面最弱的一项，并给我一个本周练习计划。",
        },
    },
    "en": {
        "first_edit": {
            "title": "Spawn point: let the AI edit a file",
            "why": "You've really started once the AI changes a file for you.",
            "steps": [
                "Open Claude Code / Codex in a project",
                "ask for one small change",
                "review the diff",
            ],
            "prompt": "Make a small change in this project: open README (create it if "
            "missing), append today's date and a one-line project summary, "
            "then tell me exactly what you changed.",
        },
        "rules_file": {
            "title": "House rules: write your first CLAUDE.md",
            "why": "CLAUDE.md / AGENTS.md is the brief your AI reads before every task "
            "— write it once, benefit forever.",
            "steps": [
                "Let the AI read the project",
                "generate a draft",
                "trim it and save it at the repo root",
            ],
            "prompt": "Read this project's structure and write a CLAUDE.md: summary, "
            "common commands (install/run/test), code style, and things not "
            "to do. Keep it under 60 lines and show me.",
        },
        "light_model": {
            "title": "Delegate: give chores to a light model",
            "why": "Light models do formatting and bulk extraction faster and save "
            "quota.",
            "steps": [
                "Type /model to see options",
                "switch to the lightest for chores",
                "switch back for design work",
            ],
            "prompt": "The next task is mechanical (bulk cleanup / format conversion). "
            "Use the lightest model; if you aren't on one, tell me how to "
            "switch with /model.",
        },
        "first_skill": {
            "title": "First gear: actually use a skill",
            "why": "A skill turns a recurring job into a one-line command.",
            "steps": [
                "List installed skills",
                "pick the one closest to your project",
                "use it on a small task",
            ],
            "prompt": "List the skills I have installed, pick the best one for this "
            "project, explain what it does, then use it on a small task.",
        },
        "parallel": {
            "title": "Go parallel: put sub-agents to work",
            "why": "Sub-agents look in several places at once and keep your main chat "
            "clean.",
            "steps": [
                "Split a task into two independent parts",
                "ask for sub-agents",
                "read the summary",
            ],
            "prompt": "Start sub-agents to do two things in parallel: A) map the project "
            "structure, B) find every TODO comment. Then summarize both for "
            "me.",
        },
        "less_rework": {
            "title": "Less rework: align before acting",
            "why": "Interruptions and blind retries waste the most; state the goal and "
            "acceptance first.",
            "steps": [
                "Ask the AI to restate the goal",
                "agree on acceptance criteria",
                "then let it work",
            ],
            "prompt": "Before starting, restate in three sentences the goal, the "
            "acceptance criteria, and your planned steps. Wait for my "
            "confirmation before acting.",
        },
        "automation": {
            "title": "Automate: set up your first hook",
            "why": "Hooks make routine steps automatic, e.g. run tests after every "
            "edit.",
            "steps": [
                "Pick a step you always repeat",
                "have the AI configure it as a hook",
                "edit a file to see it fire",
            ],
            "prompt": "Configure a Claude Code hook that runs this project's formatter "
            "or tests after you edit files. First tell me which config file "
            "and what you'll add; write it only after I confirm.",
        },
        "declutter": {
            "title": "Declutter: drop skills you don't use",
            "why": "Too many skills crowd the context; remove the ones you never use.",
            "steps": [
                "List all skills",
                "mark the ones unused for two weeks",
                "decide what to remove",
            ],
            "prompt": "List every skill under ~/.claude/skills, mark those unused in the "
            "last two weeks, and give me a suggested removal list (list only — "
            "don't delete anything).",
        },
        "graduate": {
            "title": "Graduate: all four dimensions on target",
            "why": "Routing, timing, context and reuse are all ≥85 — you've graduated.",
            "steps": [
                "Find your lowest dimension",
                "practise today's tip for a week",
                "re-check",
            ],
            "prompt": "Based on my recent usage, tell me which of model choice, timing, "
            "context management and reuse is weakest, and give me a one-week "
            "practice plan.",
        },
    },
}

_DIMENSION_TIPS = {
    "zh": {
        "routing": {
            "title": "模型分工再优化",
            "why": "旗舰模型留给难题，日常用均衡档，杂活用轻量档。",
            "steps": ["看一眼原因", "复制下面的指令给 AI", "明天再看分数变化"],
            "prompt": "请根据我接下来要做的三件事，分别建议用哪一档模型，并说明理由。",
        },
        "timing": {
            "title": "固定 AI 工作时段",
            "why": "零散使用要反复交代背景，攒在固定时段批量处理更省。",
            "steps": ["看一眼原因", "复制下面的指令给 AI", "明天再看分数变化"],
            "prompt": "请帮我把今天零散的 AI 任务整理成两个集中时段的清单。",
        },
        "context": {
            "title": "管好上下文",
            "why": "一个任务一个会话，长会话及时开新的，常用背景写进 CLAUDE.md。",
            "steps": ["看一眼原因", "复制下面的指令给 AI", "明天再看分数变化"],
            "prompt": "请总结当前会话的结论和待办，写成一段可以粘到新会话开头的交接说明。",
        },
        "leverage": {
            "title": "把重复的活沉淀下来",
            "why": "同一件事做第三次时，就把它写成 skill 或模板。",
            "steps": ["看一眼原因", "复制下面的指令给 AI", "明天再看分数变化"],
            "prompt": "请找出我最近重复做过的一类任务，把它写成一个可复用的 skill 草稿。",
        },
    },
    "en": {
        "routing": {
            "title": "Tune model routing",
            "why": "Save the flagship for hard problems; use balanced for daily work and "
            "light for chores.",
            "steps": [
                "Read why",
                "Paste the prompt below to your AI",
                "Check the score again tomorrow",
            ],
            "prompt": "For the next three things I'm going to do, recommend which model "
            "tier to use for each and why.",
        },
        "timing": {
            "title": "Batch your AI time",
            "why": "Scattered use means re-explaining context; batching into fixed slots is "
            "cheaper.",
            "steps": [
                "Read why",
                "Paste the prompt below to your AI",
                "Check the score again tomorrow",
            ],
            "prompt": "Turn my scattered AI tasks for today into two focused time-block "
            "lists.",
        },
        "context": {
            "title": "Keep context clean",
            "why": "One task per session; start fresh when it gets long; put recurring "
            "background in CLAUDE.md.",
            "steps": [
                "Read why",
                "Paste the prompt below to your AI",
                "Check the score again tomorrow",
            ],
            "prompt": "Summarize this session's conclusions and open items as a hand-off "
            "note I can paste into a new session.",
        },
        "leverage": {
            "title": "Turn repeats into assets",
            "why": "The third time you do something, make it a skill or template.",
            "steps": [
                "Read why",
                "Paste the prompt below to your AI",
                "Check the score again tomorrow",
            ],
            "prompt": "Find a task I've repeated recently and draft a reusable skill for "
            "it.",
        },
    },
}

_POOL_TIPS = {
    "zh": {
        "privacy_check": {
            "title": "练习：查看工具的隐私说明",
            "why": "无需读取日志，也可以先准备三个隐私问题。",
            "steps": ["选一个你想了解的工具", "写下数据保存位置、训练用途和删除方式三个问题"],
            "prompt": "请起草一份三问隐私检查清单：数据存在哪里、是否用于训练、如何删除。只给清单，不读取文件或修改设置。",
        },
        "fresh_session": {
            "title": "练习：写一段交接说明",
            "why": "用一个虚构任务练习写清目标、约束和验收条件。",
            "steps": ["选一个虚构任务", "写出目标、约束和检查方法"],
            "prompt": "以整理虚构的读书清单为例，起草一段包含目标、约束和验收方法的交接说明。只给草稿，不操作文件。",
        },
        "background_agent": {
            "title": "练习：拆解一个批量任务",
            "why": "先检查步骤，再决定是否执行。",
            "steps": ["用虚构数据描述一个批量任务", "列出步骤和每步的检查方法"],
            "prompt": "以整理十个虚构文件名为例，起草批量处理步骤和检查清单。不要运行命令或操作文件。",
        },
    },
    "en": {
        "privacy_check": {
            "title": "Practice: review a tool's privacy information",
            "why": "Prepare three privacy questions without reading any logs.",
            "steps": ["Choose a tool to learn about", "Ask about storage, training use and deletion"],
            "prompt": "Draft a three-question privacy checklist about storage, training use and deletion. Only provide a checklist. Do not read files or change settings.",
        },
        "fresh_session": {
            "title": "Practice: draft a hand-off note",
            "why": "Use a fictional task to state a goal, constraints and acceptance checks.",
            "steps": ["Choose a fictional task", "Write the goal, constraints and checks"],
            "prompt": "Using a fictional reading list, draft a hand-off note with a goal, constraints and acceptance checks. Only draft text. Do not operate on files.",
        },
        "background_agent": {
            "title": "Practice: break down a batch task",
            "why": "Review the steps before deciding whether to execute anything.",
            "steps": ["Describe a batch task with fictional data", "List steps and checks"],
            "prompt": "Using ten fictional file names, draft batch-processing steps and a checklist. Do not run commands or operate on files.",
        },
    },
}


_RANK_TITLES = {
    "zh": ["AI 探索者", "AI 熟练者", "AI 大师", "AI 宗师"],
    "en": ["Explorer", "Practitioner", "Master", "Grandmaster"],
}

_LABELS = {
    "zh": {
        "routing": "模型路由",
        "timing": "时间习惯",
        "context": "上下文卫生",
        "leverage": "沉淀复用",
        "tool_unavailable": "该工具数据暂不可用",
        "no_tools": "还没检测到 Claude Code 或 Codex。先安装一个，再回来体检。",
    },
    "en": {
        "routing": "Routing",
        "timing": "Timing",
        "context": "Context",
        "leverage": "Reuse",
        "tool_unavailable": "Data temporarily unavailable",
        "no_tools": "No Claude Code or Codex found yet. Install one, then come back.",
    },
}


def quest_text(key: str, locale: str) -> dict:
    return deepcopy(_QUEST_TEXT[locale][key])


def dimension_tip(key: str, locale: str) -> dict:
    return deepcopy(_DIMENSION_TIPS[locale][key])


def pool_tip(id: str, locale: str) -> dict:
    return deepcopy(_POOL_TIPS[locale][id])


def rank_title(level: int, locale: str) -> str:
    return _RANK_TITLES[locale][min(level // 3, 3)]


def label(name: str, locale: str) -> str:
    return _LABELS[locale][name]


def locale_from_env() -> str:
    language = os.environ.get("LC_ALL") or os.environ.get("LANG", "")
    return "zh" if language.startswith("zh") else "en"


_BADGE_TITLES = {
    "streak_3": ("连续 3 天", "3-day streak"),
    "streak_7": ("一周修行", "One-week streak"),
    "streak_14": ("两周修行", "Two-week streak"),
    "streak_30": ("一月修行", "30-day streak"),
    "book_5": ("图鉴 5 张", "5 cards lit"),
    "book_10": ("图鉴 10 张", "10 cards lit"),
    "book_20": ("图鉴 20 张", "20 cards lit"),
    "book_all": ("图鉴全收集", "Full collection"),
    "village_done": ("新手村出师", "Village graduate"),
}


def badge_title(key: str, locale: str) -> str:
    return _BADGE_TITLES[key][0 if locale == "zh" else 1]


def skill_level_title(level: int, locale: str) -> str:
    titles = {1: {"zh": "入门", "en": "Basics"},
              2: {"zh": "进阶", "en": "Intermediate"},
              3: {"zh": "高手", "en": "Advanced"}}
    return titles[level][locale]


_COVERAGE_LABELS = {
    "no_logs": ("尚无使用记录", "No usage records yet"),
    "permission_denied": ("无法读取日志，可稍后重试", "Logs cannot be read. Try again later"),
    "unsupported": ("此日志格式暂不支持", "This log format is not supported yet"),
    "partial": ("部分记录可用", "Some records are available"),
    "configuration_found": ("配置存在，尚未验证使用", "Configuration found; use has not been verified"),
}
for _key, (_zh, _en) in _COVERAGE_LABELS.items():
    _LABELS["zh"][_key] = _zh
    _LABELS["en"][_key] = _en


_ACTION_COPY = {
    "en": {
        "heuristic": "This is a heuristic from log metrics, not a measure of task difficulty or ability",
        "missing": "No assessable records yet",
        "partial": "Partly assessable",
        "practice": "A suggested practice; completion needs subsequent structured evidence, not a click.",
        "safe": "A built-in exercise available without supported logs. Completion is self-reported.",
        "none": "No suggestions available. Reset suggestion preferences in Settings to see them again.",
        "model_overuse": "Premium-tier API-equivalent cost share; this does not identify routine tasks or guarantee savings.",
        "fast_gap": "Fast-tier token share; model tier does not establish task difficulty.",
        "late_night": "Share of usage records between local midnight and 06:00; this does not measure sleep or productivity.",
        "fragmented": "Active local hour bins and the top-three-hour share; this does not establish interruptions.",
        "concentrated": "Top-three-hour share of usage records; this does not measure focus.",
        "context_bloat": "Compactions per recorded turn; compaction does not establish wasted context.",
        "retry": "Abort markers per recorded turn; an abort does not establish an error or repeated task.",
        "cache": "Cached input tokens divided by recorded input plus cached input; provider caching differs.",
    },
    "zh": {
        "heuristic": "这是日志指标的启发式判断，不代表任务难度或能力",
        "missing": "尚无可评估记录",
        "partial": "部分可评估",
        "practice": "建议练习；完成需要后续结构化记录，点击不代表完成。",
        "safe": "无需受支持日志的内置练习，完成情况由你自行确认。",
        "none": "暂无可推荐的练习。可在设置中重置推荐偏好。",
        "model_overuse": "旗舰档 API 折算成本占比；不能据此识别常规任务或保证节省。",
        "fast_gap": "轻量档 token 占比；模型档位不能说明任务难度。",
        "late_night": "本地零点至六点的用量记录占比；不代表睡眠或生产力。",
        "fragmented": "有活动的本地小时数与前三小时占比；不代表受到打断。",
        "concentrated": "前三小时的用量记录占比；不代表专注程度。",
        "context_bloat": "每个记录轮次的压缩次数；压缩不代表上下文浪费。",
        "retry": "中断标记与记录轮次之比；中断不代表错误或重复任务。",
        "cache": "缓存输入 token 除以输入与缓存输入总量；不同供应商的缓存机制有差异。",
    },
}


def action_copy(key: str, locale: str) -> str:
    return _ACTION_COPY[locale][key]


FIRST_PRACTICE = {
    "zh": {
        "title": "先练一步",
        "prompt": "请用简单语言解释当前项目如何启动；先不要修改文件。",
        "no_project_prompt": "帮我列出一个想做的小工具的目标和验收清单，先不要执行命令。",
        "limitation": "复制或自报不代表已验证输出正确，也不会自动通过关卡。",
    },
    "en": {
        "title": "Try one step",
        "prompt": "Explain how to start this project in plain language. Do not modify files.",
        "no_project_prompt": "Help me list the goal and acceptance checks for a small tool I want to build. Do not run commands.",
        "limitation": "Copying or self-reporting does not verify correctness or automatically pass a quest.",
    },
}

QUEST_EVIDENCE = {
    "configuration": ("配置存在，尚未验证使用", "Configuration found; use has not been verified"),
    "historical": ("历史记录，不代表本次练习", "Historical record, not evidence of this practice"),
    "new_observed": ("新观察到的使用，不代表输出正确", "Newly observed use, not verified correctness"),
    "self_reported": ("已尝试（自报）", "Tried (self-reported)"),
    "unsupported": ("暂不支持自动验证，可手动练习", "Automatic verification unavailable; practice manually"),
    "not_observed": ("尚未观察到", "Not observed yet"),
}


def first_practice(locale: str) -> dict:
    return {**FIRST_PRACTICE[locale], "validation_kind": "self_reported"}


def quest_evidence_label(kind: str, locale: str) -> str:
    return QUEST_EVIDENCE[kind][0 if locale == "zh" else 1]


PRACTICE_EVIDENCE = {
    "ready": ("待实践", "Ready to practise"),
    "started": ("已开始，等待新记录", "Started; waiting for new records"),
    "log_observed": ("日志已观察", "Observed in logs"),
    "reuse": ("再次使用", "Used again"),
    "historical": ("历史记录", "Historical record"),
    "configuration": ("配置存在", "Configuration found"),
    "self_reported": ("已尝试（自报）", "Tried (self-reported)"),
}


def practice_evidence_label(kind: str, locale: str) -> str:
    return PRACTICE_EVIDENCE[kind][0 if locale == "zh" else 1]


_REVIEW_COPY = {
    "en": {
        "tokens": "Logged tokens (excluding cache reads)",
        "price_basis": "API-equivalent at public prices, not a subscription bill",
        "matched_subtotal": "Matched subtotal USD {amount}, price coverage {pct}%",
        "price_unknown": "Price unknown", "price_date": "Price table dated {date}",
        "quota_hours": "Codex {hours}-hour window: {pct}% used",
        "quota_week": "Codex weekly window: {pct}% used",
        "quota_minutes": "Codex {minutes}-minute window: {pct}% used",
        "quota_recorded": "Quota recorded {date}", "quota_reset": "Resets {date}",
        "quota_stale": "Quota record is stale", "quota_future": "Quota record is future-dated",
        "delta": "Mean score change for matched weekdays: {delta} points",
        "accumulating": "Collecting comparable data", "version_changed": "Scoring version changed",
        "observed": "New structured practice observations: {count}",
        "no_change": "No new practice change was observed this week",
        "uncertainty": "Log evidence does not prove output quality or time saved",
        "next_practice": "One practice for next week",
        "separate": "Configuration / self-report: {configured} / {self_reported}; reuse: {reuse}",
    },
    "zh": {
        "tokens": "日志 Token（不含缓存读取）",
        "price_basis": "按公开 API 单价折算，非订阅账单",
        "matched_subtotal": "已匹配部分折算 USD {amount}，价格覆盖 {pct}%",
        "price_unknown": "价格未知", "price_date": "价格表日期 {date}",
        "quota_hours": "Codex {hours} 小时窗口已用 {pct}%", "quota_week": "Codex 周窗口已用 {pct}%",
        "quota_minutes": "Codex {minutes} 分钟窗口已用 {pct}%",
        "quota_recorded": "额度记录时间 {date}", "quota_reset": "重置时间 {date}",
        "quota_stale": "额度记录已过时", "quota_future": "额度记录时间在未来",
        "delta": "同星期窗口均分变化 {delta} 分",
        "accumulating": "可比数据积累中", "version_changed": "评分版本变化",
        "observed": "新的结构化实践观察：{count}", "no_change": "本周未观察到新的实践变化",
        "uncertainty": "日志证据不能证明输出质量或节省时间", "next_practice": "下周练一步",
        "separate": "配置 / 自报：{configured} / {self_reported}；复用：{reuse}",
    },
}


def review_labels(locale):
    return dict(_REVIEW_COPY[locale])
