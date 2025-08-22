// PSNHelper.m

#import "PSNHelper.h"

NSValue* _Nullable getPSNForPID(pid_t pid) {
    ProcessSerialNumber psn;
    
    // This tells the compiler to temporarily stop warning about deprecated functions
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    
    // This is the C function call that Swift forbids and the compiler warns about.
    // We are deliberately using it because our private APIs require the data it provides.
    if (GetProcessForPID(pid, &psn) == noErr) {
        // This tells the compiler to resume its normal warnings
        #pragma clang diagnostic pop
        
        // We wrap the C struct into an NSValue object to safely pass it back to Swift.
        return [NSValue valueWithBytes:&psn objCType:@encode(ProcessSerialNumber)];
    }
    
    #pragma clang diagnostic pop
    
    return nil;
}
