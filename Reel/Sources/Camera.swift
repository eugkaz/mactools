import Foundation

/// Автомонтаж: где приближать и как плавно двигать камеру и курсор
enum AutoEdit {
    /// Клики, близкие по времени и месту, объединяются в один «наезд»
    static func segments(_ m: RecMeta, zoom: Double) -> [ZoomSeg] {
        let clicks = m.clicks.sorted { $0[0] < $1[0] }
        var groups: [[[Double]]] = []
        for c in clicks {
            if var g = groups.last, let last = g.last {
                let cx = g.map { $0[1] }.reduce(0, +) / Double(g.count)
                let cy = g.map { $0[2] }.reduce(0, +) / Double(g.count)
                if c[0] - last[0] < 3.2 && hypot(c[1] - cx, c[2] - cy) < 0.45 {
                    g.append(c); groups[groups.count - 1] = g; continue
                }
            }
            groups.append([c])
        }
        var segs: [ZoomSeg] = []
        for g in groups {
            let s = max(0, g.first![0] - 0.9), e = min(m.duration, g.last![0] + 2.0)
            if var last = segs.last, s - last.end < 1.2 {      // почти подряд — не отъезжаем
                last.end = e; segs[segs.count - 1] = last
            } else {
                segs.append(ZoomSeg(start: s, end: max(e, s + 1.6), scale: zoom))
            }
        }
        return segs
    }
}

/// Заранее посчитанные траектории (60 кадров/с) — монтаж детерминирован и плавный
struct Track {
    static let fps = 60.0
    var zoom: [Double] = [], cx: [Double] = [], cy: [Double] = []
    var curX: [Double] = [], curY: [Double] = []

    init(meta m: RecMeta, segs: [ZoomSeg], style: Style) {
        let n = Int(m.duration * Self.fps) + 2
        let dt = 1 / Self.fps
        var si = 0
        // пружины
        var z = 1.0, zv = 0.0
        var x = 0.5, xv = 0.0, y = 0.5, yv = 0.0
        var kx = m.samples.first?[1] ?? 0.5, kxv = 0.0, ky = m.samples.first?[2] ?? 0.5, kyv = 0.0
        var tx = 0.5, ty = 0.5      // цель камеры с «мёртвой зоной»
        zoom.reserveCapacity(n); cx.reserveCapacity(n); cy.reserveCapacity(n); curX.reserveCapacity(n); curY.reserveCapacity(n)

        for i in 0..<n {
            let t = Double(i) * dt
            // сырой курсор: линейная интерполяция по выборкам
            while si + 1 < m.samples.count, m.samples[si + 1][0] <= t { si += 1 }
            var rx = 0.5, ry = 0.5
            if !m.samples.isEmpty {
                let a = m.samples[si]
                if si + 1 < m.samples.count {
                    let b = m.samples[si + 1]
                    let k = b[0] > a[0] ? min(1, max(0, (t - a[0]) / (b[0] - a[0]))) : 0
                    rx = a[1] + (b[1] - a[1]) * k; ry = a[2] + (b[2] - a[2]) * k
                } else { rx = a[1]; ry = a[2] }
            }
            // плавный курсор
            if style.smoothCursor {
                Self.spring(&kx, &kxv, rx, 26, dt); Self.spring(&ky, &kyv, ry, 26, dt)
            } else { kx = rx; ky = ry }

            // нужный зум
            var zt = 1.0
            if style.autoZoom, let s = segs.first(where: { $0.enabled && t >= $0.start && t <= $0.end }) { zt = s.scale }
            Self.spring(&z, &zv, zt, 5.2, dt)

            // камера: держит курсор в кадре, но не дёргается от мелких движений
            if zt > 1.01 {
                let dz = 0.22 / zt
                if kx - tx > dz { tx = kx - dz } else if tx - kx > dz { tx = kx + dz }
                if ky - ty > dz { ty = ky - dz } else if ty - ky > dz { ty = ky + dz }
            } else { tx = 0.5; ty = 0.5 }
            Self.spring(&x, &xv, tx, 4.2, dt); Self.spring(&y, &yv, ty, 4.2, dt)
            let half = 0.5 / max(z, 1)
            let ccx = min(max(x, half), 1 - half), ccy = min(max(y, half), 1 - half)

            zoom.append(z); cx.append(ccx); cy.append(ccy); curX.append(kx); curY.append(ky)
        }
    }

    /// Критически задемпфированная пружина (устойчива при любом шаге)
    static func spring(_ x: inout Double, _ v: inout Double, _ target: Double, _ omega: Double, _ dt: Double) {
        let f = 1 + 2 * dt * omega, oo = omega * omega, hoo = dt * oo, hhoo = dt * hoo
        let det = 1 / (f + hhoo)
        let nx = (f * x + dt * v + hhoo * target) * det
        let nv = (v + hoo * (target - x)) * det
        x = nx; v = nv
    }

    func at(_ t: Double) -> (z: Double, cx: Double, cy: Double, px: Double, py: Double) {
        guard !zoom.isEmpty else { return (1, 0.5, 0.5, 0.5, 0.5) }
        let f = max(0, t * Self.fps)
        let i = min(Int(f), zoom.count - 1), j = min(i + 1, zoom.count - 1)
        let k = f - Double(Int(f))
        func l(_ a: [Double]) -> Double { a[i] + (a[j] - a[i]) * k }
        return (l(zoom), l(cx), l(cy), l(curX), l(curY))
    }
}
