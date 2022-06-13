
at
==

A powerful, lightweight tool to execute code later

Why?
----

While the same thing can be accomplished using the standard library's `asyncdispatch`, at
stores the values in a table and only uses one future to go through them.

This has a lot of advantages:

Transparency:
The timers are all neatly accessible in a table 
instead of being hidden in the global dispatcher.
Several `at` instances can be used to group related timers
or timers that do different things. That makes it this much easier to find bugs.

Flexibility: The timers can be easily modified or removed up until they are triggered.
You can use any table you like as long as it keeps the keys sorted.

Persistence: Tables don't have to be in-memory. Using a table backed by
persistent storage can preserve triggers across program restarts.
Data is only ever read one-by-one after a trigger, so startup time is
not meaningfully affected. And since the data is used directly off disk, you don't
need to worry about whether the in-memory triggers are actually in sync with the
on-disk triggers because the disk data is used directly. If you use a memory-mapped persistent
table, this doesn't affect performance at all.

Use cases
---------

*Expiring Data*

A really cool use-case is to remove ephemeral key/value pairs from an (additional) table, especially
when persistent storage is used. For example, in a web app, this could be used for things like
session key hashes, password reset link hashes, or incomplete form data you don't want to clutter your
nice database with but are nice enough to store for your user.

*Maintenance tasks*

In most apps, maintenance tasks need to be performed- deleting old data, checking for updates,
reminding the user to do stuff or simply doing stuff later. Traditionally,
at least for web apps, external timers or special daemons are used, but it greatly simplifies both programming
and administration to keep everything in-process.

Features
--------

- Simple-yet-effective implementation designed for tens of thousands of planned triggers using only one future.
- BYOT- bring your own table, you have full control over the table or table-like object used to store trigger
  information so you have full control data is stored. It's also fairly easy to write your own table interface,
  see the filesystem-storage example.

Usage
-----

    # expire keys in a table
    import times, at, asyncdispatch, fusion/btreetables
    let data = newTable[string, string]()
    proc trigger(t: Time, k: string) =
        data.del k
    let aa = initAt(newTable[Time, string](), newTable[string, Time]())
    asyncCheck expiry.process
    data["foo"] = "bar"
    aa["foo"] = initDuration(seconds=3)

[Full Documentation](https://capocasa.github.io/at/at.html)
