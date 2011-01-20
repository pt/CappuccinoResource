@import <Foundation/CPObject.j>
@import "CRSupport.j"

var defaultIdentifierKey = @"id",
    classAttributeNames  = [CPDictionary dictionary],
    resourcePrefixes = [CPDictionary dictionary];

@implementation CappuccinoResource : CPObject
{
    CPString identifier @accessors;
}

+(CPString)setResourcePrefix:(CPString)aResourcePrefix {
  [resourcePrefixes setObject:aResourcePrefix forKey:[self className]]
}
+(CPString)resourcePrefix {
  if(![resourcePrefixes objectForKey:[self className]]){
    return ""
  }
  return [resourcePrefixes objectForKey:[self className]];
}


// override this method to use a custom identifier for lookups
+ (CPString)identifierKey
{
    return defaultIdentifierKey;
}

// this provides very, very basic pluralization (adding an 's').
// override this method for more complex inflections
+ (CPURL)resourcePath
{
    return [CPURL URLWithString: [self resourcePrefix] + @"/" + [self railsName] + @"s"];
}


+ (CPString)railsName
{
    return [[self className] railsifiedString];
}

- (JSObject)attributes
{
    CPLog.warn('This method must be declared in your class to save properly.');
    return {};
}

-(void)resourceHasLoaded {
}

- (CPArray)attributeNames
{
    if ([classAttributeNames objectForKey:[self className]]) {
        return [classAttributeNames objectForKey:[self className]];
    }

    var attributeNames = [CPArray array],
        attributes     = class_copyIvarList([self class]);
    for (var i = 0; i < attributes.length; i++) {
        [attributeNames addObject:attributes[i].name];
    }

    [classAttributeNames setObject:attributeNames forKey:[self className]];

    return attributeNames;
}

- (void)setAttributes:(JSObject)attributes
{
    for (var attribute in attributes) {
        if (attribute == [[self class] identifierKey]) {
            [self setIdentifier:attributes[attribute].toString()];
        } else {
            var attributeName = [attribute cappifiedString];
            if ([[self attributeNames] containsObject:attributeName]) {
                var value = attributes[attribute];
                  if(value != null) {
                    /*
                     * I would much rather retrieve the ivar class than pattern match the
                     * response from Rails, but objective-j does not support this.
                    */
                    switch (typeof value) {
                        case "boolean":
                            if (value) {
                                [self setValue:YES forKey:attributeName];
                            } else {
                                [self setValue:NO forKey:attributeName];
                            }
                            break;
                        case "number":
                            [self setValue:value forKey:attributeName];
                            break;
                        case "string":
                            if (value.match(/^\d{4}-\d{2}-\d{2}$/)) {
                                // its a date
                                [self setValue:[CPDate dateWithDateString:value] forKey:attributeName];
                            } else if (value.match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/)) {
                                // its a datetime
                                [self setValue:[CPDate dateWithDateTimeString:value] forKey:attributeName];
                            } else {
                                // its a string
                                [self setValue:value forKey:attributeName];
                            }
                            break;
                        case "object":
                           // array
                           if (value.length != null) {
                                var includedClass = objj_getClass([attribute classifiedString]);

                                if (includedClass != null) {
                                    var included = [];
                                    for (var i = 0; i < value.length; i++) {
                                        var newObject;
                                        var nestedValue = [value objectAtIndex:i];
                                        // In Test the nested attribute hashes can be strings
                                        if (typeof nestedValue == "string") {
                                            newObject = [includedClass new:JSON.parse(nestedValue)]
                                        } else {
                                            newObject = [includedClass new:nestedValue]
                                        }
                                        [included addObject:newObject]
                                    }
                                    [self setValue:included forKey:attributeName];
                                } else {
                                    [self setValue:value forKey:attributeName];
                                }
                           } else {
                                [self setValue:[objj_getClass([attribute classifiedString]) new:value] forKey:attributeName];
                           }
                           break;
                    }
                }
            }
        }
    }
}

+ (id)new
{
    return [self new:nil];
}

+ (id)new:(JSObject)attributes
{
    var resource = [[self alloc] init];

    if (!attributes)
        attributes = {};

    [resource setAttributes:attributes];
    return resource;
}

+ (id)create:(JSObject)attributes
{
    var resource = [self new:attributes];
    if ([resource save]) {
        return resource;
    } else {
        return nil;
    }
}

- (BOOL)save
{
    var request = [self resourceWillSave];

    if (!request) {
        return NO;
    }
    var response = [CPURLConnection sendSynchronousRequest:request];
    if (response[0] == 409){
        [self resourceDidNotSaveConflicted:response[1]];
        return NO;
    } else if (response[0] >= 400) {
        [self resourceDidNotSave:response[1]];
        return NO;
    } else {
        [self resourceDidSave:response[1]];
        return YES;
    }
}

- (BOOL)destroy
{
    var request = [self resourceWillDestroy];

    if (!request) {
        return NO;
    }

    var response = [CPURLConnection sendSynchronousRequest:request];

    if (response[0] == 200) {
        [self resourceDidDestroy];
        return YES;
    } else {
        return NO;
    }
}

+ (CPArray)all
{
    var request = [self collectionWillLoad];

    if (!request) {
        return NO;
    }

    var response = [CPURLConnection sendSynchronousRequest:request];
    if (response[0] >= 400) {
        return nil;
    } else {
        return [self collectionDidLoad:response[1]];
    }
}

+ (CPArray)allWithParams:(JSObject)params
{
    var request = [self collectionWillLoad:params];

    var response = [CPURLConnection sendSynchronousRequest:request];

    if (response[0] >= 400) {
        return nil;
    } else {
        return [self collectionDidLoad:response[1]];
    }
}

+ (id)find:(CPString)identifier
{
    var request = [self resourceWillLoad:identifier];

    if (!request) {
        return NO;
    }

    var response = [CPURLConnection sendSynchronousRequest:request];

    if (response[0] >= 400) {
        return nil;
    } else {
        return [self resourceDidLoad:response[1]];
    }
}

+ (id)findWithParams:(JSObject)params
{
    var collection = [self allWithParams:params];
    return [collection objectAtIndex:0];
}

// All the following methods post notifications using their class name
// You can observe these notifications and take further action if desired
+ (CPURLRequest)resourceWillLoad:(CPString)identifier
{
    var path             = [self resourcePath] + "/" + identifier,
        notificationName = [self className] + "ResourceWillLoad";

    if (!path) {
        return nil;
    }

    var request = [CPURLRequest requestJSONWithURL:path];
    [request setHTTPMethod:@"GET"];

    [[CPNotificationCenter defaultCenter] postNotificationName:notificationName object:self];
    return request;
}

+ (id)resourceDidLoad:(CPString)aResponse
{
    var attributes = [aResponse toJSON]
    // var attributes       = response[[self railsName]]

    var klass;
    if(attributes['type']) {
      klass = attributes['type']
    }else{
      klass = [self className]
    }

    //todo support STI in notifications
    var notificationName = [self className] + "ResourceDidLoad"
    var resource         = [objj_getClass(klass) new];

    [resource setAttributes:attributes];
    [resource resourceHasLoaded]
    [[CPNotificationCenter defaultCenter] postNotificationName:notificationName object:self];
    return resource;
}

+ (CPURLRequest)collectionWillLoad
{
    return [self collectionWillLoad:nil];
}

// can handle a JSObject or a CPDictionary
+ (CPURLRequest)collectionWillLoad:(id)params
{
    var path             = [self resourcePath],
        notificationName = [self className] + "CollectionWillLoad";

    if (params) {
        if (params.isa && [params isKindOfClass:CPDictionary]) {
            path += ("?" + [CPString paramaterStringFromCPDictionary:params]);
        } else {
            path += ("?" + [CPString paramaterStringFromJSON:params]);
        }
    }

    if (!path) {
        return nil;
    }

    var request = [CPURLRequest requestJSONWithURL:path];
    [request setHTTPMethod:@"GET"];

    [[CPNotificationCenter defaultCenter] postNotificationName:notificationName object:self];

    return request;
}

+ (CPArray)collectionDidLoad:(CPString)aResponse
{
	var	 json = [aResponse toJSON];
	promote_JSON_to_CPObjects(json, self);
	[[CPNotificationCenter defaultCenter] postNotificationName:[self className]+'CollectionDidLoad' object:self];
	return json;
}

- (CPURLRequest)resourceWillSave
{
    var abstractNotificationName = [self className] + "ResourceWillSave";

    if (identifier) {
        var path             = [[self class] resourcePath] + "/" + identifier,
            notificationName = [self className] + "ResourceWillUpdate";
    } else {
        var path             = [[self class] resourcePath],
            notificationName = [self className] + "ResourceWillCreate";
    }

    if (!path) {
        return nil;
    }

    var request = [CPURLRequest requestJSONWithURL:path];

    [request setHTTPMethod:identifier ? @"PUT" : @"POST"];
    [request setHTTPBody:[CPString JSONFromObject:[self attributes]]];

    [[CPNotificationCenter defaultCenter] postNotificationName:notificationName object:self];
    [[CPNotificationCenter defaultCenter] postNotificationName:abstractNotificationName object:self];
    return request;
}

//todo test
- (CPString)toJSON{
  return [CPString JSONFromObject:[self attributes]];
}


- (void)resourceDidSave:(CPString)aResponse
{
    var attributes               = [aResponse toJSON];
    // var attributes               = response[[[self class] railsName]]
    var abstractNotificationName = [self className] + "ResourceDidSave";

    if (identifier) {
        var notificationName = [self className] + "ResourceDidUpdate";
    } else {
        var notificationName = [self className] + "ResourceDidCreate";
    }

    [self setAttributes:attributes];
    [[CPNotificationCenter defaultCenter] postNotificationName:notificationName object:self];
    [[CPNotificationCenter defaultCenter] postNotificationName:abstractNotificationName object:self];
}

- (void)resourceDidNotSaveConflicted:(CPString)aResponse
{
    var abstractNotificationName = [self className] + "ResourceDidNotSaveConflicted";
    // TODO - do something with errors
    if (identifier) {
        var notificationName = [self className] + "ResourceDidNotUpdateConflicted";
    } else {
        var notificationName = [self className] + "ResourceDidNotCreateConflicted";
    }

    [[CPNotificationCenter defaultCenter] postNotificationName:notificationName object:self];
    [[CPNotificationCenter defaultCenter] postNotificationName:abstractNotificationName object:self];
}

- (void)resourceDidNotSave:(CPString)aResponse
{
    var abstractNotificationName = [self className] + "ResourceDidNotSave";

    // TODO - do something with errors
    if (identifier) {
        var notificationName = [self className] + "ResourceDidNotUpdate";
    } else {
        var notificationName = [self className] + "ResourceDidNotCreate";
    }

    [[CPNotificationCenter defaultCenter] postNotificationName:notificationName object:self];
    [[CPNotificationCenter defaultCenter] postNotificationName:abstractNotificationName object:self];
}

- (CPURLRequest)resourceWillDestroy
{
    var path             = [[self class] resourcePath] + "/" + identifier,
        notificationName = [self className] + "ResourceWillDestroy";

    if (!path) {
        return nil;
    }

    var request = [CPURLRequest requestJSONWithURL:path];
    [request setHTTPMethod:@"DELETE"];

    [[CPNotificationCenter defaultCenter] postNotificationName:notificationName object:self];
    return request;
}

-(void)resourceDidDestroy
{
    var notificationName = [self className] + "ResourceDidDestroy";
    [[CPNotificationCenter defaultCenter] postNotificationName:notificationName object:self];
}

-(BOOL)isEqual:(CappuccinoResource)other {
  return ([self class] == [other class] && [self identifier] == [other identifier])
}

-(BOOL)isNewRecord{
  return ([self identifier] == null ? YES : NO)
}

//todo only works one level :/
-(CPString)baseClassName {
  try {
  if( class_getName([self superclass]) == 'CappuccinoResource')
    return [self className]
  return [super baseClassName]
  }catch(e) {
    return class_getName([self superclass])
  }
}

-(CPString)toFlatJSON{
  for(var key in [self attributes]){
    return [CPString JSONFromObject:[self attributes][key]];
  }
}
@end

function promote_JSObject_to_CPObject(jsobject, klass) {
	jsobject.isa = klass;
	jsobject._UID = objj_generateObjectUID();
	
	while (klass) {
		var ivars = class_copyIvarList(klass);
		var i = 0, l = ivars.length;
		var ivarName;
	
		for (; i < l; i++) {
			ivarName = ivars[i].name;
			if (!(ivarName in jsobject)) {
				// Add a ivar slot of the object is missing it.
				jsobject[ivarName] = undefined; // add an ivar slot
			}
		}
		
		klass = klass.super_class;
	}
}

function promote_JSON_to_CPObjects(attributesArray, klass) {
	var attributesIndex = 0;
	var attributesLength = attributesArray.length;
	var attributes;
	
	for (; attributesIndex < attributesLength; attributesIndex++) {
		attributes = attributesArray[attributesIndex];
		promote_JSObject_to_CPObject(attributes, klass);
		for (var attribute in attributes) {
	        if (attribute == [klass identifierKey]) {
	            [attributes setIdentifier:attributes[attribute].toString()];
	        } else {	
				var value = attributes[attribute];
				
				// Rewrite slot name from rails_style into cappStyle.
				if (attribute != '_UID') {
					var attributeName = [attribute cappifiedString];
					if (attributeName !== attribute) {
						attributes[attributeName] = value;
						delete attributes[attribute];
					}
				}
				
				switch (typeof value) {
					case 'string':
						if (value.match(/^\d{4}-\d{2}-\d{2}$/)) {
                            // its a date
							attributes[attributeName] = [CPDate dateWithDateString:value];
                        } else if (value.match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/)) {
                            // its a datetime
							attributes[attributeName] = [CPDate dateWithDateTimeString:value];
                        }
						break;
					case 'object':
						// array
						if (value !== null && value.length) {
							var includedClass = objj_getClass([attribute classifiedString]);
							if (typeof value[0] == 'object') {
								promote_JSON_to_CPObjects(value, includedClass);
							}
						}
						break;
				}
	        }
	    }
		[attributes resourceHasLoaded];
	}
}