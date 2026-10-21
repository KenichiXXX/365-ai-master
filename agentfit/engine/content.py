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
        "fresh_session": {
            "title": "长会话记得开新会话，省钱又提质",
            "why": "会话越长，每次请求都在为历史付费，注意力也被稀释。",
            "steps": [],
            "prompt": "请就这一条，结合我的使用方式给我一个具体建议。",
        },
        "background_agent": {
            "title": "批量任务交给后台 agent，你只看结果",
            "why": "翻译、清洗一批数据这类活，让 agent 在后台跑完再叫你。",
            "steps": [],
            "prompt": "请就这一条，结合我的使用方式给我一个具体建议。",
        },
        "privacy_check": {
            "title": "任何要读你聊天记录的 AI 产品，先问三件事",
            "why": "数据存哪、是否用于训练、能否一键删除。",
            "steps": [],
            "prompt": "请就这一条，结合我的使用方式给我一个具体建议。",
        },
    },
    "en": {
        "fresh_session": {
            "title": "Start fresh sessions",
            "why": "Long sessions pay for history on every request and dilute "
            "attention.",
            "steps": [],
            "prompt": "Give me one concrete suggestion on this, based on how I "
            "work.",
        },
        "background_agent": {
            "title": "Hand batch jobs to a background agent",
            "why": "Let an agent run translations or data cleanup in the "
            "background and ping you when done.",
            "steps": [],
            "prompt": "Give me one concrete suggestion on this, based on how I "
            "work.",
        },
        "privacy_check": {
            "title": "Three questions before granting an AI app your chat history",
            "why": "Where is data stored, is it used for training, can you delete it "
            "in one click.",
            "steps": [],
            "prompt": "Give me one concrete suggestion on this, based on how I "
            "work.",
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
