import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            TransactView()
                .tabItem {
                    Image(systemName: "arrow.left.arrow.right")
                    Text("Transact")
                }
            
            ActivityView()
                .tabItem {
                    Image(systemName: "list.bullet")
                    Text("Activity")
                }
        }
        .accentColor(.orange)
    }
}

#Preview {
    ContentView()
}

