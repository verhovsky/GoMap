//
//  OfflineViewController.swift
//  Go Map!!
//
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import UIKit

class OfflineTableViewCell: UITableViewCell {
	@IBOutlet var titleLabel: UILabel!
	@IBOutlet var detailLabel: UILabel!
	@IBOutlet var button: UIButton!
	@IBOutlet var activityView: UIActivityIndicatorView!
	var tileList: [String] = []
	var tileLayer: TilesProvider?

	override func awakeFromNib() {
		if #available(iOS 13.0, *) {
			activityView.style = .medium
		}
	}
}

class OfflineViewController: UITableViewController {
	@IBOutlet var aerialCell: OfflineTableViewCell!
	@IBOutlet var mapnikCell: OfflineTableViewCell!
	var activityCount = 0

	override func viewDidLoad() {
		super.viewDidLoad()

		tableView.estimatedRowHeight = 100
		tableView.rowHeight = UITableView.automaticDimension
		aerialCell.tileLayer = AppDelegate.shared.mapView.aerialLayer
		mapnikCell.tileLayer = AppDelegate.shared.mapView.mapnikLayer
		for cell in [aerialCell!, mapnikCell!] {
			cell.tileList = cell.tileLayer!.allTilesIntersectingVisibleRect()
			cell.detailLabel.text = String.localizedStringWithFormat(
				NSLocalizedString("%lu tiles needed", comment: ""),
				UInt(cell.tileList.count))
			cell.button.isEnabled = cell.tileList.count > 0
		}
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		for cell in [aerialCell, mapnikCell] {
			cell?.activityView.stopAnimating()
		}
	}

	// MARK: - Table view delegate

	func downloadFile(for cell: OfflineTableViewCell) {
		if let cacheKey = cell.tileList.popLast() {
			cell.tileLayer?.downloadTile(forKey: cacheKey,
			                             completion: {
			                             	cell.detailLabel.text = String.localizedStringWithFormat(
			                             		NSLocalizedString("%lu tiles needed", comment: "Always plural"),
			                             		UInt(cell.tileList.count))
			                             	if cell.activityView.isAnimating {
			                             		// recurse
			                             		self.downloadFile(for: cell)
			                             	}
			                             })
		} else {
			// finished
			cell.button.setTitle(NSLocalizedString("Start", comment: "Begin downloading tiles"), for: .normal)
			cell.activityView.stopAnimating()
			activityCount -= 1
			if activityCount == 0 {
				navigationItem.setHidesBackButton(false, animated: true)
			}
		}
	}

	@IBAction func toggleDownload(_ sender: UIButton) {
		var cell = OfflineTableViewCell()
		if sender == aerialCell.button {
			cell = aerialCell
		} else {
			cell = mapnikCell
		}

		if cell.activityView.isAnimating {
			// stop download
			cell.button.setTitle(NSLocalizedString("Start", comment: ""), for: .normal)
			cell.activityView.stopAnimating()
			activityCount -= 1
			if activityCount == 0 {
				navigationItem.setHidesBackButton(false, animated: true)
			}
		} else {
			// start download
			cell.button.setTitle(NSLocalizedString("Stop", comment: ""), for: .normal)
			cell.activityView.startAnimating()
			navigationItem.setHidesBackButton(true, animated: true)
			activityCount += 1
			downloadFile(for: cell)
		}
	}
}

protocol TilesProvider {
	var mapView: MapView { get }
	func currentTiles() -> [String]
	func zoomLevel() -> Int
	func maxZoom() -> Int
	func purgeTileCache()
	func downloadTile(forKey cacheKey: String, completion: @escaping () -> Void)
}

extension TilesProvider {
	// Used for bulk downloading tiles for offline use
	func allTilesIntersectingVisibleRect() -> [String] {
		let currentSet = Set(currentTiles())

		let rect = mapView.boundingMapRectForScreen()
		let minZoomLevel = min(zoomLevel(), maxZoom())
		let maxZoomLevel = min(zoomLevel() + 2, maxZoom())

		var neededTiles: [String] = []
		for zoomLevel in minZoomLevel...maxZoomLevel {
			let zoom = Double(1 << zoomLevel) / 256.0
			let tileNorth = Int(floor(rect.origin.y * zoom))
			let tileWest = Int(floor(rect.origin.x * zoom))
			let tileSouth = Int(ceil((rect.origin.y + rect.size.height) * zoom))
			let tileEast = Int(ceil((rect.origin.x + rect.size.width) * zoom))

			if tileWest < 0 || tileWest >= tileEast || tileNorth < 0 || tileNorth >= tileSouth {
				// stuff breaks if they zoom all the way out
				continue
			}

			for tileX in tileWest..<tileEast {
				for tileY in tileNorth..<tileSouth {
					let cacheKey = QuadKey(forZoom: zoomLevel, tileX: tileX, tileY: tileY)
					if currentSet.contains(cacheKey) {
						// already have it
					} else {
						neededTiles.append(cacheKey)
					}
				}
			}
		}
		return neededTiles
	}

	func purgeTileCache() {
		URLCache.shared.removeAllCachedResponses()
	}
}
