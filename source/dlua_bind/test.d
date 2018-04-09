module dlua_bind.test;

import std.stdio;

import luajit.lua;

import dlua_bind;

string luaExample=`
function myAssert (a, b)
 if a ~= b then
	  local errMsg=string.format("Lua assert failure: %s != %s", a, b)
      print(errMsg)
      error("Assert failure error")
 end
end
function luaAdd (a, b)
  return a+b
end

--------------------------------
-- Structs
--------------------------------

local ss=Test.this(333333);
local ss2=Test.this(222222);
myAssert(ss.a, 333333);          --Check struct constructor
myAssert(ss2.a, 222222);         --Mutliple struct instances

ss.a=10
myAssert(ss.a, 10);              --Check struct  assigment
myAssert(ss2.a, 222222);         --Assigment changes only one instance

-- Check function overloading
myAssert(ss:www(), 0);
myAssert(ss:www(0), 1);
myAssert(ss:www(0, 0), 2);
myAssert(ss:www(0, "str"), 3);
myAssert(ss:www(0, "str", "str"), 3);

--------------------------------
-- Types in Types
--------------------------------

local ss=Test.this(555)
myAssert(ss.a, 555);
local w=ss:getTest(32);
myAssert(w.a, 32);
w.d=123;
myAssert(w.d, 123);
ss:useTest(w);

local bb=w:makeTestBBB();
w:use(bb);
local kk=bb:makePrintFromTest(ss);
kk:print();

local cc=TestCCC.this();
print(cc.ccc);
w:use(cc);

local tt=bb.test;
print(tt.a);

bb.test=Test.this(3030);
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

--------------------------------
-- Classes
--------------------------------


local cl=TestClass.this(555);
myAssert(cl.a, 555);          --Check constructor
cl.a=123;
myAssert(cl.a, 123);          --Check assigment

local cll=cl;                 --Check class assigment
cll.a=200;
myAssert(cll.a, 200);         
myAssert(cl.a, 200);

cl:zeroClass(cl);             --Check class assigment
myAssert(cll.a, 0);
myAssert(cl.a, 0);

myAssert(add(111, 200000), 200111);      --Check global function call

print();
print(" --- Lua test end --- ");


`;



void testLua(){
	lua_State* l=luaL_newstate();
	luaL_openlibs(l);
	
	bindObj!(Test, "Test")(l);
	bindObj!(TestBBB, "TestBBB")(l);
	bindObj!(TestCCC, "TestCCC")(l);
	bindObj!(TestClass, "TestClass")(l);
	
	bindFunction!(add, "add")(l);



	luaL_loadstring(l, luaExample.ptr);
	int returnCode=lua_pcall(l, 0, LUA_MULTRET, 0);	
	assert(returnCode==0, "Lua script error");

	callLuaFunc!(int function(int a, int b), "luaAdd")(l, 2, 2);
	auto luaAdd=getLuaFunctionCaller!(int function(int a, int b), "luaAdd")(l);
	assert(luaAdd(2, 2)==4);

	/*callLuaFunc!(void function(int a, int b), "myAssert")(l, 2, 2);	
	auto myAssert=getLuaFunctionCaller!(int function(int a, int b), "myAssert")(l);
	assert(myAssert(2, 2)==0);// myAssert in lua does not have return value, but in bindings we return ReturnType.init*/
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

	int www(){
		return 0;
	}
	int www(int ww){
		a=ww;
		return 1;
	}
	int www(int a, int b){
		return 2;
	}
	
	int www(int a, string b, string str="somstr"){
		return 3;
	}
	
	Test getTest(int aaa){
		return Test(aaa);
	}
	
	void useTest(Test test){
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






