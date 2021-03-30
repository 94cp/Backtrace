//
//  ContentView.swift
//  Shared
//
//  Created by chenp on 2021/2/21.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        Button("Main Call Stack") {
            DispatchQueue.global().async {
                print(Backtrace.backtraceMainThread())
            }
        }
        Button("Current Call Stack") {
            DispatchQueue.global().async {
                print(Backtrace.backtraceCurrentThread())
            }
        }
        Button("All Call Stack") {
            DispatchQueue.global().async {
                print(Backtrace.backtraceAllThread().joined(separator: "\n"))
            }
        }
        Button("Custom Call Stack") {
            DispatchQueue.global().async {
                let thread = Thread()
                thread.name = "Custom"
                print(Backtrace.backtrace(thread))
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
