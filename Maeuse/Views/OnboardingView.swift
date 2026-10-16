import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    var onDismiss: (Bool) -> Void
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 44
    @ScaledMetric(relativeTo: .subheadline) private var stepBadgeSize = 30

    var body: some View {
        ZStack {
            onboardingBackground.ignoresSafeArea()
            FloatingCheeseHole(size: 120, duration: 9, fill: onboardingHole, stroke: Color.maeusCardBorder).offset(x: -185, y: -410)
            FloatingCheeseHole(size: 70, duration: 7, delay: 1, fill: onboardingHole, stroke: Color.maeusCardBorder).offset(x: 205, y: -260)
            FloatingCheeseHole(size: 40, duration: 8, delay: 2, fill: onboardingHole, stroke: Color.maeusCardBorder).offset(x: -210, y: 255)
            GeometryReader { geometry in
                let wide = geometry.size.width >= 760 && !dynamicTypeSize.isAccessibilitySize
                ScrollView {
                    Group {
                        if wide {
                            HStack(alignment: .center, spacing: 36) {
                                introduction.frame(maxWidth: 300)
                                VStack(spacing: 20) {
                                    steps
                                    startButton
                                    slangHint
                                }.frame(maxWidth: 520)
                            }
                            .accessibilityIdentifier("welcome-wide")
                        } else {
                            VStack(spacing: 18) {
                                introduction
                                steps
                                startButton
                                slangHint
                            }
                        }
                    }
                    .foregroundStyle(Color.maeusForeground)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 28)
                    .frame(maxWidth: wide ? 1040 : 600)
                    .frame(minHeight: geometry.size.height)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
                .accessibilityIdentifier("welcome-scroll")
            }
        }
        .fontDesign(.rounded)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.6, dampingFraction: 0.62)) { appeared = true }
        }
    }

    private var introduction: some View {
        VStack(spacing: 14) {
            MouseCoin(size: 92, fill: logoCoinFill, shadow: colorScheme == .dark ? 0 : 6) {
                Text("€").font(.system(size: 42, weight: .heavy, design: .rounded)).foregroundStyle(Color.maeusInk)
            }
            .accessibilityHidden(true)
            .scaleEffect(appeared ? 1 : 0.82).opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 10)
            Text("Mäuse").font(.system(size: titleSize, weight: .heavy, design: .rounded)).tracking(-1.5)
            Text(loc("SplitSubtitle")).font(.body.weight(.bold)).multilineTextAlignment(.center)
        }
    }

    private var steps: some View {
        VStack(spacing: 12) {
            step(1, loc("LogExpenseTitle"), loc("LogExpenseDesc"), delay: 0.1)
            step(2, loc("ChooseSplitTitle"), loc("ChooseSplitDesc"), delay: 0.22)
            step(3, loc("TrackTotalsTitle"), loc("TrackTotalsDesc"), delay: 0.34)
        }
    }

    private var startButton: some View {
        Button(loc("GetStarted")) {
            onDismiss(true)
            withAnimation(.easeOut(duration: 0.3)) { isPresented = false }
        }
        .font(.headline.weight(.heavy))
        .foregroundStyle(ctaForeground)
        .frame(maxWidth: .infinity, minHeight: 44).padding(.vertical, 12)
        .background {
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            ZStack { shape.fill(ctaShadow).offset(x: 4, y: 4); shape.fill(ctaBackground) }
        }
        .accessibilityIdentifier("welcome-start")
    }

    private var slangHint: some View {
        Text(loc("SlangHint")).font(.footnote.weight(.bold)).italic()
            .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.center)
    }

    private func step(_ number: Int, _ title: String, _ subtitle: String, delay: Double) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)").font(.subheadline.weight(.heavy))
                .frame(width: stepBadgeSize, height: stepBadgeSize)
                .foregroundStyle(Color.maeusInk)
                .background(Color.maeusCheese, in: Circle()).overlay(Circle().stroke(Color.maeusInk, lineWidth: 2))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline.weight(.heavy))
                Text(subtitle).font(.subheadline.weight(.semibold)).foregroundStyle(Color.maeusTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background {
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            ZStack { shape.fill(Color.maeusInk).offset(x: 3, y: 3); shape.fill(onboardingCard); shape.stroke(Color.maeusCardBorder, lineWidth: 2.5) }
        }
        .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 8)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.5).delay(delay), value: appeared)
    }

    private var onboardingBackground: Color { colorScheme == .dark ? Color(hex: "211A09") : .maeusCheese }
    private var onboardingHole: Color { colorScheme == .dark ? Color(hex: "2B2210") : Color(hex: "FFF6DE") }
    private var onboardingCard: Color { colorScheme == .dark ? Color(hex: "31280F") : Color(hex: "FFF6DE") }
    private var logoCoinFill: Color { colorScheme == .dark ? .maeusCheese : .white }
    private var ctaBackground: Color { colorScheme == .dark ? .maeusCheese : .maeusInk }
    private var ctaForeground: Color { colorScheme == .dark ? .maeusInk : .maeusCheese }
    private var ctaShadow: Color { colorScheme == .dark ? .black : Color.maeusInk.opacity(0.3) }
}
