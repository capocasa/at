import times

# these happily lifted from the flatty library- many thanks!
# (but didn't want to depend the whole lib just one type)
func addInt32(s: var string, v: int32) {.inline.} =
  s.setLen(s.len + sizeof(v))
  cast[ptr int32](s[s.len - sizeof(v)].addr)[] = v
func addInt64(s: var string, v: int64) {.inline.} =
  s.setLen(s.len + sizeof(v))
  cast[ptr int64](s[s.len - sizeof(v)].addr)[] = v
func readInt64*(s: string, i: int): int64 {.inline.} =
  result = cast[ptr int64](s[i].unsafeAddr)[]
func readInt32*(s: string, i: int): int32 {.inline.} =
  result = cast[ptr int32](s[i].unsafeAddr)[]


proc timeToBlob*(t: Time):string =
  result.addInt64(t.toUnix)
  result.addInt32(t.nanosecond)

proc blobToTime*(s: string): Time =
  initTime(s.readInt64(0), s.readInt32(8).int)
