#import "CameraLiveNative.h"
#import <Syphon/SyphonMetalServer.h>
#import <Syphon/SyphonMetalClient.h>
#import <Syphon/SyphonServerDirectory.h>

@implementation CLSyphonPublisher { SyphonMetalServer *_server; }
- (instancetype)initWithName:(NSString *)name device:(id<MTLDevice>)device {
    if ((self = [super init])) {
        _server = [[SyphonMetalServer alloc] initWithName:name device:device options:nil];
        if (!_server) return nil;
    }
    return self;
}
- (BOOL)hasClients { return _server.hasClients; }
- (void)publishTexture:(id<MTLTexture>)texture commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    [_server publishFrameTexture:texture onCommandBuffer:commandBuffer
                     imageRegion:NSMakeRect(0, 0, texture.width, texture.height) flipped:NO];
}
- (void)stop { [_server stop]; _server = nil; }
- (void)dealloc { [self stop]; }
@end

@implementation CLSyphonReceiver { SyphonMetalClient *_client; }
- (instancetype)initWithServerName:(NSString *)name device:(id<MTLDevice>)device {
    if ((self = [super init])) {
        NSDictionary *description = [[[SyphonServerDirectory sharedDirectory] serversMatchingName:name appName:nil] firstObject];
        if (!description) return nil;
        _client = [[SyphonMetalClient alloc] initWithServerDescription:description device:device options:nil newFrameHandler:nil];
        if (!_client) return nil;
    }
    return self;
}
- (BOOL)hasNewFrame { return _client.hasNewFrame; }
- (id<MTLTexture>)newFrame { return [_client newFrameImage]; }
- (void)stop { [_client stop]; _client = nil; }
- (void)dealloc { [self stop]; }
@end
