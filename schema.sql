CREATE TABLE IF NOT EXISTS scores (
    time INTEGER,
    gametime INTEGER,
    eventid TEXT,
    eventuid TEXT,
    groupname TEXT,
    value REAL
    );

CREATE TABLE IF NOT EXISTS events (
    time INTEGER,
    gametimestart REAL,
    gametimeend REAL,
    handler TEXT,
    eventname TEXT,
    eventid TEXT,
    eventuid TEXT,
    custom TEXT,
    status TEXT
    );

CREATE TABLE IF NOT EXISTS logs (
    time INTEGER,
    source TEXT,
    type TEXT,
    message TEXT
    );
