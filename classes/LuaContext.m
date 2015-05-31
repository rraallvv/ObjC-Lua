//
//  LuaContext.m
//  Givit
//
//  Created by Sean Meiners on 2013/11/19.
//
//

#import "LuaContext.h"
#import "LuaExport.h"
#import "LuaExportMetaData.h"

#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

#import "lua.h"
#import "lauxlib.h"
#import "lualib.h"

#if LUA_VERSION_NUM <= 501
#define LUA_OK 0
#endif

#if ! TARGET_OS_IPHONE
const CATransform3D CATransform3DIdentity = {
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1 };
#endif

NSString *const LuaErrorDomain = @"LuaErrorDomain";

const char *LuaWrapperObjectMetatableName = "LuaWrapperObjectMetaTable";

typedef struct LuaWrapperObject {
    void *context;
    void *instance;
    void *exportData;
} LuaWrapperObject;

static int luaWrapperIndex(lua_State *L);
static int luaWrapperNewIndex(lua_State *L);
static int luaWrapperGC(lua_State *L);
static int luaWrapperCall(lua_State *L);

static int luaDumpVar(lua_State *L);

static const struct luaL_Reg luaWrapperMetaFunctions[] = {
    {"__index", luaWrapperIndex},
    {"__newindex", luaWrapperNewIndex},
    {"__gc", luaWrapperGC},
    {"__call", luaWrapperCall},
    {NULL, NULL}
};

static int luaPanicked(lua_State *L) {
    NSLog(@"Lua panicked: %s", luaL_checkstring(L, -1));
    return 0;
}

static const luaL_Reg loadedlibs[] = {
  {"_G", luaopen_base},
//  {LUA_LOADLIBNAME, luaopen_package},
//  {LUA_COLIBNAME, luaopen_coroutine},
  {LUA_TABLIBNAME, luaopen_table},
//  {LUA_IOLIBNAME, luaopen_io},
//  {LUA_OSLIBNAME, luaopen_os},
  {LUA_STRLIBNAME, luaopen_string},
//  {LUA_BITLIBNAME, luaopen_bit32},
  {LUA_MATHLIBNAME, luaopen_math},
//  {LUA_DBLIBNAME, luaopen_debug},
  {NULL, NULL}
};

@interface LuaVirtualMachine () {
	lua_State *L;
	NSMutableDictionary *_exportedClasses;
}
@end

@implementation LuaVirtualMachine

- (id)init {
    if( (self = [super init]) ) {
        L = luaL_newstate();
        lua_atpanic(L, &luaPanicked);

        // load the lua libraries
        const luaL_Reg *lib;
        for( lib = loadedlibs; lib->func; ++lib ) {
#if LUA_VERSION_NUM <= 501
            lua_pushcfunction(L, lib->func);
            lua_pushstring(L, lib->name);
            lua_call(L, 1, 0);
#else
            luaL_requiref(L, lib->name, lib->func, 1);
            lua_pop(L, 1);  /* remove lib */
#endif
        }

        lua_register(L, "dumpVar", luaDumpVar);

        luaL_newmetatable(L, LuaWrapperObjectMetatableName);
#if LUA_VERSION_NUM <= 501
        const luaL_Reg* func;
        for( func = luaWrapperMetaFunctions; func->func; ++func ) {
            lua_pushstring(L, func->name);
            lua_pushcclosure(L, func->func, 0);
            lua_settable(L, -3);
        }
#else
        luaL_setfuncs(L, luaWrapperMetaFunctions, 0);
#endif
        lua_pop(L, 1);

        _exportedClasses = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)dealloc {
    if( L )
        lua_close(L);
}

- (lua_State *)state {
	return L;
}

- (NSMutableDictionary *)exportedClasses {
	return _exportedClasses;
}

@end

@interface LuaContext () {
    lua_State *C;
    LuaVirtualMachine *_virtualMachine;
}
@end

@implementation LuaContext

- (id)initWithVirtualMachine:(LuaVirtualMachine *)virtualMachine {
	if( (self = [super init]) ) {
		_virtualMachine = virtualMachine;

		lua_State *L = _virtualMachine.state;

		C = lua_newthread(L);

		/* Fix globals */
		lua_newtable(C); /* new table for globals */
		lua_newtable(C); /* metatable for new globals */
		lua_pushliteral(C, "__index");
		lua_pushvalue(C, LUA_GLOBALSINDEX); /* __index tries old common globals */
		lua_settable(C, -3);
		lua_setmetatable(C, -2);
		lua_replace(C, LUA_GLOBALSINDEX);
	}
	return self;
}

- (id)init {
    return [self initWithVirtualMachine:[LuaVirtualMachine new]];
}

- (void)dealloc {
//    if( L )
//        lua_close(L);
}

- (LuaVirtualMachine *)virtualMachine {
	return _virtualMachine;
}

- (id)callWithArgumentsCount:(int)count error:(NSError *__autoreleasing *)error {
    id result = nil;
    int err = lua_pcall(C, count, LUA_MULTRET, 0);
    if( err == LUA_OK ) {
        int numOfReturnedValues = lua_gettop(C);
        if( numOfReturnedValues == 1 ) {
            result = toObjC(C, -1);
        }
        else if( numOfReturnedValues > 1 ) {
            result = [NSMutableArray arrayWithCapacity:numOfReturnedValues];
            for( int i=0; i<numOfReturnedValues; ++i ) {
                result[i] = toObjC(C, i+1);
            }
        }
        lua_pop(C, numOfReturnedValues);
        if( error )
            *error = nil;
    }
    else {
        if( error )
            *error = [NSError errorWithDomain:LuaErrorDomain
                                         code:err
                                     userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Could not evaluate script: %s", lua_tostring(C,-1)] }];
        lua_pop(C, 1);
    }
    return result;
}

- (id)parse:(NSString *)script error:(NSError *__autoreleasing *)error {
	if( ! script ) {
		if( error )
			*error = [NSError errorWithDomain:LuaErrorDomain
										 code:LuaError_Invalid
									 userInfo:@{ NSLocalizedDescriptionKey: @"There is no script to parse" }];
		return nil;
	}
    int err = luaL_loadstring(C, [script UTF8String]);
    if( err == LUA_OK )
        return [self callWithArgumentsCount:0 error:error];
    else {
        if( error )
            *error = [NSError errorWithDomain:LuaErrorDomain
                                         code:err
                                     userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Could not parse script: %s", lua_tostring(C,-1)] }];
        lua_pop(C, 1);
    }
    return nil;
}

- (id)parseURL:(NSURL *)url error:(NSError *__autoreleasing *)error {
    if( ! [[url scheme] isEqualToString:@"file"] ) {
        if( error )
            *error = [NSError errorWithDomain:LuaErrorDomain
                                         code:LuaError_Invalid
                                     userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid script path '%@'", url] }];
        return nil;
    }
    int err = luaL_loadfile(C, [[url path] UTF8String]);
    if( err == LUA_OK )
        return [self callWithArgumentsCount:0 error:error];
    else {
        if( error )
            *error = [NSError errorWithDomain:LuaErrorDomain
                                         code:err
                                     userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Could not parse script: %s", lua_tostring(C,-1)] }];
        lua_pop(C, 1);
    }
    return nil;
}

- (BOOL)fromObjC:(id)object {
    if( ! object )
        lua_pushnil(C);
    else if( [object isKindOfClass:[NSString class]] )
        lua_pushstring(C, [object UTF8String]);
    else if( [object isKindOfClass:[NSNumber class]] ) {
        switch( [object objCType][0] ) {
            case _C_FLT:
            case _C_DBL:
                lua_pushnumber(C, [object doubleValue]);
                break;
            case _C_CHR:
            case _C_UCHR:
                lua_pushboolean(C, [object boolValue]);
                break;
            case _C_SHT:
            case _C_USHT:
            case _C_INT:
            case _C_UINT:
            case _C_LNG:
            case _C_ULNG:
            case _C_LNG_LNG:
            case _C_ULNG_LNG:
                lua_pushinteger(C, [object longValue]);
                break;
            default:
                return NO;
        }
    }
    else if( [object isKindOfClass:[NSArray class]] ) {
        lua_newtable(C);
        [object enumerateObjectsUsingBlock:^(id item, NSUInteger idx, BOOL *stop) {
            [self fromObjC:item];
            lua_rawseti(C, -2, (int)idx + 1); // lua arrays start at 1, not 0
        }];
    }
    else if( [object isKindOfClass:[NSDictionary class]] ) {
        lua_newtable(C);
        [object enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            [self fromObjC:key];
            [self fromObjC:obj];
            lua_rawset(C, -3);
        }];
    }
    else if( [object isKindOfClass:[NSValue class]] ) {
        const char *objType = [object objCType];
        if( ! strncmp(objType, "{CGRect=", 8) ) {
            CGRect rect;
            [object getValue:&rect];
            lua_newtable(C);
            lua_pushstring(C, "x");
            lua_pushnumber(C, rect.origin.x);
            lua_rawset(C, -3);
            lua_pushstring(C, "y");
            lua_pushnumber(C, rect.origin.y);
            lua_rawset(C, -3);
            lua_pushstring(C, "width");
            lua_pushnumber(C, rect.size.width);
            lua_rawset(C, -3);
            lua_pushstring(C, "height");
            lua_pushnumber(C, rect.size.height);
            lua_rawset(C, -3);
        }
        else if( ! strncmp(objType, "{CGPoint=", 9) ) {
            CGPoint point;
            [object getValue:&point];
            lua_newtable(C);
            lua_pushstring(C, "x");
            lua_pushnumber(C, point.x);
            lua_rawset(C, -3);
            lua_pushstring(C, "y");
            lua_pushnumber(C, point.y);
            lua_rawset(C, -3);
        }
        else if( ! strncmp(objType, "{CGSize=", 8) ) {
            CGSize cgsize;
            [object getValue:&cgsize];
            lua_newtable(C);
            lua_pushstring(C, "width");
            lua_pushnumber(C, cgsize.width);
            lua_rawset(C, -3);
            lua_pushstring(C, "height");
            lua_pushnumber(C, cgsize.height);
            lua_rawset(C, -3);
        }
        else if( ! strncmp(objType, "{CGAffineTransform=", 19) ) {
            CGAffineTransform xform;
            [object getValue:&xform];
            lua_newtable(C);
            lua_pushnumber(C, xform.a);
            lua_rawseti(C, -2, 1);
            lua_pushnumber(C, xform.b);
            lua_rawseti(C, -2, 2);
            lua_pushnumber(C, xform.c);
            lua_rawseti(C, -2, 3);
            lua_pushnumber(C, xform.d);
            lua_rawseti(C, -2, 4);
            lua_pushnumber(C, xform.tx);
            lua_rawseti(C, -2, 5);
            lua_pushnumber(C, xform.ty);
            lua_rawseti(C, -2, 6);
        }
        else if( ! strncmp(objType, "{CATransform3D=", 15) ) {
            CATransform3D xform;
            [object getValue:&xform];
            lua_newtable(C);
            lua_pushnumber(C, xform.m11);
            lua_rawseti(C, -2, 1);
            lua_pushnumber(C, xform.m12);
            lua_rawseti(C, -2, 2);
            lua_pushnumber(C, xform.m13);
            lua_rawseti(C, -2, 3);
            lua_pushnumber(C, xform.m14);
            lua_rawseti(C, -2, 4);
            lua_pushnumber(C, xform.m21);
            lua_rawseti(C, -2, 5);
            lua_pushnumber(C, xform.m22);
            lua_rawseti(C, -2, 6);
            lua_pushnumber(C, xform.m23);
            lua_rawseti(C, -2, 7);
            lua_pushnumber(C, xform.m24);
            lua_rawseti(C, -2, 8);
            lua_pushnumber(C, xform.m31);
            lua_rawseti(C, -2, 9);
            lua_pushnumber(C, xform.m32);
            lua_rawseti(C, -2, 10);
            lua_pushnumber(C, xform.m33);
            lua_rawseti(C, -2, 11);
            lua_pushnumber(C, xform.m34);
            lua_rawseti(C, -2, 12);
            lua_pushnumber(C, xform.m41);
            lua_rawseti(C, -2, 13);
            lua_pushnumber(C, xform.m42);
            lua_rawseti(C, -2, 14);
            lua_pushnumber(C, xform.m43);
            lua_rawseti(C, -2, 15);
            lua_pushnumber(C, xform.m44);
            lua_rawseti(C, -2, 16);
        }
        else
            return NO;
    }
    else if( [object conformsToProtocol:@protocol(LuaExport)] ) {
        NSString *clasName = NSStringFromClass([object class]);
        //NSLog(@"%@ conforms", clasName);
        LuaExportMetaData *exportData = _virtualMachine.exportedClasses[clasName];

        if( ! exportData )
        {
            exportData = [LuaExportMetaData createExport];
            Protocol *exportProtocol = @protocol(LuaExport);
            for( Class clas = [object class]; clas; clas = [clas superclass] )
            {
                unsigned int protocolCount = 0;
                Protocol *__unsafe_unretained *protocols = class_copyProtocolList(clas, &protocolCount);
                for( unsigned int i = 0; i < protocolCount; ++i )
                {
                    //NSLog(@"%@ implements %s", object, protocol_getName(protocols[i]));
                    if( protocol_conformsToProtocol(protocols[i], exportProtocol) )
                    {
                        unsigned int propertyCount = 0;
                        objc_property_t *properties = protocol_copyPropertyList(protocols[i], &propertyCount);
                        for( unsigned int j = 0; j < propertyCount; ++j ) {
                            //NSLog(@"property: %s", property_getName(properties[j]));
                            [exportData addAllowedProperty:property_getName(properties[j]) withAttrs:property_getAttributes(properties[j])];
                        }

                        unsigned int instanceMethodCount = 0;
                        struct objc_method_description *instanceMethods = protocol_copyMethodDescriptionList(protocols[i], YES, YES, &instanceMethodCount);
                        for( unsigned int k = 0; k < instanceMethodCount; ++k ) {
                            //NSLog(@"instance method: %s", sel_getName(instanceMethods[k].name));
                            [exportData addAllowedMethod:sel_getName(instanceMethods[k].name) withTypes:instanceMethods[k].types];
                        }

                        unsigned int classMethodCount = 0;
                        struct objc_method_description *classMethods = protocol_copyMethodDescriptionList(protocols[i], YES, NO, &classMethodCount);
                        for( unsigned int k = 0; k < classMethodCount; ++k ) {
                            //NSLog(@"class method: %s", sel_getName(classMethods[k].name));
                            [exportData addAllowedMethod:sel_getName(classMethods[k].name) withTypes:classMethods[k].types];
                        }

                        free(properties);
                        properties = NULL;
                        free(instanceMethods);
                        instanceMethods = NULL;
                        free(classMethods);
                        classMethods = NULL;
                    }
                }
                free(protocols);
                protocols = NULL;
            }

            if( exportData )
                _virtualMachine.exportedClasses[clasName] = exportData;
        }

        if( exportData ) {
            LuaWrapperObject *wrapper = lua_newuserdata(C, sizeof(*wrapper));
            wrapper->context = (__bridge void*)self;
            wrapper->instance = (__bridge_retained void*)object;
            wrapper->exportData = (__bridge_retained void*)exportData;
            luaL_getmetatable(C, LuaWrapperObjectMetatableName);
            lua_setmetatable(C, -2);
            //NSLog(@"%@ adding wrapper %p with ed: %p", object, wrapper, exportData);
        }
        else
            return NO;
    }
    else if( [object isKindOfClass:[^{} class]] ) {
        LuaWrapperObject *wrapper = lua_newuserdata(C, sizeof(*wrapper));
        wrapper->context = (__bridge void*)self;
        wrapper->instance = (__bridge_retained void*)object;
        wrapper->exportData = (__bridge_retained void*)[LuaExportBlockMetaData blockMetaDataFor:object];
        luaL_getmetatable(C, LuaWrapperObjectMetatableName);
        lua_setmetatable(C, -2);
    }
    else
        return NO;

    return YES;
}

static inline id toObjC(lua_State *L, int index) {
    switch( lua_type(L, index) ) {
        case LUA_TNIL:
            return nil;
        case LUA_TNUMBER:
            return @(lua_tonumber(L, index));
        case LUA_TBOOLEAN:
            return @(lua_toboolean(L, index));
        case LUA_TSTRING:
            return [NSString stringWithUTF8String:lua_tostring(L, index)];
        case LUA_TTABLE:
        {
            BOOL isDict = NO;

            lua_pushvalue(L, index); // make sure the table is at the top
            lua_pushnil(L);  /* first key */
            while( ! isDict && lua_next(L, -2) ) {
                if( lua_type(L, -2) != LUA_TNUMBER ) {
                    isDict = YES;
                    lua_pop(L, 2); // pop key and value off the stack
                }
                else
                    lua_pop(L, 1);
            }

            id result = nil;

            if( isDict ) {
                result = [NSMutableDictionary dictionary];
                
                lua_pushnil(L);  /* first key */
                while( lua_next(L, -2) ) {
                    id key = toObjC(L, -2);
                    id object = toObjC(L, -1);
                    if( ! key )
                        continue;
                    if( ! object )
                        object = [NSNull null];
                    result[key] = object;
                    lua_pop(L, 1); // pop the value off
                }
            }
            else {
                result = [NSMutableArray array];
                
                lua_pushnil(L);  /* first key */
                while( lua_next(L, -2) ) {
                    int index = lua_tonumber(L, -2) - 1;
                    id object = toObjC(L, -1);
                    if( ! object )
                        object = [NSNull null];
                    result[index] = object;
                    lua_pop(L, 1);
                }
            }
              
            lua_pop(L, 1); // pop the table off
            return result;
        }
        case LUA_TUSERDATA:
        {
            LuaWrapperObject *wrapper = (LuaWrapperObject*)luaL_checkudata(L, index, LuaWrapperObjectMetatableName);
            if( wrapper )
                return (__bridge id)wrapper->instance;
        }
        case LUA_TFUNCTION:
        case LUA_TTHREAD:
        case LUA_TLIGHTUSERDATA:
        default:
            return nil;
    }
}

- (id)call:(NSString *)name with:(NSArray *)args error:(NSError *__autoreleasing *)error {
    lua_getglobal(C, [name UTF8String]);
    if( lua_type(C, -1) != LUA_TFUNCTION ) {
        if( error )
            *error = [NSError errorWithDomain:LuaErrorDomain
                                         code:LuaError_Invalid
                                     userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Function %@ not found", name] }];
        return nil;
    }
    int count = 0;
    for( id arg in args ) {
        count += [self fromObjC:arg] ? 1 : 0;
    }
    return [self callWithArgumentsCount:count error:error];
}

- (id)objectForKeyedSubscript:(id)key {
    if( ! [key isKindOfClass:[NSString class]] ) {
        if( [key respondsToSelector:@selector(stringValue)] )
            key = [key stringValue];
        else
            key = [key description];
    }
    lua_getglobal(C, [key UTF8String]);
    id result = toObjC(C, -1);
    lua_pop(C, 1);
    return result;
}

- (void)setObject:(id)object forKeyedSubscript:(id)key {
    if( ! [key isKindOfClass:[NSString class]] ) {
        if( [key respondsToSelector:@selector(stringValue)] )
            key = [key stringValue];
        else
            key = [key description];
    }
    if( [self fromObjC:object] )
        lua_setglobal(C, [key UTF8String]);
}

@end

static int luaGetLine(lua_State *L, int level) {
	lua_Debug ar;
	if( !lua_getstack(L, level, &ar) )
		return LUA_NOREF;
	lua_getinfo(L, "l", &ar);
	int result = ar.currentline;
	if( result == LUA_REFNIL )
		return luaGetLine(L, level + 1);
	return result;
}

static int callMethod(lua_State *L) {
    LuaWrapperObject *wrapper = (LuaWrapperObject*)lua_touserdata(L, lua_upvalueindex(1));
    const char *name = lua_tostring(L, lua_upvalueindex(2));
    //NSLog(@"calling method for %p - %s", wrapper, name);
    if( wrapper && name ) {
        int nArgs = lua_gettop(L);
        NSMutableArray *arr = [NSMutableArray arrayWithCapacity:nArgs];
        for( int i = 1; i <= nArgs; ++i ) {
            id obj = toObjC(L, i);
            if( obj )
                [arr addObject:obj];
            else
                [arr addObject:[NSNull null]];
        }
        LuaExportMetaData *ed = (__bridge LuaExportMetaData*)wrapper->exportData;
		@try {
			id obj = (__bridge id)wrapper->instance;
			id result = [ed callMethod:name withArgs:arr onInstance:obj];
			id context = (__bridge id)wrapper->context;
			return [context fromObjC:result] ? 1 : 0;
		}
		@catch (NSException *e) {
			//NSLog(@"%d: exception thrown while calling method '%s': %@", luaGetLine(L, 0), name, e);
			lua_pushfstring(L, "%d: exception thrown while calling method '%s': %s", luaGetLine(L, 0), name, [[e description] UTF8String]);
			lua_error(L);
		}
    }

    return 0;
}

int luaWrapperIndex(lua_State *L) {
    LuaWrapperObject *wrapper = (LuaWrapperObject*)luaL_checkudata(L, 1, LuaWrapperObjectMetatableName);
    const char *name = luaL_checkstring(L, 2);
    //NSLog(@"getting index for %p - %s", wrapper, name);
    if( wrapper && name ) {
        LuaExportMetaData *ed = (__bridge LuaExportMetaData*)wrapper->exportData;
        id obj = (__bridge id)wrapper->instance;
        if( [ed canReadProperty:name] ) {
            //NSLog(@"  is readable property");
            id result = [ed getProperty:name onInstance:obj];
            id context = (__bridge id)wrapper->context;
            [context fromObjC:result];
            return 1;
        }
        else if( [ed canCallMethod:name] ) {
            //NSLog(@"  is callable method");
            lua_pushlightuserdata(L, wrapper);
            lua_pushstring(L, name);
            lua_pushcclosure(L, callMethod, 2);
            return 1;
        }
        else
            lua_pushfstring(L, "%d: unable to find method or property '%s'", luaGetLine(L, 0), name);
    }
    else
        lua_pushfstring(L, "%d: missing object wrapper for method or property '%s'", luaGetLine(L, 0), name);

    //NSLog(@"  failed");
    lua_error(L);
    return 0;
}

int luaWrapperNewIndex(lua_State *L) {
    LuaWrapperObject *wrapper = (LuaWrapperObject*)luaL_checkudata(L, 1, LuaWrapperObjectMetatableName);
    const char *name = luaL_checkstring(L, 2);
    id object = toObjC(L, 3);
    //NSLog(@"setting index for %p - %s to '%@'", wrapper, name, [object description]);
    if( wrapper && name ) {
        LuaExportMetaData *ed = (__bridge LuaExportMetaData*)wrapper->exportData;
        if( [ed canWriteProperty:name] ) {
            //NSLog(@"  is writable property");
            @try {
                id obj = (__bridge id)wrapper->instance;
                [ed setProperty:name toValue:object onInstance:obj];
                return 0;
            }
            @catch (NSException *e) {
                //NSLog(@"%d: exception thrown while setting property '%s': %@", luaGetLine(L, 0), name, e);
                lua_pushfstring(L, "%d: exception thrown while setting property '%s': %s", luaGetLine(L, 0), name, [[e description] UTF8String]);
            }
        }
        else {
            //NSLog(@"%d: unable to set property '%s'", luaGetLine(L, 0), name);
            lua_pushfstring(L, "%d: unable to set property '%s'", luaGetLine(L, 0),name);
        }
    }
    else {
        //NSLog(@"%d: missing object wrapper for property '%s'", luaGetLine(L, 0), name);
        lua_pushfstring(L, "%d: missing object wrapper for property '%s'", luaGetLine(L, 0),name);
    }

    lua_error(L);
    return 0;
}

int luaWrapperGC(lua_State *L) {
    LuaWrapperObject *wrapper = (LuaWrapperObject*)luaL_checkudata(L, 1, LuaWrapperObjectMetatableName);
    if( wrapper ) {
        id object = (__bridge_transfer id)wrapper->instance;
        id exportData = (__bridge_transfer id)wrapper->exportData;
        object = nil;
        exportData = nil;
        return 0;
    }
    else {
        //NSLog("missing object wrapper for disposed object");
        lua_pushfstring(L, "%d: missing object wrapper for disposed object", luaGetLine(L, 0));
    }

    lua_error(L);
    return 0;
}

int luaWrapperCall(lua_State *L) {
    LuaWrapperObject *wrapper = (LuaWrapperObject*)luaL_checkudata(L, 1, LuaWrapperObjectMetatableName);
    if( wrapper ) {
        id object = (__bridge id)wrapper->instance;
        if( [object isKindOfClass:[^{} class]] ) {
            int nArgs = lua_gettop(L)-1; // -1 becouse of the block wrapper
            NSMutableArray *arr = [NSMutableArray arrayWithCapacity:nArgs];
            for( int i = 1; i <= nArgs; ++i ) {
                id obj = toObjC(L, 1+i); // block wrapper is 1
                if( obj )
                    [arr addObject:obj];
                else
                    [arr addObject:[NSNull null]];
            }
            LuaExportBlockMetaData *ed = (__bridge LuaExportBlockMetaData*)wrapper->exportData;
			@try {
				id obj = (__bridge id)wrapper->instance;
				id result = [ed callWithArgs:arr onInstance:obj];
				id context = (__bridge id)wrapper->context;
				return [context fromObjC:result] ? 1 : 0;
			}
			@catch (NSException *e) {
				//NSLog(@"%d: exception thrown while calling block: %@", luaGetLine(L, 0), e);
				lua_pushfstring(L, "%d: exception thrown while calling block: %s", luaGetLine(L, 0), [[e description] UTF8String]);
			}
        }
        else {
            //NSLog(@"%d: called object is not a block", luaGetLine(L, 0));
            lua_pushfstring(L, "%d: called object is not a block", luaGetLine(L, 0));
        }
    }
    else {
        //NSLog(@"%d: missing object wrapper for called object", luaGetLine(L, 0));
        lua_pushfstring(L, "%d: missing object wrapper for called object", luaGetLine(L, 0));
    }

    lua_error(L);
    return 0;
}

static int luaDumpVar(lua_State *L) {
    int nArgs = lua_gettop(L);
    NSMutableString *result = [NSMutableString string];
    for( int i = 1; i <= nArgs; ++i ) {
        id obj = toObjC(L, i);
        [result appendFormat:@"%@", [obj description]];
    }
    lua_pushstring(L, [result UTF8String]);
    return 1;
}