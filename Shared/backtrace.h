//
//  backtrace.h
//  Backtrace
//
//  Created by cp on 2021/3/1.
//

#ifndef backtrace_h
#define backtrace_h

#include <mach/mach.h>

int backtrace(thread_t thread, void** stack, int maxSymbols);

#endif /* backtrace_h */
