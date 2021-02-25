//
//  Backtrace.swift
//  Backtrace
//
//  Created by chenp on 2021/2/24.
//

import Foundation

#if arch(i386)

typealias THREAD_STATE_FLAVOR = x86_THREAD_STATE
let THREAD_STATE_COUNT  = x86_THREAD_STATE_COUNT
let __framePointer      = __ebp

#elseif arch(x86_64)

let THREAD_STATE_FLAVOR = x86_THREAD_STATE64
let THREAD_STATE_COUNT  = x86_THREAD_STATE64_COUNT
let __framePointer      = __rbp

#elseif arch(arm)

let THREAD_STATE_FLAVOR = ARM_THREAD_STATE
let THREAD_STATE_COUNT  = ARM_THREAD_STATE_COUNT
let __framePointer      = __r[7]

#elseif arch(arm64)

let THREAD_STATE_FLAVOR = ARM_THREAD_STATE64
let THREAD_STATE_COUNT  = Mach.ARM_THREAD_STATE64_COUNT//MemoryLayout<arm_thread_state64_t>.size/MemoryLayout<UInt32>.size
typealias __framePointer      = __fp

#else

#error ("Current CPU Architecture is not supported")

#endif


struct Backtrace {
    static var main_thread_t: mach_port_t?
    
    static func setup() {
        main_thread_t = mach_thread_self()
    }
    
    
}
