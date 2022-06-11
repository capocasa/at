## ******
## Expiry
## ******
##
## Efficient expiry for any table key pair.
##
## Why?
## ####
##
## It can be quite pleasant to be able to determine
## that entries in a key-value store will disappear at some time
## in the future without having to worry about making that happen.
##
## This is great for keeping all sorts of ephemeral information from
## cluttering databases, file systems and in-memory locations.
##
## Features
## ########
## 
## Efficient: Only one reusable future is used for a table of keys
##
## Flexible: Works with any table-like, in-memory and on-disk
##
## Limitations
## ###########
##
## It's currently limited to tables with strings for keys and values.
## I know, but I've already went too generic for my use case... will you fix it?
##
## The time table has to be a table that is sorted by the key.
##
## Usage
## #####
##
## In Memory
## ---------
##
## For in-memory usage we will use critbits, because they are in the standard
## library and are sorted by key. Those don't use the usual table interface, so
## we need to add some boilerplate to make it behave like a regular table. This
## isn't necessary for other sorted tables, but those aren't available in the
## standard libary.
##
## ```nim
##     # wrapper around critbits to give an interface like TableRef[string]
##     type
##       Crit = ref CritBitTree[string]
##     proc initCrit(): Crit =
##       new(result)
##     template del(t: Crit, key:string) =
##       t[].excl key
##     template `[]`(t: Crit, key:string):string =
##       t[][key]
##     template `[]=`(t: Crit, key, value: string) =
##       t[][key] = value
##     template contains(t: Crit, key: string):bool =
##       key in t[]
##     iterator keys(t: Crit): string =
##       for key in t[].keys:
##         yield key 
##  ```
## .. note::
##     A `ref` type should be used for the table because it is
##     being handled elsewhere in the interface and also from the Expiry.
##
## Now the expiry can be initialized
##
## ```nim
##
## # init using the wrapper above
## let main = initCrit()
## 
## # start expiring
## let e = initExpiry(main, t2k=initCrit(), k2t=initCrit())
## e.process
##
## ```
## You pass your `main` table that contains your data, and two additional
## tables: `t2k` to store the expiry times of each key, and `k2t` is there
## in case you need to look up when a key is set to expire. Responsibility
## for creating these is given to you because you probably want to control
## where that data is stored.
##
## That's it with the setup. Now you can expire away.
##
## ```nim
## main["foo"] = "bar"
## e.expire("foo", initDuration(minutes=20))
## e.expire("bar", dateTime(2030, 12, 31))
## ```
##
## It also works with other tables. These don't require the coaxing `critbits` do
## because they implement the more familiar table interface.
##
## ```nim
## import fusion/btreetable
## let main = initTable[string, string]()
## let e = initExpiry(main, t2k=initTable[string, string](), k2t=initTable[string, string]())
## e.process
##
## ```
##
## On-Disk
## -------
##
## Expiry really shines when it comes to expiring values that are persisted to disk-
## a key-value database, as there is no need to load data from disk into memory storage
## and keep it in sync. Just give expiry a table-like interface to the database and you're
## good to go. As an example, here is your own filesystem-based persistence layer. It's not
## particularly fast compared to other options out there but it works.
##
## ```nim
##     import io
##     type
##       FsDB = ref object
##        path: string
##     proc initFsDB(path: string): FsDB =
##     template del(t: FsDB, key:string) =
##       removeFile t.path / key
##     template `[]`(t: FsDB, key:string):string =
##       t[][key]
##     template `[]=`(t: FsDB, key, value: string) =
##       t[][key] = value
##     template contains(t: FsDB, key: string):bool =
##       key in t[]
##     iterator keys(t: FsDB): string =
##       for key in t[].keys:
##         yield key 

import asyncdispatch, asyncfutures, times, expiry/blob

type
  Expiry*[T] = ref object  # ref for the async code
    renew*: Duration
    trigger*: FutureVar[void]
    db*: T
    t2k*: T
    k2t*: T

proc next*(e: Expiry): string=
  mixin keys
  for tb in e.t2k.keys:
    return tb
  raise newException(KeyError, "next key in time-to-keys table is empty")

proc expire(e: Expiry, tb: string) =
  mixin del
  let key = e.t2k[tb]
  try:
    e.db.del(key)
  except KeyError:
    discard
  e.t2k.del(tb)
  e.k2t.del(key)

proc fromTime*(t: Time): string =
  mixin timeToBlob
  t.timeToBlob

proc toTime*(s: string): Time =
  mixin blobToTime
  s.blobToTime

proc isEmpty[T](t: T) =
  mixin next
  try:
    discard t.next
    false
  except KeyError:
    true

proc process*(e: Expiry) {.async.} =
  mixin toTime
  while true:
    let now = getTime()
    let tb = block:
      var tb:string
      while true:
        try:
          tb = e.next
          break
        except KeyError:
          discard await withTimeout[void](Future[void](e.trigger), e.renew.inMilliseconds.int)
          e.trigger.clean()
      tb
    let t = tb.toTime
    if t <= now:
      e.expire(tb)
    else:
      let d = t - now
      discard await withTimeout[void](Future[void](e.trigger), d.inMilliseconds.int)
      e.trigger.clean()

proc initExpiry*[T](db, t2k, k2t: T): Expiry[T] =
  new(result)
  result.trigger = newFutureVar[void]("expiry")
  result.db = db
  result.t2k = t2k
  result.k2t = k2t
  result.renew = initDuration(seconds=3)

proc expire*(e: Expiry, key: string, t: Time) =
  mixin `[]=`
  mixin fromTime

  let retrigger = try:
    # new next trigger, retrigger
    e.next.toTime > t
  except KeyError:
    # empty, so retrigger
    true
 
  let tb = t.fromTime
  e.t2k[tb] = key
  e.k2t[key] = tb
    
  if retrigger:
    e.trigger.complete()

template expire*(e: Expiry, key: string, d: Duration) =
  expire(e, key, getTime() + d)


