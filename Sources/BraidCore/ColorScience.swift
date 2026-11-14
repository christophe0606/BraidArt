import Foundation

public struct Lab: Sendable {
    public var l: Double
    public var a: Double
    public var b: Double
    public init(_ l: Double, _ a: Double, _ b: Double) { self.l=l; self.a=a; self.b=b }
    public init(sRGB c: RGB) {
        func linear(_ x: Double) -> Double { x<=0.04045 ? x/12.92 : pow((x+0.055)/1.055,2.4) }
        let r=linear(c.r), g=linear(c.g), b=linear(c.b)
        func f(_ x: Double) -> Double { x>216.0/24389 ? cbrt(x) : (24389.0/27*x+16)/116 }
        // Bradford-adapted sRGB to XYZ D50, matching Wolfram’s default Lab white point.
        let x=f((0.4360747*r+0.3850649*g+0.1430804*b)/0.96422)
        let y=f(0.2225045*r+0.7168786*g+0.0606169*b)
        let z=f((0.0139322*r+0.0971045*g+0.7141733*b)/0.82521)
        // Exact neutrals avoid hue noise from tiny matrix/float rounding errors.
        if c.r == c.g && c.g == c.b { self.init(116*y-16,0,0) }
        else { self.init(116*y-16,500*(x-y),200*(y-z)) }
    }
    /// CIEDE2000, kL = kC = kH = 1. Angles use radians internally.
    public func distance(to q: Lab) -> Double {
        let c1=hypot(a,b), c2=hypot(q.a,q.b), cm=(c1+c2)/2
        let cm7=pow(cm,7), k: Double=6103515625.0
        let g=0.5*(1-sqrt(cm7/(cm7+k)))
        let ap1=(1+g)*a, ap2=(1+g)*q.a
        let cp1=hypot(ap1,b), cp2=hypot(ap2,q.b)
        func hue(_ a: Double,_ b: Double) -> Double { let h=atan2(b,a); return h<0 ? h+2 * .pi : h }
        let h1=hue(ap1,b), h2=hue(ap2,q.b)
        let dl=q.l-l, dc=cp2-cp1
        var dh=h2-h1
        if cp1*cp2 == 0 { dh=0 } else if dh > .pi { dh-=2 * .pi } else if dh < -.pi { dh+=2 * .pi }
        let dH=2*sqrt(cp1*cp2)*sin(dh/2)
        let lm=(l+q.l)/2, cp=(cp1+cp2)/2
        var hm=h1+h2
        if cp1*cp2 != 0 {
            if abs(h1-h2) <= .pi { hm/=2 }
            else { hm=(hm + (hm<2 * .pi ? 2 * .pi : -2 * .pi))/2 }
        }
        let rad=Double.pi/180
        let t=1-0.17*cos(hm-30*rad)+0.24*cos(2*hm)+0.32*cos(3*hm+6*rad)-0.20*cos(4*hm-63*rad)
        let sl=1+0.015*pow(lm-50,2)/sqrt(20+pow(lm-50,2))
        let sc=1+0.045*cp, sh=1+0.015*cp*t
        let rt = -2*sqrt(pow(cp,7)/(pow(cp,7)+k))*sin(60*rad*exp(-pow((hm/rad-275)/25,2)))
        let x=dl/sl, y=dc/sc, z=dH/sh
        return sqrt(max(0,x*x+y*y+z*z+rt*y*z))
    }
}

public enum PaletteExtractor {
    /// Selects colors by perceptual diversity, preserving small accents instead of
    /// averaging them into larger regions. Each candidate is the mean of a small
    /// RGB histogram bin. Keep the main color and tonal endpoints, then choose
    /// additional colors by distance. No object recognition is involved.
    public static func distinctColors(in image: PixelImage, count: Int, minimumDistance: Double = 12) -> [RGB] {
        guard !image.pixels.isEmpty else { return [.black,.white] }
        struct Bin {
            var sum=RGB.black
            var count=0
            var color: RGB { sum*(1/Double(count)) }
        }
        var histogram=[Int:Bin]()
        for color in image.pixels {
            let r=min(31,max(0,Int(color.r*32))),g=min(31,max(0,Int(color.g*32))),b=min(31,max(0,Int(color.b*32)))
            let key=r*1024+g*32+b
            var bin=histogram[key,default:Bin()]
            bin.sum=bin.sum+color;bin.count+=1;histogram[key]=bin
        }
        // Ignore isolated bins in large photographs, but retain single pixels in
        // small sampled projects where an eye highlight may be only one pixel.
        let support=image.pixels.count>=4096 ? 2 : 1
        let populated=histogram.keys.sorted().map { histogram[$0]! }
        let supported=populated.filter { $0.count>=support }
        let bins=supported.isEmpty ? populated : supported
        guard let first=bins.indices.max(by:{bins[$0].count<bins[$1].count}) else { return [.black,.white] }
        let colors=bins.map(\.color),labs=colors.map(Lab.init(sRGB:))
        var selected=[first],used=Set([first])
        var nearest=labs.map { $0.distance(to:labs[first]) }
        // Compare hue/chroma at a common lightness so extra brightness levels
        // of the same color do not crowd out different color families.
        let chroma=labs.map { Lab(60,$0.a,$0.b) }
        var nearestChroma=chroma.map { $0.distance(to:chroma[first]) }
        let separation=minimumDistance.isFinite ? max(0,minimumDistance) : 12
        // Small highlights matter to a drawing even when they are fairly close
        // to the dominant light skin/hair color. Reserve the tonal endpoints
        // before choosing the remaining hue accents.
        var endpoints=count>=3 ? [labs.indices.min{labs[$0].l<labs[$1].l}!,labs.indices.max{labs[$0].l<labs[$1].l}!] : []
        // Once shadows have a representative, favor colors visible in the
        // midtones over additional colored shadows. This leaves room for hair,
        // eye and lip accents in photographs with a large dark tonal range.
        func priority(_ i: Int) -> Double { (nearestChroma[i]+0.05*nearest[i])*min(1,max(0,labs[i].l)/40) }
        while selected.count<max(1,count) {
            var endpoint:Int?
            while !endpoints.isEmpty,endpoint == nil {
                let next=endpoints.removeFirst()
                if !used.contains(next),nearest[next]>=separation { endpoint=next }
            }
            guard let next=endpoint ?? bins.indices.filter({!used.contains($0) && nearest[$0]>=separation}).max(by:{priority($0)<priority($1)}) else { break }
            selected.append(next);used.insert(next)
            for i in bins.indices where !used.contains(i) {
                nearest[i]=min(nearest[i],labs[i].distance(to:labs[next]))
                // Tonal endpoints cover brightness; they should not stand in
                // for a muted cool accent simply because both are nearly gray.
                if endpoint == nil { nearestChroma[i]=min(nearestChroma[i],chroma[i].distance(to:chroma[next])) }
            }
        }
        return selected.map{colors[$0]}.sorted{Lab(sRGB:$0).l<Lab(sRGB:$1).l}
    }

    /// Deterministic Lab clustering, followed by population-weighted merging of nearby colors.
    /// `count` is a maximum; `minimumDistance` is the minimum CIEDE2000 separation
    /// between returned colors. Zero keeps the original shade-preserving extraction.
    public static func dominantColors(in image: PixelImage, count: Int, minimumDistance: Double = 12) -> [RGB] {
        let samples=Array(image.pixels.enumerated().filter { $0.offset % max(1,image.pixels.count/4096) == 0 }.map(\.element))
        guard !samples.isEmpty else { return [.black,.white] }
        let target=max(1,min(count,samples.count))
        let separation=minimumDistance.isFinite ? max(0,minimumDistance) : 12
        // Start with extra candidates so several shades of a large region do not
        // use up the requested palette before a different color is represented.
        let candidateCount=separation>0 ? max(target,min(32,target*4)) : target
        let labs=samples.map(Lab.init(sRGB:))
        func d(_ a: Lab,_ b: Lab)->Double { pow(a.l-b.l,2)+pow(a.a-b.a,2)+pow(a.b-b.b,2) }
        var centers=[labs[0]], colors=[samples[0]]
        var nearest=labs.map { d($0,centers[0]) }
        for _ in 1..<candidateCount {
            let idx=nearest.indices.max { nearest[$0]<nearest[$1] }!
            if nearest[idx] < 0.01 { break }
            centers.append(labs[idx]); colors.append(samples[idx])
            for i in labs.indices { nearest[i]=min(nearest[i],d(labs[i],labs[idx])) }
        }
        var sums=[RGB](), counts=[Int]()
        for _ in 0..<16 {
            sums=Array(repeating: RGB.black,count: centers.count); counts=Array(repeating: 0,count: centers.count)
            for i in samples.indices {
                let cluster=centers.indices.min { d(labs[i],centers[$0]) < d(labs[i],centers[$1]) }!
                sums[cluster]=sums[cluster]+samples[i]; counts[cluster]+=1
            }
            for i in centers.indices where counts[i]>0 { colors[i]=sums[i]*(1/Double(counts[i])); centers[i]=Lab(sRGB: colors[i]) }
        }
        struct Cluster {
            var sum: RGB
            var count: Int
            var color: RGB { sum*(1/Double(count)) }
            var lab: Lab { Lab(sRGB:color) }
        }
        var clusters=counts.indices.filter { counts[$0]>0 }.map { Cluster(sum:sums[$0],count:counts[$0]) }
        if separation>0 {
            while clusters.count>1 {
                let labs=clusters.map(\.lab)
                var closest=(first:0,second:1,distance:Double.infinity)
                for i in labs.indices {
                    for j in (i+1)..<labs.count {
                        let distance=labs[i].distance(to:labs[j])
                        if distance<closest.distance { closest=(i,j,distance) }
                    }
                }
                guard clusters.count>target || closest.distance<separation else { break }
                let other=clusters.remove(at:closest.second)
                clusters[closest.first].sum=clusters[closest.first].sum+other.sum
                clusters[closest.first].count+=other.count
                // Recompute distances after every merge: the weighted mean can
                // move close to another color that was previously far enough away.
            }
        }
        return clusters.map(\.color).sorted{Lab(sRGB:$0).l < Lab(sRGB:$1).l}
    }
}
