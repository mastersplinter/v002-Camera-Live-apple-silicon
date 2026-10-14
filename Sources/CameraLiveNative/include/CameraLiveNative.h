#pragma once
#include <stddef.h>
#include <stdint.h>

typedef struct CLDeviceList CLDeviceList;
typedef struct CLSession CLSession;
typedef struct CLCancellation CLCancellation;

// Configure driver directories once, before enumeration or opening a camera.
void cl_configure_drivers(const char * _Nullable camlibs, const char * _Nullable iolibs);
int cl_list_devices(CLDeviceList * _Nullable * _Nonnull result);
int cl_list_count(const CLDeviceList * _Nullable list);
const char * _Nullable cl_list_model(const CLDeviceList * _Nullable list, int index);
const char * _Nullable cl_list_port(const CLDeviceList * _Nullable list, int index);
void cl_list_free(CLDeviceList * _Nullable list);
const char * _Nonnull cl_error_string(int code);
int cl_error_is_transient(int code);
CLCancellation * _Nullable cl_cancellation_new(void);
void cl_cancellation_cancel(CLCancellation * _Nullable token);
void cl_cancellation_free(CLCancellation * _Nullable token);
int cl_session_open(const char * _Nonnull model, const char * _Nonnull port,
                    CLCancellation * _Nullable token, CLSession * _Nullable * _Nonnull result);
int cl_session_preview(CLSession * _Nonnull session, void * _Nullable * _Nonnull bytes, size_t * _Nonnull length);
int cl_session_keep_alive(CLSession * _Nonnull session);
void cl_bytes_free(void * _Nullable bytes);
void cl_session_close(CLSession * _Nullable session);

#ifdef __OBJC__
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
NS_ASSUME_NONNULL_BEGIN
@interface CLSyphonPublisher : NSObject
- (nullable instancetype)initWithName:(NSString *)name device:(id<MTLDevice>)device;
@property (readonly) BOOL hasClients;
- (void)publishTexture:(id<MTLTexture>)texture commandBuffer:(id<MTLCommandBuffer>)commandBuffer;
- (void)stop;
@end
// Used by the diagnostics receiver to verify actual Syphon discovery and transfer.
@interface CLSyphonReceiver : NSObject
- (nullable instancetype)initWithServerName:(NSString *)name device:(id<MTLDevice>)device;
@property (readonly) BOOL hasNewFrame;
- (nullable id<MTLTexture>)newFrame;
- (void)stop;
@end
NS_ASSUME_NONNULL_END
#endif
