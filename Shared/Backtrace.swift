//
//  Backtrace.swift
//  Backtrace
//
//  Created by chenp on 2021/2/24.
//

import Foundation

struct Backtrace {
    static var main_thread_t: mach_port_t?
    
    static func setup() {
        main_thread_t = mach_thread_self()
    }
    
    static func callstack(_ thread: Thread) {
        
    }
    
    static func mach_callstack(_ thread: thread_t) {
        let stackSize: Int32 = 128
        let addrs = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: Int(stackSize))
        defer {
            addrs.deallocate()
        }
        
        let frameCount = mach_backtrace(thread, addrs, stackSize)
    }
    
//    static func machThread(from thread: Thread) -> thread_t {
//        
//    }
}
