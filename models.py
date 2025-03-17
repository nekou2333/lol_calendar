import pytz
from pydantic import BaseModel, Field
from ics import Event, Organizer
from datetime import datetime, timedelta


class Match(BaseModel):
    MatchName: str = Field(alias="bMatchName")
    GameName: str
    GameTypeName: str
    GameProcName: str
    MatchDate: str
    ScoreA: str
    ScoreB: str
    GameMode: str

    def to_event(self) -> Event:
        match_name = self.MatchName
        score_a = int(self.ScoreA) or 0
        score_b = int(self.ScoreB) or 0
        if score_a != 0 or score_b != 0:
            match_name += f" - {self.ScoreA} : {self.ScoreB}"

        date = datetime.strptime(self.MatchDate, "%Y-%m-%d %H:%M:%S")

        e = Event(
            name=match_name,
            description=f"{self.GameName}{self.GameTypeName}{self.GameProcName}",
            organizer=Organizer(
                common_name=f"英雄联盟{self.GameName}", email="lpl@qq.com"
            ),
            begin=date.astimezone(pytz.UTC),
            duration=timedelta(hours=int(self.GameMode)),
            url="https://lpl.qq.com/es/live.shtml",
            status="TENTATIVE",
        )
        return e
