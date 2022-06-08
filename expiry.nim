
import asyncdispatch, asyncfutures, tables, times, limdb, flatty

type
  Expiry = object
    renew: Duration
    trigger: ref Future[void]
    db: Database
    timedb: Database
    keydb: Database

proc next(e: Expiry): string=
  for tb in e.timedb.keys:
    echo "NEXT KEY ", tb
    result = tb
    break

proc process(e: Expiry) {.async.} =
  var now:Time
  now = getTime()
  if e.timedb.len == 0:
    discard await withTimeout[void](e.trigger[], e.renew.inMilliseconds.int)
    e.trigger[] = newFuture[void]("expiry" & e.db.name)
    asyncCheck e.process()
    return
  let tb = e.next
  let key = e.timedb[tb]
  let t = tb.fromFlatty(Time)
  echo "TB ", tb, " KEY ", key
  if t <= now:
    try:
      e.db.del(key)
    except KeyError:
      discard
    e.timedb.del(tb, key)
    e.keydb.del(key, tb)
  else:
    let d = t - now
    echo "WAIT BEGIN DURATION ", d, " UNTIL ", t, " NOW IS ", now
    discard await withTimeout[void](e.trigger[], d.inMilliseconds.int)
    echo "WAIT END"
    e.trigger[] = newFuture[void]("expiry" & e.db.name)
    asyncCheck e.process()


proc initExpiry(db, timedb, keydb: Database): Expiry =
  new(result.trigger)
  result.trigger[] = newFuture[void]("expiry" & db.name)
  result.db = db
  result.timedb = timedb
  result.keydb = keydb
  result.renew = initDuration(seconds=3)

proc initExpiry(db: Database, timedbName="", keydbName=""): Expiry =
  var timedbName = if timedbName == "": "xpt" & db.name else: timedbName
  var keydbName = if keydbName == "": "xpk" & db.name else: keydbName
  initExpiry(
    db,
    db.initDatabase(timedbName),
    db.initDatabase(keydbName)
  )

proc expire(e: Expiry, key: string, t: Time) =
  let tb = t.toFlatty
  e.timedb[tb] = key
  e.keydb[key] = tb

  if e.timedb.len == 0 or e.next.fromFlatty(Time) > t:
    e.trigger[].complete()

template expire(e: Expiry, key: string, d: Duration) =
  expire(e, key, getTime() + d)


