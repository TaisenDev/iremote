#import <Foundation/Foundation.h>
void IRFindHost(NSData *fingerprint, NSString *lastAddress, void (^completion)(NSString *address, uint16_t port));
