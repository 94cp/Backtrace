import Foundation
//import G
import Darwin

#if arch(i386)

private var THREAD_STATE_FLAVOR = x86_THREAD_STATE
private var THREAD_STATE_COUNT = mach_msg_type_number_t(MemoryLayout<x86_thread_state_t>.size / MemoryLayout<Int32>.size)

#elseif arch(x86_64)

private var THREAD_STATE_FLAVOR = x86_THREAD_STATE64
private var THREAD_STATE_COUNT = mach_msg_type_number_t(MemoryLayout<x86_thread_state64_t>.size / MemoryLayout<Int32>.size)

#elseif arch(arm)

private var THREAD_STATE_FLAVOR = ARM_THREAD_STATE
private var THREAD_STATE_COUNT = mach_msg_type_number_t(MemoryLayout<arm_thread_state_t>.size / MemoryLayout<Int32>.size)

#elseif arch(arm64)

private var THREAD_STATE_FLAVOR = ARM_THREAD_STATE64
private var THREAD_STATE_COUNT = mach_msg_type_number_t(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<Int32>.size)

#else

#error("Current CPU Architecture is not supported")

#endif

public struct Backtrace {
    private func callStackSymbols(_ thread: thread_t) {
        let maxSize = 128
        let addrs = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: maxSize)
        defer { addrs.deallocate() }
        let count = backtrace(thread, stack: addrs, maxSize)
        var symbols: [String] = []
//        Thread.callStackSymbols
        if let bs = (addrs, count) {
            
        }
        
    }
    
    private func backtrace(_ thread: thread_t, stack: UnsafeMutablePointer<UnsafeMutableRawPointer?>, _ maxSymbols: Int) -> Int {
        var mContext = mcontext_t.allocate(capacity: 1).pointee
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
        if let __linkRegisterPointer = UnsafeMutablePointer<UnsafeMutableRawPointer?>(bitPattern: UInt(mContext.__ss.__lr))?.pointee {
            stack[i] = __linkRegisterPointer
            i += 1
        }
        #endif
        
        #if arch(i386)
        let __framePointer = mContext.__ss.__ebp
        #elseif arch(x86_64)
        let __framePointer = mContext.__ss.__rbp
        #elseif arch(arm)
        let __framePointer = mContext.__ss.__r[7]
        #elseif arch(arm64)
        let __framePointer = mContext.__ss.__fp
        #endif

        guard var curFramePointer = UnsafeMutablePointer<UnsafeMutableRawPointer?>(bitPattern: UInt(__framePointer)) else { return 0 }
        while i < maxSymbols {
            if let preFramePointer = UnsafeMutablePointer<UnsafeMutableRawPointer?>(bitPattern: UInt(bitPattern: curFramePointer.pointee)) {
                stack[i] = curFramePointer.successor().pointee
                curFramePointer = preFramePointer
                i += 1
            }
        }
        
        return i
    }
}

/**
 
 int mach_backtrace(thread_t thread, void** stack, int maxSymbols) {
     _STRUCT_MCONTEXT machineContext;
     mach_msg_type_number_t stateCount = THREAD_STATE_COUNT;
     
     kern_return_t kret = thread_get_state(thread, THREAD_STATE_FLAVOR, (thread_state_t)&(machineContext.__ss), &stateCount);
     if (kret != KERN_SUCCESS) {
         return 0;
     }

     int i = 0;
 #if defined(__arm__) || defined (__arm64__)
     stack[i] = (void *)machineContext.__ss.__lr;
     ++i;
 #endif
     void **currentFramePointer = (void **)machineContext.__ss.__framePointer;
     while (i < maxSymbols && currentFramePointer) {
         void **previousFramePointer = *currentFramePointer;
         if (!previousFramePointer) break;
         stack[i] = *(currentFramePointer+1);
         currentFramePointer = previousFramePointer;
         ++i;
     }
     return i;
 }
 
 */

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
