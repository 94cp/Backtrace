//
//  backtrace.h
//  Backtrace
//
//  Created by chenp on 2021/2/21.
//

#ifndef backtrace_h
#define backtrace_h

#include <mach/mach.h>

int cbacktrace(thread_t thread, void** stack, int maxSymbols);

#endif /* backtrace_h */
