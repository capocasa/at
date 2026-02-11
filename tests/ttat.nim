
import std/[os, times, tables, critbits], ../tat, ../at/timeblobs

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
# 'tat' supports wrappers to serialize
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

proc trigger(t: Time, k: string) =
  db.del k

let a = initTat(initCritBitTree[string](), initCritBitTree[string]())
a.process()

proc main() =

  db["foo"] = "bar"
  db["fuz"] = "buz"

  a["foo"] = initDuration(seconds=1)
  a["fuz"] = initDuration(seconds=2)

  sleep(500)
  assert "foo" in db
  assert "fuz" in db
  sleep(1000)
  assert "foo" notin db
  assert "fuz" in db
  sleep(1000)
  assert "foo" notin db
  assert "fuz" notin db

main()
a.stop()
