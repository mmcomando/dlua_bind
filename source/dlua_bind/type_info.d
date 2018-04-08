module dlua_bind.type_info;

import std.meta: AliasSeq;
import std.stdio;
import std.traits;


struct TypeData{
	string name;
	long size;
	long aligment;
	Field[] fields;
	bool isCustomVector;
}

struct Field{
	string name;
	TypeData typeData;
	string stringUda;
}

TypeData getTypeData(T)(){
	TypeData data;
	data.name=T.stringof;
	data.size=T.sizeof;
	data.aligment=T.alignof;
	
	static if( is(T==struct) ){
		alias TFields=Fields!T;
		alias Names=FieldNameTuple!T;
		foreach(i, F; TFields){
			alias TP = AliasSeq!(__traits(getAttributes, T.tupleof[i]));
			string stringUda;
			static if( is(typeof(TP[0])==string) ){
				stringUda=TP[0];
				
			}
			data.fields~=Field(Names[i], getTypeData!F, stringUda);
		}
	}
	return data;
}


// Working with function overloads migh be painful so generate some data for it

// Maps to lua constant values
enum LuaType{
	none=-1,
	nil=0,
	boolean=1,
	lightuserdata=2,
	number=3,
	string=4, 
	table=5,
	function_=6,
	userdata=7,
	thread=9
}

LuaType toLuaType(T)(){
	static if( isIntegral!T || isFloatingPoint!T ){
		return LuaType.number;
	}else static if( is(T==string) ){
		return LuaType.string;
	}else{
		return LuaType.userdata;
	}
}

struct ParameterData{
	TypeData typeData;
	LuaType luaType;
	bool hasDefaultValue;
}

struct OverloadData{
	TypeData returnTypeData;
	ParameterData[] parameters;
	
	size_t minParametersNum(){
		size_t parsNum=parameters.length;
		foreach(p; parameters){
			parsNum-=p.hasDefaultValue;
		}
		return parsNum;
	}
	
	bool callableUsingArgsNum(size_t argsNum){
		return (argsNum>=minParametersNum && argsNum<=parameters.length);
	}
}

struct ProcedureData{
	string name;
	OverloadData[] overloads;
	
	size_t minParametersNum(){
		import std.algorithm: minElement;
		return minElement!"a.minParametersNum"(overloads).minParametersNum;
	}
	
}

// To generate data for normal function give module in place of StructType
ProcedureData getProcedureData(alias StructType, string procedureName)(){
	ProcedureData procedureData;
	procedureData.name=procedureName;
	alias overloads= typeof(__traits(getOverloads, StructType, procedureName));
	foreach(overloadNum, overload; overloads){
		OverloadData overloadData;
		
		alias FUN=overloads[overloadNum];
		alias Parms=Parameters!FUN;		
		alias ParmsDefault=ParameterDefaults!(__traits(getOverloads, StructType, procedureName)[overloadNum]);		
		enum bool hasReturn= !is(ReturnType!FUN==void);
		enum bool hasParms=Parms.length>0;
		
		overloadData.returnTypeData=getTypeData!(ReturnType!FUN);
		
		foreach(ParNum, Par; Parms){
			ParameterData parameterData;
			parameterData.typeData=getTypeData!Par;
			parameterData.hasDefaultValue= ( !is(ParmsDefault[ParNum]==void) );
			parameterData.luaType= toLuaType!Par;
			overloadData.parameters~=parameterData;
		}
		
		procedureData.overloads~=overloadData;
	}
	
	return procedureData;
}


unittest{
	static struct Test {
		int procA(int a, int b, int c=10, int d=10){return 0;}
		int procA(int a, int b=100, int c=10){return 0;}
		
		int proc(){return 0;}
		int proc(int a){return 0;}
		int proc(int a, int b){return 0;}
		int proc(int a, int b=100, int c=10){return 0;}
		int proc(string a, int b){return 0;}
		int proc(int a, string b){return 0;}
		int proc(int a, string b, double c ){return 0;}
	}
	// Data for procedure
	enum ProcedureData procedureDataA=getProcedureData!(Test, "procA");
	static assert(procedureDataA.overloads.length==2);
	static assert(procedureDataA.overloads[0].parameters.length==4);
	static assert(procedureDataA.overloads[1].parameters.length==3);
	static assert(procedureDataA.overloads[0].minParametersNum==2);
	static assert(procedureDataA.overloads[1].minParametersNum==1);
	static assert(procedureDataA.minParametersNum==1);
	static assert(procedureDataA.overloads[0].returnTypeData.name=="int");
	static assert(procedureDataA.overloads[0].parameters[0].typeData.name=="int");
	
	// Data for function
	enum ProcedureData funcData=getProcedureData!(mutils.type_info, "func");
	static assert(funcData.overloads.length==7);
	static assert(funcData.overloads[0].parameters.length==0);
	static assert(funcData.overloads[1].parameters.length==1);
	static assert(funcData.overloads[2].parameters.length==2);
	static assert(funcData.overloads[3].parameters.length==3);
	static assert(funcData.overloads[4].parameters.length==2);
	static assert(funcData.overloads[5].parameters.length==2);
	static assert(funcData.overloads[6].parameters.length==3);
	static assert(funcData.overloads[3].minParametersNum==1);
	static assert(funcData.minParametersNum==0);
	static assert(funcData.overloads[0].returnTypeData.name=="int");
	static assert(funcData.overloads[1].parameters[0].typeData.name=="int");
}

// Used only for tests
private:
int func(){return 0;}
int func(int a){return 0;}
int func(int a, int b){return 0;}
int func(int a, int b=100, int c=10){return 0;}
int func(string a, int b){return 0;}
int func(int a, string b){return 0;}
int func(int a, string b, double c ){return 0;}
