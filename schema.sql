CREATE TABLE IF NOT EXISTS score (
    time INTEGER,
    eventuid TEXT,
    groupname TEXT,
    value REAL
    );

CREATE TABLE IF NOT EXISTS event (
    time INTEGER,
    handler TEXT,
    eventname TEXT,
    eventuid TEXT,
    custom TEXT,
    status TEXT
    );

CREATE TABLE IF NOT EXISTS log (
    time INTEGER,
    source TEXT,
    type TEXT,
    message TEXT
    );
