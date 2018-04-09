module dlua_bind.lua;

import std.conv : emplace;
import std.experimental.allocator;
import std.experimental.allocator.mallocator;
import std.stdio;
import std.traits;
import std.typecons : Tuple,tuple;

import luajit.lua;

import dlua_bind.bind;
import dlua_bind.type_info;
import dlua_bind.utils;

// TODO function parameters passed by ref

/*__gshared lua_State* gLuaState;

 void initialize(){
 gLuaState = luaL_newstate();
 luaL_openlibs(gLuaState);

 luaL_loadstring(gLuaState, luaExample.ptr);
 lua_pcall(gLuaState, 0, LUA_MULTRET, 0);	
 }*/

struct LuaCallFunc(Func, string name){
	static assert( isFunctionPointer!Func );

	lua_State* l;

	auto opCall(Parameters!Func args) {
		enum bool hasReturn= !is(ReturnType!Func==void);

		lua_getglobal(l, name);  
		foreach(ref arg; args){
			pushReturnValue(l, arg);// Push  argument 
		}

		// Do the call 
		int ok=lua_pcall(l, args.length, 0, 0);
		if(ok!=0){
			writeln("Error calling lua function");
			static if(hasReturn){
				return (ReturnType!Func).init;// Return default value
			}
		}
		static if(hasReturn){
			ReturnType!Func returnValue;
			setValueFromLuaStack(l, -1, returnValue);
			return returnValue;
		} 
	}

}

auto getLuaFunctionCaller(Func, string name)(lua_State* l){
	LuaCallFunc!(Func, name) caller;
	caller.l=l;
	return caller;
}

auto callLuaFunc(Func, string name, Args...)(lua_State* l, auto ref Args args){
	static assert( isFunctionPointer!Func );
	static assert( (Parameters!Func).length==Args.length );

	enum bool hasReturn= !is(ReturnType!Func==void);
	auto myAssert=getLuaFunctionCaller!(Func, name)(l);

	return myAssert(args);
}

StructType* allocateObjInLua(StructType)(lua_State* l, StructType* data=null)
	if( is(StructType==struct) )
{
	if(data is null){
		data=cast(StructType*)(Mallocator.instance.allocate(StructType.sizeof).ptr);
	}

	StructType** udata = cast(StructType **)lua_newuserdata(l, size_t.sizeof);
	*udata = data;
	string metaTableName=getMetatableName!StructType;
	lua_getfield(l, LUA_REGISTRYINDEX, metaTableName.ptr);
	lua_setmetatable(l, -2);
	
	return data;
}

StructType allocateObjInLua(StructType)(lua_State* l, StructType data=null)
	if( is(StructType==class) )
{
	if(data is null){
		data=Mallocator.instance.make!(StructType);
	}
	
	StructType* udata = cast(StructType *)lua_newuserdata(l, size_t.sizeof);
	*udata = data;
	string metaTableName=getMetatableName!StructType;
	lua_getfield(l, LUA_REGISTRYINDEX, metaTableName.ptr);
	lua_setmetatable(l, -2);
	
	return data;
}

auto getObjFromUserData(T)(lua_State* l, int argNum){
	enum metaTableName=getMetatableName!T;
	static if( is(T==class) ){
		T var = *cast(T *)luaL_checkudata(l, argNum, metaTableName);
	}else{
		T* var = *cast(T **)luaL_checkudata(l, argNum, metaTableName);
	}
	return var;
}

int createObj(StructType)(lua_State* l, int argsStart){
	int argsNum=lua_gettop(l)-argsStart+1;

	auto data=allocateObjInLua!(StructType)(l);
	if(argsNum){
		static if(hasMember!(StructType, "__ctor")){
			static if( is(StructType==class) ){
				callProcedure!(StructType, "__ctor")(data, l, 1, argsNum);
			}else{
				callProcedure!(StructType, "__ctor")(*data, l, 1, argsNum);
			}
		}else{
			emplace(data);
			foreach(i, ref field; (*data).tupleof){
				if(i>=argsNum){
					break;
				}
				setValueFromLuaStack(l, i+1, field);
			}
		}
		
	}else{
		emplace(data);
	}

	return 1;	
}

int l_indexHandler(StructType)(lua_State* l){
	// stack has userdata, index 
	lua_pushvalue(l, 2);                     // dup index 
	lua_rawget(l, lua_upvalueindex(1));      // lookup member by name 
	if (!lua_islightuserdata(l, -1)) {
		lua_pop(l, 1);                         // drop value 
		lua_pushvalue(l, 2);                   // dup index 
		lua_gettable(l, lua_upvalueindex(2));  // else try methods 
		if (lua_isnil(l, -1))                  // invalid member 
			luaL_error(l, "cannot get member '%s'", lua_tostring(l, 2));
		return 1;
	}
	
	MemberSetGet* m = cast(MemberSetGet*)lua_touserdata(l, -1);  // member info 
	lua_pop(l, 1);     
	luaL_checktype(l, 1, LUA_TUSERDATA);
	auto var=getObjFromUserData!(StructType)(l, 1);
	return m.func(l, cast(void*)var);
}

int l_newIndexHandler(StructType)(lua_State *l){
	lua_pushvalue(l, 2);                     // dup index 
	lua_rawget(l, lua_upvalueindex(1));      // lookup member by name 
	if (!lua_islightuserdata(l, -1))         // invalid member 
		luaL_error(l, "cannot set member '%s'", lua_tostring(l, 2));
	
	
	MemberSetGet* m = cast(MemberSetGet*)lua_touserdata(l, -1);  // member info 
	lua_pop(l, 1);                               // drop lightuserdata 
	luaL_checktype(l, 1, LUA_TUSERDATA);         // dup index 

	auto var=getObjFromUserData!(StructType)(l, 1);
	m.func(l, cast(void*)var);
	return 0;
}

int l_createObj(StructType)(lua_State* l){
	return createObj!(StructType)(l, 1);	
}

int l_deleteObj(StructType)(lua_State* l){
	auto var=getObjFromUserData!(StructType)(l, 1);
	Mallocator.instance.dispose(var);
	return 0;	
}

int l_setValue(StructType, string valueName)(lua_State* l, void* objPtr){
	alias Type=typeof( __traits(getMember, StructType, valueName) );

	static if( is(StructType==class) ){
		StructType foo = cast(StructType)objPtr;
		Type* member=&__traits(getMember, foo, valueName);
	}else{
		StructType* foo = cast(StructType *)objPtr;
		Type* member=&__traits(getMember, *foo, valueName);
	}

	

	static if( isNumeric!Type){
		*member = cast(Type)luaL_checknumber(l, -1);
	}else static if( is(Type==char) ){
		size_t strSize=0;
		const char * str = luaL_checklstring(l, -1, &strSize);
		assertInLua(strSize==1, "Bad lua char assigment");
		*member = str[0];
	}else static if( is(Type==struct) ){
		Type* var=getObjFromUserData!(Type)(l, -1);
		*member = *var;
	}else{
		static assert(0, "Set value type not supported");
	}

	return 0;
}

int l_getValue(StructType, string valueName)(lua_State* l, void* objPtr){
	alias Type=typeof(__traits(getMember, StructType, valueName));

	static if( is(StructType==class) ){
		StructType foo = cast(StructType)objPtr;
		Type* val=&__traits(getMember, foo, valueName);
	}else{
		StructType* foo = cast(StructType *)objPtr;
		Type* val=&__traits(getMember, *foo, valueName);
	}

	static if( is(Type==struct) ){
		pushReturnValue(l, val);
	}else{
		pushReturnValue(l, *val);

	}

	return 1;
}

int callProcedure(StructType, string procedureName)(ref StructType varOrModule, lua_State* l, int argsStart, int argsNum){
	mixin callProcedureTemplate;
	return callProcedureImpl();
}

int l_callProcedure(StructType, string procedureName)(lua_State* l){
	int argsNum=lua_gettop(l)-1;
	auto var=getObjFromUserData!(StructType)(l, 1);
	static if( is(StructType==class) ){
		return callProcedure!(StructType, procedureName)(var, l, 2, argsNum);
	}else{
		return callProcedure!(StructType, procedureName)(*var, l, 2, argsNum);
	}
}

int l_callProcedureGlobal(alias varOrModule, string procedureName)(lua_State* l){
	int argsStart=1;
	int argsNum=lua_gettop(l);
	
	mixin callProcedureTemplate;
	
	return callProcedureImpl();	
}

mixin template callProcedureTemplate(){
	int callProcedureImpl(){
		alias overloads= typeof(__traits(getOverloads, varOrModule, procedureName));
		int overloadNummm=chooseFunctionOverload!(getProcedureData!(varOrModule, procedureName))(l, argsStart, argsNum);
		if(overloadNummm==-1){
			return 0;
		}
		
		int returnValuesNum=0;
	sw:switch(overloadNummm){
			foreach(overloadNum, overload; overloads){
				case overloadNum:
				
				alias FUN=overloads[overloadNum];
				alias ParmsDefault=ParameterDefaults!(__traits(getOverloads, varOrModule, procedureName)[overloadNum]);		
				alias Parms=Parameters!FUN;
				
				enum bool hasReturn= !is(ReturnType!FUN==void);
				enum bool hasParms=Parms.length>0;
				
				static assert(Parms.length<16);// Lua stack has minimum 16 slots
				
				returnValuesNum=hasReturn;
				
				static if(hasParms){
					auto parms=getParmsTuple!(FUN, ParmsDefault)(l, argsStart, argsNum);
				}else{
					auto parms=tuple!();
				}
				
				static if(hasReturn){
					auto ret=__traits(getOverloads, varOrModule, procedureName)[overloadNum](parms.expand);
					static if(procedureName=="__ctor"){
						emplace(&varOrModule, ret);// For some reason __ctor returns value and does not modify 'var' object
					}else{
						pushReturnValue(l, ret);
					}
				}else{
					__traits(getOverloads, varOrModule, procedureName)[overloadNum](parms.expand);
				}
				
				break sw;
			}
			
			default:
				assert(1, "No overload with that number");
		}
		
		return returnValuesNum;
	}

}




void pushReturnValue(T)(lua_State* l, T val){
	pushReturnValue(l, val);
}

void pushReturnValue(T)(lua_State* l, ref T val){
	static if( isIntegral!T || isFloatingPoint!T ){
		lua_pushnumber(l, val);
	}else static if( is(T==char) ){
		lua_pushlstring(l, &val, 1);
	}else static if( is(T==bool) ){
		lua_pushboolean(l, val);
	}else static if( is(T==string) ){
		lua_pushlstring(l, val.ptr, val.length);
	}else static if( is(T==struct) ){
		T* data=allocateObjInLua!(T)(l);
		emplace(data, val);
	}else static if( isPointer!T ){
		alias Type=typeof(*val);
		allocateObjInLua!(Type)(l, val);
	}else static if( is(T==class) ){
		allocateObjInLua!(T)(l, val);
	}else{
		static assert(0, "Return value not supported");
	}
}



auto getParmsTuple(FUN, ParmsDefault...)(lua_State* l, int argsStart, int argsNum){
	alias Parms=Parameters!FUN;
	static assert(Parms.length<=LUA_MINSTACK);// Minimim lua stack slots
	Tuple!(Parms) parms;

	foreach(int i, PARM; Parms){
		if(i>=argsNum){
			static if( !is(ParmsDefault[i]==void) ){
				parms[i]=ParmsDefault[i];
			}
			continue;
		}
		setValueFromLuaStack(l, argsStart+i ,parms[i]);
	}
	return parms;
}

void setValueFromLuaStack(T)(lua_State* l, int valueStackNum, ref T value){
	int type=lua_type(l, valueStackNum);
	if(type==LUA_TNIL){
		return;
	}
	static if( isIntegral!T || isFloatingPoint!T ){
		value=cast(T)luaL_checknumber(l, valueStackNum);
	}else static if( is(T==string) ){
		size_t strLen=0;
		const char* luaStr=luaL_checklstring(l, valueStackNum, &strLen);
		value=(luaStr[0..strLen]).idup;
	}else static if( is(T==struct) ){
		T* var=getObjFromUserData!(T)(l, valueStackNum);
		value=*var;
	}else static if( is(T==class) ){
		T var=getObjFromUserData!(T)(l, valueStackNum);
		value=var;
	}else{
		pragma(msg, T);
		//luaWarning("Type not supported");
		static assert(0, "Type not supported");
	}
}

