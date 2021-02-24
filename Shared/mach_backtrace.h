//
//  mach_backtrace.h
//  Backtrace
//
//  Created by chenp on 2021/2/24.
//

#ifndef mach_backtrace_h
#define mach_backtrace_h

#include <mach/mach.h>

int mach_backtrace(thread_t thread, void** stack, int maxSymbols);

#endif /* mach_backtrace_h */
