import json
import urllib.request
from datetime import datetime, timedelta

def fetch_schedule_data(url):
    with urllib.request.urlopen(url) as response:
        return json.load(response)

def convert_to_ics_date(date_str):
    dt = datetime.strptime(date_str, '%Y-%m-%d %H:%M:%S')
    return dt.strftime('%Y%m%dT%H%M%S')

def generate_ics(matches, cal_name):
    ics_content = [
        'BEGIN:VCALENDAR',
        'VERSION:2.0',
        'PRODID:-//Schedule Generator//{cal_name}//EN',
    ]

    for match in matches:
        start_time = convert_to_ics_date(match['MatchDate'])
        end_time = (datetime.strptime(match['MatchDate'], '%Y-%m-%d %H:%M:%S') + timedelta(hours=2)).strftime('%Y%m%dT%H%M%S')

        ics_event = [
            'BEGIN:VEVENT',
            f'UID:{match["bMatchId"]}',
            f'DTSTART:{start_time}',
            f'DTEND:{end_time}',
            f'SUMMARY:{match["bMatchName"] + (" - " + match.get("ScoreA", "0") + " : " + match.get("ScoreB", "0") if (match.get("ScoreA") and match.get("ScoreB") and (match["ScoreA"] != "0" or match["ScoreB"] != "0")) else "")}',
            f'DESCRIPTION:{match["GameName"]} - {match["GameTypeName"]}',
            'LOCATION:默认',
            'END:VEVENT'
        ]
        ics_content.extend(ics_event)

    ics_content.append('END:VCALENDAR')
    return '\n'.join(ics_content)

def get_teams(matches):
    teams = {}
    for match in matches:
        if 'vs' in match['bMatchName']:
            team_a, team_b = [t.strip() for t in match['bMatchName'].split('vs')]
            for team in [team_a, team_b]:
                if team not in teams:
                    teams[team] = []
                teams[team].append(match)
    return teams


def filter_allowed_games(matches):
    allowed_types = {'职业联赛', '全球总决赛', '季中冠军赛'}
    filtered = []
    for match in matches:
        game_name = match.get('GameName', '')
        match_obj = re.search(r'(\d+)([^\d]+)', game_name)
        if match_obj:
            type_name = match_obj.group(2).strip()
            if type_name in allowed_types:
                filtered.append(match)
    return filtered

def get_game_types(matches):
    types = {}
    for match in matches:
        game_type = match.get('GameName', 'default')
        if game_type not in types:
            types[game_type] = []
        types[game_type].append(match)
    return types


import os
import re

def main():
    api_url = 'https://lpl.qq.com/web201612/data/LOL_MATCH2_MATCH_HOMEPAGE_BMATCH_LIST.js'
    schedule_data = fetch_schedule_data(api_url)
    all_matches = schedule_data.get('msg', [])
    filtered_matches = filter_allowed_games(all_matches)

    # Generate by game type
    game_types = get_game_types(filtered_matches)
    for type_name, matches in game_types.items():
        dir_path = f'games/{type_name}'
        os.makedirs(dir_path, exist_ok=True)
        ics_content = generate_ics(matches, type_name)
        with open(f'{dir_path}/{type_name}.ics', 'w', encoding='utf-8') as f:
            f.write(ics_content)

    # Generate by team
    teams = get_teams(filtered_matches)
    for team_name, matches in teams.items():
        dir_path = f'teams/{team_name}'
        os.makedirs(dir_path, exist_ok=True)
        ics_content = generate_ics(matches, team_name)
        with open(f'{dir_path}/{team_name}.ics', 'w', encoding='utf-8') as f:
            f.write(ics_content)

if __name__ == '__main__':
    main()