## ****
## at/t
## ****
##
## A powerful, lightweight tool to execute code later, using threads
##
## Why?
## ####
##
## `att` is the thread-based equivalent of `at`. If you don't use async in your application,
## or if you prefer the simplicity of threads, `att` gives you the exact same functionality
## without pulling in `asyncdispatch`.
##
## It has all the same advantages as `at`:
##
## Transparency:
## The timers are all neatly accessible in a table
## instead of being hidden in a thread somewhere.
## Several `att` instances can be used to group related timers
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
## Thread safety: All table operations are protected by a lock, so you can safely
## add and remove triggers from any thread.
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
## - Simple-yet-effective implementation designed for tens of thousands of planned triggers using only one thread.
## - BYOT- bring your own table, you have full control over the table or table-like object used to store trigger
##   information so you have full control over how data is stored. It's also fairly easy to write your own table interface,
##   see the filesystem-storage example in `at`.
## - No dependency on `asyncdispatch`. If you're not using async, you don't have to start.
##
## Differences from `at`
## #####################
##
## The API is intentionally almost identical. Here's what's different:
##
## - `initAtt` instead of `initAt`
## - `a.process()` instead of `asyncCheck a.process()`
## - `a.stop()` to cleanly shut down the processing thread when you're done
## - No need for `asyncdispatch`, `waitFor` or `sleepAsync`
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
## import std/[os, times, tables, critbits], at/t, at/timeblobs
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
## # Now we add a trigger proc that `att` will call.
## # It accesses `data` as a global, but it can be placed into
## # a proc to use a closure instead.
##
## proc trigger(t: Time, k: string) =
##     data.del k
##
## # Now we can initialize `att`. We make two tables and pass them in.
## # This allows for a lot of flexibility.
## let aa = initAtt(initCritBitTree[string](), initTable[string, Time])
## aa.process()
##
## # now let's add some data that will be deleted in three seconds
## data["foo"] = "bar"
## aa["foo"] = initDuration(seconds=3)
##
## # when you're done, stop the processing thread
## # aa.stop()
## ```
##
## If you don't mind using nimble packages, there is a really nice module `btreetables`
## in the `fusion` package that can be used.
##
## ```nim
## import times, at/t, fusion/btreetables
## let data = newTable[string, string]()  # this is a btree table too but could be a regular one
## proc trigger(t: Time, k: string) =
##     data.del k
## let aa = initAtt(newTable[Time, string](), newTable[string, Time]())
## aa.process()
## data["foo"] = "bar"
## aa["foo"] = initDuration(seconds=3)
## ```
##
## `sorta` tables from nimble work great too
##
## ```nim
## import times, sorta, at/t, tables
## var s = initSortedTable[string, Time]()
## var data = newTable[string, string]()
## proc trigger(t: Time, k: string) =
## data.del k
## let aa = initAtt(initSortedTable[Time, string](), initSortedTable[string, Time]())
## aa.process()
## data["foo"] = "bar"
## aa["foo"] = initDuration(seconds=3)
## ```
##
## On-Disk
## -------
##
## Now for the main event- `att` really shines when it comes to expiring values that are persisted to disk-
## a key-value database, as there is no need to load the time information from disk into memory storage
## and keep it in sync- everything stays on disk until there is a trigger.
##
## Just give `att` a table-like interface to the database and you're
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
## import at/t, os, limdb, times, at/timeblobs
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
## let aa = initAtt(data.initDatabase("att time-to-key"), data.initDatabase("att key-to-time"))
## aa.process()
##
## data["foo"] = "bar"
## aa["foo"] = initDuration(seconds=3)
## ```
##
## And this is how `att` is meant to be used.
##

import std/[times, locks, os]

when defined(posix):
  type
    CTimespec {.importc: "struct timespec", header: "<time.h>", bycopy.} = object
      tv_sec {.importc.}: clong
      tv_nsec {.importc.}: clong

  proc c_pthread_cond_timedwait(cond: pointer, lock: pointer, abstime: ptr CTimespec): cint
    {.importc: "pthread_cond_timedwait", header: "<pthread.h>".}

type
  Att*[TTimeToKey, TTable2] = object
    ## A powerful, lightweight tool to execute code later, using threads.
    t2k*: TTimeToKey
    k2t*: TTable2
    lock*: Lock
    cond*: Cond
    thread*: Thread[pointer]
    running*: bool

proc next*(a: Att): Time =
  ## Internal use, uses the `keys` iterator to get the first time of the
  ## times-to-keys table to start waiting.
  mixin keys
  for t in a.t2k.keys:
    return t
  raise newException(KeyError, "next key in time-to-keys table is empty")

proc trigger*[T](t: Time, key: T) =
  ## This is a trigger that does nothing. This needs to be implemented by you-
  ## copy the definition and place it in the same file you instantiate `tat` in.
  discard

proc trigger*[T](a: Att, t: Time, key: T) =
  ## This is a trigger that allows access to the `att` object. Use with caution.
  ## Don't implement both if you don't want both to run.
  discard

proc waitCondUntil*(cond: var Cond, lock: var Lock, deadline: Time) =
  ## Wait on a condition variable until an absolute deadline.
  when defined(posix):
    var ts: CTimespec
    ts.tv_sec = deadline.toUnix.clong
    ts.tv_nsec = deadline.nanosecond.clong
    discard c_pthread_cond_timedwait(addr cond, addr lock, addr ts)
  else:
    # Fallback for non-POSIX: release lock, sleep, re-acquire.
    let d = deadline - getTime()
    let ms = d.inMilliseconds
    if ms <= 0: return
    release(lock)
    sleep(ms.int)
    acquire(lock)

proc initAtt*[TTimeToKey, TTable2](t2k: TTimeToKey, k2t: TTable2): Att[TTimeToKey, TTable2] =
  ## Initialize an `att` tool to execute code later using threads.
  ##
  ## You give it two tables or table-like objects, one to store times and associated keys,
  ## in the others the keys are mapped to the times in case they need to be looked up.
  ##
  ## The time-to-key table needs to be of the kind that sorts by its keys.
  result.t2k = t2k
  result.k2t = k2t
  initLock(result.lock)
  initCond(result.cond)
  result.running = false

template process*(a: var Att) =
  ## Call after initializing to start processing in a background thread.
  mixin trigger
  mixin del
  a.running = true

  proc attProcessThread(arg: pointer) {.thread.} =
    {.cast(gcsafe).}:
      let aa = cast[ptr type(a)](arg)
      while aa[].running:
        acquire(aa[].lock)
        let t = block:
          var t: Time
          while true:
            try:
              t = aa[].next
              break
            except KeyError:
              waitCondUntil(aa[].cond, aa[].lock, getTime() + initDuration(days=1))
              if not aa[].running:
                release(aa[].lock)
                return
          t
        let now = getTime()
        if t <= now:
          let key = aa[].t2k[t]
          aa[].t2k.del(t)
          aa[].k2t.del(key)
          release(aa[].lock)
          trigger(t, key)
          trigger(aa[], t, key)
        else:
          waitCondUntil(aa[].cond, aa[].lock, t)
          release(aa[].lock)

  createThread(a.thread, attProcessThread, cast[pointer](addr a))

proc stop*(a: var Att) =
  ## Stop the processing thread and wait for it to finish.
  a.running = false
  signal(a.cond)
  joinThread(a.thread)

proc `[]=`*[T](a: var Att, key: T, t: Time) =
  ## Set a trigger as an absolute time.
  mixin `[]=`
  acquire(a.lock)
  let retrigger = try:
    a.next > t
  except KeyError:
    # empty, so retrigger
    true
  a.t2k[t] = key
  a.k2t[key] = t
  release(a.lock)
  if retrigger:
    signal(a.cond)

proc `[]=`*[T](a: var Att, key: T, d: Duration) =
  ## Set a trigger relative to now.
  a[key] = getTime() + d

proc del*[T](a: var Att, key: T) =
  ## Manually remove a trigger by its key
  acquire(a.lock)
  let t = a.k2t[key]
  let retrigger = a.next == t
  a.t2k.del(t)
  a.k2t.del(key)
  release(a.lock)
  if retrigger:
    signal(a.cond)

proc del(a: var Att, t: Time) =
  ## Manually remove a trigger by its time (need be exact to the nanosecond)
  acquire(a.lock)
  let key = a.t2k[t]
  let retrigger = a.next == t
  a.k2t.del(key)
  a.t2k.del(t)
  release(a.lock)
  if retrigger:
    signal(a.cond)
