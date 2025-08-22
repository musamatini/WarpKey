// WarpKey-Bridging-Header.h
#import <CoreGraphics/CoreGraphics.h>
#import <ApplicationServices/ApplicationServices.h>
#import "PSNHelper.h"

// Private SkyLight functions for window focusing
CG_EXTERN CGError _SLPSSetFrontProcessWithOptions(void *psn, uint32_t wid, uint32_t mode);
CG_EXTERN CGError SLPSPostEventRecordTo(void *psn, uint8_t *bytes);

// Private function for brute-force AX search
CG_EXTERN CFTypeRef _Nullable _AXUIElementCreateWithRemoteToken(CFDataRef _Nonnull token);
