import pytest

from agentfit.engine import content as C


@pytest.mark.parametrize("loc", ["zh", "en"])
def test_every_entry_complete(loc):
    assert C.QUESTS == [
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
    for k in C.QUESTS:
        t = C.quest_text(k, loc)
        assert t["title"] and t["why"] and len(t["steps"]) == 3 and t["prompt"]
    for k in ["routing", "timing", "context", "leverage"]:
        t = C.dimension_tip(k, loc)
        assert t["title"] and t["prompt"] and C.label(k, loc)
    for pid in C.POOL:
        assert C.pool_tip(pid, loc)["title"]
    assert [C.rank_title(n, loc) for n in (0, 3, 6, 9)] == (
        ["AI 探索者", "AI 熟练者", "AI 大师", "AI 宗师"]
        if loc == "zh"
        else ["Explorer", "Practitioner", "Master", "Grandmaster"]
    )


def test_no_money_saving_claims():
    import inspect

    src = inspect.getsource(C)
    for bad in ("省了 $", "save $", "saved $", "每月可省"):
        assert bad not in src


def test_locale_from_env(monkeypatch):
    monkeypatch.setenv("LANG", "zh_CN.UTF-8")
    monkeypatch.delenv("LC_ALL", raising=False)
    assert C.locale_from_env() == "zh"
    monkeypatch.setenv("LANG", "ja_JP.UTF-8")
    assert C.locale_from_env() == "en"


@pytest.mark.parametrize(
    "lang,lc_all,expected",
    [
        ("en_US.UTF-8", "zh_TW.UTF-8", "zh"),
        ("zh_CN.UTF-8", "en_US.UTF-8", "en"),
        ("zh_CN.UTF-8", "", "zh"),
        (None, None, "en"),
    ],
)
def test_locale_precedence_and_fallback(monkeypatch, lang, lc_all, expected):
    for name, value in (("LANG", lang), ("LC_ALL", lc_all)):
        if value is None:
            monkeypatch.delenv(name, raising=False)
        else:
            monkeypatch.setenv(name, value)
    assert C.locale_from_env() == expected


@pytest.mark.parametrize(
    "loc,titles",
    [
        ("zh", ["AI 探索者", "AI 熟练者", "AI 大师", "AI 宗师"]),
        ("en", ["Explorer", "Practitioner", "Master", "Grandmaster"]),
    ],
)
def test_all_rank_levels(loc, titles):
    assert [C.rank_title(n, loc) for n in range(10)] == (
        [titles[0]] * 3 + [titles[1]] * 3 + [titles[2]] * 3 + [titles[3]]
    )
