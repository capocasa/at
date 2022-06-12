
import std/asyncdispatch, std/os, std/times, std/tables, std/critbits, ../at, ../at/timeblobs

# a critbittree requires some boilerplate to be used like a regular table
proc initCritBitTree[T](): CritBitTree[T] =
  discard
iterator keys*(t: CritBitTree[string]): Time =
  for k in critbits.keys(t):
    yield k.blobToTime
proc del*(tab: var CritBitTree, t: Time) =
  tab.excl t.timeToBlob
proc del*(t: var CritBitTree, k: string) =
  t.excl k

# like other tables that do not support arbitrary objects as keys,
# 'at' supports wrappers to serialize
template `[]`*(a: CritBitTree, t: Time): string =
  a[t.timeToBlob]
template `[]`*(a: CritBitTree, s: string): Time =
  a[s].blobToTime
template `[]=`*(a: CritBitTree, t: Time, s: string) =
  a[t.timeToBlob] = s
template `[]=`*(a: CritBitTree, s: string, t: Time) =
  a[s] = t.timeToBlob

# initialize our test table
# must be a ref to refer to it outside the expiry
var db = newTable[string, string]()

proc trigger(a: At, t: Time, k: string) =
  db.del k

let a = initAt(initCritBitTree[string](), initCritBitTree[string]())
asyncCheck a.process()

proc main() {.async.} =

  db["foo"] = "bar"
  db["fuz"] = "buz"
  
  a["foo"] = initDuration(seconds=1)
  a["fuz"] = initDuration(seconds=2)

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


