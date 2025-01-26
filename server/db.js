import { Database } from 'jsr:@db/sqlite@0.12'

const db = new Database('bubble.db')

const cachedStmts = {}
const stmt = (s) => (cachedStmts[s] || (cachedStmts[s] = db.prepare(s)))
const run = (s, ...a) => stmt(s).run(...a)

// Logging

;`
  CREATE TABLE IF NOT EXISTS network (
    url TEXT,
    payload TEXT,
    response TEXT,
    time INTEGER
  );
`.split(/;\n\n+/).map((s) => db.prepare(s).run())
export const logNetwork = async (url, payload, response, time) => {
  stmt(`INSERT INTO network VALUES (?, ?, ?, ?)`)
    .run(url, payload, response, time)
}

;`
  CREATE TABLE IF NOT EXISTS game_record (
    image TEXT,
    target TEXT,
    recognized TEXT,
    time INTEGER
  );
`.split(/;\n\n+/).map((s) => db.prepare(s).run())
export const logGame = async (target, image, recognized) => {
  stmt(`INSERT INTO game_record VALUES (?, ?, ?, ?)`)
    .run(image, target, recognized, Date.now())
}

export const recentSuccessfulGames = async () => {
  const values =
    stmt(`SELECT image, target, recognized FROM game_record WHERE target = recognized ORDER BY rowid DESC LIMIT 30`)
      .values()
  return values
}
export const recentGames = async () => {
  const values =
    stmt(`SELECT image, target, recognized FROM game_record ORDER BY rowid DESC LIMIT 50`)
      .values()
  return values
}
