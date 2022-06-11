
import asyncdispatch, asyncfutures, times, expiry/blob

type
  Expiry*[T] = ref object  # ref for the async code
    renew*: Duration
    trigger*: FutureVar[void]
    db*: T
    timeToKey*: T
    keyToTime*: T

proc next*(e: Expiry): string=
  mixin keys
  for tb in e.timeToKey.keys:
    return tb

proc expire(e: Expiry, tb: string) =
  mixin del
  let key = e.timeToKey[tb]
  try:
    e.db.del(key)
  except KeyError:
    discard
  e.timeToKey.del(tb)
  e.keyToTime.del(key)

proc process*(e: Expiry) {.async.} =
  while true:
    let now = getTime()
    while e.timeToKey.len == 0:
      discard await withTimeout[void](Future[void](e.trigger), e.renew.inMilliseconds.int)
      e.trigger.clean()
    let tb = e.next
    let t = tb.fromBlob()
    echo $t, " ", $now
    if t <= now:
      e.expire(tb)
    else:
      let d = t - now
      discard await withTimeout[void](Future[void](e.trigger), d.inMilliseconds.int)
      e.trigger.clean()

proc initExpiry*[T](db, timeToKey, keyToTime: T): Expiry[T] =
  new(result)
  result.trigger = newFutureVar[void]("expiry")
  result.db = db
  result.timeToKey = timeToKey
  result.keyToTime = keyToTime
  result.renew = initDuration(seconds=3)

proc expire*(e: Expiry, key: string, t: Time) =
  mixin `[]=`
  let retrigger = e.timeToKey.len == 0 or e.next.fromBlob > t
  
  let tb = t.toBlob
  e.timeToKey[tb] = key
  e.keyToTime[key] = tb
    
  if retrigger:
    e.trigger.complete()

template expire*(e: Expiry, key: string, d: Duration) =
  expire(e, key, getTime() + d)


