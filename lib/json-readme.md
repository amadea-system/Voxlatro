# JSON Library

This library is a modified copy from the library used by Steamodded.
We modified it to support encoding of `null` values through the `json.null` sentinel. This is necessary for Talon RPC Protocol.
Decoding of `null` values is still not supported.

## Other potential libraries

- [actboy168/json.lua: A pure Lua JSON library.](https://github.com/actboy168/json.lua)
  