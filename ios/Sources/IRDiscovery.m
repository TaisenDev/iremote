#import "IRDiscovery.h"
#import "IRSession.h"
#import <QuartzCore/QuartzCore.h>
#import <Security/Security.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <poll.h>
#import <sys/socket.h>
#import <unistd.h>

static const uint16_t IRDiscoveryPort = 47921;

static NSString *IRSearch(NSData *fingerprint, NSString *lastAddress) {
    if (fingerprint.length != 12) return nil;
    uint8_t request[18] = {'I','R','L','A','N','1'};
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof(request) - 6, request + 6) != errSecSuccess) return nil;
    int fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (fd == -1) return nil;
    int enabled = 1;
    setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &enabled, sizeof(enabled));
    struct sockaddr_in target = {0};
    target.sin_len = sizeof(target);
    target.sin_family = AF_INET;
    target.sin_port = htons(IRDiscoveryPort);
    if (IRIsPrivateIPv4(lastAddress)) {
        inet_pton(AF_INET, lastAddress.UTF8String, &target.sin_addr);
        sendto(fd, request, sizeof(request), 0, (struct sockaddr *)&target, sizeof(target));
    }
    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) == 0) {
        for (struct ifaddrs *entry = interfaces; entry; entry = entry->ifa_next) {
            const unsigned int flags = IFF_UP | IFF_BROADCAST;
            if ((entry->ifa_flags & flags) != flags || !entry->ifa_addr || !entry->ifa_dstaddr ||
                entry->ifa_addr->sa_family != AF_INET || entry->ifa_dstaddr->sa_family != AF_INET) continue;
            struct sockaddr_in *broadcast = (struct sockaddr_in *)entry->ifa_dstaddr;
            target.sin_addr = broadcast->sin_addr;
            sendto(fd, request, sizeof(request), 0, (struct sockaddr *)&target, sizeof(target));
        }
        freeifaddrs(interfaces);
    }
    NSString *found = nil;
    CFTimeInterval expires = CACurrentMediaTime() + 1.0;
    while (!found) {
        int remaining = (int)((expires - CACurrentMediaTime()) * 1000);
        if (remaining <= 0) break;
        struct pollfd watched = {fd, POLLIN, 0};
        if (poll(&watched, 1, remaining) <= 0) break;
        uint8_t answer[33];
        struct sockaddr_in peer = {0};
        socklen_t length = sizeof(peer);
        ssize_t size = recvfrom(fd, answer, sizeof(answer), MSG_DONTWAIT, (struct sockaddr *)&peer, &length);
        if (size != 32 || peer.sin_family != AF_INET || ntohs(peer.sin_port) != IRDiscoveryPort ||
            memcmp(answer, request, sizeof(request)) || memcmp(answer + 20, fingerprint.bytes, 12))
            continue;
        uint16_t port = (uint16_t)answer[18] << 8 | answer[19];
        if (port != IRDiscoveryPort) continue;
        char buffer[INET_ADDRSTRLEN];
        if (!inet_ntop(AF_INET, &peer.sin_addr, buffer, sizeof(buffer))) continue;
        NSString *candidate = [NSString stringWithUTF8String:buffer];
        if (IRIsPrivateIPv4(candidate)) found = candidate;
    }
    close(fd);
    return found;
}

void IRFindHost(NSData *fingerprint, NSString *lastAddress, void (^completion)(NSString *address)) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *address = IRSearch(fingerprint, lastAddress);
        dispatch_async(dispatch_get_main_queue(), ^{ completion(address); });
    });
}
