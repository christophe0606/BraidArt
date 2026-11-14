import Foundation

public struct Block: Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int
    public init(x: Int,y: Int,width: Int,height: Int) { self.x=x;self.y=y;self.width=width;self.height=height }
}
public struct BlockProblem: Sendable {
    public var lp: String
    public var warmStart: String
    public var block: Block
    public var left: [Int]?
    public var top: [Int]?
}

public enum PartitionSolver {
    public static func makeProblem(block: Block, image: PixelImage, data: TileData, costs: CostTable,
                                   left: [Int]? = nil, top: [Int]? = nil) throws -> BlockProblem {
        guard block.width>0,block.height>0,block.x>=0,block.y>=0,block.x+block.width<=image.width,block.y+block.height<=image.height,
              left == nil || left?.count==block.height,top == nil || top?.count==block.width,
              costs.tileCount==data.allTiles.count,costs.values.count==image.width*image.height*costs.tileCount,
              (left ?? []).allSatisfy({data.allTiles.indices.contains($0-1)}),
              (top ?? []).allSatisfy({data.allTiles.indices.contains($0-1)}) else { throw BraidError.invalid("Invalid partition or boundary dimensions.") }
        let n=data.allTiles.count
        func v(_ cell: Int,_ tileID: Int)->String { "x\(cell)_\(tileID)" }
        func terms(_ cell: Int,_ ids: [Int],_ sign: String = "+") -> String { ids.map{"\(sign) \(v(cell,$0))"}.joined(separator:" ") }
        var lines=["Minimize"," obj:"]
        for r in 0..<block.height { for c in 0..<block.width {
            let p=(block.y+r)*image.width+block.x+c,cell=r*block.width+c
            lines.append(data.allTiles.map { String(format:" + %.9f %@",locale:Locale(identifier:"en_US_POSIX"),costs[p,$0.id-1],v(cell,$0.id)) }.joined())
        }}
        lines.append("Subject To")
        for r in 0..<block.height { for c in 0..<block.width {
            let cell=r*block.width+c
            lines.append(" choose\(cell): \(terms(cell,Array(1...n))) = 1")
            if c+1<block.width {
                for group in data.topologyH.dropLast() { lines.append(" h\(cell)_\(group.color): \(terms(cell,group.outgoing)) \(terms(cell+1,group.incoming,"-")) = 0") }
            }
            if r+1<block.height {
                for group in data.topologyV.dropLast() { lines.append(" v\(cell)_\(group.color): \(terms(cell,group.outgoing)) \(terms(cell+block.width,group.incoming,"-")) = 0") }
            }
            if c==0,let left=left {
                let color=data.allTiles[left[r]-1].right
                lines.append(" left\(r): \(terms(cell,data.allTiles.filter{$0.left==color}.map(\.id))) = 1")
            }
            if r==0,let top=top {
                let color=data.allTiles[top[c]-1].bottom
                lines.append(" top\(c): \(terms(cell,data.allTiles.filter{$0.top==color}.map(\.id))) = 1")
            }
        }}
        lines.append("Binary")
        for cell in 0..<(block.width*block.height) { lines.append(data.allTiles.map{v(cell,$0.id)}.joined(separator:" ")) }
        lines.append("End")
        // A valid incumbent protects short interactive time limits from returning a relaxation.
        var seed=[Int](repeating:1,count:block.width*block.height),warm=[String]()
        for r in 0..<block.height { for c in 0..<block.width {
            let cell=r*block.width+c,p=(block.y+r)*image.width+block.x+c
            let lc: Int? = c>0 ? data.allTiles[seed[cell-1]-1].right : left.map{data.allTiles[$0[r]-1].right}
            let tc: Int? = r>0 ? data.allTiles[seed[cell-block.width]-1].bottom : top.map{data.allTiles[$0[c]-1].bottom}
            let candidates=data.allTiles.filter{(lc==nil || $0.left==lc) && (tc==nil || $0.top==tc)}
            guard let best=candidates.min(by:{costs[p,$0.id-1]<costs[p,$1.id-1]}) else { throw BraidError.invalid("Partition boundaries are infeasible.") }
            seed[cell]=best.id
            for tile in data.allTiles { warm.append("\(cell*n+tile.id-1) \(v(cell,tile.id)) \(tile.id==best.id ? 1 : 0)") }
        }}
        return BlockProblem(lp:lines.joined(separator:"\n")+"\n",warmStart:warm.joined(separator:"\n")+"\n",block:block,left:left,top:top)
    }
    public static func parseSolution(_ text: String, problem: BlockProblem, data: TileData) throws -> (ids: [Int], optimal: Bool, status: String) {
        let lines=text.components(separatedBy:.newlines)
        let header=lines.first ?? ""
        let lower=header.lowercased()
        guard (lower.hasPrefix("optimal") || lower.hasPrefix("stopped")), !lower.contains("no integer"), !lower.contains("infeasible"), !lower.contains("unbounded") else {
            throw BraidError.invalid("CBC did not return an integer solution: \(header)")
        }
        let count=problem.block.width*problem.block.height,n=data.allTiles.count
        var values=[Double](repeating:0,count:count*n),seen=Set<Int>()
        for line in lines.dropFirst() {
            let fields=line.split(whereSeparator:{$0.isWhitespace})
            guard let nameIndex=fields.firstIndex(where:{$0.hasPrefix("x")}),nameIndex+1<fields.count else { continue }
            let name=fields[nameIndex].dropFirst().split(separator:"_")
            guard name.count==2,let cell=Int(name[0]),let tile=Int(name[1]),(0..<count).contains(cell),(1...n).contains(tile),
                  let value=Double(fields[nameIndex+1]),value.isFinite,abs(value-value.rounded())<1e-5,(-1e-5...1.00001).contains(value) else { throw BraidError.invalid("CBC returned malformed or fractional tile choices.") }
            let index=cell*n+tile-1
            guard seen.insert(index).inserted else { throw BraidError.invalid("CBC returned duplicate variables.") }
            values[index]=value.rounded()
        }
        var ids=[Int]()
        for cell in 0..<count {
            let selected=(0..<n).filter{values[cell*n+$0]==1}
            guard selected.count==1 else { throw BraidError.invalid("CBC did not select exactly one tile per pixel.") }
            ids.append(selected[0]+1)
        }
        let w=problem.block.width,h=problem.block.height
        let rows=(0..<h).map{Array(ids[($0*w)..<(($0+1)*w)])}
        try SolveResult(solution:rows,reports:[],costBackend:"",elapsedSeconds:0).validate(tileData:data)
        for r in 0..<h { if let left=problem.left, data.allTiles[left[r]-1].right != data.allTiles[rows[r][0]-1].left { throw BraidError.invalid("CBC violated the left partition boundary.") } }
        for c in 0..<w { if let top=problem.top, data.allTiles[top[c]-1].bottom != data.allTiles[rows[0][c]-1].top { throw BraidError.invalid("CBC violated the top partition boundary.") } }
        // CBC may say 'Optimal (within gap tolerance)': that is feasible, not proven exact.
        return (ids,lower.hasPrefix("optimal") && !lower.contains("gap"),header)
    }
    public static func solve(image: PixelImage, settings: Settings, executable: URL,
                             progress: @escaping @Sendable (Double,String) async -> Void = {_,_ in}) async throws -> (TileData,SolveResult) {
        try settings.validate();try image.validate();try Task.checkCancellation()
        let started=Date(),data=TileData(settings:settings)
        await progress(0,"Computing CIE2000 tile errors…")
        let costs=try CostEngine.compute(image:image,tiles:data)
        let s=settings.partitionSize,cols=(image.width+s-1)/s,rows=(image.height+s-1)/s
        var solution=Array(repeating:Array(repeating:0,count:image.width),count:image.height),reports=[PartitionReport]()
        // Match partitionSolve: first row, first column, then row-major interior.
        var order=(0..<cols).map{(0,$0)}
        order += (1..<rows).map{($0,0)}
        for r in 1..<rows { for c in 1..<cols { order.append((r,c)) } }
        for (index,coordinate) in order.enumerated() {
            try Task.checkCancellation()
            let (r,c)=coordinate,x=c*s,y=r*s,w=min(s,image.width-x),h=min(s,image.height-y)
            await progress(Double(index)/Double(order.count),"Solving part \(index+1) of \(order.count) · \(w) × \(h) tiles")
            let left: [Int]? = c>0 ? (0..<h).map{solution[y+$0][x-1]} : nil
            let top: [Int]? = r>0 ? (0..<w).map{solution[y-1][x+$0]} : nil
            let problem=try makeProblem(block:Block(x:x,y:y,width:w,height:h),image:image,data:data,costs:costs,left:left,top:top)
            let blockStart=Date()
            let text=try await CBCRunner.solve(problem:problem,executable:executable,settings:settings)
            let parsed=try parseSolution(text,problem:problem,data:data)
            var objective=0.0
            for yy in 0..<h { for xx in 0..<w {
                let id=parsed.ids[yy*w+xx];solution[y+yy][x+xx]=id;objective+=costs[(y+yy)*image.width+x+xx,id-1]
            }}
            reports.append(PartitionReport(row:r,column:c,width:w,height:h,objective:objective,provenOptimal:parsed.optimal,solverStatus:parsed.status,elapsedSeconds:Date().timeIntervalSince(blockStart)))
        }
        let result=SolveResult(solution:solution,reports:reports,costBackend:costs.backend,elapsedSeconds:Date().timeIntervalSince(started))
        try result.validate(tileData:data);await progress(1,"Rendering result…");return (data,result)
    }
}
