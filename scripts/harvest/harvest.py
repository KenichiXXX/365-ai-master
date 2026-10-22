"""Build public daily rankings without reading local AI-tool data or credentials."""
import argparse
from copy import deepcopy
from datetime import date, timedelta
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import urllib.request
from urllib.error import HTTPError

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from agentfit.engine.content_pool import OFFICIAL_REPOS, validate

USER_AGENT = "365aimaster-harvester/0.1 (+https://github.com/19800104zhao-svg/365-ai-master)"
CATALOG_URL = "https://www.skillleaderboard.com/api/catalog"


def urllib_fetch(url: str) -> dict:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def subprocess_gh(query: str) -> dict:
    result = subprocess.run(
        ["gh", "api", "search/repositories", "--method", "GET",
         "-H", "User-Agent: " + USER_AGENT, "-f", "q=" + query,
         "-f", "sort=stars", "-f", "order=desc", "-f", "per_page=50"],
        capture_output=True, text=True, check=True, timeout=30,
    )
    return json.loads(result.stdout)


PRODUCT_REPOS = (
    "openai/codex", "google-gemini/gemini-cli", "sst/opencode", "QwenLM/qwen-code",
    "cline/cline", "Aider-AI/aider", "continuedev/continue", "block/goose",
    "anthropics/claude-code", "All-Hands-AI/OpenHands", "MoonshotAI/kimi-cli",
)


class GitHubNotFound(Exception):
    pass


def subprocess_repo(repo: str) -> dict:
    try:
        result = subprocess.run(["gh", "api", "repos/" + repo, "-H", "User-Agent: " + USER_AGENT],
                                capture_output=True, text=True, check=True, timeout=30)
    except subprocess.CalledProcessError as error:
        if "HTTP 404" in (error.stderr or ""):
            raise GitHubNotFound(repo) from error
        raise
    return json.loads(result.stdout)


def fetch_github_products(run_gh=subprocess_repo) -> list[dict]:
    items = []
    for repo in PRODUCT_REPOS:
        try:
            items.append(run_gh(repo))
        except GitHubNotFound:
            continue
    return items


def select_products(items, history: dict, *, today=None) -> list[dict]:
    previous = history.get(((today or date.today()) - timedelta(days=7)).isoformat(), {})
    return sorted([{**item, "stars7d": item["stargazers_count"] - previous[item["full_name"]]
                    if item["full_name"] in previous else None} for item in items],
                  key=lambda item: item["stargazers_count"], reverse=True)


def subprocess_claude(texts: list[str]) -> str:
    prompt = ("Translate these English one-liners faithfully into short Chinese. "
              "Return only a JSON array of strings in the same order, with no additions.\n"
              + json.dumps(texts, ensure_ascii=False))
    return subprocess.run(["claude", "-p", "--model", "haiku", prompt],
                          capture_output=True, text=True, check=True, timeout=30).stdout


def fetch_skill_leaderboard(fetch=urllib_fetch) -> list[dict]:
    return fetch(CATALOG_URL)["catalog"]


def fetch_github_agents(run_gh=subprocess_gh, today=None) -> list[dict]:
    cutoff = ((today or date.today()) - timedelta(days=30)).isoformat()
    items = []
    for topic in ("ai-agents", "ai-agent", "coding-agent", "agent-framework"):
        query = f"topic:{topic} stars:>1000 archived:false fork:false pushed:>{cutoff}"
        items.extend(run_gh(query)["items"])
    return items


def select_skills(items, n=20) -> list[dict]:
    eligible = [item for item in items if item["stars"] >= 300
                and ((item.get("summary") or "").strip() or (item.get("tagline") or "").strip())]
    # The live catalog sometimes has "stars7d": null — rank those after known growth.
    return sorted(eligible, key=lambda item: (item.get("stars7d") or 0, item["stars"]), reverse=True)[:n]


def select_agents(items, history: dict, n=20, *, today=None) -> list[dict]:
    previous = history.get(((today or date.today()) - timedelta(days=7)).isoformat(), {})
    unique = {}
    for item in items:
        if (item.get("archived") or item.get("fork") or not (item.get("description") or "").strip()
                or not item.get("license")):
            continue
        repo = item["full_name"]
        delta = item["stargazers_count"] - previous[repo] if repo in previous else None
        unique[repo] = {**item, "stars7d": delta}
    return sorted(unique.values(), key=lambda item: (
        item["stars7d"] is not None, item["stars7d"] if item["stars7d"] is not None else 0,
        item["stargazers_count"],
    ), reverse=True)[:n]


def to_ranking_item(repo: str, url: str, en: str, zh: str | None,
                    stars: int, stars7d: int | None, *, metadata: dict | None = None) -> dict:
    metadata = metadata or {}
    return {"name": repo, "url": url, "tagline": {"en": en, "zh": zh or en},
            "match": [repo.split("/")[1].lower()], "stars": stars, "stars7d": stars7d,
            "source_url": metadata.get("source_url", url), "source_date": metadata.get("source_date"),
            "source_type": metadata.get("source_type", "repository"),
            "task_category": metadata.get("task_category"), "compatibility": metadata.get("compatibility"),
            "caution": metadata.get("caution", {"zh": "安装前请核对权限与来源",
                                                "en": "Check permissions and source before installing"})}


class OfficialRedirectPolicy(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        raise HTTPError(newurl, code, "official source redirect refused", headers, fp)


def official_fetch(url: str) -> list[dict]:
    allowed = {f"https://api.github.com/repos/{repo}/releases" for repo in OFFICIAL_REPOS.values()}
    if url not in allowed:
        raise ValueError("unsupported official update source")
    opener = urllib.request.build_opener(OfficialRedirectPolicy())
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with opener.open(request, timeout=30) as response:
        return json.load(response)


def fetch_tool_updates(reviews: list[dict], fetch=official_fetch, today=None) -> list[dict]:
    """Join reviewed compatibility/copy to real official releases; never infer either."""
    today = today or date.today()
    releases = {}
    result = []
    for review in reviews:
        tool = review["tool"]
        if tool not in OFFICIAL_REPOS:
            raise ValueError("unsupported official update source")
        if tool not in releases:
            releases[tool] = fetch(f"https://api.github.com/repos/{OFFICIAL_REPOS[tool]}/releases")
        for release in releases[tool]:
            if (release.get("id") != review["release_id"] or release.get("draft")
                    or release.get("prerelease") or not release.get("published_at")):
                continue
            result.append({key: review[key] for key in ("id", "tool", "summary", "practice_id", "compatibility")}
                          | {"source_url": release["html_url"], "fetched_at": today.isoformat(),
                             "released_at": date.fromisoformat(release["published_at"][:10]).isoformat()})
    return result


def translate_zh(texts: list[str], run_claude=subprocess_claude) -> list[str | None]:
    if not texts:
        return []
    try:
        translated = json.loads(run_claude(texts))
        if (isinstance(translated, list) and len(translated) == len(texts)
                and all(isinstance(text, str) and text.strip() for text in translated)):
            return translated
    except (OSError, ValueError, subprocess.SubprocessError):
        pass
    return [None] * len(texts)


def build_content(base: dict, skills: list, agents: list, today: date, *, tool_updates=None, products=None) -> dict:
    content = deepcopy(base)
    content["rankings"] = {"skill": deepcopy(skills), "agent": deepcopy(agents), "rotate": False,
                           "source": "The Skill Leaderboard · GitHub", "updated_at": today.isoformat(),
                           "origin": "public"}
    content["rankings"]["product"] = deepcopy(products if products is not None else base["rankings"]["product"])
    categories = {item["name"].casefold(): item["task_category"]
                  for kind in ("skill", "agent") for item in base["rankings"][kind]
                  if item.get("task_category")}
    for kind in ("skill", "agent"):
        for item in content["rankings"][kind]:
            if not item.get("task_category") and item["name"].casefold() in categories:
                item["task_category"] = categories[item["name"].casefold()]
    content["updated_at"] = today.isoformat()
    content["tool_updates"] = tool_updates or []
    return content


def _write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent,
                                         prefix=path.name + ".", delete=False) as stream:
            temporary = Path(stream.name)
            json.dump(data, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", type=Path, default=ROOT / "agentfit/engine/content_pool.json")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--history", type=Path, required=True)
    parser.add_argument("--no-translate", action="store_true")
    parser.add_argument("--updates", type=Path, help="Reviewed official release IDs, compatibility and bilingual copy")
    args = parser.parse_args(argv)
    today = date.today()
    try:
        base = json.loads(args.base.read_text(encoding="utf-8"))
        history = json.loads(args.history.read_text(encoding="utf-8")) if args.history.exists() else {}
        reviews = json.loads(args.updates.read_text(encoding="utf-8")) if args.updates else []
        updates = fetch_tool_updates(reviews)
        skills = select_skills(fetch_skill_leaderboard())
        raw_agents = fetch_github_agents(today=today)
        agents = select_agents(raw_agents, history, today=today)
        raw_products = fetch_github_products()
        products = select_products(raw_products, history, today=today)
        if len(products) < 5:
            raise ValueError("product ranking requires at least 5 items")
        if len(skills) < 10 or len(agents) < 10:
            raise ValueError("each ranking requires at least 10 eligible items")
        texts = [(item.get("tagline") or "").strip() or (item.get("summary") or "").strip() for item in skills]
        texts += [(item.get("description") or item["full_name"]).strip() for item in agents + products]
        translations = [None] * len(texts) if args.no_translate else translate_zh(texts)
        skill_rows = [to_ranking_item(item["repo"], "https://github.com/" + item["repo"],
                                     texts[i], translations[i], item["stars"], item.get("stars7d"),
                                     metadata={**item, "source_type": "catalog"})
                      for i, item in enumerate(skills)]
        agent_rows = [to_ranking_item(item["full_name"], item["html_url"],
                                     texts[len(skills) + i], translations[len(skills) + i],
                                     item["stargazers_count"], item["stars7d"], metadata=item)
                      for i, item in enumerate(agents)]
        product_rows = [to_ranking_item(item["full_name"], item["html_url"],
                                       texts[len(skills) + len(agents) + i], translations[len(skills) + len(agents) + i],
                                       item["stargazers_count"], item["stars7d"], metadata=item)
                        for i, item in enumerate(products)]
        content = build_content(base, skill_rows, agent_rows, today, tool_updates=updates, products=product_rows)
        if not validate(content):
            raise ValueError("generated content failed validation")
        cutoff = (today - timedelta(days=34)).isoformat()
        history = {day: counts for day, counts in history.items() if cutoff <= day <= today.isoformat()}
        history[today.isoformat()] = {item["full_name"]: item["stargazers_count"] for item in raw_agents + raw_products}
    except (OSError, ValueError, KeyError, TypeError, AttributeError, subprocess.SubprocessError) as error:
        print(f"harvest aborted: {error}", file=sys.stderr)
        return 3
    _write_json(args.out, content)
    _write_json(args.history, history)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
