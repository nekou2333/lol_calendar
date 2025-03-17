import requests
from pathlib import Path
import json
from ics import Calendar
from consts import API_URL, OUTPUTS
from models import Match
from itertools import groupby
from typing import List


def load_data(is_debug: bool = False):
    if is_debug:
        print("Loading example data")
        data = Path("example.json").read_text()
    else:
        print("Loading data from API")
        data = requests.get(API_URL).text

    content = json.loads(data)
    matches = [Match(**item) for item in content.get("msg")]
    return matches


def group_games(games: List[Match]):
    for game_name, grouped_games in groupby(games, key=lambda game: game.GameName):
        generate_ics(game_name, list(grouped_games))


def generate_ics(name: str, games: List[Match]):
    if not name.endswith(".ics"):
        name += ".ics"
    cal = Calendar()

    for game in games:
        event = game.to_event()
        cal.events.add(event)

    with OUTPUTS.joinpath(name).open("w", encoding="utf8") as f:
        f.writelines(cal.serialize_iter())


if __name__ == "__main__":
    from argparse import ArgumentParser

    parser = ArgumentParser()
    parser.add_argument("--debug", type=bool, default=False)
    args = parser.parse_args()

    games = load_data(is_debug=args.debug)
    generate_ics("LOL赛事", games)
    group_games(games)
