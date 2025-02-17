//
//  AccountInfoTableViewController.swift
//  Go Map!!
//
//  Created by Patrick Steiner on 13.07.23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import UIKit
import SafariServices

final class AccountInfoTableViewController: UITableViewController {
	@IBOutlet private var activityIndicator: UIActivityIndicatorView!
	@IBOutlet private var refreshAccountButton: UIButton!
	@IBOutlet private var usernameLabel: UILabel!
	@IBOutlet private var changesetsLabel: UILabel!

	private let appDelegate = AppDelegate.shared

	override func viewDidLoad() {
		super.viewDidLoad()

		if #available(iOS 13.0, *) {
			activityIndicator.style = .medium
		} else {
			activityIndicator.style = .white
		}

		setupUI()
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)

		fetchAccountInfos()
	}

	override func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
		guard let cell = tableView.cellForRow(at: indexPath),
			  cell.accessoryType == .detailButton
		else { return }
		showAccountDetails()
	}

	private func fetchAccountInfos() {
		if activityIndicator.isAnimating {
			return
		}

		activityIndicator.color = .darkGray
		activityIndicator.startAnimating()
		refreshAccountButton.isHidden = true

		appDelegate.oAuth2.getUserDetails { [weak self] dict in
			guard let strongSelf = self else { return }

			strongSelf.activityIndicator.stopAnimating()
			strongSelf.refreshAccountButton.isHidden = false

			if let dict {
				if let name = dict["display_name"] as? String {
					strongSelf.appDelegate.userName = name
					strongSelf.usernameLabel.text = name
				}

				if let changesets = dict["changesets"] as? [String: Any], let count = changesets["count"] as? Int64 {
					strongSelf.changesetsLabel.text = "\(count)"
				}

			} else {
				strongSelf.presentBadLoginDialog()
			}
		}
	}

	private func showAccountDetails() {
		guard let username = appDelegate.userName,
			username != ""
		else {
			return
		}
		let urlAsString = "\(OSM_SERVER.queryURL)/user/\(username)"
		guard let url = URL(string: urlAsString) else { return }

		let safariViewController = SFSafariViewController(url: url)
		safariViewController.modalPresentationStyle = .overCurrentContext
		safariViewController.popoverPresentationController?.sourceView = view
		present(safariViewController, animated: true)
	}

	private func setupUI() {
		if let username = appDelegate.userName {
			usernameLabel.text = username
		}
	}

	private func presentBadLoginDialog() {
		let alert = UIAlertController(
			title: NSLocalizedString("Bad login", comment: ""),
			message: NSLocalizedString("Not found", comment: "User credentials not found"),
			preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""),
		                              style: .cancel,
		                              handler: nil))
		present(alert, animated: true)
	}

	@IBAction func didTapRefreshButton(_ sender: UIButton) {
		fetchAccountInfos()
	}

	@IBAction func didTapSignOutButton(_ sender: UIButton) {
		appDelegate.oAuth2.removeAuthorization()
		appDelegate.userName = nil

		navigationController?.popToRootViewController(animated: true)
	}
}
