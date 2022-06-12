
import std/asyncdispatch, std/os, std/times, std/tables, std/critbits, ../at, ../at/timeblobs

# a critbittree requires some boilerplate to be used like a regular table
proc initCritBitTree[T](): CritBitTree[T] =
  discard
iterator keys*(t: CritBitTree[string]): Time =
  for k in critbits.keys(t):
    yield k.blobToTime
proc del*(tab: var CritBitTree, t: Time) =
  tab.excl t.timeToBlob
template `[]`*(a: CritBitTree, t: Time): string =
  a[t.timeToBlob]
template `[]=`*(a: CritBitTree, t: Time, s: string) =
  a[t.timeToBlob] = s

# initialize our test table
# must be a ref to refer to it outside the expiry
var db = newTable[string, string]()

proc trigger(a: At, t: Time, k: string) =
  db.del k

let a = initAt(initCritBitTree[string](), initTable[string, Time]())
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


