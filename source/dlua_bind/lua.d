module dlua_bind.lua;

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
local cl=TestClass.this(555);
cl:print();
cl.a=123;
print(cl.a);
local cll=cl;

cll.a=200;
print(cl.a);
cl:zeroClass(cl);
print(cl.a);
print(cll.a);

print(fff(111, 200000));
`;

string luaExample5354=`
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

local tt=bb.test;
print(tt.a);

bb.test=hey.this(3030);
print(bb.test.a);
bb.test:printA();

print("ww");
bb.test.a=123123;
bb.test:printA();
print(bb.test.a);

local ccc=TestCCC.this(22);
print(ccc.ccc);
local testPtr=bb:getTestPointer();
print(testPtr.a);
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

void initialize(){
	gLuaState = luaL_newstate();
	luaL_openlibs(gLuaState);

	bindStruct!(Test, "hey")(gLuaState);
	bindStruct!(TestBBB, "TestBBB")(gLuaState);
	bindStruct!(TestCCC, "TestCCC")(gLuaState);
	bindStruct!(TestClass, "TestClass")(gLuaState);

	bindFunction!(add, "fff")(gLuaState);

	luaL_loadstring(gLuaState, luaExample.ptr);
	lua_pcall(gLuaState, 0, LUA_MULTRET, 0);	
}


template AliasSeqIter(int elementsNum){
	import std.range: iota;
	import std.meta;
	alias AliasSeqIter=aliasSeqOf!( iota(0, elementsNum) );
}

struct MemberSetGet{
	string name;
	int function(lua_State* l, void* objPtr) func; 
}


string[] getMembersForLua(T)(){
	string[] members;
	foreach(member; __traits(allMembers, T)){
		enum bool hasBuildInFactoryMember=is(T==class) && member=="factory";
		static if(member!="Monitor" && !hasBuildInFactoryMember ){
			members~=member;
		}
	}
	return members;

}

string[] getFunctionMembers(StructType)(){
	string[] members;
	enum string[] allMembers=getMembersForLua!StructType;
	foreach(i; AliasSeqIter!(allMembers.length)){
		enum string member=allMembers[i];
		alias Type=  typeof(__traits(getMember, StructType, member));
		static if( isFunction!( Type ) ){
			members~=member;
		}
	}
	return members;
}

string[] getSetFieldMembers(StructType)(){
	string[] members;
	enum string[] allMembers=getMembersForLua!StructType;
	foreach(i; AliasSeqIter!(allMembers.length)){
		enum string member=allMembers[i];
		alias Type=  typeof(__traits(getMember, StructType, member));
		static if( !isFunction!( Type ) && !is(Type==const) && !is(Type==immutable) ){
			members~=member;
		}
	}
	return members;
}

string[] getGetFieldMembers(StructType)(){
	string[] members;
	enum string[] allMembers=getMembersForLua!StructType;
	foreach(i; AliasSeqIter!(allMembers.length)){
		enum string member=allMembers[i];
		alias Type=  typeof(__traits(getMember, StructType, member));
		static if( !isFunction!( Type ) ){
			members~=member;
		}
	}
	return members;
}

void bindStruct(StructType, string luaStructName)(lua_State* l){
	enum string[] functionMembers=getFunctionMembers!StructType;
	enum string[] setFieldMembers=getSetFieldMembers!StructType;
	enum string[] getFieldMembers=getGetFieldMembers!StructType;

	luaL_Reg[functionMembers.length+2+1] functions;// Last one is marking the end of array for lua. Two additional fields for constructor and destructor
	static MemberSetGet[setFieldMembers.length] setters;
	static MemberSetGet[getFieldMembers.length] getters;

	foreach(i; AliasSeqIter!(functionMembers.length)){
		enum member=functionMembers[i];
		functions[i]=luaL_Reg( (member~"\0").ptr, &l_callProcedure!(StructType, member));
	}

	foreach(i; AliasSeqIter!(setFieldMembers.length)){
		enum member=setFieldMembers[i];
		setters[i]=MemberSetGet( member, &l_setValue!(StructType, member) );
	}

	foreach(i; AliasSeqIter!(getFieldMembers.length)){
		enum member=getFieldMembers[i];
		getters[i]=MemberSetGet( member, &l_getValue!(StructType, member) );
	}

	
	functions[$-3]=luaL_Reg("this", &l_createObj!(StructType));
	functions[$-2]=luaL_Reg("__gc", &l_deleteObj!(StructType));	

	
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
	lua_pushcclosure(l, &l_indexHandler!StructType, 2);
	lua_rawset(l, metatable);   //  metatable.__index = l_indexHandler 
	
	// Add custom __newindex operator
	lua_pushliteral(l, "__newindex");
	lua_newtable(l);              // Table for members you can set    
	// Fill with setters 
	foreach(ref reg; setters){
		lua_pushstring(l, reg.name.ptr);
		lua_pushlightuserdata(l, cast(void*)&reg);
		lua_settable(l, -3);
	}	
	lua_pushcclosure(l, &l_newIndexHandler!StructType, 1);
	lua_rawset(l, metatable);     // metatable.__newindex = l_newIndexHandler 



	lua_setglobal(l, luaStructName);

	lua_pop(l, 1);// Pop left value

	//lua_pushcclosure(l, &l_createObj!(StructType), 0);
	//lua_setglobal(l, luaStructName);
	
}

void bindFunction(alias FUN, string name)(lua_State* l){
	static assert( is(typeof(FUN)==function), "This function can bind only functions");
	lua_pushcclosure(l, &l_callProcedureGlobal!(__traits(parent, FUN), __traits(identifier, FUN)), 0);
	lua_setglobal(l, name);
}


void assertInLua(bool ok, string err){
	if(!ok){
		writeln(err);
	}
}

void luaWarning(string str){
	writeln("Lua binding warning: ",str);
}


void stackDump (lua_State *l) {
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

string getMetatableName(T)(){
	return "luaL_"~T.stringof;
}

string getMetatableNameFromTypeName(string typeName){
	return "luaL_"~typeName;
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



int chooseFunctionOverload(ProcedureData procedureData)(lua_State* l, int argsStart, int argsNum){	
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
	if (p == null) {  // value is not a userdata? 
		return false;
	}
	if (lua_getmetatable(l, ud)) {  // does it have a metatable? 
		lua_getfield(l, LUA_REGISTRYINDEX, metaTableName);  // get correct metatable 
		if (lua_rawequal(l, -1, -2)) {  // does it have the correct mt? 
			lua_pop(l, 2);  // remove both metatables 
			return true;
		}
	}
	return false;
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











struct Test{
	int a=10;
	char b='z';
	const float c=10.3;
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
		//writeln("dtor Test");
	}
}



struct TestBBB{
	int numA;
	float bb=123;
	Test test;

	TestBBB makePrintFromTest(Test test){
		writeln(this);
		return TestBBB(test.a, bb);
	}

	void print(){
		writeln(this);
	}

	Test* getTestPointer(){
		return &test;
	}
}

struct TestCCC{
	int ccc;
}

class TestClass{
	int a;
	this(){}
	this(int a){
		this.a=a;
	}

	void print(){
		writeln("TestClass:", a);
	}

	void zeroClass(TestClass cl){
		cl.a=0;
	}
}

int add(int a, int b){
	return a+b;
}


int testFunc(){
	writeln("!00000000000000");
	return 0;
}

int testFunc(int a){
	writeln("!1111111111111111111");
	return a;
}

int testFunc(int a, int b){
	writeln("!22222222222");
	return a*b;
}









