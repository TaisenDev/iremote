#import "IRPhoneStore.h"
#import <Security/Security.h>

NSData *IRFingerprint(NSString *value) {
    value = [[value stringByReplacingOccurrencesOfString:@"-" withString:@""]
             stringByReplacingOccurrencesOfString:@" " withString:@""];
    if (value.length != 24 ||
        [value rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] invertedSet]].location != NSNotFound)
        return nil;
    NSMutableData *result = [NSMutableData dataWithCapacity:12];
    for (NSUInteger index = 0; index < value.length; index += 2) {
        uint8_t byte = (uint8_t)strtoul([[value substringWithRange:NSMakeRange(index, 2)] UTF8String], NULL, 16);
        [result appendBytes:&byte length:1];
    }
    return result;
}

static NSDictionary *IRDeviceQuery(void) {
    return @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
             (__bridge id)kSecAttrService: @"com.taisendev.iremote",
             (__bridge id)kSecAttrAccount: @"paired-device"};
}
NSDictionary *IRSavedDevice(void) {
    NSMutableDictionary *query = [IRDeviceQuery() mutableCopy];
    query[(__bridge id)kSecReturnData] = @YES;
    CFTypeRef found = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &found) != errSecSuccess) return nil;
    NSData *data = CFBridgingRelease(found);
    id plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL];
    return [plist isKindOfClass:[NSDictionary class]] ? plist : nil;
}
BOOL IRSaveDevice(NSDictionary *device) {
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:device format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
    if (!data) return NO;
    NSDictionary *update = @{(__bridge id)kSecValueData: data};
    OSStatus existing = SecItemUpdate((__bridge CFDictionaryRef)IRDeviceQuery(), (__bridge CFDictionaryRef)update);
    if (existing == errSecSuccess) return YES;
    if (existing != errSecItemNotFound) return NO;
    NSMutableDictionary *item = [IRDeviceQuery() mutableCopy];
    [item addEntriesFromDictionary:update];
    item[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly;
    return SecItemAdd((__bridge CFDictionaryRef)item, NULL) == errSecSuccess;
}
BOOL IRForgetDevice(void) {
    OSStatus result = SecItemDelete((__bridge CFDictionaryRef)IRDeviceQuery());
    return result == errSecSuccess || result == errSecItemNotFound;
}
