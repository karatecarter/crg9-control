import AppKit
let directory = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let n = CGFloat(pixels)
        NSColor(calibratedRed: 0.06, green: 0.12, blue: 0.22, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: n*0.04,y:n*0.04,width:n*0.92,height:n*0.92),xRadius:n*0.2,yRadius:n*0.2).fill()
        let screen = NSBezierPath(roundedRect: NSRect(x:n*0.13,y:n*0.34,width:n*0.74,height:n*0.37),xRadius:n*0.045,yRadius:n*0.045)
        NSColor(calibratedRed:0.18,green:0.72,blue:0.9,alpha:1).setFill();screen.fill()
        NSColor(calibratedRed:0.05,green:0.2,blue:0.34,alpha:1).setFill()
        NSBezierPath(roundedRect:NSRect(x:n*0.155,y:n*0.365,width:n*0.69,height:n*0.32),xRadius:n*0.025,yRadius:n*0.025).fill()
        NSColor.white.setStroke();let arrow=NSBezierPath();arrow.lineWidth=n*0.025
        arrow.move(to:NSPoint(x:n*0.32,y:n*0.525));arrow.line(to:NSPoint(x:n*0.68,y:n*0.525))
        arrow.move(to:NSPoint(x:n*0.60,y:n*0.60));arrow.line(to:NSPoint(x:n*0.68,y:n*0.525));arrow.line(to:NSPoint(x:n*0.60,y:n*0.45));arrow.stroke()
        NSColor(calibratedWhite:0.7,alpha:1).setFill();NSBezierPath(roundedRect:NSRect(x:n*0.40,y:n*0.25,width:n*0.20,height:n*0.025),xRadius:n*0.01,yRadius:n*0.01).fill()
        image.unlockFocus()
        let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
        let name="icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent(name))
    }
}
let process=Process();process.executableURL=URL(fileURLWithPath:"/usr/bin/iconutil");process.arguments=["-c","icns",directory.path];try process.run();process.waitUntilExit()
if process.terminationStatus != 0 { exit(process.terminationStatus) }
