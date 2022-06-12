## ******
## At
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
##     being handled elsewhere in the interface and also from the At.
##
## Now the expiry can be initialized
##
## ```nim
##
## # init using the wrapper above
## let main = initCrit()
## 
## # start expiring
## let a = initAt(main, t2k=initCrit(), k2t=initCrit())
## a.process
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
## a.expire("foo", initDuration(minutes=20))
## a.expire("bar", dateTime(2030, 12, 31))
## ```
##
## It also works with other tables. These don't require the coaxing `critbits` do
## because they implement the more familiar table interface.
##
## ```nim
## import fusion/btreetable
## let main = initTable[string, string]()
## let a = initAt(main, t2k=initTable[string, string](), k2t=initTable[string, string]())
## a.process
##
## ```
##
## On-Disk
## -------
##
## At really shines when it comes to expiring values that are persisted to disk-
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

import asyncdispatch, asyncfutures, times

type
  At*[TTimeToKey, TTable2] = ref object  # ref for the async code
    trigger*: FutureVar[void]
    t2k*: TTimeToKey
    k2t*: TTable2

proc next*(a: At): Time =
  mixin keys
  for t in a.t2k.keys:
    return t
  raise newException(KeyError, "next key in time-to-keys table is empty")

proc trigger*[T](a: At, t: Time, key: T) =
  discard

proc process*(a: At) {.async.} =
  mixin trigger
  mixin del
  while true:
    let now = getTime()
    let t = block:
      var t: Time
      while true:
        try:
          t = a.next
          break
        except KeyError:
          discard await withTimeout[void](Future[void](a.trigger), initDuration(days=1).inMilliseconds.int)
          a.trigger.clean()
      t
    if t <= now:
      let key = a.t2k[t]
      trigger(a, t, key)
      a.t2k.del(t)
      a.k2t.del(key)
    else:
      let d = t - now
      discard await withTimeout[void](Future[void](a.trigger), d.inMilliseconds.int)
      a.trigger.clean()

proc initAt*[TTimeToKey, TTable2](t2k: TTimeToKey, k2t: TTable2): At[TTimeToKey, TTable2] =
  new(result)
  result.t2k = t2k
  result.k2t = k2t
  result.trigger = newFutureVar[void]("at")


proc `[]=`*[T](a: At, key: T, t: Time) =
  mixin `[]=`

  let retrigger = try:
    a.next > t
  except KeyError:
    # empty, so retrigger
    true
 
  a.t2k[t] = key
  a.k2t[key] = t

  if retrigger:
    a.trigger.complete()

proc `[]=`*[T](a: At, key: T, d: Duration) =
  a[key] = getTime() + d

proc del*[T](a: At, key: T) =
  let t = a.k2t[key]
  let retrigger = a.next == t
  del a.t2k[t]
  del a.k2t[key]
  if retrigger:
    a.trigger.complete()

proc del(a: At, t: Time) =
  let key = a.t2k[t]
  let retrigger = a.next == t
  del a.k2t[key]
  del a.t2k[t]
  if retrigger:
    a.trigger.complete()

