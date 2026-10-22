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
            "title": "让 AI 改一个文件",
            "why": "从一个小改动开始",
            "steps": [
                "打开项目",
                "改一处文件",
                "检查改动",
            ],
            "prompt": "请在当前项目里做一个小改动：找到 README（没有就新建），在末尾加一行今天的日期和一句项目简介，改完告诉我改了哪里。",
        },
        "rules_file": {
            "title": "写好项目规则",
            "why": "让 AI 每次开工有章可循",
            "steps": [
                "让 AI 读项目",
                "生成 CLAUDE.md",
                "审阅后保存",
            ],
            "prompt": "请阅读当前项目结构，帮我写一份 CLAUDE.md：项目简介、常用命令（安装/运行/测试）、代码风格约定、不要做的事，控制在 "
            "60 行以内，写完给我看。",
        },
        "light_model": {
            "title": "切到轻量模型",
            "why": "简单活更快、更省额度",
            "steps": [
                "输入 /model",
                "选最轻的一档",
                "复杂任务再切回",
            ],
            "prompt": "接下来这个任务是机械性的（批量整理/格式转换），请用最轻量的模型完成；如果当前不是轻量模型，告诉我怎么用 /model "
            "切换。",
        },
        "first_skill": {
            "title": "用起一个技能",
            "why": "常干的活，一句话调用",
            "steps": [
                "查看已装技能",
                "选一个合适的",
                "完成一个小任务",
            ],
            "prompt": "请列出我当前已安装的 skill，挑一个最适合这个项目的，说明它能做什么，然后用它完成一个小任务。",
        },
        "parallel": {
            "title": "让子代理同时干活",
            "why": "独立任务一起做",
            "steps": [
                "拆成两件独立任务",
                "启动子代理",
                "检查汇总",
            ],
            "prompt": "请启动子代理并行完成两件事：A 梳理项目目录结构，B 找出所有 TODO 注释；完成后汇总给我。",
        },
        "less_rework": {
            "title": "先对齐再动手",
            "why": "先说清目标和验收标准",
            "steps": ["让 AI 复述目标", "确认验收标准", "再开始执行"],
            "prompt": "开始之前，请先用三句话复述你理解的任务目标、验收标准和打算的步骤，等我确认后再动手。",
        },
        "automation": {
            "title": "自动跑一次测试",
            "why": "改完代码，自动检查",
            "steps": [
                "选一个固定动作",
                "配置 hook",
                "改文件验证触发",
            ],
            "prompt": "请帮我配置一个 Claude Code "
            "hook：每次你改完文件后自动运行本项目的格式化或测试命令。先告诉我要改哪个配置文件、写什么，我确认后再写入。",
        },
        "declutter": {
            "title": "清理闲置技能",
            "why": "把空间留给常用技能",
            "steps": ["列出所有技能", "标出闲置技能", "决定保留哪些"],
            "prompt": "请列出 ~/.claude/skills 下的所有 skill，标出最近两周没用过的，给我一份建议卸载清单（只列出，不要删除）。",
        },
        "graduate": {
            "title": "练好最弱的一项",
            "why": "四项都达到 85 分即可出师",
            "steps": ["找到最低分", "练习一周", "重新体检"],
            "prompt": "请根据我最近的使用习惯，指出我在模型选择、作息、上下文管理、复用沉淀四方面最弱的一项，并给我一个本周练习计划。",
        },
    },
    "en": {
        "first_edit": {
            "title": "Edit one file",
            "why": "Start with a small change",
            "steps": [
                "Open a project",
                "Ask for one edit",
                "Review the diff",
            ],
            "prompt": "Make a small change in this project: open README (create it if "
            "missing), append today's date and a one-line project summary, "
            "then tell me exactly what you changed.",
        },
        "rules_file": {
            "title": "Write project rules",
            "why": "Give your AI a reusable brief",
            "steps": [
                "Ask AI to read the project",
                "Draft CLAUDE.md",
                "Review and save",
            ],
            "prompt": "Read this project's structure and write a CLAUDE.md: summary, "
            "common commands (install/run/test), code style, and things not "
            "to do. Keep it under 60 lines and show me.",
        },
        "light_model": {
            "title": "Switch to a light model",
            "why": "Use less quota for simple tasks",
            "steps": [
                "Type /model",
                "Pick the lightest tier",
                "Switch back for hard tasks",
            ],
            "prompt": "The next task is mechanical (bulk cleanup / format conversion). "
            "Use the lightest model; if you aren't on one, tell me how to "
            "switch with /model.",
        },
        "first_skill": {
            "title": "Try a skill",
            "why": "Run a routine task with one command",
            "steps": [
                "List installed skills",
                "Pick one for this project",
                "Use it on a small task",
            ],
            "prompt": "List the skills I have installed, pick the best one for this "
            "project, explain what it does, then use it on a small task.",
        },
        "parallel": {
            "title": "Run tasks in parallel",
            "why": "Handle independent tasks together",
            "steps": [
                "Split into independent tasks",
                "Start sub-agents",
                "Review the summary",
            ],
            "prompt": "Start sub-agents to do two things in parallel: A) map the project "
            "structure, B) find every TODO comment. Then summarize both for "
            "me.",
        },
        "less_rework": {
            "title": "Agree before acting",
            "why": "Make the goal and checks clear",
            "steps": [
                "Ask AI to restate the goal",
                "Agree on acceptance checks",
                "Start the work",
            ],
            "prompt": "Before starting, restate in three sentences the goal, the "
            "acceptance criteria, and your planned steps. Wait for my "
            "confirmation before acting.",
        },
        "automation": {
            "title": "Automate a routine check",
            "why": "Run checks after each edit",
            "steps": [
                "Pick a repeated step",
                "Configure a hook",
                "Edit a file to test it",
            ],
            "prompt": "Configure a Claude Code hook that runs this project's formatter "
            "or tests after you edit files. First tell me which config file "
            "and what you'll add; write it only after I confirm.",
        },
        "declutter": {
            "title": "Review unused skills",
            "why": "Make room for the skills you use",
            "steps": [
                "List all skills",
                "Mark unused ones",
                "Decide what to keep",
            ],
            "prompt": "List every skill under ~/.claude/skills, mark those unused in the "
            "last two weeks, and give me a suggested removal list (list only — "
            "don't delete anything).",
        },
        "graduate": {
            "title": "Improve your weakest area",
            "why": "Reach 85 in all four areas",
            "steps": [
                "Find your lowest score",
                "Practise for a week",
                "Re-check",
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
            "title": "切到轻量模型",
            "why": "旗舰留给难题，简单活用轻量",
            "steps": ["输入 /model", "选择轻量档", "明天再体检"],
            "prompt": "请根据我接下来要做的三件事，分别建议用哪一档模型，并说明理由。",
        },
        "timing": {
            "title": "集中处理 AI 任务",
            "why": "同类问题一起处理",
            "steps": ["列出今天任务", "安排两个时段", "集中处理"],
            "prompt": "请帮我把今天零散的 AI 任务整理成两个集中时段的清单。",
        },
        "context": {
            "title": "开一个新会话",
            "why": "一个任务一个会话",
            "steps": ["总结当前结论", "打开新会话", "粘贴必要背景"],
            "prompt": "请总结当前会话的结论和待办，写成一段可以粘到新会话开头的交接说明。",
        },
        "leverage": {
            "title": "把重复任务存成技能",
            "why": "下次一句话就能调用",
            "steps": ["找出重复任务", "写成技能草稿", "下次再用一次"],
            "prompt": "请找出我最近重复做过的一类任务，把它写成一个可复用的 skill 草稿。",
        },
    },
    "en": {
        "routing": {
            "title": "Choose a lighter model",
            "why": "Save flagship models for hard tasks",
            "steps": [
                "Type /model",
                "Choose a light tier",
                "Re-check tomorrow",
            ],
            "prompt": "For the next three things I'm going to do, recommend which model "
            "tier to use for each and why.",
        },
        "timing": {
            "title": "Batch your AI tasks",
            "why": "Handle similar tasks together",
            "steps": [
                "List today’s tasks",
                "Choose two time blocks",
                "Work through each batch",
            ],
            "prompt": "Turn my scattered AI tasks for today into two focused time-block "
            "lists.",
        },
        "context": {
            "title": "Start a fresh chat",
            "why": "Keep one task per conversation",
            "steps": [
                "Summarize current conclusions",
                "Open a new chat",
                "Paste only needed context",
            ],
            "prompt": "Summarize this session's conclusions and open items as a hand-off "
            "note I can paste into a new session.",
        },
        "leverage": {
            "title": "Save a repeated task as a skill",
            "why": "Reuse it with one command next time",
            "steps": [
                "Find a repeated task",
                "Draft a reusable skill",
                "Try it again next time",
            ],
            "prompt": "Find a task I've repeated recently and draft a reusable skill for "
            "it.",
        },
    },
}

_POOL_TIPS = {
    "zh": {
        "privacy_check": {
            "title": "查看隐私说明",
            "why": "先了解数据如何使用",
            "steps": ["选一个工具", "查保存和训练用途", "查删除方式"],
            "prompt": "请起草一份三问隐私检查清单：数据存在哪里、是否用于训练、如何删除。只给清单，不读取文件或修改设置。",
        },
        "fresh_session": {
            "title": "写一段交接说明",
            "why": "练习说清目标和检查方法",
            "steps": ["选一个虚构任务", "写出目标和约束", "列出检查方法"],
            "prompt": "以整理虚构的读书清单为例，起草一段包含目标、约束和验收方法的交接说明。只给草稿，不操作文件。",
        },
        "background_agent": {
            "title": "拆解一个批量任务",
            "why": "执行前先看清步骤",
            "steps": ["虚构十个文件名", "列出处理步骤", "列出检查方法"],
            "prompt": "以整理十个虚构文件名为例，起草批量处理步骤和检查清单。不要运行命令或操作文件。",
        },
    },
    "en": {
        "privacy_check": {
            "title": "Review privacy information",
            "why": "Check how a tool handles your data",
            "steps": ["Choose a tool", "Check storage and training use", "Check deletion options"],
            "prompt": "Draft a three-question privacy checklist about storage, training use and deletion. Only provide a checklist. Do not read files or change settings.",
        },
        "fresh_session": {
            "title": "Draft a hand-off note",
            "why": "Practise clear goals and checks",
            "steps": ["Choose a fictional task", "Write its goal and constraints", "List acceptance checks"],
            "prompt": "Using a fictional reading list, draft a hand-off note with a goal, constraints and acceptance checks. Only draft text. Do not operate on files.",
        },
        "background_agent": {
            "title": "Break down a batch task",
            "why": "Review steps before running them",
            "steps": ["Invent ten file names", "List processing steps", "List checks"],
            "prompt": "Using ten fictional file names, draft batch-processing steps and a checklist. Do not run commands or operate on files.",
        },
    },
}


_RANK_TITLES = {
    "zh": ["AI 探索者", "AI 熟练者", "AI 大师", "AI 宗师"],
    "en": ["Explorer", "Practitioner", "Master", "Grandmaster"],
}

_LABELS = {
    "zh": {'routing': '模型路由', 'timing': '时间习惯', 'context': '上下文卫生', 'leverage': '沉淀复用', 'tool_unavailable': '该工具数据暂不可用', 'no_tools': '先安装 Claude Code 或 Codex', 'no_logs': '尚无使用记录', 'permission_denied': '无法读取日志，可稍后重试', 'unsupported': '此日志格式暂不支持', 'partial': '部分记录可用', 'configuration_found': '已配置，尚未验证使用'},
    "en": {'routing': 'Routing', 'timing': 'Timing', 'context': 'Context', 'leverage': 'Reuse', 'tool_unavailable': 'Data temporarily unavailable', 'no_tools': 'Install Claude Code or Codex to begin', 'no_logs': 'No usage records yet', 'permission_denied': 'Logs cannot be read. Try again later', 'unsupported': 'This log format is not supported yet', 'partial': 'Some records are available', 'configuration_found': 'Configured; use not verified'},
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
    "configuration_found": ("已配置，尚未验证使用", "Configured; use not verified"),
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
    "configuration": ("已配置，尚未验证使用", "Configured; use not verified"),
    "historical": ("历史记录，非本次练习", "Past record, not this practice"),
    "new_observed": ("观察到使用，未验证正确性", "Use observed; correctness unverified"),
    "self_reported": ("已尝试（自报）", "Tried (self-reported)"),
    "unsupported": ("请手动练习", "Practise manually"),
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
        "price_partial_unknown": "Some model prices are unknown",
        "price_tier_basis": "Known model tiers use approximate API rates; cache writes use the input tier rate",
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
        "price_partial_unknown": "部分模型价格未知",
        "price_tier_basis": "已知模型按档位近似折算，缓存写入按输入档位价估算",
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


def practice_calendar_labels(locale):
    rows = {
        "title": ("实践历", "Practice calendar"),
        "observed": ("日志实践", "Observed practice"),
        "self_reported": ("自报尝试", "Self-reported attempt"),
        "usage_only": ("仅有使用记录", "Usage only"),
        "unavailable": ("数据不可用", "Data unavailable"),
        "rest": ("休息不会扣除已获成就", "Rest does not remove earned achievements"),
        "streak": ("连续有 AI 使用记录 {n} 天", "AI usage: {n} consecutive days"),
    }
    return {key: values[0 if locale == "zh" else 1] for key, values in rows.items()}


def local_validation_labels(locale):
    zh = locale == "zh"
    return {"title": "本机验证面板" if zh else "Local validation",
            "privacy": "仅代表本次安装，不会上报" if zh else "Only on this device; nothing reported",
            "not_yet": "尚未到观察日期" if zh else "Observation date has not arrived"}


_CHECKUP_DETAILS = {
    "zh": {
        "healthy": "没有扣分，保持住",
        "unknown": "记录不足，暂无法判断",
        "keep": "保持当前习惯",
        "model_overuse": ("旗舰占比偏高", ["日常用均衡档", "简单活用轻量档"]),
        "fast_gap": ("轻量占比偏低", ["输入 /model", "简单活切轻量档"]),
        "late_night": ("深夜用量偏高", ["白天安排任务", "次日检查结果"]),
        "fragmented": ("时段较零散", ["固定两个时段", "同类问题一起处理"]),
        "context_bloat": ("压缩比例偏高", ["完成后开新对话", "只读必要片段", "保存常用背景"]),
        "cache": ("缓存命中偏低", ["固定规则放开头", "变化问题放最后"]),
        "retry": ("中断比例偏高", ["失败两次先停下", "缩小任务再试"]),
        "evidence": {
            "premium_tokens": ("旗舰 Token", "≤60%"),
            "model_overuse": ("旗舰折算占比", "≤60%"),
            "fast_gap": ("轻量占比", "≥5%"),
            "late_night": ("深夜占比", "≤25%"),
            "fragmented": ("最忙三小时", None),
            "concentrated": ("活跃小时段", None),
            "context_bloat": ("压缩 / 提问", "压缩少于 3 次或占比 <10%"),
            "retry": ("中断 / 提问", "提问少于 10 次或占比 <10%"),
            "cache": ("缓存命中", "≥50%"),
            "reuse": ("技能调用", None),
        },
    },
    "en": {
        "healthy": "No deductions. Keep it up.",
        "unknown": "Not enough records yet",
        "keep": "Keep your current habits",
        "model_overuse": ("High flagship share", ["Use a balanced tier by default", "Use a light tier for simple tasks"]),
        "fast_gap": ("Low light-model share", ["Type /model", "Try a light tier for simple tasks"]),
        "late_night": ("High late-night usage", ["Plan work during the day", "Review results the next morning"]),
        "fragmented": ("Scattered hours", ["Choose two time blocks", "Batch similar questions"]),
        "context_bloat": ("Frequent compactions", ["Start fresh after each task", "Read only needed excerpts", "Save recurring background"]),
        "cache": ("Low cache hit rate", ["Put fixed rules first", "Put changing questions last"]),
        "retry": ("Frequent interruptions", ["Pause after two failures", "Narrow the task and retry"]),
        "evidence": {
            "premium_tokens": ("Flagship tokens", "≤60%"),
            "model_overuse": ("Flagship cost share", "≤60%"),
            "fast_gap": ("Light share", "≥5%"),
            "late_night": ("Late-night share", "≤25%"),
            "fragmented": ("Busiest 3 hours", None),
            "concentrated": ("Active hours", None),
            "context_bloat": ("Compactions / prompts", "Fewer than 3 compressions or <10%"),
            "retry": ("Interruptions / prompts", "Fewer than 10 prompts or <10%"),
            "cache": ("Cache hits", "≥50%"),
            "reuse": ("Skill calls", None),
        },
    },
}


def checkup_detail_copy(locale: str) -> dict:
    return deepcopy(_CHECKUP_DETAILS[locale])

# Task 45: fixed, local-only game copy. No downloaded or generated rewards.
GAME_TIPS = [
    ("今天也向前走了一小步。", "One small step forward today."),
    ("先试一件小事，再看结果。", "Try one thing, then check."),
    ("好问题值得多花一分钟。", "A good question deserves another minute."),
    ("记下一个今天的新发现。", "Note a new discovery."),
    ("让 AI 帮你开始，由你来判断。", "Let AI start; you decide."),
    ("学会一招，就找机会用一次。", "Try your new skill."),
    ("休息一下，回来会更清楚。", "Take a break and return with fresh eyes."),
    ("小任务也能练出好习惯。", "Small tasks build good habits."),
    ("清楚的目标，让合作更轻松。", "A clear goal makes collaboration easier."),
    ("做完以后，花一点时间检查。", "Take a moment to check your work."),
    ("把复杂的事拆成一小步。", "Break it into one step."),
    ("保留判断，也保持好奇。", "Stay curious and keep your judgment."),
    ("今天的新招，明天可以再试。", "Try today's new skill again tomorrow."),
    ("把有用的做法留给下一次。", "Keep useful approaches for next time."),
    ("遇到卡点，先说清楚问题。", "Describe the problem first."),
    ("让工具为你的目标服务。", "Let your tools serve your goals."),
    ("不必一次学完，慢慢来。", "You do not have to learn it all at once."),
    ("试过以后，你会更了解自己的方法。", "Try it and reflect."),
    ("给下一次的自己留一句提示。", "Leave yourself a helpful note."),
    ("今天的认真，值得一个小庆祝。", "Celebrate today’s effort."),
]
GAME_LEVELS = {
    "zh": ["学徒", "见习", "熟练", "专家", "大师", "宗师"],
    "en": ["Apprentice", "Novice", "Skilled", "Expert", "Master", "Grandmaster"],
}
GAME_WEEKLY = {
    "cards": (2, {"zh": "点亮 2 张新卡", "en": "Light up 2 new cards"}),
    "checkins": (5, {"zh": "打卡 5 天", "en": "Check in on 5 days"}),
    "practices": (3, {"zh": "完成 3 次练习", "en": "Complete 3 practices"}),
    "dimension": (5, {"zh": "让一个维度提高 5 分", "en": "Raise one dimension by 5 points"}),
}
