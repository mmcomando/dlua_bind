# dlua_bind
Library to bind D with Lua and Lua with D.

This library is in early stages of development thus bugs might be common.

# Example
Binding code in D
```D
bindObj!(TestStruct, "TestStruct")(l);
bindFunction!(add, "add")(l);

```

Using D objects in Lua
```Lua
local s=TestStruct.this(123)
s.a=add(1, 2)
print(s.a)
```

Calling Lua function in D
```Lua
// Direct Call
callLuaFunc!(int function(int a, int b), "luaAdd")(l, 2, 2);

// Call through caller
auto luaAdd=getLuaFunctionCaller!(int function(int a, int b), "luaAdd")(l);
assert(luaAdd(2, 2)==4);
```


Features
--------
Implemented
- binding functions
- binding member functions
- binding classes
- binding structs
- operator overloading
- fields getters
- fields setters
- pointers
- constructors
- default constructors

TODO
- passing arguments by reference
- binding global variables
- object constructor in global space
- custom string types
