
import std/asyncdispatch, std/os, std/times, limdb, ../expiry

let dirName = getTempDir() / "texpiry.lmdb"
removeDir(dirName)
let db = initDatabase(dirName, "test")
let db1 = initDatabase(db, "testtimes")
let db2 = initDatabase(db, "testkeys")
let e = initExpiry(db, db1, db2)
asyncCheck e.process()

proc main() {.async.} =

  db["foo"] = "bar"
  db["fuz"] = "buz"
  e.expire("foo", initDuration(seconds=1))
  e.expire("fuz", initDuration(seconds=2))

  await sleepAsync(500)
  assert "foo" in db
  assert "fuz" in db
  await sleepAsync(1000)
  assert "foo" notin db
  assert "fuz" in db
  await sleepAsync(1000)
  assert "foo" notin db
  assert "fuz" notin db

waitFor main()

removeDir(dirName)

