## Lua Profiler in pure Lua

### Dependencies
- https://github.com/thenumbernine/lua-parser

### Usage:
`lua -lprofile -lscript.to.run`

### How It Works:
- first it overrides the `require` function
- next, for lua files, parses them, 
- inserts profiling calls into beginning of blocks of code
- and recompiles

### TODO:
- associate ast tokens with line/col, so anonymous functions can be traced back to their origin
