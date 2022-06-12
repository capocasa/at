## ****
## `at`
## ****
##
## A lightweight tool to execute code later
##
## Why?
## ####
##
## While the same thing can be accomplished using the standard library's `asyncdispatch`, at
## stores the values in a table and only uses one future to go through them.
##
## This has a lot of advantages:
##
## :Transparency:
##     The timers are all neatly accessible in a table 
##     instead of being hidden in the global dispatcher.
##     Several `at` instances can be used to group related timers
##     or timers that do different things.
##
##     That makes it this much easier to find bugs.
## :Flexibility:
##     The timers can be easily modified or removed up until they are triggered.
##
##     You can use any table you like as long as it keeps the keys sorted.
##
## :Persistence:
##     Tables don't have to be in-memory. Using a table backed by
##     persistent storage can preserve triggers across program restarts.
##     Data is only ever read one-by-one after a trigger, so startup time is
##     not meaningfully affected.
##
## Use cases
## #########
##
## :Expiring Data:
## A really cool use-case is to remove ephemeral key/value pairs from an (additional) table, especially
## when persistent storage is used. For example, in a web app, this could be used for things like
## session key hashes, password reset link hashes, or incomplete form data you don't want to clutter your
## nice database with but are nice enough to store for your user.
##
## :Maintenance tasks:
## In most apps, maintenance tasks need to be performed- deleting old data, checking for updates,
## reminding the user to do stuff or simply doing stuff later. Traditionally,
## at least for web apps, external timers or special daemons are used, but it greatly simplifies both programming
## and administration to keep everything in-processspecial.
##
## Limitations
## ###########
##
## The table to look up times `t2k` has to be one that is sorted by the key.
##
## This is currently the case for:
##
## In-Memory tables: `std/bitcrittree` (requires some boilerplate), `fusion/btreetable` and `pkg/sorta`.
##
## Persistent tables: `pkg/limdb` (requires supplied type conversion), `pkg/nimdbx` (untested)
##
## Usage
## #####
##
## In Memory
## ---------
##
## It's often good to stick to the standard library as much as possible, however
## the only key-sorted table in the standard libary is the `CritBitTable`. This
## has a somewhat different interface to regular tables, so a bit of boilerplate
## code is needed to convince it to act like one. Also only strings are supported
## for the keys, so we have to define some converters. This boilerplate can be omitted
## for other tables.
##
## ```nim
## # this stuff is only needed to get critbits in shape to use for storage,
## # in order to use as few packages as possible
## import std/times, std/critbits, at, at/timeblobs
##
## # a critbittree requires some boilerplate to be accessed like a regular table
## proc initCritBitTree[string](): CritBitTree[string] =
##   discard
## iterator keys*(t: CritBitTree[string]): Time =
##   for k in critbits.keys(t):
##     yield k.blobToTime
## proc del*(tab: var CritBitTree, t: Time) =
##   tab.excl t.timeToBlob
## proc del*(t: var CritBitTree, k: string) =
##   t.excl k
## 
## # and some wrappers to serialize the time to a string 
## template `[]`*(a: CritBitTree, t: Time): string =
##   a[t.timeToBlob]
## template `[]`*(a: CritBitTree, s: string): Time =
##   a[s].blobToTime
## template `[]=`*(a: CritBitTree, t: Time, s: string) =
##   a[t.timeToBlob] = s
## template `[]=`*(a: CritBitTree, s: string, t: Time) =
##   a[s] = t.timeToBlob
## ```
##
## Now that we've got the critbit behaving like a proper table,
## we can get started.
##
## ```nim
## # We store our ephemeral data in a regular table. Note it's a `ref`
## # otherwise the modifications would be made on a copy.
##
## let data = newTable[string, string]()
##
## # Now we add a trigger proc that `at` will call.
## # It accesses `data` as a global, but it can be placed into
## # a proc to use a closure instead.
##
## proc trigger(a: At, t: Time, k: string) =
##     data.del k
##
## # Now we can initialize `at`. We make two tables and pass them in.
## # This allows for a lot of flexibility.
## let expiry = initAt(initCritBitTree[string](), initCritBitTree[string]())
## expiry.process
##
## # now let's add some data that will be deleted in three seconds
## data["foo"] = "bar"
## expiry["foo"] = initDuration(seconds=3)
##
## If you don't mind using nimble packages, there is a really nice module `btreetables`
## in the `fusion` package that can be used.
##
## ```nim
## import times, at, asyncdispatch, fusion/btreetables
## let data = newTable[string, string]()  # this is a btree table too but could be a regular one
## proc trigger(a: At, t: Time, k: string) =
##     data.del k
## let aa = initAt(newTable[Time, string](), newTable[string, Time]())    
## asyncCheck expiry.process
## data["foo"] = "bar"
## aa["foo"] = initDuration(seconds=3)
## ```
##
## Sorta tables work great too
##
## import times, sorta, at, asyncdispatch, tables
## var s = initSortedTable[string, Time]()
## var data = newTable[string, string]()
## proc trigger(a: At, t: Time, k: string) =
##     data.del k
## let aa = initAt(initSortedTable[Time, string](), initSortedTable[string, Time]())
## asyncCheck aa.process
## data["foo"] = "bar"
## aa["foo"] = initDuration(seconds=3)
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

