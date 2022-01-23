//
//  EditorMapLayer+Ocean.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/21/20.
//  Copyright © 2020 Bryce Cogswell. All rights reserved.
//

import CoreGraphics
import Foundation
import UIKit

extension OSMPoint: Hashable {
	public func hash(into hasher: inout Hasher) {
		hasher.combine(x)
		hasher.combine(y)
	}
}

extension EditorMapLayer {
	private static func AppendNodes(
		to list: inout ShorelineSegmentNodes,
		fromWay: OsmWay,
		addToBack: Bool,
		reverseNodes: Bool)
	{
		// water goes on the right
		let waterSide = fromWay.tags["natural"] == "coastline" ? reverseNodes ? 1 : -1 : 0
		list.waterSide += waterSide

		let nodes = reverseNodes ? fromWay.nodes.reversed() : fromWay.nodes
		if addToBack {
			// insert at back of list
			list.nodes.append(contentsOf: nodes.dropFirst())
		} else {
			// insert at front of list
			list.nodes.insert(contentsOf: nodes.dropLast(), at: 0)
		}
	}

	private static func IsPointInRect(_ pt: OSMPoint, rect: OSMRect) -> Bool {
		let delta = 0.0001
		if pt.x < rect.origin.x - delta {
			return false
		}
		if pt.x > rect.origin.x + rect.size.width + delta {
			return false
		}
		if pt.y < rect.origin.y - delta {
			return false
		}
		if pt.y > rect.origin.y + rect.size.height + delta {
			return false
		}
		return true
	}

	private enum SIDE: Int {
		case LEFT, TOP, RIGHT, BOTTOM

		func nextClockwise() -> SIDE {
			return SIDE(rawValue: (self.rawValue+1) % 4)!
		}
	}

	private static func WallForPoint(_ pt: OSMPoint, rect: OSMRect) -> SIDE {
		let delta = 0.01
		if fabs(pt.x - rect.origin.x) < delta {
			return .LEFT
		}
		if fabs(pt.y - rect.origin.y) < delta {
			return .TOP
		}
		if fabs(pt.x - rect.origin.x - rect.size.width) < delta {
			return .RIGHT
		}
		if fabs(pt.y - rect.origin.y - rect.size.height) < delta {
			return .BOTTOM
		}
		fatalError()
	}

	private static func IsClockwisePolygon(_ points: [OSMPoint]) -> Bool {
		if points.count < 4 { // first and last repeat
			return false // invalid
		}
		if points[0] != points.last! {
			return false // invalid
		}
		var area = 0.0
		let offset = points[0]
		var previous = OSMPoint(x: 0, y: 0)

		for point in points[1..<points.count] {
			let current = OSMPoint(x: point.x - offset.x, y: point.y - offset.y)
			area += previous.x * current.y - previous.y * current.x
			previous = current
		}
		area *= 0.5
		return area >= 0
	}

	private static func RotateLoop(_ loop: inout [OSMPoint], viewRect: OSMRect) -> Bool {
		if loop.count < 4 {
			return false // bad loop
		}
		if loop[0] != loop.last! {
			return false // bad loop
		}
		loop.removeLast()
		var index = 0
		for point in loop {
			if !viewRect.containsPoint(point) {
				break
			}
			index += 1
			if index >= loop.count {
				index = -1
				break
			}
		}
		if index > 0 {
			let set = 0..<index
			let a = loop[set]
			loop.removeSubrange(set)
			loop.append(contentsOf: a)
		}
		loop.append(loop[0])
		return index >= 0
	}

	private static func ClipLineToRectWall(p1: OSMPoint, p2: OSMPoint, rect: OSMRect) -> [PointWithWall] {
		if p1.x.isInfinite || p2.x.isInfinite {
			return []
		}

		let topWall = rect.origin.y
		let bottomWall = rect.origin.y + rect.size.height
		let leftWall = rect.origin.x
		let rightWall = rect.origin.x + rect.size.width

		let dx = p2.x - p1.x
		let dy = p2.y - p1.y

		// get distances in terms of 0..1
		// we compute crossings for not only the rectangles walls but also the projections of the walls outside the rectangle,
		// so 4 possible interesection points
		var cross = [(Double,SIDE)]()
		if dx != 0 {
			let vLeft = (leftWall - p1.x) / dx
			if vLeft >= 0, vLeft <= 1 {
				cross.append((vLeft,.LEFT))
			}
			let vRight = (rightWall - p1.x) / dx
			if vRight >= 0, vRight <= 1 {
				cross.append((vRight,.RIGHT))
			}
		}
		if dy != 0 {
			let vTop = (topWall - p1.y) / dy
			if vTop >= 0, vTop <= 1 {
				cross.append((vTop,.TOP))
			}
			let vBottom = (bottomWall - p1.y) / dy
			if vBottom >= 0, vBottom <= 1 {
				cross.append((vBottom,.BOTTOM))
			}
		}

		// sort crossings according to distance from p1
		cross.sort(by: {p1,p2 in p1.0 < p2.0})

		// get the points that are actually inside the rect (max 2)
		let pts = cross.map { PointWithWall(point: OSMPoint(x: p1.x + $0.0 * dx, y: p1.y + $0.0 * dy), wall: $0.1) }
			.filter { IsPointInRect($0.point, rect: rect) }

		return pts
	}

	static func ClipLineToRect(p1: OSMPoint, p2: OSMPoint, rect: OSMRect) -> [OSMPoint] {
		return ClipLineToRectWall(p1: p1, p2: p2, rect: rect).map{ $0.point }
	}

	private struct PointWithWall {
		let point: OSMPoint
		let wall: SIDE?
	}

	// Clip a path so it's start and end points are connected to a rect.
	private static func clip(points: [OSMPoint], to viewRect: OSMRect) -> [PointWithWall]
	{
		var newPoints = [PointWithWall]()
		newPoints.reserveCapacity(points.count)

		var prev = points[0]
		var prevInside = viewRect.containsPoint(prev)

		for pt in points.dropFirst() {
			let inside = viewRect.containsPoint(pt)
			defer {
				prev = pt
				prevInside = inside
			}

			var cross: [PointWithWall] = []
			if !(prevInside && inside) {
				// at least one point was outside, so determine where line intersects the screen
				cross = Self.ClipLineToRectWall(p1: prev, p2: pt, rect: viewRect)
			}

			if inside {
				if prevInside {
					// both inside
					if !newPoints.isEmpty {
						newPoints.append(PointWithWall(point: pt, wall: nil))
					}
				} else {
					// went from outside to inside
					newPoints.append(cross[0])
					newPoints.append(PointWithWall(point: pt, wall: nil))
				}
			} else {
				if prevInside {
					// went from inside to outside
					newPoints.append(cross.last!)
					newPoints.append(PointWithWall(point: pt, wall: nil))
				} else {
					// went from outside to outside, but still may have crossed
					newPoints.append(contentsOf: cross)
					newPoints.append(PointWithWall(point: pt, wall: nil))
				}
			}
		}
		// there might be points at the tail that are outside, so delete them
		while let last = newPoints.last,
			  last.wall == nil
		{
			_ = newPoints.popLast()
		}
		return newPoints
	}

	private static func connectClockwise(p1: PointWithWall, p2: PointWithWall, viewRect: OSMRect) -> [OSMPoint] {
		if p1.wall == p2.wall {
			switch p1.wall {
			case .TOP where p1.point.x <= p2.point.x: fallthrough
			case .BOTTOM where p1.point.x >= p2.point.x: fallthrough
			case .LEFT where p1.point.y >= p2.point.y: fallthrough
			case .RIGHT where p1.point.y <= p2.point.y:
				return [p1.point, p2.point]
			default: break
			}
		}
		var wall = p1.wall!
		var pts = [p1.point]
		repeat {
			switch wall {
			case .TOP:		pts.append(OSMPoint(x: viewRect.origin.x+viewRect.size.width, y: viewRect.origin.y))
			case .RIGHT:	pts.append(OSMPoint(x: viewRect.origin.x+viewRect.size.width, y: viewRect.origin.y+viewRect.size.height))
			case .BOTTOM:	pts.append(OSMPoint(x: viewRect.origin.x, y: viewRect.origin.y+viewRect.size.height))
			case .LEFT:		pts.append(OSMPoint(x: viewRect.origin.x, y: viewRect.origin.y))
			}
			wall = wall.nextClockwise()
		} while wall != p2.wall
		pts.append(p2.point)
		return pts
	}

	struct ShorelineSegmentNodes {
		var nodes: [OsmNode]
		var waterSide: Int // positive is left, negative is right
	}
	class ShorelineSegment {
		var nodes: [OSMPoint]
		var waterSide: Int // positive is left, negative is right
		init(nodes: [OSMPoint], waterSide: Int) {
			self.nodes = nodes
			self.waterSide = waterSide
		}

		func entryAngle() -> Double {
			return atan2(nodes.first!.y, nodes.first!.x)
		}
		func exitAngle() -> Double {
			return atan2(nodes.last!.y, nodes.last!.x)
		}
	}

	// input is an array of OsmWay
	// output is an array of arrays of OsmNode
	// take a list of ways and return a new list of ways with contiguous ways joined together.
	private static func joinConnectedWays(_ origList: [OsmWay]) -> [ShorelineSegmentNodes] {
		// connect ways together forming congiguous runs
		var origList = origList.filter({ $0.nodes.count > 1 })
		var newList = [ShorelineSegmentNodes]()
		while let wayOrig = origList.popLast() {
			// find all segments that connect to the current way
			var nodeList = ShorelineSegmentNodes(nodes: [wayOrig.nodes.first!], waterSide: 0)
			Self.AppendNodes(to: &nodeList, fromWay: wayOrig, addToBack: true, reverseNodes: false)

			while nodeList.nodes.first != nodeList.nodes.last {
				// find a way adjacent to current list
				if let idx = origList.firstIndex(where: { nodeList.nodes.last == $0.nodes.first }) {
					Self.AppendNodes(to: &nodeList, fromWay: origList[idx], addToBack: true, reverseNodes: false)
					origList.remove(at: idx)
				} else if let idx = origList.firstIndex(where: { nodeList.nodes.last == $0.nodes.last }) {
					Self.AppendNodes(to: &nodeList, fromWay: origList[idx], addToBack: true, reverseNodes: true)
					origList.remove(at: idx)
				} else if let idx = origList.firstIndex(where: { nodeList.nodes.first == $0.nodes.last }) {
					Self.AppendNodes(to: &nodeList, fromWay: origList[idx], addToBack: false, reverseNodes: false)
					origList.remove(at: idx)
				} else if let idx = origList.firstIndex(where: { nodeList.nodes.first == $0.nodes.first }) {
					Self.AppendNodes(to: &nodeList, fromWay: origList[idx], addToBack: false, reverseNodes: true)
					origList.remove(at: idx)
				} else {
					break // didn't find anything to connect to
				}
			}
			newList.append(nodeList)
		}
		return newList
	}

	private func convertNodesToScreenPoints(_ nodeList: [OsmNode]) -> [OSMPoint] {
		return nodeList.map { node -> OSMPoint in
			let pt = self.owner.mapTransform.screenPoint(forLatLon: node.latLon, birdsEye: false)
			return OSMPoint(pt)
		}
	}

	private static func visibleSegmentsOfWay(_ way: [OSMPoint], inView viewRect: OSMRect) -> [[OSMPoint]] {
		// trim nodes in outlines to only internal paths
		var way = way
		var newWays = [[OSMPoint]]()

		var first = true
		var prevInside = false
		let isLoop = way[0] == way.last!
		var prevPoint = OSMPoint(x: 0, y: 0)
		var trimmedSegment: [OSMPoint]?

		if isLoop {
			// rotate loop to ensure start/end point is outside viewRect
			let ok = Self.RotateLoop(&way, viewRect: viewRect)
			if !ok {
				// entire loop is inside view
				return [way]
			}
		}

		for pt in way {
			let isInside = viewRect.containsPoint(pt)
			if first {
				first = false
				
			} else {
				var isEntry = false
				var isExit = false
				if prevInside {
					if isInside {
						// still inside
					} else {
						// moved to outside
						isExit = true
					}
				} else {
					if isInside {
						// moved inside
						isEntry = true
					} else {
						// if previous and current are both outside maybe we intersected
						if viewRect.intersectsLineSegment(prevPoint, pt),
						   !pt.x.isInfinite,
						   !prevPoint.x.isInfinite
						{
							isEntry = true
							isExit = true
						} else {
							// still outside
						}
					}
				}

				let pts = (isEntry || isExit) ? Self.ClipLineToRect(p1: prevPoint, p2: pt, rect: viewRect) : nil
				if isEntry {
					// start tracking trimmed segment
					let v = pts![0]
					trimmedSegment = [v]
				}
				if isExit {
					// end of trimmed segment. If the way began inside the viewrect then trimmedSegment is nil and gets ignored
					if trimmedSegment != nil {
						let v = pts!.last!
						trimmedSegment!.append(v)
						newWays.append(trimmedSegment!)
						trimmedSegment = nil
					}
				} else if isInside {
					// internal node for trimmed segment
					if trimmedSegment != nil {
						trimmedSegment!.append(pt)
					}
				}
			}
			prevPoint = pt
			prevInside = isInside
		}
		return newWays
	}

	private static func addPointList(_ list: [OSMPoint], toPath path: CGMutablePath) {
		var first = true
		for p in list {
			if p.x.isInfinite {
				break
			}
			let pt = CGPoint(p)
			if first {
				first = false
				path.move(to: pt)
			} else {
				path.addLine(to: pt)
			}
		}
	}

	private static func connectSegmentsToScreen(visibleSegments: [ShorelineSegment],
	                                            points: [OSMPoint],
	                                            entryDict: [OSMPoint: ShorelineSegment],
	                                            viewRect: OSMRect) -> CGMutablePath?
	{
		var visibleSegments = visibleSegments

		// We have a set of discontiguous arrays of coastline nodes sorted clockwise.
		// Draw segments adding points at screen corners to connect them.
		let path = CGMutablePath()
		while let firstOutline = visibleSegments.popLast() {
			var exit = firstOutline.nodes.last!

			Self.addPointList(firstOutline.nodes, toPath: path)

			while true {
				// find next point following exit point
				var nextOutline: ShorelineSegment? = entryDict[exit] // check if exit point is also entry point
				if nextOutline == nil { // find next entry point following exit point
					let exitIndex = points.firstIndex(of: exit)!
					let entryIndex = (exitIndex + 1) % points.count
					nextOutline = entryDict[points[entryIndex]]
				}
				guard let nextOutline = nextOutline else {
					return nil
				}
				let entry = nextOutline.nodes[0]

				// connect exit point to entry point following clockwise borders
				if true {
					var point1 = exit
					let point2 = entry
					var wall1 = Self.WallForPoint(point1, rect: viewRect)
					let wall2 = Self.WallForPoint(point2, rect: viewRect)

					wall_loop: while true {
						switch wall1 {
						case .LEFT:
							if wall2 == .LEFT, point1.y > point2.y {
								break wall_loop
							}
							point1 = OSMPoint(x: viewRect.origin.x, y: viewRect.origin.y)
							path.addLine(to: CGPoint(point1))
							fallthrough
						case .TOP:
							if wall2 == .TOP, point1.x < point2.x {
								break wall_loop
							}
							point1 = OSMPoint(x: viewRect.origin.x + viewRect.size.width, y: viewRect.origin.y)
							path.addLine(to: CGPoint(point1))
							fallthrough
						case .RIGHT:
							if wall2 == .RIGHT, point1.y < point2.y {
								break wall_loop
							}
							point1 = OSMPoint(
								x: viewRect.origin.x + viewRect.size.width,
								y: viewRect.origin.y + viewRect.size.height)
							path.addLine(to: CGPoint(point1))
							fallthrough
						case .BOTTOM:
							if wall2 == .BOTTOM, point1.x > point2.x {
								break wall_loop
							}
							point1 = OSMPoint(x: viewRect.origin.x, y: viewRect.origin.y + viewRect.size.height)
							path.addLine(to: CGPoint(point1))
							wall1 = .LEFT
						}
					}
				}

				if nextOutline === firstOutline {
					break
				}
				if visibleSegments.first(where: { $0 === nextOutline }) == nil {
					return nil
				}
				for pt in nextOutline.nodes {
					path.addLine(to: CGPoint(pt))
				}

				exit = nextOutline.nodes.last!
				visibleSegments.removeAll { $0 === nextOutline }
			}
		}
		return path
	}

	public func getOceanLayer(_ objectList: ContiguousArray<OsmBaseObject>) -> CAShapeLayer? {
		// get all coastline ways
		var outerWays = [OsmWay]()
		var innerWays = [OsmWay]()
		var oceanWays = [OsmWay]()

		for object in objectList {
			if object.isShoreline() {
				if let way = object as? OsmWay,
				   way.nodes.count >= 2
				{
					if object.tags["natural"] == "coastline" {
						oceanWays.append(way)
					} else if way.isClosed() {
						continue // this function only deals with multi-segment water bodies
					} else {
						outerWays.append(way)
					}
				} else if let relation = object as? OsmRelation {
					for member in relation.members {
						if let way = member.obj as? OsmWay,
						   way.nodes.count >= 2
						{
							if member.role == "outer" {
								outerWays.append(way)
							} else if member.role == "inner" {
								innerWays.append(way)
							} else {
								// skip
							}
						}
					}
				}
			}
		}
		if innerWays.count + outerWays.count + oceanWays.count == 0 {
			return nil
		}

		// Connect ways together forming contiguous runs.
		// If there is a natural=coastline then waterSide will be set appropriately (water on right).
		let outerNodes = Self.joinConnectedWays(outerWays)
		let innerNodes = Self.joinConnectedWays(innerWays)
		let oceanNodes = Self.joinConnectedWays(oceanWays)

		// convert lists of nodes to screen points
		var outerSegments = outerNodes.map {
			ShorelineSegment(nodes: self.convertNodesToScreenPoints($0.nodes), waterSide: $0.waterSide)
		}
		var innerSegments = innerNodes.map {
			ShorelineSegment(nodes: self.convertNodesToScreenPoints($0.nodes), waterSide: $0.waterSide)
		}
		var oceanSegments = oceanNodes.map {
			ShorelineSegment(nodes: self.convertNodesToScreenPoints($0.nodes), waterSide: $0.waterSide)
		}

		// Delete loops with a degenerate number of nodes. These are typically data errors
		// since a real loop needs 4 nodes including the duplicated first/last:
		outerSegments.removeAll(where: { $0.nodes.count < 4 && $0.nodes.first == $0.nodes.last })
		innerSegments.removeAll(where: { $0.nodes.count < 4 && $0.nodes.first == $0.nodes.last })
		oceanSegments.removeAll(where: { $0.nodes.count < 4 && $0.nodes.first == $0.nodes.last })

		// ensure waterside is to the right
		outerSegments = outerSegments.map{
			return $0.nodes.first == $0.nodes.last && !Self.IsClockwisePolygon($0.nodes)
			? ShorelineSegment(nodes: $0.nodes.reversed(), waterSide: 1)
			: $0
		}
		innerSegments = innerSegments.map{
			return $0.nodes.first == $0.nodes.last && Self.IsClockwisePolygon($0.nodes)
			? ShorelineSegment(nodes: $0.nodes.reversed(), waterSide: 1)
			: $0
		}
		oceanSegments = outerSegments.map{
			return $0.waterSide < 0
			? ShorelineSegment(nodes: $0.nodes.reversed(), waterSide: 1)
			: $0
		}

		// Clip segments to screen
		let cgViewRect = bounds
		let viewRect = OSMRect(cgViewRect)

		outerSegments = outerSegments.flatMap({ segment in
			Self.visibleSegmentsOfWay(segment.nodes, inView: viewRect).map{
				ShorelineSegment(nodes: $0, waterSide: segment.waterSide)
			}
		})
		innerSegments = innerSegments.flatMap({ segment in
			Self.visibleSegmentsOfWay(segment.nodes, inView: viewRect).map{
				ShorelineSegment(nodes: $0, waterSide: segment.waterSide)
			}
		})
		oceanSegments = oceanSegments.flatMap({ segment in
			Self.visibleSegmentsOfWay(segment.nodes, inView: viewRect).map{
				ShorelineSegment(nodes: $0, waterSide: segment.waterSide)
			}
		})

		var segments: [(Double,ShorelineSegment)] = (outerSegments + innerSegments + oceanSegments).map{
			($0.entryAngle(), $0)
		}.sorted { lhs, rhs in lhs.0 < rhs.0 }

		let cgPath = CGMutablePath()

		// Add complete loops to path
		outerSegments.removeAll(where: {
			if $0.nodes.first == $0.nodes.last {
				let nodes = Self.IsClockwisePolygon($0.nodes) ? $0.nodes : $0.nodes.reversed()
				cgPath.addLines(between: nodes.map{CGPoint($0)})
				return true
			}
			return false
		})
		innerSegments.removeAll(where: {
			if $0.nodes.first == $0.nodes.last {
				let nodes = Self.IsClockwisePolygon($0.nodes) ? $0.nodes.reversed() : $0.nodes
				cgPath.addLines(between: nodes.map{CGPoint($0)})
				return true
			}
			return false
		})
		oceanSegments.removeAll(where: {
			if $0.nodes.first == $0.nodes.last {
				let nodes = Self.IsClockwisePolygon($0.nodes) == ($0.waterSide > 0) ? $0.nodes : $0.nodes.reversed()
				cgPath.addLines(between: nodes.map{CGPoint($0)})
				return true
			}
			return false
		})


		// Handle coastlines for which we need to complete the loop ourself
		oceanSegments.removeAll(where: { ocean in
			let points = Self.clip(points: ocean.nodes, to:viewRect)
			if points.count < 2 {
				return true
			}
			let frame = Self.connectClockwise(p1: points.first!, p2: points.last!, viewRect: viewRect)
			let loop = points.map{$0.point} + frame
			cgPath.addLines(between: loop.map{ CGPoint($0)})
			return true
		})

		// At this point we only have incomplete loops with no waterSide.
		outerSegments += innerSegments
		innerSegments = []

		// trim nodes in segments to only visible paths
		var visibleSegments = [ShorelineSegment]()
		for segment in outerSegments {
			let a = Self.visibleSegmentsOfWay(segment.nodes, inView: viewRect)
			visibleSegments.append(contentsOf: a.map {
				ShorelineSegment(nodes: $0, waterSide: segment.waterSide)
			})
		}

		let layer = CAShapeLayer()
		layer.path = cgPath
		layer.frame = bounds
		layer.bounds = bounds
		layer.fillColor = UIColor(red: 0, green: 0, blue: 1, alpha: 0.1).cgColor
		layer.strokeColor = UIColor.blue.cgColor
		layer.lineWidth = 2.0
		//		layer.zPosition		= Z_OCEAN;	// FIXME

		return layer
	}
}
