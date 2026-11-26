// Мост к MediaRemote: на macOS 15.4+ данные «Сейчас играет» отдаются только процессам Apple,
// поэтому библиотеку загружает системный /usr/bin/perl (у него есть нужное право).
// Вывод — JSON-строки в stdout; команды читаются из stdin: "cmd N", "seek T".
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#include <dlfcn.h>
#include <CommonCrypto/CommonDigest.h>

typedef void (*GetInfoFn)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*GetPlayingFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*GetPIDFn)(dispatch_queue_t, void (^)(int));
typedef void (*RegisterFn)(dispatch_queue_t);
typedef Boolean (*SendFn)(int, CFDictionaryRef);
typedef void (*SetTimeFn)(double);

static GetInfoFn getInfo; static GetPlayingFn getPlaying; static GetPIDFn getPID;
static RegisterFn reg; static SendFn sendCmd; static SetTimeFn setTime;
static NSString *lastArt = @"";
static NSString *lastLine = @"";
static dispatch_queue_t q;

static void emit(void) {
    getPID(q, ^(int pid) {
        getPlaying(q, ^(Boolean playing) {
            getInfo(q, ^(CFDictionaryRef ref) {
                NSDictionary *d = (__bridge NSDictionary *)ref;
                NSMutableDictionary *o = [NSMutableDictionary dictionary];
                o[@"playing"] = @(playing);
                NSRunningApplication *app = pid > 0 ? [NSRunningApplication runningApplicationWithProcessIdentifier:pid] : nil;
                if (app.bundleIdentifier) o[@"bundle"] = app.bundleIdentifier;
                if (app.localizedName) o[@"app"] = app.localizedName;
                if (d) {
                    id v;
                    if ((v = d[@"kMRMediaRemoteNowPlayingInfoTitle"])) o[@"title"] = v;
                    if ((v = d[@"kMRMediaRemoteNowPlayingInfoArtist"])) o[@"artist"] = v;
                    if ((v = d[@"kMRMediaRemoteNowPlayingInfoAlbum"])) o[@"album"] = v;
                    if ((v = d[@"kMRMediaRemoteNowPlayingInfoDuration"])) o[@"duration"] = v;
                    if ((v = d[@"kMRMediaRemoteNowPlayingInfoElapsedTime"])) o[@"elapsed"] = v;
                    if ((v = d[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"])) o[@"rate"] = v;
                    NSDate *ts = d[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
                    if ([ts isKindOfClass:NSDate.class]) o[@"ts"] = @(ts.timeIntervalSince1970);
                    NSData *art = d[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
                    if ([art isKindOfClass:NSData.class] && art.length) {
                        unsigned char h[CC_MD5_DIGEST_LENGTH];
                        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
                        CC_MD5(art.bytes, (CC_LONG)art.length, h);
                        NSString *key = [NSString stringWithFormat:@"%02x%02x%02x%02x%02x%02x%02x%02x", h[0],h[1],h[2],h[3],h[4],h[5],h[6],h[7]];
                        o[@"artId"] = key;
                        if (![key isEqualToString:lastArt]) { lastArt = key; o[@"art"] = [art base64EncodedStringWithOptions:0]; }
                    }
                }
                NSData *j = [NSJSONSerialization dataWithJSONObject:o options:0 error:nil];
                if (!j) return;
                NSString *line = [[NSString alloc] initWithData:j encoding:NSUTF8StringEncoding];
                if ([line isEqualToString:lastLine]) return;
                lastLine = line;
                fprintf(stdout, "%s\n", line.UTF8String); fflush(stdout);
            });
        });
    });
}

void nd_main(void *a, void *b) {
    void *mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!mr) { fprintf(stdout, "{\"error\":\"no MediaRemote\"}\n"); fflush(stdout); exit(2); }
    getInfo = dlsym(mr, "MRMediaRemoteGetNowPlayingInfo");
    getPlaying = dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    getPID = dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationPID");
    reg = dlsym(mr, "MRMediaRemoteRegisterForNowPlayingNotifications");
    sendCmd = dlsym(mr, "MRMediaRemoteSendCommand");
    setTime = dlsym(mr, "MRMediaRemoteSetElapsedTime");
    q = dispatch_queue_create("nd.np", DISPATCH_QUEUE_SERIAL);
    reg(q);
    for (NSString *n in @[@"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                          @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                          @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
                          @"kMRMediaRemoteNowPlayingPlaybackQueueChangedNotification"]) {
        [NSNotificationCenter.defaultCenter addObserverForName:n object:nil queue:nil usingBlock:^(NSNotification *x) { emit(); }];
    }
    emit();
    // Страховка: раз в секунду (дешёвый запрос; одинаковые строки не печатаются)
    dispatch_source_t t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q);
    dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), NSEC_PER_SEC, 200 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(t, ^{ emit(); });
    dispatch_resume(t);
    // Команды из stdin; конец stdin (приложение закрылось) — выходим
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        char buf[256];
        while (fgets(buf, sizeof buf, stdin)) {
            int c; double s;
            if (strncmp(buf, "art", 3) == 0) { dispatch_sync(q, ^{ lastArt = @""; lastLine = @""; }); }
            else if (sscanf(buf, "cmd %d", &c) == 1) sendCmd(c, NULL);
            else if (sscanf(buf, "seek %lf", &s) == 1) {
                // 24 = SeekToPlaybackPosition — понимают браузеры, Spotify, Музыка; старый SetElapsedTime — запасной
                NSDictionary *opt = @{@"kMRMediaRemoteOptionPlaybackPosition": @(s)};
                if (!sendCmd(24, (__bridge CFDictionaryRef)opt) && setTime) setTime(s);
            }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), q, ^{ emit(); });
        }
        exit(0);
    });
    CFRunLoopRun();
}
