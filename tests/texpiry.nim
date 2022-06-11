

import std/asyncdispatch, std/os, std/times, critbits, ../expiry

# set up a critbittree with the proper interface for testing
type
  Crit = ref CritBitTree[string]

proc initCrit(): Crit =
  new(result)
template del(t: Crit, key:string) =
  t[].excl key
template len(t: Crit):int =
  t[].len
template `[]`(t: Crit, key:string):string =
  t[][key]
template `[]=`(t: Crit, key, value: string) =
  t[][key] = value
template contains(t: Crit, key: string):bool =
  key in t[]
iterator keys(t: Crit): string =
  for key in t[].keys:
    yield key

let db = initCrit()
let timeToKey = initCrit()
let keyToTime = initCrit()

var e = initExpiry(db, timeToKey, keyToTime)
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


