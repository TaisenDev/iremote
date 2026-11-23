#import <UIKit/UIKit.h>

typedef NS_ENUM(uint8_t, IRCommand) {
    IRResume = 1, IRPair, IRFrame, IRPointer, IRScroll, IRText, IRKey,
    IRReady = 64, IRPicture, IRRefused, IRStill
};

BOOL IRIsPrivateIPv4(NSString *address);

@interface IRSession : NSObject
@property (nonatomic, copy) void (^onReady)(NSData *newToken);
@property (nonatomic, copy) void (^onFrame)(UIImage *frame);
@property (nonatomic, copy) void (^onFailure)(NSString *reason, BOOL retryable);
- (void)startAt:(NSString *)address port:(uint16_t)port fingerprint:(NSData *)fingerprint
      credential:(NSData *)credential pairing:(BOOL)pairing;
- (void)send:(IRCommand)command data:(NSData *)data;
- (void)stop;
@end
