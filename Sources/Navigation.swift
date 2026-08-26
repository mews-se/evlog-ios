import SwiftUI

// a plain < in every pushed view: the system back gesture competes with the maps'
// panning and gets stuck there
struct BackButton: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel(Text("Back"))
                }
            }
    }
}

extension View {
    func appBackButton() -> some View { modifier(BackButton()) }
}

// what a detail page shows, with enough alongside to title the page before it loads
enum DetailTarget: Hashable {
    case drive(id: Int, day: Date)
    case charge(ids: [Int], address: String?)
}

// a pushed detail carries the whole run it was opened from, so the neighbours are
// a swipe away instead of a trip back to the list
struct DetailRoute: Hashable {
    let targets: [DetailTarget]
    let index: Int
}

// whole details in a paged container. the gesture has to come from the container
// rather than from inside a page: the maps already cost the app the system back
// swipe, and the charts claim a horizontal drag of their own for scrubbing
struct DetailPager: View {
    let api: APIClient
    let carID: Int
    let route: DetailRoute
    var tessieCosts: [Int: Double] = [:]

    @State private var index: Int

    init(api: APIClient, carID: Int, route: DetailRoute, tessieCosts: [Int: Double] = [:]) {
        self.api = api
        self.carID = carID
        self.route = route
        self.tessieCosts = tessieCosts
        _index = State(initialValue: route.index)
    }

    var body: some View {
        TabView(selection: $index) {
            ForEach(Array(route.targets.enumerated()), id: \.offset) { i, target in
                page(target).tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .appBackButton()
    }

    @ViewBuilder
    private func page(_ target: DetailTarget) -> some View {
        switch target {
        case .drive(let id, _):
            DriveDetailView(api: api, carID: carID, driveID: id)
        case .charge(let ids, _):
            ChargeDetailView(api: api, carID: carID, chargeIDs: ids, tessieCosts: tessieCosts)
        }
    }

    private var title: String {
        switch route.targets[index] {
        case .drive(_, let day): return Fmt.day(day)
        case .charge(_, let address): return address ?? String(localized: "Charge")
        }
    }
}
