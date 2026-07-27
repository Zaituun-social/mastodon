"""Pool of Egyptian Arabic names for the fake accounts, each paired with an
ASCII transliteration for usernames/emails (Mastodon local usernames must
match [a-z0-9_]+).

Display names are deliberately plain "first + last name" combos rather than
anything that reads as a bot or an announced "expert" -- the goal is
accounts that pass as ordinary people, with the domain expertise coming
through in what they actually write, not in their profile.
"""

FIRST_NAMES = [
    ("محمد", "mohamed"),
    ("مدحت", "medhat"),
    ("لينا", "lina"),
    ("سارة", "sara"),
    ("أحمد", "ahmed"),
    ("منى", "mona"),
    ("كريم", "kareem"),
    ("ياسمين", "yasmin"),
    ("طارق", "tarek"),
    ("هبة", "heba"),
    ("عمرو", "amr"),
    ("دينا", "dina"),
    ("هشام", "hesham"),
    ("نور", "nour"),
    ("خالد", "khaled"),
    ("رانيا", "rania"),
]

LAST_NAMES = [
    ("السيد", "elsayed"),
    ("عبد الله", "abdallah"),
    ("محمود", "mahmoud"),
    ("فؤاد", "fouad"),
    ("راشد", "rashed"),
    ("عزت", "ezzat"),
    ("حلمي", "helmy"),
    ("زكي", "zaki"),
    ("سليمان", "soliman"),
    ("نجيب", "naguib"),
]
