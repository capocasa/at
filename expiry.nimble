
version       = "0.1.0"
author        = "Carlo Capocasa"
description   = "A lightweight tool to expire keys in a persistent key-value store after a certain time similar to how redis does it"
license       = "MIT"

requires "limdb"

task test, "Run tests":
    exec "nim c -r tests/texpiry"
    rmFile "tests/texpiry"

task docs, "Generate docs":
    exec "nim doc -o:docs/expiry.html expiry.nim"

