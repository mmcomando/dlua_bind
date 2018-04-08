module dlua_bind.bind;

import std.traits;

import luajit.lua;

import dlua_bind.lua;
import dlua_bind.utils;

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