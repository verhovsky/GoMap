//
//  QuestMarker.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/5/23.
//  Copyright © 2023 Bryce. All rights reserved.
//

import Foundation
import UIKit

// An OSM object for a quest
class QuestMarker: MapMarker {
	let ident: String
	let quest: QuestProtocol

	override var markerIdentifier: String {
		return ident
	}

	override func shouldHide() -> Bool {
		guard let object = object else { return true }
		return !quest.appliesTo(object)
	}

	override var buttonLabel: String { "Q" }
	override var buttonIcon: UIImage? { quest.icon }

	init(object: OsmBaseObject, quest: QuestProtocol) {
		let center = object.selectionPoint()
		self.quest = quest
		ident = "quest-\(quest.ident)-\(object is OsmNode ? "n" : object is OsmWay ? "w" : "r")\(object.ident)"
		super.init(lat: center.lat, lon: center.lon)
		self.object = object
	}
}
