// CoachAnalysisView.swift
// PoseA – Coach Analytics Dashboard
// Drop this file into your Xcode project. No other dependencies needed.

import SwiftUI

// MARK: ─── Measurement Metric ─────────────────────────────────────────────────
// To add a new metric later, just add a case here and supply data.

enum CoachMetric: String, CaseIterable, Identifiable {
    case flightHeight     = "Flight Height"
    case swingAngle       = "Swing Angle"
    case releaseVelocity  = "Release Velocity"
    case barForce         = "Bar Force"

    var id: String { rawValue }

    var unit: String {
        switch self {
        case .flightHeight:    return "cm"
        case .swingAngle:      return "°"
        case .releaseVelocity: return "m/s"
        case .barForce:        return "N"
        }
    }

    var icon: String {
        switch self {
        case .flightHeight:    return "arrow.up.to.line"
        case .swingAngle:      return "angle"
        case .releaseVelocity: return "wind"
        case .barForce:        return "bolt.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .flightHeight:    return Color(red:0.22,green:0.60,blue:0.98)
        case .swingAngle:      return Color(red:0.65,green:0.55,blue:0.98)
        case .releaseVelocity: return Color(red:0.20,green:0.83,blue:0.60)
        case .barForce:        return Color(red:0.98,green:0.75,blue:0.22)
        }
    }

    var isAvailable: Bool {
        switch self {
        case .flightHeight: return true
        default:            return false
        }
    }
}

// MARK: ─── Data Model ─────────────────────────────────────────────────────────

struct FlightTrialRecord: Identifiable {
    let id      = UUID()
    let subject: String
    let trial:   String
    let frame:   Int
    let point:   String
    let ratio:   String
    let height:  Double
    let action:  String
}

extension FlightTrialRecord {
    static let sampleData: [FlightTrialRecord] = [
        .init(subject:"Sub1",trial:"Order8",  frame:478,point:"Nose",ratio:"-",height:83.1, action:"Yamawaki"),
        .init(subject:"Sub1",trial:"Order4",  frame:552,point:"Nose",ratio:"-",height:98.3, action:"Yamawaki"),
        .init(subject:"Sub1",trial:"Order12", frame:580,point:"Nose",ratio:"-",height:92.2, action:"Yamawaki"),
        .init(subject:"Sub2",trial:"Order2",  frame:421,point:"Nose",ratio:"-",height:108.41,action:"Yamawaki"),
        .init(subject:"Sub2",trial:"Order6",  frame:600,point:"Nose",ratio:"-",height:113.3, action:"Yamawaki"),
        .init(subject:"Sub2",trial:"Order10", frame:448,point:"Nose",ratio:"-",height:110.94,action:"Yamawaki"),
        .init(subject:"Sub2",trial:"Order26", frame:583,point:"Nose",ratio:"-",height:115.8, action:"Tkatchev"),
        .init(subject:"Sub2",trial:"Order29", frame:561,point:"Nose",ratio:"-",height:108.7, action:"Tkatchev"),
        .init(subject:"Sub2",trial:"Order32", frame:630,point:"Nose",ratio:"-",height:109.8, action:"Tkatchev"),
        .init(subject:"Sub3",trial:"Order3",  frame:543,point:"Nose",ratio:"-",height:111.7, action:"Tkatchev"),
        .init(subject:"Sub3",trial:"Order7",  frame:597,point:"Nose",ratio:"-",height:107.5, action:"Tkatchev"),
        .init(subject:"Sub3",trial:"Order11", frame:594,point:"Nose",ratio:"-",height:109.5, action:"Tkatchev"),
        .init(subject:"Sub3",trial:"Order27", frame:666,point:"Nose",ratio:"-",height:108.5, action:"Tkatchev"),
        .init(subject:"Sub3",trial:"Order30", frame:669,point:"Nose",ratio:"-",height:105.9, action:"Tkatchev"),
        .init(subject:"Sub3",trial:"Order33", frame:693,point:"Nose",ratio:"-",height:108.7, action:"Tkatchev"),
        .init(subject:"Sub4",trial:"Order1",  frame:557,point:"Nose",ratio:"-",height:114.3, action:"Tkatchev"),
        .init(subject:"Sub4",trial:"Order5",  frame:537,point:"Nose",ratio:"-",height:112.9, action:"Tkatchev"),
        .init(subject:"Sub4",trial:"Order9",  frame:524,point:"Nose",ratio:"-",height:115.5, action:"Tkatchev"),
        .init(subject:"Sub4",trial:"Order25", frame:567,point:"Nose",ratio:"-",height:151.3, action:"Yamawaki"),
        .init(subject:"Sub4",trial:"Order28", frame:551,point:"Nose",ratio:"-",height:151.1, action:"Yamawaki"),
        .init(subject:"Sub4",trial:"Order31", frame:664,point:"Nose",ratio:"-",height:144.4, action:"Yamawaki"),
    ]
}

// MARK: ─── Color Palette ──────────────────────────────────────────────────────

extension Color {
    static let coachBG     = Color(red:0.05,green:0.07,blue:0.12)
    static let coachCard   = Color(red:0.09,green:0.12,blue:0.18)
    static let coachBorder = Color.white.opacity(0.07)
    static let coachAccent = Color(red:0.22,green:0.60,blue:0.98)
    static let coachGold   = Color(red:1.00,green:0.75,blue:0.20)
    static let coachMuted  = Color(red:0.40,green:0.50,blue:0.62)

    static func subjectColor(_ s: String) -> Color {
        switch s {
        case "Sub1": return Color(red:0.22,green:0.74,blue:0.97)
        case "Sub2": return Color(red:0.20,green:0.83,blue:0.60)
        case "Sub3": return Color(red:0.96,green:0.28,blue:0.71)
        case "Sub4": return Color(red:0.98,green:0.57,blue:0.19)
        default:     return .white
        }
    }

    static func actionColor(_ a: String) -> Color {
        switch a {
        case "Yamawaki": return Color(red:0.65,green:0.55,blue:0.98)
        case "Tkatchev":  return Color(red:0.98,green:0.75,blue:0.22)
        default:          return .white
        }
    }
}

// MARK: ─── Array Helpers ──────────────────────────────────────────────────────

extension Array where Element == Double {
    var avg: Double { isEmpty ? 0 : reduce(0,+)/Double(count) }
    var stdDev: Double {
        let m = avg
        return isEmpty ? 0 : sqrt(map{($0-m)*($0-m)}.reduce(0,+)/Double(count))
    }
}

// MARK: ─── Stats ──────────────────────────────────────────────────────────────

struct SubjectStats {
    let subject: String
    let trials:  [FlightTrialRecord]
    var avgHeight: Double { trials.map(\.height).avg }
    var maxHeight: Double { trials.map(\.height).max() ?? 0 }
    var minHeight: Double { trials.map(\.height).min() ?? 0 }
    var stdDev:    Double { trials.map(\.height).stdDev }
    var rank: Int = 0
}

struct ActionStats {
    let action: String
    let trials: [FlightTrialRecord]
    var avgHeight: Double { trials.map(\.height).avg }
    var maxHeight: Double { trials.map(\.height).max() ?? 0 }
    var count: Int { trials.count }
}

// MARK: ─── Access Gate ────────────────────────────────────────────────────────

struct CoachAccessGateView: View {
    @Binding var isUnlocked: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var showError = false
    @State private var shakeOffset: CGFloat = 0
    @FocusState private var focused: Bool
    private let correctCode = "COACH2025"

    var body: some View {
        ZStack {
            Color.coachBG.ignoresSafeArea()
            RadialGradient(colors:[Color.coachAccent.opacity(0.12),.clear],
                           center:.top,startRadius:0,endRadius:420).ignoresSafeArea()
            VStack(spacing:0) {
                Spacer()
                ZStack {
                    Circle().fill(Color.coachAccent.opacity(0.12)).frame(width:80,height:80)
                    Image(systemName:"figure.gymnastics")
                        .font(.system(size:34,weight:.medium))
                        .foregroundStyle(LinearGradient(
                            colors:[Color.coachAccent,Color(red:0.22,green:0.9,blue:0.95)],
                            startPoint:.topLeading,endPoint:.bottomTrailing))
                }.padding(.bottom,24)

                Text("Coach Analytics")
                    .font(.system(size:26,weight:.bold,design:.rounded)).foregroundColor(.white)
                Text("Enter your access code to continue")
                    .font(.system(size:14)).foregroundColor(.coachMuted).padding(.top,6).padding(.bottom,36)

                VStack(spacing:12) {
                    SecureField("Access Code",text:$code)
                        .focused($focused)
                        .font(.system(size:18,weight:.semibold,design:.monospaced))
                        .multilineTextAlignment(.center).foregroundColor(.white)
                        .padding(.vertical,14).padding(.horizontal,20)
                        .background(RoundedRectangle(cornerRadius:14).fill(Color.coachCard)
                            .overlay(RoundedRectangle(cornerRadius:14)
                                .strokeBorder(showError ? Color.red.opacity(0.7):Color.coachBorder,lineWidth:1)))
                        .offset(x:shakeOffset).onSubmit { verify() }
                    if showError {
                        Text("Incorrect code. Please try again.")
                            .font(.system(size:12)).foregroundColor(.red.opacity(0.85))
                            .transition(.opacity.combined(with:.move(edge:.top)))
                    }
                }.frame(maxWidth:300).padding(.bottom,20)

                Button(action:verify) {
                    HStack(spacing:8) {
                        Image(systemName:"lock.open.fill").font(.system(size:14,weight:.semibold))
                        Text("Unlock Dashboard").font(.system(size:15,weight:.bold,design:.rounded))
                    }
                    .foregroundColor(.white).frame(maxWidth:300).padding(.vertical,15)
                    .background(LinearGradient(colors:[Color.coachAccent,Color(red:0.12,green:0.7,blue:0.95)],
                                               startPoint:.leading,endPoint:.trailing).cornerRadius(14))
                    .shadow(color:Color.coachAccent.opacity(0.35),radius:12,y:6)
                }

                Button("Cancel"){ dismiss() }
                    .font(.system(size:13)).foregroundColor(.coachMuted).padding(.top,16)
                Spacer()
                Text("Demo code: COACH2025")
                    .font(.system(size:11,design:.monospaced)).foregroundColor(.white.opacity(0.1)).padding(.bottom,24)
            }.padding(.horizontal,32)
        }.onAppear{ focused=true }
    }

    private func verify() {
        if code==correctCode { isUnlocked=true }
        else { showError=true; triggerShake(); code="" }
    }
    private func triggerShake() {
        withAnimation(.interpolatingSpring(stiffness:600,damping:10)){shakeOffset = -10}
        DispatchQueue.main.asyncAfter(deadline:.now()+0.08){
            withAnimation(.interpolatingSpring(stiffness:600,damping:10)){shakeOffset=10}}
        DispatchQueue.main.asyncAfter(deadline:.now()+0.16){
            withAnimation(.interpolatingSpring(stiffness:600,damping:10)){shakeOffset = -6}}
        DispatchQueue.main.asyncAfter(deadline:.now()+0.24){
            withAnimation(.spring()){shakeOffset=0}}
    }
}

// MARK: ─── Dashboard Tab ─────────────────────────────────────────────────────

enum CoachDashboardTab: String, CaseIterable {
    case ranking="Ranking", perSubject="Per Subject", byAction="By Action", rawTable="Raw Data"
    var icon: String {
        switch self {
        case .ranking:    return "trophy.fill"
        case .perSubject: return "person.3.fill"
        case .byAction:   return "arrow.up.and.down.circle.fill"
        case .rawTable:   return "tablecells"
        }
    }
}

// MARK: ─── Metric Selector Dropdown ──────────────────────────────────────────

struct MetricSelectorView: View {
    @Binding var selected: CoachMetric
    @State private var isExpanded = false

    var body: some View {
        ZStack(alignment:.topLeading) {
            // Collapsed button
            Button {
                withAnimation(.spring(response:0.3,dampingFraction:0.75)){isExpanded.toggle()}
            } label: {
                HStack(spacing:8) {
                    ZStack {
                        Circle().fill(selected.accentColor.opacity(0.18)).frame(width:28,height:28)
                        Image(systemName:selected.icon)
                            .font(.system(size:11,weight:.semibold)).foregroundColor(selected.accentColor)
                    }
                    VStack(alignment:.leading,spacing:1) {
                        Text("METRIC").font(.system(size:9,weight:.heavy)).foregroundColor(.coachMuted).tracking(1.5)
                        Text(selected.rawValue).font(.system(size:13,weight:.bold,design:.rounded)).foregroundColor(.white)
                    }
                    Image(systemName:isExpanded ? "chevron.up":"chevron.down")
                        .font(.system(size:10,weight:.bold)).foregroundColor(.coachMuted).padding(.leading,2)
                }
                .padding(.horizontal,12).padding(.vertical,8)
                .background(RoundedRectangle(cornerRadius:12).fill(Color.coachCard)
                    .overlay(RoundedRectangle(cornerRadius:12)
                        .strokeBorder(selected.accentColor.opacity(0.35),lineWidth:1)))
                .shadow(color:selected.accentColor.opacity(0.15),radius:6,y:3)
            }

            // Dropdown panel
            if isExpanded {
                VStack(alignment:.leading,spacing:2) {
                    Text("SELECT METRIC")
                        .font(.system(size:9,weight:.heavy)).foregroundColor(.coachMuted).tracking(1.5)
                        .padding(.horizontal,14).padding(.top,12).padding(.bottom,4)
                    Divider().background(Color.coachBorder).padding(.horizontal,8)
                    ForEach(CoachMetric.allCases) { metric in
                        MetricDropdownRow(metric:metric, isActive:metric==selected) {
                            guard metric.isAvailable else { return }
                            withAnimation(.spring(response:0.3,dampingFraction:0.75)){
                                selected=metric; isExpanded=false
                            }
                        }
                    }
                    .padding(.bottom,8)
                }
                .frame(width:240)
                .background(RoundedRectangle(cornerRadius:14)
                    .fill(Color(red:0.07,green:0.10,blue:0.16))
                    .shadow(color:.black.opacity(0.5),radius:20,y:8))
                .overlay(RoundedRectangle(cornerRadius:14).strokeBorder(Color.coachBorder))
                .offset(y:52)
                .zIndex(100)
                .transition(.asymmetric(
                    insertion:.opacity.combined(with:.scale(scale:0.95,anchor:.topLeading)),
                    removal:  .opacity.combined(with:.scale(scale:0.95,anchor:.topLeading))
                ))
            }
        }
    }
}

struct MetricDropdownRow: View {
    let metric: CoachMetric; let isActive: Bool; let onTap: () -> Void
    var body: some View {
        Button(action:onTap) {
            HStack(spacing:12) {
                ZStack {
                    Circle().fill(metric.accentColor.opacity(isActive ? 0.25:0.10)).frame(width:32,height:32)
                    Image(systemName:metric.icon)
                        .font(.system(size:12,weight:.semibold))
                        .foregroundColor(metric.isAvailable ? metric.accentColor : .coachMuted)
                }
                VStack(alignment:.leading,spacing:2) {
                    HStack(spacing:6) {
                        Text(metric.rawValue)
                            .font(.system(size:13,weight:isActive ? .bold:.medium,design:.rounded))
                            .foregroundColor(metric.isAvailable ? .white : .coachMuted)
                        if !metric.isAvailable {
                            Text("Coming Soon")
                                .font(.system(size:9,weight:.bold))
                                .foregroundColor(Color(red:0.60,green:0.42,blue:0.98))
                                .padding(.horizontal,6).padding(.vertical,2)
                                .background(Color(red:0.60,green:0.42,blue:0.98).opacity(0.15))
                                .cornerRadius(4)
                        }
                    }
                    Text("Unit: \(metric.unit)").font(.system(size:10)).foregroundColor(.coachMuted)
                }
                Spacer()
                if isActive {
                    Image(systemName:"checkmark.circle.fill")
                        .font(.system(size:14)).foregroundColor(metric.accentColor)
                }
            }
            .padding(.horizontal,14).padding(.vertical,9)
            .background(isActive ? metric.accentColor.opacity(0.08):Color.clear)
            .contentShape(Rectangle())
        }
        .disabled(!metric.isAvailable)
    }
}

// MARK: ─── Filter Bar ─────────────────────────────────────────────────────────

struct DashboardFilterBar: View {
    let allData: [FlightTrialRecord]
    @Binding var selectedSubjects: Set<String>
    @Binding var selectedActions:  Set<String>

    private var subjects: [String] { Array(Set(allData.map(\.subject))).sorted() }
    private var actions:  [String] { Array(Set(allData.map(\.action))).sorted() }

    var activeFilterCount: Int {
        (selectedSubjects.count < subjects.count ? subjects.count - selectedSubjects.count : 0) +
        (selectedActions.count  < actions.count  ? actions.count  - selectedActions.count  : 0)
    }

    var body: some View {
        ScrollView(.horizontal,showsIndicators:false) {
            HStack(spacing:6) {
                if activeFilterCount > 0 {
                    Button {
                        withAnimation {
                            selectedSubjects = Set(subjects)
                            selectedActions  = Set(actions)
                        }
                    } label: {
                        HStack(spacing:4) {
                            Image(systemName:"xmark.circle.fill").font(.system(size:10))
                            Text("Clear \(activeFilterCount)")
                        }
                        .font(.system(size:11,weight:.semibold)).foregroundColor(.white)
                        .padding(.horizontal,10).padding(.vertical,5)
                        .background(Color.red.opacity(0.25)).cornerRadius(20)
                        .overlay(RoundedRectangle(cornerRadius:20).strokeBorder(Color.red.opacity(0.4),lineWidth:1))
                    }.transition(.scale.combined(with:.opacity))
                }

                Text("SUBJECTS").font(.system(size:9,weight:.heavy)).tracking(1.2)
                    .foregroundColor(.coachMuted).padding(.leading,4)

                ForEach(subjects,id:\.self) { sub in
                    let on = selectedSubjects.contains(sub)
                    FilterPill(label:sub,color:Color.subjectColor(sub),isSelected:on){
                        withAnimation(.spring(response:0.25,dampingFraction:0.7)){
                            if on { selectedSubjects.remove(sub) } else { selectedSubjects.insert(sub) }
                        }
                    }
                }

                Rectangle().fill(Color.coachBorder).frame(width:1,height:20)

                Text("ACTIONS").font(.system(size:9,weight:.heavy)).tracking(1.2).foregroundColor(.coachMuted)

                ForEach(actions,id:\.self) { act in
                    let on = selectedActions.contains(act)
                    FilterPill(label:act,color:Color.actionColor(act),isSelected:on){
                        withAnimation(.spring(response:0.25,dampingFraction:0.7)){
                            if on { selectedActions.remove(act) } else { selectedActions.insert(act) }
                        }
                    }
                }
            }
            .padding(.horizontal,24).padding(.vertical,10)
        }
    }
}

// MARK: ─── Main Dashboard ─────────────────────────────────────────────────────

struct CoachAnalysisDashboardView: View {
    let data: [FlightTrialRecord]
    @State private var selectedTab:      CoachDashboardTab = .ranking
    @State private var selectedMetric:   CoachMetric       = .flightHeight
    @State private var selectedSubjects: Set<String>       = []
    @State private var selectedActions:  Set<String>       = []
    @State private var appeared = false
    @Environment(\.dismiss) private var dismiss

    private var filteredData: [FlightTrialRecord] {
        data.filter { selectedSubjects.contains($0.subject) && selectedActions.contains($0.action) }
    }

    var body: some View {
        ZStack {
            Color.coachBG.ignoresSafeArea()
            VStack {
                RadialGradient(colors:[selectedMetric.accentColor.opacity(0.07),.clear],
                               center:.top,startRadius:0,endRadius:500).frame(height:400)
                Spacer()
            }.ignoresSafeArea()

            VStack(spacing:0) {
                // Header
                HStack(alignment:.center,spacing:12) {
                    VStack(alignment:.leading,spacing:2) {
                        HStack(spacing:7) {
                            Image(systemName:"figure.gymnastics").font(.system(size:12,weight:.semibold))
                                .foregroundColor(selectedMetric.accentColor)
                            Text("COACH ANALYTICS").font(.system(size:10,weight:.heavy))
                                .foregroundColor(selectedMetric.accentColor).tracking(2)
                        }
                        Text("Comparative Dashboard")
                            .font(.system(size:20,weight:.bold,design:.rounded)).foregroundColor(.white)
                    }
                    Spacer()

                    // ── Metric dropdown ──
                    MetricSelectorView(selected:$selectedMetric)

                    HStack(spacing:6) {
                        PillBadge(label:"\(filteredData.count) trials",color:selectedMetric.accentColor)
                        if filteredData.count < data.count {
                            PillBadge(label:"filtered",color:.red.opacity(0.85))
                        }
                    }

                    Button { dismiss() } label: {
                        Image(systemName:"xmark.circle.fill").font(.system(size:22))
                            .foregroundColor(.white.opacity(0.22))
                    }
                }
                .padding(.horizontal,24).padding(.top,20).padding(.bottom,12)

                // Tab bar
                ScrollView(.horizontal,showsIndicators:false) {
                    HStack(spacing:4) {
                        ForEach(CoachDashboardTab.allCases,id:\.self) { tab in
                            TabButton(tab:tab,selected:selectedTab==tab,accentColor:selectedMetric.accentColor){
                                withAnimation(.spring(response:0.3,dampingFraction:0.75)){selectedTab=tab}
                            }
                        }
                    }.padding(.horizontal,24)
                }.padding(.bottom,10)

                // Filter bar
                DashboardFilterBar(allData:data,selectedSubjects:$selectedSubjects,selectedActions:$selectedActions)

                Divider().background(Color.coachBorder)

                // Content
                if !selectedMetric.isAvailable {
                    ComingSoonBanner(metric:selectedMetric)
                } else {
                    ScrollView {
                        Group {
                            if filteredData.isEmpty {
                                EmptyFilterView()
                            } else {
                                VStack(spacing:20) {
                                    switch selectedTab {
                                    case .ranking:
                                        RankingTabView(subjects:buildSubjectStats(filteredData),allData:filteredData,metric:selectedMetric)
                                    case .perSubject:
                                        PerSubjectTabView(subjects:buildSubjectStats(filteredData),allData:filteredData,metric:selectedMetric)
                                    case .byAction:
                                        ByActionTabView(actions:buildActionStats(filteredData),allData:filteredData,metric:selectedMetric)
                                    case .rawTable:
                                        RawTableTabView(data:filteredData,metric:selectedMetric)
                                    }
                                }
                                .padding(.horizontal,24).padding(.vertical,20)
                            }
                        }
                        .opacity(appeared ? 1:0).offset(y:appeared ? 0:14)
                    }
                }
            }
        }
        .onAppear {
            selectedSubjects = Set(data.map(\.subject))
            selectedActions  = Set(data.map(\.action))
            withAnimation(.easeOut(duration:0.4).delay(0.1)){ appeared=true }
        }
        .onChange(of:selectedTab)      { _,_ in animateRefresh() }
        .onChange(of:selectedMetric)   { _,_ in animateRefresh() }
        .onChange(of:selectedSubjects) { _,_ in animateRefresh() }
        .onChange(of:selectedActions)  { _,_ in animateRefresh() }
    }

    private func animateRefresh() {
        appeared=false
        withAnimation(.easeOut(duration:0.25).delay(0.04)){ appeared=true }
    }
    private func buildSubjectStats(_ d:[FlightTrialRecord]) -> [SubjectStats] {
        var stats = Dictionary(grouping:d,by:\.subject)
            .map{SubjectStats(subject:$0.key,trials:$0.value)}
            .sorted{$0.avgHeight>$1.avgHeight}
        for i in stats.indices { stats[i].rank=i+1 }
        return stats
    }
    private func buildActionStats(_ d:[FlightTrialRecord]) -> [ActionStats] {
        Dictionary(grouping:d,by:\.action)
            .map{ActionStats(action:$0.key,trials:$0.value)}
            .sorted{$0.avgHeight>$1.avgHeight}
    }
}

// MARK: ─── Coming Soon Banner ─────────────────────────────────────────────────

struct ComingSoonBanner: View {
    let metric: CoachMetric
    var body: some View {
        VStack(spacing:16) {
            Spacer()
            ZStack {
                Circle().fill(metric.accentColor.opacity(0.10)).frame(width:72,height:72)
                Image(systemName:metric.icon).font(.system(size:30,weight:.medium))
                    .foregroundColor(metric.accentColor.opacity(0.7))
            }
            Text("\(metric.rawValue) Analysis")
                .font(.system(size:18,weight:.bold,design:.rounded)).foregroundColor(.white)
            Text("This metric is not yet available.\nData collection coming in a future update.")
                .font(.system(size:13)).foregroundColor(.coachMuted).multilineTextAlignment(.center)
            Text("Unit: \(metric.unit)")
                .font(.system(size:11,design:.monospaced)).foregroundColor(metric.accentColor.opacity(0.6))
                .padding(.horizontal,12).padding(.vertical,5)
                .background(metric.accentColor.opacity(0.08)).cornerRadius(8)
            Spacer()
        }.padding(40)
    }
}

// MARK: ─── Empty Filter ───────────────────────────────────────────────────────

struct EmptyFilterView: View {
    var body: some View {
        VStack(spacing:14) {
            Spacer()
            Image(systemName:"line.3.horizontal.decrease.circle")
                .font(.system(size:40)).foregroundColor(.coachMuted.opacity(0.5))
            Text("No data matches your filters")
                .font(.system(size:16,weight:.semibold,design:.rounded)).foregroundColor(.coachMuted)
            Text("Adjust the subject or action filters above.")
                .font(.system(size:13)).foregroundColor(.coachMuted.opacity(0.6))
            Spacer()
        }.frame(maxWidth:.infinity).padding(.top,80)
    }
}

// MARK: ─── Tab: Ranking ───────────────────────────────────────────────────────

struct RankingTabView: View {
    let subjects: [SubjectStats]; let allData: [FlightTrialRecord]; let metric: CoachMetric
    private var globalMax: Double { allData.map(\.height).max() ?? 1 }
    private var globalAvg: Double { allData.map(\.height).avg }
    private var globalMin: Double { allData.map(\.height).min() ?? 0 }

    var body: some View {
        VStack(spacing:16) {
            HStack(spacing:12) {
                KPICard(label:"Session Best", value:String(format:"%.1f",globalMax),unit:metric.unit,icon:"arrow.up.circle.fill",  color:.coachGold)
                KPICard(label:"Session Avg",  value:String(format:"%.1f",globalAvg),unit:metric.unit,icon:"chart.bar.fill",         color:metric.accentColor)
                KPICard(label:"Session Low",  value:String(format:"%.1f",globalMin),unit:metric.unit,icon:"arrow.down.circle.fill", color:.coachMuted)
                KPICard(label:"Total Trials", value:"\(allData.count)",              unit:"trials",   icon:"list.number",            color:Color(red:0.65,green:0.55,blue:0.98))
            }

            if subjects.count >= 3 { PodiumView(subjects:subjects,metric:metric) }

            CoachCard(title:"Overall Rankings",subtitle:"Sorted by average \(metric.rawValue.lowercased())") {
                VStack(spacing:0) {
                    HStack {
                        Text("Rank").frame(width:40,alignment:.center)
                        Text("Subject").frame(maxWidth:.infinity,alignment:.leading)
                        Text("Avg").frame(width:72,alignment:.trailing)
                        Text("Best").frame(width:72,alignment:.trailing)
                        Text("Std Dev").frame(width:68,alignment:.trailing)
                        Text("Trials").frame(width:50,alignment:.trailing)
                    }
                    .font(.system(size:11,weight:.semibold)).foregroundColor(.coachMuted)
                    .padding(.horizontal,16).padding(.vertical,10)
                    Divider().background(Color.coachBorder)

                    ForEach(Array(subjects.enumerated()),id:\.element.subject) { idx,stat in
                        VStack(spacing:0) {
                            HStack {
                                RankMedal(rank:stat.rank).frame(width:40,alignment:.center)
                                HStack(spacing:8) {
                                    Circle().fill(Color.subjectColor(stat.subject)).frame(width:8,height:8)
                                    Text(stat.subject).font(.system(size:14,weight:.semibold,design:.rounded)).foregroundColor(.white)
                                }.frame(maxWidth:.infinity,alignment:.leading)
                                Text(String(format:"%.1f \(metric.unit)",stat.avgHeight)).frame(width:72,alignment:.trailing)
                                    .font(.system(size:13,weight:.bold,design:.monospaced)).foregroundColor(Color.subjectColor(stat.subject))
                                Text(String(format:"%.1f",stat.maxHeight)).frame(width:72,alignment:.trailing)
                                    .font(.system(size:13,design:.monospaced)).foregroundColor(.white.opacity(0.8))
                                Text(String(format:"±%.1f",stat.stdDev)).frame(width:68,alignment:.trailing)
                                    .font(.system(size:12,design:.monospaced)).foregroundColor(.coachMuted)
                                Text("\(stat.trials.count)").frame(width:50,alignment:.trailing)
                                    .font(.system(size:13,design:.monospaced)).foregroundColor(.coachMuted)
                            }
                            .padding(.horizontal,16).padding(.vertical,12)
                            .background(idx%2==0 ? Color.clear:Color.white.opacity(0.02))

                            GeometryReader { geo in
                                HStack(spacing:0) {
                                    Rectangle()
                                        .fill(LinearGradient(
                                            colors:[Color.subjectColor(stat.subject).opacity(0.45),Color.subjectColor(stat.subject).opacity(0.12)],
                                            startPoint:.leading,endPoint:.trailing))
                                        .frame(width:geo.size.width*(stat.avgHeight/globalMax))
                                    Spacer()
                                }
                            }.frame(height:2)
                        }
                    }
                }
            }
        }
    }
}

// MARK: ─── Tab: Per Subject ───────────────────────────────────────────────────

struct PerSubjectTabView: View {
    let subjects: [SubjectStats]; let allData: [FlightTrialRecord]; let metric: CoachMetric
    @State private var selectedSubject: String? = nil
    var displaySubjects: [SubjectStats] {
        selectedSubject==nil ? subjects : subjects.filter{$0.subject==selectedSubject}
    }
    var body: some View {
        VStack(spacing:16) {
            ScrollView(.horizontal,showsIndicators:false) {
                HStack(spacing:8) {
                    FilterPill(label:"All",isSelected:selectedSubject==nil){ withAnimation{selectedSubject=nil} }
                    ForEach(subjects,id:\.subject){s in
                        FilterPill(label:s.subject,color:Color.subjectColor(s.subject),isSelected:selectedSubject==s.subject){
                            withAnimation{selectedSubject=(selectedSubject==s.subject) ? nil:s.subject}
                        }
                    }
                }
            }
            ForEach(displaySubjects,id:\.subject){stat in
                SubjectDetailCard(stat:stat,allData:allData,metric:metric)
            }
        }
    }
}

struct SubjectDetailCard: View {
    let stat: SubjectStats; let allData: [FlightTrialRecord]; let metric: CoachMetric
    private var sortedTrials: [FlightTrialRecord] { stat.trials.sorted{$0.trial<$1.trial} }
    private var globalMax: Double { allData.map(\.height).max() ?? 1 }
    var body: some View {
        CoachCard(title:stat.subject,
                  subtitle:"\(stat.trials.count) trials · avg \(String(format:"%.1f",stat.avgHeight)) \(metric.unit)",
                  accentColor:Color.subjectColor(stat.subject)) {
            VStack(spacing:14) {
                HStack(spacing:0) {
                    MiniStat(label:"Best",  value:String(format:"%.1f",stat.maxHeight),color:.coachGold)
                    Divider().background(Color.coachBorder).frame(height:36)
                    MiniStat(label:"Avg",   value:String(format:"%.1f",stat.avgHeight),color:Color.subjectColor(stat.subject))
                    Divider().background(Color.coachBorder).frame(height:36)
                    MiniStat(label:"Worst", value:String(format:"%.1f",stat.minHeight),color:.coachMuted)
                    Divider().background(Color.coachBorder).frame(height:36)
                    MiniStat(label:"Std",   value:String(format:"±%.1f",stat.stdDev),  color:.coachMuted)
                }
                .padding(.horizontal,16).padding(.vertical,8).background(Color.white.opacity(0.03)).cornerRadius(10)
                Divider().background(Color.coachBorder)
                VStack(spacing:8){
                    ForEach(sortedTrials){trial in
                        TrialBarRow(trial:trial,subjectColor:Color.subjectColor(stat.subject),
                                    globalMax:globalMax,subjectAvg:stat.avgHeight,unit:metric.unit)
                    }
                }.padding(.horizontal,4)
            }.padding(.vertical,4)
        }
    }
}

struct TrialBarRow: View {
    let trial: FlightTrialRecord; let subjectColor: Color
    let globalMax: Double; let subjectAvg: Double; let unit: String
    var body: some View {
        HStack(spacing:10) {
            Text(trial.trial).font(.system(size:11,weight:.medium,design:.monospaced))
                .foregroundColor(.coachMuted).frame(width:72,alignment:.leading)
            Text(trial.action).font(.system(size:9,weight:.bold))
                .foregroundColor(Color.actionColor(trial.action))
                .padding(.horizontal,6).padding(.vertical,2)
                .background(Color.actionColor(trial.action).opacity(0.15)).cornerRadius(4).frame(width:68)
            GeometryReader{geo in
                ZStack(alignment:.leading){
                    RoundedRectangle(cornerRadius:4).fill(Color.white.opacity(0.04)).frame(height:18)
                    Rectangle().fill(subjectColor.opacity(0.3)).frame(width:1,height:22)
                        .offset(x:geo.size.width*(subjectAvg/globalMax))
                    RoundedRectangle(cornerRadius:4)
                        .fill(LinearGradient(colors:[subjectColor.opacity(0.8),subjectColor.opacity(0.5)],
                                             startPoint:.leading,endPoint:.trailing))
                        .frame(width:geo.size.width*(trial.height/globalMax),height:18)
                }
            }.frame(height:18)
            Text(String(format:"%.1f",trial.height))
                .font(.system(size:12,weight:.bold,design:.monospaced)).foregroundColor(subjectColor).frame(width:48,alignment:.trailing)
            Text(unit).font(.system(size:10)).foregroundColor(.coachMuted)
        }
    }
}

// MARK: ─── Tab: By Action ────────────────────────────────────────────────────

struct ByActionTabView: View {
    let actions: [ActionStats]; let allData: [FlightTrialRecord]; let metric: CoachMetric
    private var globalMax: Double { allData.map(\.height).max() ?? 1 }
    var body: some View {
        VStack(spacing:16) {
            HStack(spacing:12){ForEach(actions,id:\.action){ActionKPICard(stat:$0,unit:metric.unit)}}

            ForEach(actions,id:\.action){actionStat in
                CoachCard(title:actionStat.action,
                          subtitle:"\(actionStat.count) trials across all subjects",
                          accentColor:Color.actionColor(actionStat.action)){
                    VStack(spacing:12){
                        let subGroups=Dictionary(grouping:actionStat.trials,by:\.subject)
                            .map{(subject:$0.key,trials:$0.value)}.sorted{$0.subject<$1.subject}
                        ForEach(subGroups,id:\.subject){group in
                            let subAvg=group.trials.map(\.height).avg
                            let subMax=group.trials.map(\.height).max() ?? 0
                            HStack(spacing:10){
                                HStack(spacing:6){
                                    Circle().fill(Color.subjectColor(group.subject)).frame(width:7,height:7)
                                    Text(group.subject).font(.system(size:12,weight:.semibold)).foregroundColor(.white)
                                }.frame(width:60,alignment:.leading)
                                Text("\(group.trials.count) trials").font(.system(size:11)).foregroundColor(.coachMuted).frame(width:52)
                                GeometryReader{geo in
                                    ZStack(alignment:.leading){
                                        RoundedRectangle(cornerRadius:4).fill(Color.white.opacity(0.04)).frame(height:16)
                                        RoundedRectangle(cornerRadius:4)
                                            .fill(LinearGradient(colors:[Color.subjectColor(group.subject).opacity(0.7),Color.subjectColor(group.subject).opacity(0.3)],startPoint:.leading,endPoint:.trailing))
                                            .frame(width:geo.size.width*(subAvg/globalMax),height:16)
                                    }
                                }.frame(height:16)
                                VStack(alignment:.trailing,spacing:1){
                                    Text(String(format:"%.1f",subAvg)).font(.system(size:12,weight:.bold,design:.monospaced)).foregroundColor(Color.subjectColor(group.subject))
                                    Text("best \(String(format:"%.1f",subMax))").font(.system(size:9,design:.monospaced)).foregroundColor(.coachMuted)
                                }.frame(width:72,alignment:.trailing)
                            }
                        }
                        Divider().background(Color.coachBorder)
                        HStack{
                            Label("Avg \(String(format:"%.1f \(metric.unit)",actionStat.avgHeight))",systemImage:"chart.bar")
                                .font(.system(size:12,weight:.semibold)).foregroundColor(Color.actionColor(actionStat.action))
                            Spacer()
                            Label("Best \(String(format:"%.1f \(metric.unit)",actionStat.maxHeight))",systemImage:"arrow.up.circle")
                                .font(.system(size:12)).foregroundColor(.coachGold)
                        }.padding(.top,2)
                    }.padding(.vertical,4)
                }
            }

            CoachCard(title:"Action Comparison",subtitle:"Average \(metric.rawValue.lowercased()) per action"){
                VStack(spacing:12){
                    ForEach(actions,id:\.action){a in
                        HStack(spacing:12){
                            Text(a.action).font(.system(size:13,weight:.semibold)).foregroundColor(.white).frame(width:90,alignment:.leading)
                            GeometryReader{geo in
                                ZStack(alignment:.leading){
                                    RoundedRectangle(cornerRadius:6).fill(Color.white.opacity(0.04))
                                    RoundedRectangle(cornerRadius:6)
                                        .fill(LinearGradient(colors:[Color.actionColor(a.action),Color.actionColor(a.action).opacity(0.5)],startPoint:.leading,endPoint:.trailing))
                                        .frame(width:geo.size.width*(a.avgHeight/globalMax))
                                        .shadow(color:Color.actionColor(a.action).opacity(0.4),radius:6)
                                }
                            }.frame(height:26)
                            Text(String(format:"%.1f \(metric.unit)",a.avgHeight))
                                .font(.system(size:13,weight:.bold,design:.monospaced)).foregroundColor(Color.actionColor(a.action)).frame(width:80,alignment:.trailing)
                        }
                    }
                }.padding(.vertical,4)
            }
        }
    }
}

// MARK: ─── Tab: Raw Table ────────────────────────────────────────────────────

struct RawTableTabView: View {
    let data: [FlightTrialRecord]; let metric: CoachMetric
    @State private var sortKey: SortKey = .height
    @State private var ascending = false
    enum SortKey { case subject,trial,height,action }
    private var sortedData: [FlightTrialRecord] {
        data.sorted{
            switch sortKey {
            case .subject: return ascending ? $0.subject<$1.subject : $0.subject>$1.subject
            case .trial:   return ascending ? $0.trial<$1.trial     : $0.trial>$1.trial
            case .height:  return ascending ? $0.height<$1.height   : $0.height>$1.height
            case .action:  return ascending ? $0.action<$1.action   : $0.action>$1.action
            }
        }
    }
    var body: some View {
        CoachCard(title:"Raw \(metric.rawValue) Data",subtitle:"Tap column headers to sort"){
            VStack(spacing:0){
                HStack{
                    SortHeader("Subject",key:.subject,current:$sortKey,asc:$ascending).frame(width:65)
                    SortHeader("Trial",  key:.trial,  current:$sortKey,asc:$ascending).frame(width:80)
                    SortHeader("Action", key:.action, current:$sortKey,asc:$ascending).frame(maxWidth:.infinity)
                    Text("Frame").font(.system(size:10,weight:.semibold)).foregroundColor(.coachMuted).frame(width:54,alignment:.trailing)
                    SortHeader("\(metric.rawValue) (\(metric.unit))",key:.height,current:$sortKey,asc:$ascending).frame(width:90,alignment:.trailing)
                }
                .padding(.horizontal,16).padding(.vertical,10)
                Divider().background(Color.coachBorder)
                ForEach(Array(sortedData.enumerated()),id:\.element.id){idx,record in
                    HStack{
                        HStack(spacing:6){
                            Circle().fill(Color.subjectColor(record.subject)).frame(width:6,height:6)
                            Text(record.subject).font(.system(size:12,weight:.medium)).foregroundColor(.white)
                        }.frame(width:65,alignment:.leading)
                        Text(record.trial).font(.system(size:11,design:.monospaced)).foregroundColor(.coachMuted).frame(width:80,alignment:.leading)
                        Text(record.action).font(.system(size:11,weight:.semibold)).foregroundColor(Color.actionColor(record.action)).frame(maxWidth:.infinity,alignment:.leading)
                        Text("\(record.frame)").font(.system(size:11,design:.monospaced)).foregroundColor(.coachMuted).frame(width:54,alignment:.trailing)
                        Text(String(format:"%.1f \(metric.unit)",record.height))
                            .font(.system(size:12,weight:.bold,design:.monospaced)).foregroundColor(Color.subjectColor(record.subject)).frame(width:90,alignment:.trailing)
                    }
                    .padding(.horizontal,16).padding(.vertical,9)
                    .background(idx%2==0 ? Color.clear:Color.white.opacity(0.02))
                }
            }
        }
    }
}

// MARK: ─── Shared Components ──────────────────────────────────────────────────

struct CoachCard<Content:View>: View {
    let title,subtitle: String; var accentColor: Color = .coachAccent
    @ViewBuilder let content: ()->Content
    var body: some View {
        VStack(alignment:.leading,spacing:0){
            VStack(alignment:.leading,spacing:2){
                Text(title).font(.system(size:14,weight:.bold,design:.rounded)).foregroundColor(.white)
                Text(subtitle).font(.system(size:11)).foregroundColor(.coachMuted)
            }.padding(.horizontal,16).padding(.top,14).padding(.bottom,10)
            Divider().background(Color.coachBorder)
            content().padding(.horizontal,16).padding(.bottom,14).padding(.top,12)
        }
        .background(Color.coachCard).cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius:14).strokeBorder(Color.coachBorder,lineWidth:1))
        .overlay(alignment:.top){
            RoundedRectangle(cornerRadius:14).fill(accentColor).frame(height:2).padding(.top,-0.5).clipped()
        }
    }
}

struct KPICard: View {
    let label,value,unit,icon: String; let color: Color
    var body: some View {
        VStack(alignment:.leading,spacing:4){
            HStack{Image(systemName:icon).font(.system(size:12)).foregroundColor(color);Spacer()}
            Text(value).font(.system(size:20,weight:.black,design:.monospaced)).foregroundColor(color)
            Text(label).font(.system(size:10,weight:.medium)).foregroundColor(.coachMuted).lineLimit(1)
        }
        .padding(12).frame(maxWidth:.infinity,alignment:.leading)
        .background(Color.coachCard).cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(Color.coachBorder))
    }
}

struct MiniStat: View {
    let label,value: String; let color: Color
    var body: some View {
        VStack(spacing:2){
            Text(value).font(.system(size:15,weight:.bold,design:.monospaced)).foregroundColor(color)
            Text(label).font(.system(size:9,weight:.medium)).foregroundColor(.coachMuted)
        }.frame(maxWidth:.infinity)
    }
}

struct PillBadge: View {
    let label: String; var color: Color = .coachAccent
    var body: some View {
        Text(label).font(.system(size:11,weight:.semibold)).foregroundColor(color)
            .padding(.horizontal,10).padding(.vertical,4).background(color.opacity(0.12)).cornerRadius(20)
    }
}

struct FilterPill: View {
    let label: String; var color: Color = .coachAccent; let isSelected: Bool; let action: ()->Void
    var body: some View {
        Button(action:action){
            Text(label).font(.system(size:12,weight:.semibold))
                .foregroundColor(isSelected ? .white:color)
                .padding(.horizontal,14).padding(.vertical,6)
                .background(isSelected ? color:color.opacity(0.1)).cornerRadius(20)
                .overlay(RoundedRectangle(cornerRadius:20).strokeBorder(color.opacity(isSelected ? 0:0.3),lineWidth:1))
        }
    }
}

struct TabButton: View {
    let tab: CoachDashboardTab; let selected: Bool; var accentColor: Color = .coachAccent; let action: ()->Void
    var body: some View {
        Button(action:action){
            HStack(spacing:6){
                Image(systemName:tab.icon).font(.system(size:11,weight:.semibold))
                Text(tab.rawValue).font(.system(size:13,weight:selected ? .bold:.medium,design:.rounded))
            }
            .foregroundColor(selected ? .white:.coachMuted)
            .padding(.horizontal,14).padding(.vertical,8)
            .background(selected ? accentColor.opacity(0.22):Color.clear).cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(selected ? accentColor.opacity(0.5):Color.clear,lineWidth:1))
        }
    }
}

struct RankMedal: View {
    let rank: Int
    var body: some View {
        switch rank {
        case 1: Image(systemName:"medal.fill").foregroundColor(.coachGold).font(.system(size:16))
        case 2: Image(systemName:"medal.fill").foregroundColor(Color(red:0.75,green:0.78,blue:0.82)).font(.system(size:16))
        case 3: Image(systemName:"medal.fill").foregroundColor(Color(red:0.80,green:0.50,blue:0.25)).font(.system(size:16))
        default: Text("\(rank)").font(.system(size:13,weight:.bold,design:.monospaced)).foregroundColor(.coachMuted)
        }
    }
}

struct ActionKPICard: View {
    let stat: ActionStats; let unit: String
    var body: some View {
        VStack(alignment:.leading,spacing:6){
            Text(stat.action).font(.system(size:13,weight:.bold,design:.rounded)).foregroundColor(Color.actionColor(stat.action))
            Text(String(format:"%.1f \(unit)",stat.avgHeight)).font(.system(size:20,weight:.black,design:.monospaced)).foregroundColor(.white)
            Text("avg · \(stat.count) trials").font(.system(size:10)).foregroundColor(.coachMuted)
        }
        .padding(14).frame(maxWidth:.infinity,alignment:.leading)
        .background(Color.coachCard).cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(Color.actionColor(stat.action).opacity(0.3)))
    }
}

struct SortHeader: View {
    let title: String; let key: RawTableTabView.SortKey
    @Binding var current: RawTableTabView.SortKey; @Binding var asc: Bool
    init(_ t:String,key:RawTableTabView.SortKey,current:Binding<RawTableTabView.SortKey>,asc:Binding<Bool>){
        title=t;self.key=key;_current=current;_asc=asc
    }
    var body: some View {
        Button{if current==key{asc.toggle()}else{current=key;asc=false}} label:{
            HStack(spacing:3){
                Text(title).font(.system(size:10,weight:.semibold)).foregroundColor(current==key ? .coachAccent:.coachMuted)
                if current==key{Image(systemName:asc ? "chevron.up":"chevron.down").font(.system(size:8,weight:.bold)).foregroundColor(.coachAccent)}
            }
        }
    }
}

struct PodiumView: View {
    let subjects: [SubjectStats]; let metric: CoachMetric
    var body: some View {
        CoachCard(title:"Top Performers",subtitle:"Ranked by average \(metric.rawValue.lowercased())"){
            HStack(alignment:.bottom,spacing:10){
                if subjects.count>=2{PodiumBlock(stat:subjects[1],height:70,label:"2nd",metric:metric)}
                PodiumBlock(stat:subjects[0],height:95,label:"1st",metric:metric)
                if subjects.count>=3{PodiumBlock(stat:subjects[2],height:52,label:"3rd",metric:metric)}
            }.padding(.vertical,8)
        }
    }
}

struct PodiumBlock: View {
    let stat: SubjectStats; let height: CGFloat; let label: String; let metric: CoachMetric
    var body: some View {
        VStack(spacing:4){
            Text(stat.subject).font(.system(size:12,weight:.bold,design:.rounded)).foregroundColor(.white)
            Text(String(format:"%.1f \(metric.unit)",stat.avgHeight))
                .font(.system(size:11,weight:.semibold,design:.monospaced)).foregroundColor(Color.subjectColor(stat.subject))
            ZStack{
                RoundedRectangle(cornerRadius:8)
                    .fill(LinearGradient(colors:[Color.subjectColor(stat.subject).opacity(0.4),Color.subjectColor(stat.subject).opacity(0.15)],startPoint:.top,endPoint:.bottom))
                    .overlay(RoundedRectangle(cornerRadius:8).strokeBorder(Color.subjectColor(stat.subject).opacity(0.4)))
                Text(label).font(.system(size:12,weight:.black,design:.rounded)).foregroundColor(Color.subjectColor(stat.subject))
            }.frame(width:80,height:height)
        }.frame(maxWidth:.infinity)
    }
}

// MARK: ─── Entry Point ────────────────────────────────────────────────────────

struct CoachAnalysisView: View {
    @State private var isUnlocked = false
    let data: [FlightTrialRecord] = FlightTrialRecord.sampleData
    var body: some View {
        if isUnlocked {
            CoachAnalysisDashboardView(data:data)
        } else {
            CoachAccessGateView(isUnlocked:$isUnlocked).onAppear{isUnlocked=false}
        }
    }
}
