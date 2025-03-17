from pathlib import Path

API_URL = "https://lpl.qq.com/web201612/data/LOL_MATCH2_MATCH_HOMEPAGE_BMATCH_LIST.js"
OUTPUTS = Path("outputs")
if not OUTPUTS.exists():
    OUTPUTS.mkdir(parents=True)
GAMES = OUTPUTS.joinpath("games")
if not GAMES.exists():
    GAMES.mkdir(parents=True)
