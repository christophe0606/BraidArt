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
    /// Deterministic Lab k-means with farthest-point seeds. Returned as editable sRGB colors.
    public static func dominantColors(in image: PixelImage, count: Int) -> [RGB] {
        let samples=Array(image.pixels.enumerated().filter { $0.offset % max(1,image.pixels.count/4096) == 0 }.map(\.element))
        guard !samples.isEmpty else { return [.black,.white] }
        let labs=samples.map(Lab.init(sRGB:))
        func d(_ a: Lab,_ b: Lab)->Double { pow(a.l-b.l,2)+pow(a.a-b.a,2)+pow(a.b-b.b,2) }
        var centers=[labs[0]], colors=[samples[0]]
        for _ in 1..<max(1,count) {
            let idx=labs.indices.max { i,j in
                centers.map{d(labs[i],$0)}.min()! < centers.map{d(labs[j],$0)}.min()!
            }!
            if centers.map({d(labs[idx],$0)}).min()! < 0.01 { break }
            centers.append(labs[idx]); colors.append(samples[idx])
        }
        for _ in 0..<16 {
            var sums=Array(repeating: RGB.black,count: centers.count), counts=Array(repeating: 0,count: centers.count)
            for i in samples.indices {
                let cluster=centers.indices.min { d(labs[i],centers[$0]) < d(labs[i],centers[$1]) }!
                sums[cluster]=sums[cluster]+samples[i]; counts[cluster]+=1
            }
            for i in centers.indices where counts[i]>0 { colors[i]=sums[i]*(1/Double(counts[i])); centers[i]=Lab(sRGB: colors[i]) }
        }
        return colors.sorted{Lab(sRGB:$0).l < Lab(sRGB:$1).l}
    }
}
