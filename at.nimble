
version       = "0.1.0"
author        = "Carlo Capocasa"
description   = "A lightweight general purpose timed callback tool for when you need a lot of them. Works with disk-persisted tables."
license       = "MIT"

task test, "Run tests":
    exec "nim c -r tests/tat"
    rmFile "tests/tat"

task docs, "Generate docs":
    exec "nim doc -o:docs/at.html at.nim"

