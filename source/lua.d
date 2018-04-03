module lua;

import core.atomic;

import std.conv: emplace;
import std.typecons;
import std.traits;
import std.stdio;

import std.experimental.allocator;
import std.experimental.allocator.mallocator;

import luajit.lua;

import mutils.type_info;

string luaExample=`
local ss=hey.this(555)
ss:printA()
local w=ss:getTest(32);
w.d=123;
w:printA();
ss:printTest(w);

local bb=w:makeTestBBB();
w:use(bb);
local kk=bb:makePrintFromTest(ss);
kk:print();

local cc=TestCCC.this();
print(cc.ccc);
w:use(cc);
`;
string luaExample23=`
local ss=hey.this()
ss:printA()
 ss=hey.this(123232311)
local xxxx=ss.a
print(xxxx);
ss:printA()
ss.c=3.14
ss:printA()
`;

string luaExample3=`
local ss=hey.this(333333)
ss:printA()
ss.a=100
ss:printA()
`;

string luaExample2=`
local m = 100;
print(m);
print("lll");
local ss=hey.this(333333)
local ss2=hey.this(222222)
ss.a=10
ss:printA()
ss2:printA()
ss:www(888)
ss:printA()
ss:www(1, 2)
ss:www(1, "strA")
ss:www(1, "strA", "strB")
ss:www(1)
ss:printA()
`;


__gshared lua_State* gLuaState;


static void stackDump (lua_State *l) {
	printf("\nStack dump start:\n ");
	int i;
	int top = lua_gettop(l);
	for (i = 1; i <= top; i++) {  /* repeat for each level */
		int t = lua_type(l, i);
		switch (t) {
			
			case LUA_TSTRING:  /* strings */
				printf("`%s'", lua_tostring(l, i));
				break;
				
			case LUA_TBOOLEAN:  /* booleans */
				printf(lua_toboolean(l, i) ? "true" : "false");
				break;
				
			case LUA_TNUMBER:  /* numbers */
				printf("%g", lua_tonumber(l, i));
				break;
				
			default:  /* other values */
				printf("%s", lua_typename(l, t));
				break;
				
		}
		printf("\n  ");  /* put a separator */
	}
	printf("\nend\n\n");  /* end the listing */
}


int index_handler(StructType)(lua_State* l){
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
	//writeln("ppppppppppp");

	//lua_pushinteger(L, 3);

	MemberSetGet* m = cast(MemberSetGet*)lua_touserdata(l, -1);  /* member info */
	lua_pop(l, 1);     
	luaL_checktype(l, 1, LUA_TUSERDATA);
	enum metaTableName=getMetatableName!StructType;
	StructType* var = *cast(StructType **)luaL_checkudata(l, 1, metaTableName);
	return m.func(l, var);
}

int newindex_handler(StructType)(lua_State *l){
	lua_pushvalue(l, 2);                     // dup index 
	lua_rawget(l, lua_upvalueindex(1));      // lookup member by name 
	if (!lua_islightuserdata(l, -1))         // invalid member 
		luaL_error(l, "cannot set member '%s'", lua_tostring(l, 2));

	
	MemberSetGet* m = cast(MemberSetGet*)lua_touserdata(l, -1);  // member info 
	lua_pop(l, 1);                               // drop lightuserdata 
	luaL_checktype(l, 1, LUA_TUSERDATA);         // dup index 

	enum metaTableName=getMetatableName!StructType;
	StructType* var = *cast(StructType **)luaL_checkudata(l, 1, metaTableName);
	m.func(l, var);
	return 0;
}
struct MemberSetGet{
	string name;
	int function(lua_State* l, void* objPtr) func; 
}


void initialize(){
	gLuaState = luaL_newstate();
	luaL_openlibs(gLuaState);

	bindStruct!(Test, "hey")(gLuaState);
	bindStruct!(TestBBB, "TestBBB")(gLuaState);
	bindStruct!(TestCCC, "TestCCC")(gLuaState);

	luaL_loadstring(gLuaState, luaExample.ptr);
	lua_pcall(gLuaState, 0, LUA_MULTRET, 0);	
}


string[] getFunctionMembers(StructType)(){
	string[] members;
	foreach(member; __traits(allMembers, StructType)){
		alias Type=  typeof(__traits(getMember, StructType, member));
		static if( isFunction!( Type ) ){
			members~=member;
		}
	}
	return members;
}

string[] getFieldMembers(StructType)(){
	string[] members;
	foreach(member; __traits(allMembers, StructType)){
		alias Type=  typeof(__traits(getMember, StructType, member));
		static if( !isFunction!( Type ) ){
			members~=member;
		}
	}
	return members;
}


template AliasSeqIter(int elementsNum){
	import std.range: iota;
	import std.meta;
	alias AliasSeqIter=aliasSeqOf!( iota(0, elementsNum) );
}

void bindStruct(StructType, string luaStructName)(lua_State* l){
	enum string[] functionMembers=getFunctionMembers!StructType;
	enum string[] fieldMembers=getFieldMembers!StructType;

	luaL_Reg[functionMembers.length+2+1] functions;// Last one is marking the end of array for lua. Two additional fields for constructor and destructor
	static MemberSetGet[fieldMembers.length] setters;
	static MemberSetGet[fieldMembers.length] getters;

	foreach(i; AliasSeqIter!(functionMembers.length)){
		enum member=functionMembers[i];
		alias Type=  typeof(__traits(getMember, StructType, member));
		static if( isFunction!( Type ) ){
			functions[i]=luaL_Reg( (member~"\0").ptr, &l_callProcedure!(StructType, member));
		}
	}

	foreach(i; AliasSeqIter!(fieldMembers.length)){
		enum member=fieldMembers[i];
		alias Type=  typeof(__traits(getMember, StructType, member));
		static if( !isFunction!( Type ) ){
			setters[i]=MemberSetGet( member, &l_setValue!(StructType, member) );
			getters[i]=MemberSetGet( member, &l_getValue!(StructType, member) );
		}
	}

	
	functions[$-3]=luaL_Reg("this", &l_createObj!(StructType));
	functions[$-2]=luaL_Reg("__gc", &deleteObj!(StructType));

	

	
	// Create metatable for this struct
	string metaTableName=getMetatableName!StructType;
	luaL_newmetatable(l, metaTableName.ptr);
	int metatable = lua_gettop(l);	

	// Add methods to table
	luaL_openlib(l, metaTableName.ptr, functions.ptr, 0);
	int methods = lua_gettop(l);

	// Add custom __index operator
	lua_pushliteral(l, "__index");
	lua_pushvalue(l, metatable);  // upvalue index 1 	
	// Fill metatable with getters 
	foreach(ref reg; getters){
		lua_pushstring(l, reg.name.ptr);
		lua_pushlightuserdata(l, cast(void*)&reg);
		lua_settable(l, -3);
	}
	lua_pushvalue(l, methods);    // upvalue index 2
	lua_pushcclosure(l, &index_handler!StructType, 2);
	lua_rawset(l, metatable);   //  metatable.__index = index_handler 
	
	
	

	// Add custom __newindex operator
	lua_pushliteral(l, "__newindex");
	lua_newtable(l);              // Table for members you can set    
	// Fill with setters 
	foreach(ref reg; setters){
		lua_pushstring(l, reg.name.ptr);
		lua_pushlightuserdata(l, cast(void*)&reg);
		lua_settable(l, -3);
	}	
	lua_pushcclosure(l, &newindex_handler!StructType, 1);
	lua_rawset(l, metatable);     // metatable.__newindex = newindex_handler 
	
	lua_setglobal(l, luaStructName);

}





void bindFunction(alias FUN, string name)(){
	lua_pushcclosure(gLuaState, &createLuaBindFunction!(FUN), 0);
	lua_setglobal(gLuaState, name);
}

string getMetatableName(T)(){
	return "luaL_"~T.stringof;
}

string getMetatableNameFromTypeName(string typeName){
	return "luaL_"~typeName;
}

int l_createObj(StructType)(lua_State* l){
	return createObj!(StructType)(l, 1);	
}

StructType* allocateObjInLua(StructType)(lua_State* l){
	StructType* data= cast(StructType*)(Mallocator.instance.allocate(StructType.sizeof).ptr);
	StructType** udata = cast(StructType **)lua_newuserdata(l, size_t.sizeof);
	*udata = data;
	string metaTableName=getMetatableName!StructType;
	lua_getfield(l, LUA_REGISTRYINDEX, metaTableName.ptr);
	lua_setmetatable(l, -2);

	return data;
}

int createObj(StructType)(lua_State* l, int argsStart){
	int argsNum=lua_gettop(l)-argsStart+1;

	StructType* data=allocateObjInLua!(StructType)(l);
	if(argsNum){
		static if(hasMember!(StructType, "__ctor")){
			callProcedure!(StructType, "__ctor")(data, l, 1, argsNum);
		}else{
			stackDump(l);
			writeln(argsNum);
			assert(0, "Default constructor, with parameters not implemented");
		}

	}else{
		//*data=StructType.init;
		emplace(data);
	}
	return 1;	
}

int deleteObj(StructType)(lua_State* l){
	enum metaTableName=getMetatableName!StructType;
	StructType* foo = *cast(StructType **)luaL_checkudata(l, 1, metaTableName);
	Mallocator.instance.dispose(foo);
	return 0;	
}



void assertInLua(bool ok, string err){
	if(!ok){
		writeln(err);
	}
}


int l_setValue(StructType, string valueName)(lua_State* l, void* objPtr){
	StructType* foo = cast(StructType *)objPtr;

	alias Type=typeof( __traits(getMember, StructType, valueName) );

	static if( isNumeric!Type){
		__traits(getMember, *foo, valueName) = cast(Type)luaL_checknumber(l, -1);
	}else{
		luaWarning( "Set value not supported");
	}

	return 0;
}

int l_getValue(StructType, string valueName)(lua_State* l, void* objPtr){
	StructType* foo = cast(StructType *)objPtr;
	
	alias Type=typeof( __traits(getMember, StructType, valueName) );
	
	static if( isNumeric!Type){
		lua_pushnumber(l, __traits(getMember, *foo, valueName));
		//= cast(Type)luaL_checknumber(l, -1);
	}else{
		luaWarning( "Get value not supported");
	}
	
	return 1;
}

int l_callProcedure(StructType, string procedureName)(lua_State* l){
	int argsNum=lua_gettop(l)-1;
	enum metaTableName=getMetatableName!StructType;
	StructType* foo = *cast(StructType **)luaL_checkudata(l, 1, metaTableName.ptr);
	return callProcedure!(StructType, procedureName)(foo, l, 2, argsNum);
}



int callProcedure(StructType, string procedureName)(StructType* var, lua_State* l, int argsStart, int argsNum){
	//StructType* var = *cast(StructType **)luaL_checkudata(l, 1, metaTableName.ptr);
	alias overloads= typeof(__traits(getOverloads, *var, procedureName));
	int overloadNummm=chooseFunctionOverload!(getProcedureData!(StructType, procedureName))(l, argsStart, argsNum);
	if(overloadNummm==-1){
		return 0;
	}

	
	int returnValuesNum=0;
sw:switch(overloadNummm){
		foreach(overloadNum, overload; overloads){
			case overloadNum:

			alias FUN=overloads[overloadNum];
			alias ParmsDefault=ParameterDefaults!(__traits(getOverloads, StructType, procedureName)[overloadNum]);		
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
				auto ret=__traits(getOverloads, *var, procedureName)[overloadNum](parms.expand);
				static if(procedureName=="__ctor"){
					emplace(var, ret);// For some reason __ctors returns value and does not modify 'var' object
				}else{
					pushReturnValue(l, ret);
				}
			}else{
				__traits(getOverloads, *var, procedureName)[overloadNum](parms.expand);
			}

			break sw;
		}

		default:
			assert(1, "No overload with that number");
	}

	return returnValuesNum;
}


int chooseFunctionOverload(ProcedureData procedureData)(lua_State* l, int argsStart, int argsNum){
	//int argsNum=lua_gettop(l)-argsStart+1;
	
	bool noChoice= (procedureData.overloads.length==1);
	if(noChoice){
		return 0;
	}
	
	int callableIndex=-1;
OVERLOADS:foreach(int i, OverloadData overload; procedureData.overloads){
		bool callable=overload.callableUsingArgsNum(argsNum);
		if(!callable){
			continue;
		}
		foreach(int k, ParameterData parm; overload.parameters){
			if(k>=argsNum){
				continue;
			}
			if(lua_type(l, argsStart+k)!=parm.luaType){
				continue OVERLOADS;				
			}else if(parm.luaType==LuaType.userdata){
				string metaTableName=getMetatableNameFromTypeName(parm.typeData.name)~"\0";
				bool ok=isUserType(l, argsStart+k, metaTableName.ptr);
				if(ok==false){
					continue OVERLOADS;			
				}
			}
		}
		
		if(callable){
			if(callableIndex!=-1){
				writeln("There are two matching function overloads for this lua parameters. Procedure: ", procedureData.name);
				return -1;
			}
			callableIndex=i;
		}
	}
	
	assertInLua(callableIndex!=-1, " No matching function overload for this lua parameters. ");
	return callableIndex;
}

bool isUserType(lua_State* l, int ud, const char* metaTableName){
	void *p = lua_touserdata(l, ud);
	if (p == null) {  /* value is not a userdata? */
		return false;
	}
	if (lua_getmetatable(l, ud)) {  /* does it have a metatable? */
		lua_getfield(l, LUA_REGISTRYINDEX, metaTableName);  /* get correct metatable */
		if (lua_rawequal(l, -1, -2)) {  /* does it have the correct mt? */
			lua_pop(l, 2);  /* remove both metatables */
			return true;
		}
	}
	return false;

}



void pushReturnValue(T)(lua_State* l, ref T val){
	static if( isIntegral!T || isFloatingPoint!T ){
		lua_pushinteger(l, val);
	}else{
		//luaWarning("Return type not supported");

		//stackDump(l);
		//T* data= cast(T*)(Mallocator.instance.allocate(T.sizeof).ptr);
		T* data=allocateObjInLua!(T)(l);
		emplace(data, val);
		//*udata=data;
	}
}

void luaWarning(string str){
	writeln("Lua binding warning: ",str);
}

auto getParmsTuple(FUN, ParmsDefault...)(lua_State* l, int argsStart, int argsNum){
	alias Parms=Parameters!FUN;
	static assert(Parms.length<=16);// Lua stack has minimum 16 slots
	Tuple!(Parms) parms;
	//int argsNum=lua_gettop(l)-argsStart+1;
	foreach(int i, PARM; Parms){
		if(i>=argsNum){
			static if( !is(ParmsDefault[i]==void) ){
				parms[i]=ParmsDefault[i];
			}
			continue;
		}
		static if( isIntegral!PARM || isFloatingPoint!PARM ){
			parms[i]=cast(PARM)luaL_checknumber(l, argsStart+i);
		}else static if( is(PARM==string) ){
			size_t strLen=0;
			const char* luaStr=luaL_checklstring(l, argsStart+i, &strLen);
			parms[i]=(luaStr[0..strLen]).idup;
		}else static if( is(PARM==struct) ){
			enum metaTableName=getMetatableName!PARM;
			PARM* m = *cast(PARM **)luaL_checkudata(l, argsStart+i, metaTableName.ptr);
			parms[i]=*m;
		}else{
			//pragma(msg, PARM);
			//static assert(0, "Type not supported");
			luaWarning("Type not supported");
		}
	}
	return parms;
}



struct Test{
	int a=10;
	char b='z';
	float c=10.3;
	int d;

	this(int ww){
		a=ww;
	}
	this(int ww, int aa){
		writeln("ctor1: ", ww, ", ", aa);		
	}
	void printA(){
		writefln("printA: %s, %s, %s, %s", a, b, c, d);
	}
	void www(){
		writeln("www0");
	}
	void www(int ww){
		writeln("www1: ", ww);
		a=ww;
	}
	void www(int a, int b){
		writeln("www2: ", a, ", ", b);
	}

	void www(int a, string b, string str="somstr"){
		writeln("www3: ", a, ", ", b, ", ", str);
	}

	Test getTest(int aaa){
		return Test(aaa);
	}

	void printTest(Test test){
		test.printA();
	}

	TestBBB makeTestBBB(){
		return TestBBB();
	}

	void use(TestBBB test){
		writeln("Got: ", test);
	}

	void use(TestCCC test){
		writeln("Got: ", test);
	}

	~this(){
		//writeln(a);
		//writeln("aaaaaaaaaaaaaaaaa");
	}
}



struct TestBBB{
	int numA;
	float bb=123;

	TestBBB makePrintFromTest(Test test){
		writeln(this);
		return TestBBB(test.a, bb);
	}
	void print(){
		writeln(this);
	}
}

struct TestCCC{
	int ccc;
}

int add(int a, int b){
	return a+b;
}

int createLuaBindFunction(alias FUN)(lua_State* l){
	enum bool hasReturn= !is(ReturnType!FUN==void);
	alias Parms=Parameters!FUN;
	static assert(Parms.length<=16);// Lua stack has minimum 16 slots
	
	assert(lua_gettop(l)==Parms.length);
	Tuple!(Parms) parms;
	foreach(i, PARM; Parms){
		static if( isIntegral!PARM || isFloatingPoint!PARM ){
			parms[i]=cast(PARM)luaL_checknumber(l, i+1);
		}else{
			static assert(0, "Type not supported");
		}
	}
	
	static if(hasReturn){
		auto ret=FUN(parms.expand);
		pushReturnValue(l, ret);
	}else{
		FUN(parms.expand);
	}
	return 1;
	
}

