from typing import List, Literal

from pydantic import BaseModel, Field


class TimeInsight(BaseModel):
    """一条时间习惯洞察。"""
    pattern: str
    advice: str


class DimensionScore(BaseModel):
    """体检分项得分 (0-100)。"""
    key: str
    label: str
    score: int = Field(ge=0, le=100)


class CheckupIssue(BaseModel):
    """一条体检发现项 (360 式: 问题 + 修复方案 + 分步执行)。"""
    severity: Literal["critical", "warning", "info"]
    dimension: str
    title: str
    detail: str
    fix: str
    impact: str
    steps: List[str] = Field(default_factory=list)  # 分步执行方案 (优化方案页)
