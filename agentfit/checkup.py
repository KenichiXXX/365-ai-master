"""四维体检评分 — CLI / 引擎 / 云端共用的唯一来源。"""
from typing import Dict, List, Optional, Tuple

from agentfit.models.checkup import CheckupIssue, DimensionScore, TimeInsight
from agentfit.pricing import classify_model

# fast 档价格约为 premium 档的 1/10 — 用于节省估算
FAST_VS_PREMIUM_COST_RATIO = 0.1
# 假设 premium 用量中约 40% 是本可下放的常规任务 (保守估计)
ROUTABLE_SHARE_OF_PREMIUM = 0.4


def diagnose_model_mix(
    usage_by_model: Dict[str, dict],
    total_cost_7d: float,
) -> Tuple[str, float, Dict[str, bool]]:
    """诊断当前模型使用结构。

    返回 (诊断文本, 预估每月可节省美元, 信号 flags)。
    flags: model_overuse=旗舰档成本超配; fast_gap=几乎没用轻量模型。
    诊断闸门以**成本份额**为准 (premium 单价约为 fast 10 倍,
    成本集中远早于 token 集中出现, 用 token 份额做闸门会漏报最典型的浪费)。
    """
    flags = {"model_overuse": False, "fast_gap": False}
    if not usage_by_model:
        return (
            "还没同步到你各个模型的用量明细(在电脑上运行一次 agentfit sync 即可)。"
            "下面先给你通用的『什么活用什么模型』对照表;同步后会变成个性化诊断。",
            0.0,
            flags,
        )

    tier_tokens = {"premium": 0, "balanced": 0, "fast": 0}
    tier_cost = {"premium": 0.0, "balanced": 0.0, "fast": 0.0}
    for name, u in usage_by_model.items():
        tier = classify_model(name)
        tier_tokens[tier] += int(u.get("tokens", 0))
        tier_cost[tier] += float(u.get("cost", 0.0))

    total_tokens = sum(tier_tokens.values()) or 1
    total_cost = sum(tier_cost.values())
    fast_token_share = tier_tokens["fast"] / total_tokens
    # 明细成本缺失时退回 token 份额估算
    if total_cost > 0:
        premium_cost_share = tier_cost["premium"] / total_cost
    else:
        premium_cost_share = tier_tokens["premium"] / total_tokens

    monthly_cost = total_cost_7d / 7.0 * 30.0
    saving = 0.0
    parts = []

    if premium_cost_share > 0.6:
        flags["model_overuse"] = True
        saving = (
            tier_cost["premium"] / 7.0 * 30.0
            * ROUTABLE_SHARE_OF_PREMIUM
            * (1 - FAST_VS_PREMIUM_COST_RATIO)
        )
        parts.append(
            f"旗舰档模型吃掉了你 {premium_cost_share:.0%} 的用量价值。"
            "按经验其中约四成是可以下放的常规任务——把它们切到轻量档。"
        )
    elif premium_cost_share > 0.3:
        parts.append(
            f"旗舰档占成本 {premium_cost_share:.0%},结构基本健康。"
            "留意别把格式化、提取类杂活也丢给它。"
        )
    else:
        parts.append(f"旗舰档仅占成本 {premium_cost_share:.0%},模型分层意识很好。")

    if fast_token_share < 0.05:
        flags["fast_gap"] = True
        parts.append(
            "你几乎没有使用轻量模型——这是最大的优化空间。"
            "机械任务切过去,速度和成本同时改善。"
        )
        if saving == 0.0:
            saving = monthly_cost * 0.2

    return " ".join(parts), round(saving, 2), flags


def analyze_time_habits(
    hourly_histogram: Optional[List[int]],
) -> Tuple[List[TimeInsight], List[int], Dict[str, bool]]:
    """从 24 小时使用分布提取习惯洞察。返回 (insights, peak_hours, flags)。

    flags: no_data / late_night / fragmented / concentrated。
    """
    flags = {
        "no_data": False,
        "late_night": False,
        "fragmented": False,
        "concentrated": False,
    }
    if not hourly_histogram or len(hourly_histogram) != 24 or sum(hourly_histogram) == 0:
        flags["no_data"] = True
        return (
            [
                TimeInsight(
                    pattern="暂无时间分布数据",
                    advice="运行一次 agentfit sync 同步数据后,教练就能告诉你什么时间该干什么。",
                )
            ],
            [],
            flags,
        )

    total = sum(hourly_histogram)
    ranked = sorted(range(24), key=lambda h: hourly_histogram[h], reverse=True)
    peak_hours = sorted(ranked[:3])
    insights: List[TimeInsight] = []

    late_night = sum(hourly_histogram[0:6]) / total
    if late_night > 0.25:
        flags["late_night"] = True
        insights.append(
            TimeInsight(
                pattern=f"深夜(0-6点)用量占 {late_night:.0%}",
                advice="把批量任务(整理数据/翻译/跑测试)设成后台定时任务,深夜自动跑,"
                "你只在白天做需要判断力的决策。熬夜盯着 AI 干活是双输。",
            )
        )

    active_hours = sum(1 for c in hourly_histogram if c > 0)
    top3_share = sum(hourly_histogram[h] for h in ranked[:3]) / total
    if active_hours >= 14 and top3_share < 0.45:
        flags["fragmented"] = True
        insights.append(
            TimeInsight(
                pattern=f"全天碎片化使用({active_hours} 个小时段有活动)",
                advice="碎片化使用意味着反复重建上下文,这是隐形浪费。"
                "把零散问题攒到固定的 2-3 个'AI 工作时段'集中处理,"
                "一个会话内批量完成同类任务。",
            )
        )
    elif top3_share >= 0.6:
        flags["concentrated"] = True
        insights.append(
            TimeInsight(
                pattern=f"使用高度集中在 {'/'.join(f'{h}点' for h in peak_hours)}(占 {top3_share:.0%})",
                advice="集中使用是好习惯。进一步:在高峰时段开始前,"
                "先把当天要用的资料和模板准备好,让高峰时段纯产出。",
            )
        )

    if not insights:
        insights.append(
            TimeInsight(
                pattern=f"高峰时段: {'/'.join(f'{h}点' for h in peak_hours)}",
                advice="时间分布正常。可以尝试把最难的任务安排在你的高峰时段,"
                "机械任务丢给后台批处理。",
            )
        )

    return insights, peak_hours, flags


def _clamp(v: int, lo: int = 20, hi: int = 100) -> int:
    return max(lo, min(hi, v))


def compute_checkup(
    rule_hits: Dict[str, bool],
    mix_flags: Dict[str, bool],
    time_flags: Dict[str, bool],
    cache_hit_rate: Optional[float],
    saving: float,
) -> Tuple[List[DimensionScore], List[CheckupIssue]]:
    """360 式体检: 四维分项得分 + 发现的问题清单 (每项带修复方案)。"""
    issues: List[CheckupIssue] = []

    # --- 维度 1: 模型路由 ---
    routing = 95
    if mix_flags.get("model_overuse"):
        routing -= 40
        issues.append(CheckupIssue(
            severity="critical",
            dimension="模型路由",
            title="旗舰模型承担了过多常规任务",
            detail=f"旗舰档吃掉了大部分成本,其中约四成是轻量模型就能干好的活。",
            fix="给日常任务设默认模型: 机械任务用 Haiku 级,日常编码用 Sonnet 级,只在架构/疑难问题时手动切换旗舰档。",
            impact="成本或额度消耗下降 30-60%",
            steps=[
                "把日常默认模型设为 Sonnet 级 (Claude Code 里输入 /model 即可切换)",
                "机械任务 (格式转换/批量提取/分类) 明确指定 Haiku 级模型执行",
                "把模型使用规则写进 CLAUDE.md——点「一键修复」自动生成,复制粘贴即可",
                "一周后重新体检,确认旗舰档成本占比降到 60% 以下",
            ],
        ))
    if mix_flags.get("fast_gap"):
        routing -= 20
        issues.append(CheckupIssue(
            severity="warning",
            dimension="模型路由",
            title="几乎没有使用轻量模型",
            detail="格式转换、提取、分类这类机械任务在用中高档模型跑,既慢又贵。",
            fix="把机械任务切到 Haiku 级模型: 速度快 3-5 倍,价格约为主力模型 1/10。",
            impact="机械任务成本下降 80-90%",
            steps=[
                "列出你最常做的 3 类机械任务 (如格式转换/提取/摘要)",
                "这些任务发起时明确指定 Haiku 级模型",
                "大批量任务改成后台批处理,异步跑完再看结果",
            ],
        ))

    # --- 维度 2: 时间习惯 ---
    time_score = 90
    if time_flags.get("late_night"):
        time_score -= 25
        issues.append(CheckupIssue(
            severity="warning",
            dimension="时间习惯",
            title="深夜高强度使用",
            detail="0-6 点用量占比过高。人盯着 AI 跑批量任务是双输: 你在熬夜,AI 在等你确认。",
            fix="把批量任务(整理数据/翻译/跑测试)设成后台定时任务深夜自动跑,白天只做需要判断力的决策。",
            impact="夺回睡眠,同样的产出",
            steps=[
                "梳理深夜在做的任务,区分「需要我判断」和「机器能自己跑」",
                "「机器能自己跑」的部分设成定时任务 (Claude Code 支持定时任务,或用 cron)",
                "第二天早上只审结果,不熬夜盯过程",
            ],
        ))
    if time_flags.get("fragmented"):
        time_score -= 20
        issues.append(CheckupIssue(
            severity="warning",
            dimension="时间习惯",
            title="全天碎片化使用",
            detail="零散使用意味着反复重建上下文,时间和费用都花在重复交代背景上。",
            fix="固定 2-3 个'AI 工作时段',把零散问题攒起来,一个会话内批量处理同类任务。",
            impact="上下文重建成本大幅下降,专注度提升",
            steps=[
                "在日程里固定 2-3 个「AI 工作时段」(建议上午一段、下午一段)",
                "零散问题先记到待办清单,不立刻开新会话",
                "工作时段内按任务类型分组,同类问题在同一个会话里批量处理",
            ],
        ))
    if time_flags.get("concentrated"):
        time_score = min(95, time_score + 5)

    # --- 维度 3: 上下文卫生 ---
    context = 95
    if rule_hits.get("RULE_CONTEXT_BLOAT"):
        context -= 35
        issues.append(CheckupIssue(
            severity="critical",
            dimension="上下文卫生",
            title="会话上下文膨胀",
            detail="聊天记录越滚越长,AI 每次回答都要重读全部历史——你在为没用的旧内容反复付费。",
            fix="一个任务聊完就开新对话;大文件只让 AI 读需要的部分;常用背景写成固定模板,别每次重贴。",
            impact="单次对话 token 消耗下降 30-50%",
            steps=[
                "养成习惯: 每完成一个任务就开新会话 (Claude Code 里输入 /clear)",
                "读大文件时指定需要的部分,避免整个文件进上下文",
                "把反复交代的项目背景写进 CLAUDE.md,一次沉淀永久生效",
            ],
        ))
    if cache_hit_rate is not None and cache_hit_rate < 0.5:
        context -= 20
        issues.append(CheckupIssue(
            severity="warning",
            dimension="上下文卫生",
            title=f"缓存命中率仅 {cache_hit_rate:.0%}",
            detail="提示词开头不稳定,缓存没有生效,输入费用一直按全价在跑。",
            fix="把 system prompt 和固定参考资料放在提示词开头并保持稳定,变化的内容放末尾。",
            impact="输入成本最高降 90%",
            steps=[
                "检查高频提示词,把固定部分 (角色设定/规则/参考资料) 挪到最前面",
                "固定部分逐字保持稳定——改一个字缓存就失效",
                "变化的问题和数据统一放在提示词末尾",
                "一周后重新体检,目标缓存命中率回到 60% 以上",
            ],
        ))
    if rule_hits.get("RULE_ERROR_RETRY_LOOP"):
        context -= 15
        issues.append(CheckupIssue(
            severity="warning",
            dimension="上下文卫生",
            title="无效重试循环",
            detail="同一个任务失败后被原样重发了好几次——第三次几乎必然还是失败,钱白花。",
            fix="连续失败 2 次就停下来: 换个问法、把任务拆小,或者补充关键信息再试。",
            impact="消灭 10-20% 的无效消耗",
            steps=[
                "立规矩: 同一任务连续失败 2 次,强制停止原样重发",
                "失败后三选一: 缩小任务范围 / 补充关键上下文 / 换一种表述",
                "反复失败的任务记入避坑清单,下次绕开同样的坑",
            ],
        ))

    # --- 维度 4: 沉淀复用 ---
    leverage = 85
    if rule_hits.get("RULE_MISSING_SKILL"):
        leverage -= 30
        issues.append(CheckupIssue(
            severity="info",
            dimension="沉淀复用",
            title="高频任务未沉淀为 skill",
            detail="同样的活每次都从头教 AI 一遍,时间和钱都花在重复解释上。",
            fix="把常干的活写成 skill 模板: 一次写好,反复复用,结果还更稳定。",
            impact="重复任务耗时下降一半以上",
            steps=[
                "找出本周重复做过 3 次以上的任务",
                "把它的完整提示词和步骤整理成一个 skill 或固定模板",
                "下次直接调用模板,只补充本次的差异信息",
            ],
        ))
    if time_flags.get("fragmented"):
        leverage -= 10

    dims = [
        DimensionScore(key="routing", label="模型路由", score=_clamp(routing)),
        DimensionScore(key="timing", label="时间习惯", score=_clamp(time_score)),
        DimensionScore(key="context", label="上下文卫生", score=_clamp(context)),
        DimensionScore(key="leverage", label="沉淀复用", score=_clamp(leverage)),
    ]
    severity_rank = {"critical": 0, "warning": 1, "info": 2}
    issues.sort(key=lambda i: severity_rank[i.severity])
    return dims, issues


# 总分的唯一出口: 四维分项加权。客户端上报的 score 只作兼容字段, 不参与展示与排名。
DIMENSION_WEIGHTS = {"routing": 0.25, "timing": 0.25, "context": 0.25, "leverage": 0.25}


def overall_from_dimensions(dims: List[DimensionScore]) -> int:
    total = sum(DIMENSION_WEIGHTS[d.key] * d.score for d in dims)
    return int(total + 0.5)  # 四舍五入 (round() 是银行家舍入)


def tier_for_score(score: int) -> str:
    if score >= 90:
        return "S"
    if score >= 75:
        return "A"
    if score >= 60:
        return "B"
    return "C"


def checkup_score(
    rule_hits: Optional[Dict[str, bool]],
    usage_by_model: Optional[Dict[str, dict]],
    hourly_histogram: Optional[List[int]],
    cache_hit_rate: Optional[float],
    total_cost_7d: float,
) -> Tuple[int, str]:
    """由画像算出 (总分, 段位) — 入库前调用, 保证排名与报告同口径。"""
    _, saving, mix_flags = diagnose_model_mix(usage_by_model or {}, total_cost_7d)
    _, _, time_flags = analyze_time_habits(hourly_histogram)
    dims, _ = compute_checkup(rule_hits or {}, mix_flags, time_flags, cache_hit_rate, saving)
    score = overall_from_dimensions(dims)
    return score, tier_for_score(score)
