import Foundation
import CoreGraphics
let args = CommandLine.arguments
let x = Double(args[1])!, y = Double(args[2])!
let p = CGPoint(x: x, y: y)
let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)!
move.post(tap: .cghidEventTap); usleep(200000)
let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)!
let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)!
down.post(tap: .cghidEventTap); usleep(80000); up.post(tap: .cghidEventTap)
