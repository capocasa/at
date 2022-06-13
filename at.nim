## **
## at
## **
##
## A powerful, lightweight tool to execute code later
##
## Why?
## ####
##
## While the same thing can be accomplished using the standard library's `asyncdispatch`, `at`
## stores the values in a table and only uses one future to go through them.
##
## This has a lot of advantages:
##
## Transparency:
## The timers are all neatly accessible in a table 
## instead of being hidden in the global dispatcher.
## Several `at` instances can be used to group related timers
## or timers that do different things. That makes it this much easier to find bugs.
##
## Flexibility: The timers can be easily modified or removed up until they are triggered.
## You can use any table you like as long as it keeps the keys sorted.
##
## Persistence: Tables don't have to be in-memory. Using a table backed by
## persistent storage can preserve triggers across program restarts.
## Data is only ever read one-by-one after a trigger, so startup time is
## not meaningfully affected. And since the data is used directly off disk, you don't
## need to worry about whether the in-memory triggers are actually in sync with the
## on-disk triggers because the disk data is used directly. If you use a memory-mapped persistent
## table, this doesn't affect performance at all.
##
## Use cases
## #########
##
## *Expiring Data*
##
## A really cool use-case is to remove ephemeral key/value pairs from an (additional) table, especially
## when persistent storage is used. For example, in a web app, this could be used for things like
## session key hashes, password reset link hashes, or incomplete form data you don't want to clutter your
## nice database with but are nice enough to store for your user.
##
## *Maintenance tasks*
##
## In most apps, maintenance tasks need to be performed- deleting old data, checking for updates,
## reminding the user to do stuff or simply doing stuff later. Traditionally,
## at least for web apps, external timers or special daemons are used, but it greatly simplifies both programming
## and administration to keep everything in-process.
##
## Features
## ########
##
## - Simple-yet-effective implementation designed for tens of thousands of planned triggers using only one future.
## - BYOT- bring your own table, you have full control over the table or table-like object used to store trigger
##   information so you have full control data is stored. It's also fairly easy to write your own table interface,
##   see the filesystem-storage example.
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
## Other tables can be of any type.
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
## import std/asyncdispatch, std/os, std/times, std/tables, std/critbits, at, at/timeblobs
## 
## # a critbittree requires some boilerplate to be used like a regular table, of type [Time, string]
## proc initCritBitTree[T](): CritBitTree[T] =
##   discard
## iterator keys*(t: CritBitTree[string]): Time =
##   for k in critbits.keys(t):
##     yield k.blobToTime
## proc del*(tab: var CritBitTree, t: Time) =
##   tab.excl t.timeToBlob
## template `[]`*(a: CritBitTree, t: Time): string =
##   a[t.timeToBlob]                                                 
## template `[]=`*(a: CritBitTree, t: Time, s: string) =
##   a[t.timeToBlob] = s
##
## # Now that we've got the critbit behaving like a proper table,
## # we can get started.
##
## # We store our ephemeral data in a regular table. Note it's a `ref`
## # otherwise the modifications would be made on a copy.
##
## let data = newTable[string, string]()
##
## # Now we add a trigger proc that `at` will call.
## # It accesses `data` as a global, but it can be placed into
## # a proc to use a closure instead.
##
## proc trigger(t: Time, k: string) =
##     data.del k
##
## # Now we can initialize `at`. We make two tables and pass them in.
## # This allows for a lot of flexibility.
## let aa = initAt(initCritBitTree[string](), initTable[string, Time])
## asyncCheck aa.process()
##
## # now let's add some data that will be deleted in three seconds
## data["foo"] = "bar"
## aa["foo"] = initDuration(seconds=3)
## ```
##
## If you don't mind using nimble packages, there is a really nice module `btreetables`
## in the `fusion` package that can be used.
##
## ```nim
## import times, at, asyncdispatch, fusion/btreetables
## let data = newTable[string, string]()  # this is a btree table too but could be a regular one
## proc trigger(t: Time, k: string) =
##     data.del k
## let aa = initAt(newTable[Time, string](), newTable[string, Time]())    
## asyncCheck aa.process
## data["foo"] = "bar"
## aa["foo"] = initDuration(seconds=3)
## ```
##
## `sorta` tables from nimble work great too
##
## ```nim
## import times, sorta, at, asyncdispatch, tables
## var s = initSortedTable[string, Time]()
## var data = newTable[string, string]()
## proc trigger(t: Time, k: string) =
## data.del k
## let aa = initAt(initSortedTable[Time, string](), initSortedTable[string, Time]())
## asyncCheck aa.process
## data["foo"] = "bar"
## aa["foo"] = initDuration(seconds=3)
## ```
##
## On-Disk
## -------
##
## Now for the main event- `at` really shines when it comes to expiring values that are persisted to disk-
## a key-value database, as there is no need to load the time information from disk into memory storage
## and keep it in sync- everything stays on disk until there is a trigger.
##
## Just give `at` a table-like interface to the database and you're
## good to go. As an example, you could create your own filesystem-based persistence layer. That's not
## particularly fast compared to other options out there but it works and does not require any dependencies.
##
## ```nim
## # TODO: add file system database example
## ```
##
## Most likely, you will prefer to use a tried-and-true key-value store
## like LMDB- here wrapped into a table-like interface by LimDB:
##
## ```nim
## import at, os, asyncdispatch, limdb, times, at/timeblobs
##
## # LimDB requires some boilerplate because it only supports strings
## iterator keys*(a: limdb.Database): Time =
##   for k in limdb.keys(a):
##     yield k.blobToTime
## proc del*(a: limdb.Database, t: Time) =
##   a.del t.timeToBlob
## 
## template `[]`*(a: limdb.Database, t: Time): string =
##   limdb.`[]`(a, t.timeToBlob)
## template `[]`*(a: limdb.Database, s: string): Time =
##   limdb.`[]`(a, s.blobToTime)
## template `[]=`*(a: limdb.Database, t: Time, s: string) =
##   limdb.`[]=`(a, t.timeToBlob, s)
## template `[]=`*(a: limdb.Database, s: string, t: Time) =
##   limdb.`[]=`(a, s, t.timeToBlob)
## 
## let data = initDatabase(getTempDir() / "limdb", "main")
## 
## proc trigger(t: Time, k: string) =
##   data.del k
## 
## let aa = initAt(data.initDatabase("at time-to-key"), data.initDatabase("at key-to-time"))
## asyncCheck aa.process()
## 
## data["foo"] = "bar"
## aa["foo"] = initDuration(seconds=3)
## ```
##
## And this is how `at`is meant to be used.
##
##


import asyncdispatch, asyncfutures, times

type
  At*[TTimeToKey, TTable2] = ref object  # ref for the async code
    ## A powerful, lightweight tool to execute code later
    trigger*: FutureVar[void]
    t2k*: TTimeToKey
    k2t*: TTable2

proc next*(a: At): Time =
  ## Internal use, uses the `keys` iterator to get the first time of the
  ## times-to-keys table to start waiting.
  mixin keys
  for t in a.t2k.keys:
    return t
  raise newException(KeyError, "next key in time-to-keys table is empty")

proc trigger*[T](t: Time, key: T) =
  ## This is a trigger that does nothing. This needs to be implemented by you-
  ## copy the definition and place it in the same file you instantiate `at` in.
  discard

proc trigger*[T](a: At, t: Time, key: T) =
  ## This is a trigger that allows access to the `at` object. Use with caution.
  ## Don't implement both if you don't want both to run.
  discard

proc process*(a: At) {.async.} =
  ## Call after initializing to start processing. This sets up the future and waits.
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
      trigger(t, key)
      trigger(a, t, key)
      a.t2k.del(t)
      a.k2t.del(key)
    else:
      let d = t - now
      discard await withTimeout[void](Future[void](a.trigger), d.inMilliseconds.int)
      a.trigger.clean()

proc initAt*[TTimeToKey, TTable2](t2k: TTimeToKey, k2t: TTable2): At[TTimeToKey, TTable2] =
  ## Initialize an `at` tool to execute code later.
  ##
  ## You give it two tables or table-like objects, one to store times and associated keys,
  ## in the others the keys are mapped to the times in case they need to be looked up.
  ##
  ## The time-to-key table needs to be of the kind that sorts by its keys. critbits works in
  ## the standard library, and so does btreetable in fusion.
  ##
  ## Persistent table-like objects are often preferred.
  ##
  new(result)
  result.t2k = t2k
  result.k2t = k2t
  result.trigger = newFutureVar[void]("at")


proc `[]=`*[T](a: At, key: T, t: Time) =
  ## Set a trigger as an absolute time.
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
  ## Set a trigger relative to now.
  a[key] = getTime() + d

proc del*[T](a: At, key: T) =
  ## Manually remove a trigger by its key
  let t = a.k2t[key]
  let retrigger = a.next == t
  del a.t2k[t]
  del a.k2t[key]
  if retrigger:
    a.trigger.complete()

proc del(a: At, t: Time) =
  ## Manually remove a trigger by its time (need be exact to the nanosecond)
  let key = a.t2k[t]
  let retrigger = a.next == t
  del a.k2t[key]
  del a.t2k[t]
  if retrigger:
    a.trigger.complete()

