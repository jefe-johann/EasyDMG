//
//  ContentView.swift
//  EasyDMG
//
//  This view is not used in the app since it runs in background-only mode.
//  Kept for potential future settings UI.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "opticaldiscdrive")
                .imageScale(.large)
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("EasyDMG")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("This app runs in the background.\nDouble-click any DMG file to install.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
    }
}

#Preview {
    ContentView()
}
