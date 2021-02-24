//
//  ContentView.swift
//  Shared
//
//  Created by cp on 2021/2/24.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("Hello, world!")
            .padding()
        Button("Backtrace") {
            Backtrace.setup()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
