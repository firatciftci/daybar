import AppKit
import SwiftUI

struct WeatherBadge: View {
    let forecast: DayForecast
    @State private var presented = false
    @State private var pinned = false
    @State private var overBadge = false
    @State private var overCard = false
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        Button {
            hoverTask?.cancel()
            if pinned {
                presented = false
            } else {
                pinned = true
                presented = true
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: forecast.symbolName)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 12))
                    .accessibilityHidden(true)
                Text(forecast.high)
                    .foregroundStyle(.primary)
                Text(forecast.low)
                    .foregroundStyle(.tertiary)
            }
            .font(.system(size: 11.5, weight: .medium).monospacedDigit())
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.primary.opacity(overBadge || presented ? 0.08 : 0), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .padding(.horizontal, -6)
        .animation(Motion.fade, value: overBadge || presented)
        .onHover { inside in
            overBadge = inside
            scheduleHover()
        }
        .popover(isPresented: $presented, arrowEdge: .bottom) {
            WeatherCard(forecast: forecast)
                .onHover { inside in
                    overCard = inside
                    scheduleHover()
                }
        }
        .onChange(of: presented) { _, shown in
            if !shown { pinned = false }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.weatherBadgeLabel(forecast.condition, forecast.high, forecast.low))
        .accessibilityHint(L.weatherBadgeHint)
        .accessibilityAddTraits(.isButton)
    }

    private func scheduleHover() {
        hoverTask?.cancel()
        let inside = overBadge || overCard
        hoverTask = Task {
            try? await Task.sleep(for: .milliseconds(inside ? 450 : 300))
            guard !Task.isCancelled else { return }
            if overBadge || overCard {
                presented = true
            } else if !pinned {
                presented = false
            }
        }
    }
}

struct WeatherCard: View {
    let forecast: DayForecast
    @Environment(WeatherModel.self) private var weather
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(Fmt.longDay(forecast.date))
                Spacer(minLength: 8)
                if let place = weather.placeName {
                    Label(place, systemImage: "location.fill")
                        .labelStyle(.titleAndIcon)
                        .imageScale(.small)
                        .lineLimit(1)
                }
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Image(systemName: forecast.symbolName)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 32))
                    .frame(width: 40)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(forecast.condition)
                        .font(.system(size: 15, weight: .semibold))
                    Text(L.weatherHighLow(forecast.high, forecast.low))
                        .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
                if let value = forecast.precipitation { row(L.precipitation, "drop.fill", value) }
                if let value = forecast.wind { row(L.wind, "wind", value) }
                if let value = forecast.uvIndex { row(L.uvIndex, "sun.max.fill", value) }
                if let date = forecast.sunrise { row(L.sunrise, "sunrise.fill", Fmt.time(date)) }
                if let date = forecast.sunset { row(L.sunset, "sunset.fill", Fmt.time(date)) }
            }
            .font(.system(size: 12))
            VStack(spacing: 8) {
                Button {
                    if let url = URL(string: "weather://") {
                        NSWorkspace.shared.open(url)
                    }
                    dismiss()
                } label: {
                    Label(L.openWeather, systemImage: "arrow.up.forward.app")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                if let credit = weather.credit {
                    Link(credit.label, destination: credit.legalPage)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(width: 260)
    }

    private func row(_ title: String, _ symbol: String, _ value: String) -> some View {
        GridRow {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol)
                    .symbolRenderingMode(.multicolor)
                    .frame(width: 16)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
