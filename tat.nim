## **
## tat
## **
##
## A powerful, lightweight tool to execute code later, using threads.
##
## Thread-based equivalent of `at`. Same API, uses threads instead of async.
##
## Instead of `asyncCheck a.process()`, call `a.process()` to start a background thread.
## Instead of `sleepAsync`, use `os.sleep`. Instead of `waitFor`, just call your code directly.
##
## Usage
## #####
##
## ```nim
## import std/[os, times, tables, critbits], tat, at/timeblobs
##
## # CritBitTree boilerplate (same as for `at`)
## proc initCritBitTree[T](): CritBitTree[T] = discard
## iterator keys*(t: CritBitTree[string]): Time =
##   for k in critbits.keys(t): yield k.blobToTime
## proc del*(tab: var CritBitTree, t: Time) = tab.excl t.timeToBlob
## proc del*(tab: var CritBitTree, k: string) = tab.excl k
## template `[]`*(a: CritBitTree, t: Time): string = a[t.timeToBlob]
## template `[]=`*(a: CritBitTree, t: Time, s: string) = a[t.timeToBlob] = s
## template `[]=`*(a: CritBitTree, s: string, t: Time) = a[s] = t.timeToBlob
##
## let data = newTable[string, string]()
## proc trigger(t: Time, k: string) =
##   data.del k
##
## let aa = initTat(initCritBitTree[string](), initCritBitTree[string]())
## aa.process()
##
## data["foo"] = "bar"
## aa["foo"] = initDuration(seconds=3)
## ```

import std/[times, locks, os]

when defined(posix):
  type
    CTimespec {.importc: "struct timespec", header: "<time.h>", bycopy.} = object
      tv_sec {.importc.}: clong
      tv_nsec {.importc.}: clong

  proc c_pthread_cond_timedwait(cond: pointer, lock: pointer, abstime: ptr CTimespec): cint
    {.importc: "pthread_cond_timedwait", header: "<pthread.h>".}

type
  Tat*[TTimeToKey, TTable2] = ref object  # ref for thread safety
    ## A powerful, lightweight tool to execute code later, using threads.
    t2k*: TTimeToKey
    k2t*: TTable2
    lock*: Lock
    cond*: Cond
    thread*: Thread[pointer]
    running*: bool

proc next*(a: Tat): Time =
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

proc trigger*[T](a: Tat, t: Time, key: T) =
  ## This is a trigger that allows access to the `tat` object. Use with caution.
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

proc initTat*[TTimeToKey, TTable2](t2k: TTimeToKey, k2t: TTable2): Tat[TTimeToKey, TTable2] =
  ## Initialize a `tat` tool to execute code later using threads.
  ##
  ## You give it two tables or table-like objects, one to store times and associated keys,
  ## in the others the keys are mapped to the times in case they need to be looked up.
  ##
  ## The time-to-key table needs to be of the kind that sorts by its keys.
  new(result)
  result.t2k = t2k
  result.k2t = k2t
  initLock(result.lock)
  initCond(result.cond)
  result.running = false

template process*(a: Tat) =
  ## Call after initializing to start processing in a background thread.
  mixin trigger
  mixin del
  a.running = true

  proc tatProcessThread(arg: pointer) {.thread.} =
    {.cast(gcsafe).}:
      let aa = cast[type(a)](arg)
      while aa.running:
        acquire(aa.lock)
        let t = block:
          var t: Time
          while true:
            try:
              t = aa.next
              break
            except KeyError:
              waitCondUntil(aa.cond, aa.lock, getTime() + initDuration(days=1))
              if not aa.running:
                release(aa.lock)
                return
          t
        let now = getTime()
        if t <= now:
          let key = aa.t2k[t]
          echo "DEL ", key
          aa.t2k.del(t)
          aa.k2t.del(key)
          release(aa.lock)
          trigger(t, key)
          trigger(aa, t, key)
        else:
          let d = t - now
          echo "WAIT ", d.inSeconds, " seconds"
          waitCondUntil(aa.cond, aa.lock, t)
          release(aa.lock)

  createThread(a.thread, tatProcessThread, cast[pointer](a))

proc stop*(a: Tat) =
  ## Stop the processing thread and wait for it to finish.
  a.running = false
  signal(a.cond)
  joinThread(a.thread)

proc `[]=`*[T](a: Tat, key: T, t: Time) =
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

proc `[]=`*[T](a: Tat, key: T, d: Duration) =
  ## Set a trigger relative to now.
  a[key] = getTime() + d

proc del*[T](a: Tat, key: T) =
  ## Manually remove a trigger by its key
  acquire(a.lock)
  let t = a.k2t[key]
  let retrigger = a.next == t
  a.t2k.del(t)
  a.k2t.del(key)
  release(a.lock)
  if retrigger:
    signal(a.cond)

proc del(a: Tat, t: Time) =
  ## Manually remove a trigger by its time (need be exact to the nanosecond)
  acquire(a.lock)
  let key = a.t2k[t]
  let retrigger = a.next == t
  a.k2t.del(key)
  a.t2k.del(t)
  release(a.lock)
  if retrigger:
    signal(a.cond)
