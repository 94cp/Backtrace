//
//  Backtrace.swift
//  Backtrace
//
//  Created by chenp on 2021/2/21.
//

import Foundation

/// 亦可在桥接文件中#import "backtrace.h"
@_silgen_name("cbacktrace")
private func cbacktrace(_ thread: thread_t, stack: UnsafeMutablePointer<UnsafeMutableRawPointer?>!, _ maxSymbols: Int32) -> Int32

/// 亦可在桥接文件中#import <execinfo.h>
@_silgen_name("backtrace_symbols")
private func backtrace_symbols(_ stack: UnsafePointer<UnsafeMutableRawPointer?>!, _ frames: Int32) -> UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>?

public struct Backtrace {
    public static func backtrace(_ thread: Thread) -> String {
        let prefix = "Backtrace of : \(thread.description)\n"
        var css: [String] = []
        if Thread.current == thread {
            for symbol in Thread.callStackSymbols {
                css.append(demangleSymbol(symbol))
            }
        } else {
            let mach = machThread(from: thread)
            css = callStackSymbols(mach)
        }
        return prefix +  css.joined(separator: "\n")
    }
    
    public static func backtraceMainThread() -> String {
        return backtrace(Thread.main)
    }
    
    public static func backtraceCurrentThread() -> String {
        return backtrace(Thread.current)
    }
    
    public static func backtraceAllThread() -> [String] {
        var count: mach_msg_type_number_t = 0
        var threads: thread_act_array_t!
        
        var symbols: [String] = []
        
        if task_threads(mach_task_self_, &(threads), &count) != KERN_SUCCESS {
            let mach = mach_thread_self()
            let css = callStackSymbols(mach)
            let prefix = "Backtrace of : \(mach.description)\n"
            symbols.append(prefix + css.joined(separator: "\n"))
            return symbols
        }
    
        for i in 0..<count {
            let mach = threads[Int(i)]
            let css = callStackSymbols(mach)
            let prefix = "Backtrace of : thread \(i + 1)\n"
            symbols.append(prefix + css.joined(separator: "\n"))
        }
        return symbols
    }
    
    public static var main_thread_t: mach_port_t?
}

extension Backtrace {
    private static func machThread(from thread: Thread) -> thread_t {
        var count: mach_msg_type_number_t = 0
        var threads: thread_act_array_t!
    
        guard task_threads(mach_task_self_, &(threads), &count) == KERN_SUCCESS else {
            return mach_thread_self()
        }

        if !Thread.isMainThread && thread.isMainThread && main_thread_t == nil {
            DispatchQueue.main.sync {
                main_thread_t = mach_thread_self()
            }
            return main_thread_t ?? mach_thread_self()
        }
        
        let originName = thread.name
        defer { thread.name = originName }
        
        thread.name = String(Int(Date.init().timeIntervalSince1970))
        for i in 0..<count {
            let machThread = threads[Int(i)]
            if let p_thread = pthread_from_mach_thread_np(machThread) {
                var name: [Int8] = Array<Int8>(repeating: 0, count: 128)
                pthread_getname_np(p_thread, &name, name.count)
                if thread.name == String(cString: name) {
                    return machThread
                }
            }
        }
        
        return mach_thread_self()
    }
}

extension Backtrace {
    private static func demangleSymbol(_ symbol: String) -> String {
        guard let regexp = try? NSRegularExpression(pattern: "^(?:\\S+ +){3}(\\S+) ", options: []),
              let match = regexp.firstMatch(in: symbol, options: [], range: NSMakeRange(0, symbol.utf16.count)),
              match.numberOfRanges > 1  else { return symbol }
        
        let sname = (symbol as NSString).substring(with: match.range(at: 1))
        let demangleSname = swift_demangle(sname)

        return symbol.replacingOccurrences(of: sname, with: demangleSname)
    }
    
    private static func callStackSymbols(_ thread: thread_t) -> [String] {
        let maxSize = 128
        let addrs = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: maxSize)
        defer { addrs.deallocate() }
        
        // Swift 方式1
        let count = backtrace(thread, stack: addrs, maxSize)
        // C 方式2
//        let count = Int(cbacktrace(thread, stack: addrs, Int32(maxSize)))
        
        var symbols: [String] = []
        
        // 命名重整 方式1
//        let buf = UnsafeBufferPointer(start: addrs, count: count)
//        symbols = buf.enumerated().map({
//            guard let addr = $0.element else {
//                return "<null>"
//            }
//            return AddressInfo(address: UInt(bitPattern: addr), index: $0.offset).description
//        })
        
        // 命名重整 方式2

        if let bs = backtrace_symbols(addrs, Int32(count)) {
            symbols = UnsafeBufferPointer(start: bs, count: count).map {
                guard let symbol = $0 else {
                    return "<null>"
                }
                return demangleSymbol(String(cString: symbol))
            }
            free(bs)
        }
 
        
        return symbols
    }
    
    private static func backtrace(_ thread: thread_t, stack: UnsafeMutablePointer<UnsafeMutableRawPointer?>, _ maxSymbols: Int) -> Int {
        #if arch(i386)

        let THREAD_STATE_FLAVOR = x86_THREAD_STATE
        let THREAD_STATE_COUNT = mach_msg_type_number_t(MemoryLayout<x86_thread_state_t>.size / MemoryLayout<Int32>.size)

        #elseif arch(x86_64)

        let THREAD_STATE_FLAVOR = x86_THREAD_STATE64
        let THREAD_STATE_COUNT = mach_msg_type_number_t(MemoryLayout<x86_thread_state64_t>.size / MemoryLayout<Int32>.size)

        #elseif arch(arm)

        let THREAD_STATE_FLAVOR = ARM_THREAD_STATE
        let THREAD_STATE_COUNT = mach_msg_type_number_t(MemoryLayout<arm_thread_state_t>.size / MemoryLayout<Int32>.size)

        #elseif arch(arm64)

        let THREAD_STATE_FLAVOR = ARM_THREAD_STATE64
        let THREAD_STATE_COUNT = mach_msg_type_number_t(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<Int32>.size)

        #else

        #error("Current CPU Architecture is not supported")

        #endif
        
        let mc = mcontext_t.allocate(capacity: 1)
        defer { mc.deallocate() }
        
        var mContext = mc.pointee
        var stateCount = THREAD_STATE_COUNT
        
        let kret = withUnsafeMutablePointer(to: &(mContext.__ss)) {
            $0.withMemoryRebound(to: natural_t.self, capacity: 1) {
                thread_get_state(thread, THREAD_STATE_FLAVOR, $0, &stateCount)
            }
        }
        if kret != KERN_SUCCESS {
            return 0
        }
        
        var i = 0
        
        #if arch(arm) || arch(arm64)
        // __lr链接寄存器，保存返回上一层调用的地址
        if let __lr = UnsafeMutableRawPointer(bitPattern: UInt(mContext.__ss.__lr)) {
            stack[i] = __lr
            i += 1
        }
        #endif
        
        #if arch(i386)
        let __fp = mContext.__ss.__ebp
        #elseif arch(x86_64)
        let __fp = mContext.__ss.__rbp
        #elseif arch(arm)
        let __fp = mContext.__ss.__r[7]
        #elseif arch(arm64)
        let __fp = mContext.__ss.__fp
        #endif
        
        /// 当前栈帧中FP的值存储的是上一个栈帧的FP地址
        guard var cur__fp = UnsafeMutablePointer<UnsafeMutableRawPointer?>(bitPattern: UInt(__fp)) else { return i }
        
        while i < maxSymbols  {
            guard let pre__fp = UnsafeMutablePointer<UnsafeMutableRawPointer?>(bitPattern: UInt(bitPattern: cur__fp.pointee)) else { return i }
            
            stack[i] = cur__fp.successor().pointee
            cur__fp = pre__fp
            i += 1
        }
        
        return i
    }
}

/**
 *  fill a backtrace call stack array of given thread
 *
 *  Stack frame structure for x86/x86_64:
 *
 *    | ...                   |
 *    +-----------------------+ hi-addr     ------------------------
 *    | func0 ip              |
 *    +-----------------------+
 *    | func0 bp              |--------|     stack frame of func1
 *    +-----------------------+        v
 *    | saved registers       |  bp <- sp
 *    +-----------------------+   |
 *    | local variables...    |   |
 *    +-----------------------+   |
 *    | func2 args            |   |
 *    +-----------------------+   |         ------------------------
 *    | func1 ip              |   |
 *    +-----------------------+   |
 *    | func1 bp              |<--+          stack frame of func2
 *    +-----------------------+
 *    | ...                   |
 *    +-----------------------+ lo-addr     ------------------------
 *
 *  list we need to get is `ip` from bottom to top
 *
 *
 *  Stack frame structure for arm/arm64:
 *
 *    | ...                   |
 *    +-----------------------+ hi-addr     ------------------------
 *    | func0 lr              |
 *    +-----------------------+
 *    | func0 fp              |--------|     stack frame of func1
 *    +-----------------------+        v
 *    | saved registers       |  fp <- sp
 *    +-----------------------+   |
 *    | local variables...    |   |
 *    +-----------------------+   |
 *    | func2 args            |   |
 *    +-----------------------+   |         ------------------------
 *    | func1 lr              |   |
 *    +-----------------------+   |
 *    | func1 fp              |<--+          stack frame of func2
 *    +-----------------------+
 *    | ...                   |
 *    +-----------------------+ lo-addr     ------------------------
 *
 *  when function return, first jump to lr, then restore lr
 *  (namely first address in list is current lr)
 *
 *  fp (frame pointer) is r7 register under ARM and fp register in ARM64
 *  reference: iOS ABI Function Call Guide https://developer.apple.com/library/ios/documentation/Xcode/Conceptual/iPhoneOSABIReference/Articles/ARMv7FunctionCallingConventions.html#//apple_ref/doc/uid/TP40009022-SW1
 *
 *  @param thread   mach thread for tracing
 *  @param stack    caller space for saving stack trace info
 *  @param maxSymbols max stack array count
 *
 *  @return call stack address array
 */
