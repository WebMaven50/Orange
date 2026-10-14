-- One row per page view or click. There is no IP address column: only a daily one-way hash.
CREATE TABLE IF NOT EXISTS hits (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts INTEGER NOT NULL,        -- unix seconds
  day TEXT NOT NULL,          -- YYYY-MM-DD, UTC
  type TEXT NOT NULL,         -- 'view' or 'click'
  path TEXT NOT NULL,         -- page path, no query string
  ref_host TEXT,              -- referring site, '(direct)' or '(internal)'
  ref_url TEXT,               -- referring page without query string
  country TEXT,
  region TEXT,
  city TEXT,
  visitor TEXT NOT NULL,      -- daily one-way hash, cannot be reversed to an IP
  target TEXT                 -- clicks: what was clicked and where it went
);
CREATE INDEX IF NOT EXISTS idx_hits_day ON hits(day);
CREATE INDEX IF NOT EXISTS idx_hits_type_day ON hits(type, day);
