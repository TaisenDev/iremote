#import "IRSession.h"
#import <Security/Security.h>
#import <Security/SecureTransport.h>
#import <CommonCrypto/CommonDigest.h>
#import <QuartzCore/QuartzCore.h>
#import <ImageIO/ImageIO.h>
#import <arpa/inet.h>
#import <errno.h>
#import <fcntl.h>
#import <netinet/tcp.h>
#import <sys/socket.h>
#import <poll.h>
#import <unistd.h>

typedef struct {
    int socket;
    CFTimeInterval deadline;
} IRChannel;

BOOL IRIsPrivateIPv4(NSString *address) {
    if (!address.length) return NO;
    struct in_addr parsed;
    if (inet_pton(AF_INET, address.UTF8String, &parsed) != 1) return NO;
    uint32_t value = ntohl(parsed.s_addr);
    return (value >> 24) == 10 || (value >> 20) == 0xac1 || (value >> 16) == 0xc0a8;
}

static int IRConnect(NSString *address, uint16_t port) {
    int fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (fd < 0) return -1;
    struct sockaddr_in target = {0};
    target.sin_len = sizeof(target);
    target.sin_family = AF_INET;
    target.sin_port = htons(port);
    inet_pton(AF_INET, address.UTF8String, &target.sin_addr);
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags == -1 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) == -1) { close(fd); return -1; }
    if (connect(fd, (struct sockaddr *)&target, sizeof(target)) != 0) {
        struct pollfd watched = {fd, POLLOUT, 0};
        int error = 0;
        socklen_t size = sizeof(error);
        if (errno != EINPROGRESS || poll(&watched, 1, 3500) <= 0 ||
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &size) != 0 || error != 0) {
            close(fd);
            return -1;
        }
    }
    return fd;
}

static OSStatus IRTransfer(SSLConnectionRef connection, void *bytes, size_t *length, BOOL sending) {
    IRChannel *channel = (IRChannel *)connection;
    size_t requested = *length;
    *length = 0;
    while (*length < requested) {
        int remaining = (int)((channel->deadline - CACurrentMediaTime()) * 1000);
        if (remaining <= 0) return errSSLClosedAbort;
        struct pollfd watched = {channel->socket, sending ? POLLOUT : POLLIN, 0};
        int ready = poll(&watched, 1, remaining);
        if (ready < 0 && errno == EINTR) continue;
        if (ready <= 0) return errSSLClosedAbort;
        char *next = (char *)bytes + *length;
        ssize_t amount = sending
            ? send(channel->socket, next, requested - *length, 0)
            : recv(channel->socket, next, requested - *length, 0);
        if (amount < 0 && (errno == EINTR || errno == EWOULDBLOCK)) continue;
        if (amount < 0) return errSSLClosedAbort;
        if (amount == 0) return errSSLClosedGraceful;
        *length += amount;
    }
    return noErr;
}

static OSStatus IRRead(SSLConnectionRef context, void *bytes, size_t *length) {
    return IRTransfer(context, bytes, length, NO);
}

static OSStatus IRWrite(SSLConnectionRef context, const void *bytes, size_t *length) {
    return IRTransfer(context, (void *)bytes, length, YES);
}

static BOOL IRPinMatches(SSLContextRef tls, NSData *expected) {
    SecTrustRef trust = NULL;
    if (SSLCopyPeerTrust(tls, &trust) != noErr || !trust) return NO;
    SecCertificateRef leaf = SecTrustGetCertificateAtIndex(trust, 0);
    NSData *der = leaf ? CFBridgingRelease(SecCertificateCopyData(leaf)) : nil;
    CFRelease(trust);
    if (!der || expected.length != 12) return NO;
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(der.bytes, (CC_LONG)der.length, hash);
    const unsigned char *pin = expected.bytes;
    unsigned char difference = 0;
    for (NSUInteger index = 0; index < expected.length; index++) difference |= hash[index] ^ pin[index];
    return difference == 0;
}

static BOOL IRReadExactly(SSLContextRef tls, void *bytes, size_t length) {
    for (size_t offset = 0; offset < length;) {
        size_t amount = 0;
        OSStatus result = SSLRead(tls, (char *)bytes + offset, length - offset, &amount);
        offset += amount;
        if ((result != noErr && result != errSSLWouldBlock) || amount == 0) return NO;
    }
    return YES;
}

static UIImage *IRDecode(NSData *data) {
    if (!data.length) return nil;
    NSDictionary *options = @{(NSString *)kCGImageSourceShouldCache: @YES};
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!source) return nil;
    NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
    NSInteger width = [properties[(NSString *)kCGImagePropertyPixelWidth] integerValue];
    NSInteger height = [properties[(NSString *)kCGImagePropertyPixelHeight] integerValue];
    CGImageRef decoded = width > 0 && width <= 1024 && height > 0 && height <= 768
        ? CGImageSourceCreateImageAtIndex(source, 0, (__bridge CFDictionaryRef)options) : NULL;
    UIImage *result = decoded ? [UIImage imageWithCGImage:decoded] : nil;
    if (decoded) CGImageRelease(decoded);
    CFRelease(source);
    return result;
}

@implementation IRSession {
    dispatch_queue_t _work;
    SSLContextRef _tls;
    IRChannel _channel;
    BOOL _authenticated;
    BOOL _stopped;
    NSUInteger _pending;
}
- (instancetype)init {
    if ((self = [super init])) {
        _work = dispatch_queue_create("iremote.session", DISPATCH_QUEUE_SERIAL);
        _channel.socket = -1;
    }
    return self;
}
- (void)dealloc { [self closeChannel]; }
- (void)closeChannel {
    _authenticated = NO;
    if (_tls) { CFRelease(_tls); _tls = NULL; }
    if (_channel.socket >= 0) { close(_channel.socket); _channel.socket = -1; }
}
- (void)stop {
    @synchronized (self) { _stopped = YES; }
    dispatch_async(_work, ^{ [self closeChannel]; });
}
- (BOOL)stopped {
    @synchronized (self) { return _stopped; }
}
- (void)fail:(NSString *)reason retryable:(BOOL)retryable {
    [self closeChannel];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![self stopped] && self.onFailure) self.onFailure(reason, retryable);
    });
}
- (BOOL)write:(IRCommand)type body:(NSData *)data {
    _channel.deadline = CACurrentMediaTime() + 4;
    NSUInteger count = data.length;
    uint8_t header[] = {type, count >> 24, count >> 16, count >> 8, count};
    NSMutableData *message = [NSMutableData dataWithBytes:header length:sizeof(header)];
    if (count) [message appendData:data];
    size_t sent = 0;
    return SSLWrite(_tls, message.bytes, message.length, &sent) == noErr && sent == message.length;
}
- (NSData *)readType:(IRCommand *)type maximum:(NSUInteger)limit {
    _channel.deadline = CACurrentMediaTime() + 4;
    uint8_t header[5];
    if (!IRReadExactly(_tls, header, sizeof(header))) return nil;
    uint32_t size = (uint32_t)header[1] << 24 | (uint32_t)header[2] << 16 | (uint32_t)header[3] << 8 | header[4];
    if (size > limit) return nil;
    *type = header[0];
    NSMutableData *data = [NSMutableData dataWithLength:size];
    return size == 0 || IRReadExactly(_tls, data.mutableBytes, size) ? data : nil;
}
- (void)startAt:(NSString *)address port:(uint16_t)port fingerprint:(NSData *)fingerprint
      credential:(NSData *)credential pairing:(BOOL)pairing {
    dispatch_async(_work, ^{
        if ([self stopped]) return;
        if (!IRIsPrivateIPv4(address)) {
            [self fail:@"Usa la dirección IPv4 local que muestra la PC." retryable:NO]; return;
        }
        _channel.socket = IRConnect(address, port);
        if (_channel.socket < 0) {
            [self fail:@"La PC no responde. Comprueba la red y el receptor." retryable:YES]; return;
        }
        _tls = SSLCreateContext(kCFAllocatorDefault, kSSLClientSide, kSSLStreamType);
        if (!_tls || SSLSetIOFuncs(_tls, IRRead, IRWrite) != noErr ||
            SSLSetConnection(_tls, &_channel) != noErr ||
            SSLSetProtocolVersionMin(_tls, kTLSProtocol12) != noErr ||
            SSLSetProtocolVersionMax(_tls, kTLSProtocol12) != noErr ||
            SSLSetSessionOption(_tls, kSSLSessionOptionBreakOnServerAuth, true) != noErr) {
            [self fail:@"No se pudo preparar TLS 1.2." retryable:NO]; return;
        }
        _channel.deadline = CACurrentMediaTime() + 5;
        OSStatus hello = SSLHandshake(_tls);
        if (hello != errSSLServerAuthCompleted) {
            [self fail:@"Falló la negociación TLS con la PC." retryable:YES]; return;
        }
        if (!IRPinMatches(_tls, fingerprint)) {
            [self fail:@"La huella de la PC cambió. Compruébala antes de volver a emparejar." retryable:NO]; return;
        }
        if (SSLHandshake(_tls) != noErr || ![self write:pairing ? IRPair : IRResume body:credential]) {
            [self fail:@"Se interrumpió la conexión cifrada." retryable:YES]; return;
        }
        IRCommand reply;
        NSData *payload = [self readType:&reply maximum:32];
        if (!payload) {
            [self fail:@"La PC interrumpió la autenticación." retryable:YES]; return;
        }
        if (reply != IRReady || payload.length != (pairing ? 32 : 0)) {
            [self fail:@"Credencial rechazada. Genera un código en el receptor." retryable:NO]; return;
        }
        _authenticated = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![self stopped] && self.onReady) self.onReady(payload);
        });
        [self requestFrame];
    });
}
- (void)requestFrame {
    if (!_authenticated || [self stopped]) return;
    @autoreleasepool {
        CFTimeInterval start = CACurrentMediaTime();
        IRCommand type = 0;
        NSData *data = [self write:IRFrame body:nil] ? [self readType:&type maximum:1024 * 1024] : nil;
        UIImage *frame = type == IRPicture ? IRDecode(data) : nil;
        if (!data || !(frame || (type == IRStill && data.length == 0))) {
            [self fail:@"Se perdió la conexión con la PC." retryable:YES]; return;
        }
        CFTimeInterval delay = MAX(0.0, (frame ? 0.105 : 0.22) - (CACurrentMediaTime() - start));
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self stopped]) return;
            if (frame && self.onFrame) self.onFrame(frame);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delay * NSEC_PER_SEC), _work, ^{ [self requestFrame]; });
        });
    }
}
- (void)send:(IRCommand)command data:(NSData *)data {
    if (data.length > 4096 || [self stopped]) return;
    @synchronized (self) {
        if (_pending >= 96 && command == IRPointer && data.length == 5 &&
            ((const uint8_t *)data.bytes)[4] == 0) return;
        if (_pending >= 192) {
            [self stop];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.onFailure) self.onFailure(@"La red no pudo seguir el ritmo de los controles.", YES);
            });
            return;
        }
        _pending++;
    }
    dispatch_async(_work, ^{
        @synchronized (self) { _pending--; }
        if (_authenticated && ![self stopped] && ![self write:command body:data])
            [self fail:@"Se perdió la conexión con la PC." retryable:YES];
    });
}
@end
