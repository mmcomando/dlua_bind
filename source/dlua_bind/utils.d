module dlua_bind.utils;

import std.stdio;

import luajit.lua;

import dlua_bind.type_info;


template AliasSeqIter(int elementsNum){
	import std.range: iota;
	import std.meta;
	alias AliasSeqIter=aliasSeqOf!( iota(0, elementsNum) );
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


int chooseFunctionOverload(FunctionData procedureData)(lua_State* l, int argsStart, int argsNum){	
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