#import <Foundation/Foundation.h>
NSData *IRFingerprint(NSString *value);
NSDictionary *IRSavedDevice(void);
BOOL IRSaveDevice(NSDictionary *device);
BOOL IRForgetDevice(void);
