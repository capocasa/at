
version       = "0.1.0"
author        = "Carlo Capocasa"
description   = "A powerful, lightweight tool to execute code later"
license       = "MIT"

task test, "Run tests":
    exec "nim c -r tests/tat"
    rmFile "tests/tat"

task docs, "Generate docs":
    exec "nim doc -o:docs/at.html at.nim"

