import Foundation

/// Fits tile averages while keeping every retained strand visibly separated
/// from the background. The score uses CIEDE2000, like the partition solver,
/// without imposing strand continuity between neighboring tiles.
public enum BackgroundExtractor {
    /// The default visibility threshold; individual extractions use the saved
    /// settings value, independently of the separation between strand colors.
    public static let minimumStrandDistance=Settings.defaultBackgroundMinimumDistance
    public struct Match:Sendable {
        public let background:RGB
        public let palette:[RGB]
    }

    public static func matching(_ image:PixelImage,settings:Settings) throws -> Match {
        try settings.validate()
        let samples=weightedSamples(image.pixels.map { settings.grayscale ? neutral($0) : $0 })
        let total=max(1,Double(samples.reduce(0) { $0+$1.count }))
        let mean=samples.reduce(RGB.black) { $0+$1.color*(Double($1.count)/total) }
        let targets=samples.map { (lab:Lab(sRGB:$0.color),count:Double($0.count)) }
        let strandLabs=settings.palette.map(Lab.init(sRGB:))

        // Derive the background's affine contribution from the shared tile model
        // rather than duplicating its crossing and curved-strand area formulas.
        var black=settings;black.background = .black
        var white=settings;white.background = .white;white.palette=[.black]
        let dark=TileData(settings:black).allTiles
        let weights=Dictionary(uniqueKeysWithValues:TileData(settings:white).allTiles.map { ($0.kind,$0.average.r) })
        struct Mixture:Hashable { let strands:RGB;let backgroundWeight:Double;let strandMask:Int }
        var seen=Set<Mixture>()
        let mixtures=dark.compactMap { tile -> Mixture? in
            let mixture=Mixture(strands:tile.average,backgroundWeight:weights[tile.kind]!,
                                strandMask:(1<<tile.firstColor)|(1<<tile.secondColor))
            return seen.insert(mixture).inserted ? mixture : nil
        }
        func bounded(_ color:RGB)->RGB {
            let color=RGB(min(1,max(0,color.r)),min(1,max(0,color.g)),min(1,max(0,color.b)))
            return settings.grayscale ? neutral(color) : color
        }
        func visibleStrands(_ background:RGB)->Int {
            let lab=Lab(sRGB:background)
            return strandLabs.indices.reduce(0) { mask,i in
                strandLabs[i].distance(to:lab)>=settings.backgroundMinimumDistance ? mask|(1<<i) : mask
            }
        }
        func averages(_ background:RGB,mask:Int)->[RGB] {
            mixtures.filter { $0.strandMask & mask == $0.strandMask }.map { $0.strands+background*$0.backgroundWeight }
        }
        var candidates=[bounded(settings.background),.black,.white,.gray,mean]+settings.palette+samples.prefix(8).map(\.color)
        // A good background can lie beyond the source colors: compensate for
        // the strands' contribution when matching the average image tone.
        for color in settings.palette {
            for weight in Set(mixtures.map(\.backgroundWeight)).sorted() where weight>1e-8 {
                candidates.append(bounded((mean+color * -(1-weight))*(1/weight)))
            }
        }
        let preferred=Set(candidates.map(bounded))
        if settings.grayscale {
            for i in 0...256 { let v=Double(i)/256;candidates.append(RGB(v,v,v)) }
        } else {
            for r in 0...8 { for g in 0...8 { for b in 0...8 {
                candidates.append(RGB(Double(r)/8,Double(g)/8,Double(b)/8))
            } } }
        }
        var tested=Set<RGB>()
        let options=candidates.map(bounded).filter { tested.insert($0).inserted }.map { (color:$0,mask:visibleStrands($0)) }
        // Keep every extracted strand whenever possible. If their exclusion
        // regions cover the available background space, omit the fewest colors.
        var strandCount=options.map { $0.mask.nonzeroBitCount }.max() ?? 0
        guard strandCount>0 else {
            throw BraidError.invalid("No background can meet the selected contrast with these strand colors. Lower Background contrast and extract again.")
        }
        let eligible=options.filter { $0.mask.nonzeroBitCount==strandCount }
        func approximateScore(_ background:RGB,mask:Int)->Double {
            let colors=averages(background,mask:mask)
            return samples.prefix(16).reduce(0) { sum,sample in
                let closest=colors.reduce(Double.infinity) { nearest,color in
                    let dr=sample.color.r-color.r,dg=sample.color.g-color.g,db=sample.color.b-color.b
                    return min(nearest,dr*dr+dg*dg+db*db)
                }
                return sum+Double(sample.count)*closest
            }
        }
        // Rank the coarse grid cheaply, then use the solver's perceptual metric
        // for promising candidates and local refinement. Ties retain grid order.
        var ranked:[(index:Int,color:RGB,mask:Int,score:Double)]=[]
        for (index,option) in eligible.enumerated() {
            ranked.append((index,option.color,option.mask,approximateScore(option.color,mask:option.mask)))
        }
        ranked.sort { lhs,rhs in lhs.score == rhs.score ? lhs.index<rhs.index : lhs.score<rhs.score }
        var seeds=eligible.filter { preferred.contains($0.color) }
        seeds.append(contentsOf:ranked.prefix(16).map { (color:$0.color,mask:$0.mask) })
        func score(_ background:RGB,mask:Int,limit:Double = .infinity) throws -> Double {
            try Task.checkCancellation()
            let labs=averages(background,mask:mask).map(Lab.init(sRGB:))
            var sum=0.0
            for target in targets {
                var closest=Double.infinity
                for lab in labs {
                    closest=min(closest,target.lab.distance(to:lab))
                    if closest<1e-10 { break }
                }
                sum+=target.count*closest
                if sum>=limit { break }
            }
            return sum
        }
        var best=eligible[0].color,bestMask=eligible[0].mask,bestScore=Double.infinity
        tested=[]
        func consider(_ background:RGB) throws {
            guard tested.insert(background).inserted else { return }
            let mask=visibleStrands(background),count=mask.nonzeroBitCount
            guard count>=strandCount else { return }
            let value=try score(background,mask:mask,limit:count>strandCount ? .infinity : bestScore)
            if count>strandCount || value<bestScore {
                best=background;bestMask=mask;bestScore=value;strandCount=count
            }
        }
        for candidate in seeds { try consider(candidate.color) }
        // Refine only within the hard visibility constraint. Gray mode searches
        // one neutral axis across the full black-to-white range.
        for step in [0.2,0.08,0.03,0.01,0.003] {
            for _ in 0..<2 {
                let original=best
                for axis in 0..<(settings.grayscale ? 1 : 3) {
                    for direction in [-1.0,1] {
                        let delta=step*direction
                        if settings.grayscale { try consider(bounded(RGB(best.r+delta,best.g+delta,best.b+delta))) }
                        else { try consider(bounded(RGB(best.r+(axis==0 ? delta : 0),best.g+(axis==1 ? delta : 0),best.b+(axis==2 ? delta : 0)))) }
                    }
                }
                if best==original { break }
            }
        }
        let palette=settings.palette.indices.filter { bestMask & (1<<$0) != 0 }.map { settings.palette[$0] }
        return Match(background:best,palette:palette)
    }

    /// Image preparation already produces gray; equalize rounding differences in
    /// its channels so extracted colors and background are exactly neutral.
    public static func neutral(_ color:RGB)->RGB {
        let value=(color.r+color.g+color.b)/3
        return RGB(value,value,value)
    }

    private struct Sample { let color:RGB;let count:Int }
    private static func weightedSamples(_ pixels:[RGB])->[Sample] {
        var counts=[RGB:Int]()
        for color in pixels { counts[color,default:0]+=1 }
        let ordered=counts.keys.sorted {
            if $0.r != $1.r { return $0.r<$1.r }
            if $0.g != $1.g { return $0.g<$1.g }
            return $0.b<$1.b
        }
        if ordered.count>128 {
            // Deterministic, population-weighted quantiles of actual pixel colors.
            // This bounds the interactive search without spatial sampling aliases.
            var sampled=[RGB:Int](),index=0,cumulative=counts[ordered[0]]!
            for i in 0..<128 {
                let rank=(Double(i)+0.5)*Double(pixels.count)/128
                while Double(cumulative)<=rank,index<ordered.count-1 { index+=1;cumulative+=counts[ordered[index]]! }
                sampled[ordered[index],default:0]+=1
            }
            counts=sampled
        }
        return counts.map { Sample(color:$0.key,count:$0.value) }.sorted {
            if $0.count != $1.count { return $0.count>$1.count }
            if $0.color.r != $1.color.r { return $0.color.r<$1.color.r }
            if $0.color.g != $1.color.g { return $0.color.g<$1.color.g }
            return $0.color.b<$1.color.b
        }
    }
}
