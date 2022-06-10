
import asyncdispatch, asyncfutures, tables, times, limdb, flatty, expiry/blob



type
  Expiry* = object
    renew*: Duration
    trigger*: FutureVar[void]
    db*: Database
    timedb*: Database
    keydb*: Database

proc next*(e: Expiry): string=
  for tb in e.timedb.keys:
    return tb

proc remove(e: Expiry, tb: string) =
  let key = e.timedb[tb]
  try:
    e.db.del(key)
  except KeyError:
    discard
  e.timedb.del(tb, key)
  e.keydb.del(key, tb)

proc process*(e: Expiry) {.async.} =
  while true:
    let now = getTime()
    while e.timedb.len == 0:
      discard await withTimeout[void](Future[void](e.trigger), e.renew.inMilliseconds.int)
      e.trigger.clean()
    let tb = e.next
    let t = tb.fromBlob()
    if t <= now:
      e.remove(tb)
    else:
      let d = t - now
      discard await withTimeout[void](Future[void](e.trigger), d.inMilliseconds.int)
      e.trigger.clean()

proc initExpiry*(db, timedb, keydb: Database): Expiry =
  result.trigger = newFutureVar[void]("expiry" & db.name)
  result.db = db
  result.timedb = timedb
  result.keydb = keydb
  result.renew = initDuration(seconds=3)

proc initExpiry*(db: Database, timedbName="", keydbName=""): Expiry =
  var timedbName = if timedbName == "": "xpt" & db.name else: timedbName
  var keydbName = if keydbName == "": "xpk" & db.name else: keydbName
  initExpiry(
    db,
    db.initDatabase(timedbName),
    db.initDatabase(keydbName)
  )

proc expire*(e: Expiry, key: string, t: Time) =

  let retrigger = e.timedb.len == 0 or e.next.fromBlob > t
  
  let tb = t.toBlob
  e.timedb[tb] = key
  e.keydb[key] = tb
    
  if retrigger:
    e.trigger.complete()

template expire*(e: Expiry, key: string, d: Duration) =
  expire(e, key, getTime() + d)


