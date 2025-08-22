// PSNHelper.h
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

// Declares our helper function. It takes a process ID (pid)
// and returns the ProcessSerialNumber wrapped in an NSValue object,
// which is easy for Swift to understand.
NSValue* _Nullable getPSNForPID(pid_t pid);
