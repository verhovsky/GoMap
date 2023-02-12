//
//  QuestBuilder.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/8/23.
//  Copyright © 2023 Bryce. All rights reserved.
//

import UIKit

class QuestBuilderFeatureCell: UICollectionViewCell {
	@IBOutlet var label: UILabel?
	@IBAction func deleteItem(_ sender: Any?) {
		onDelete?(self)
	}

	var onDelete: ((QuestBuilderFeatureCell) -> Void)?

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		contentView.layer.cornerRadius = 5
		contentView.layer.masksToBounds = true
	}
}

class QuestBuilder: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout,
	UITextFieldDelegate
{
	@IBOutlet var presetField: UIButton?
	@IBOutlet var includeFeaturesView: UICollectionView?
	@IBOutlet var excludeFeaturesView: UICollectionView?
	@IBOutlet var includeFeaturesHeightConstraint: NSLayoutConstraint?
	@IBOutlet var excludeFeaturesHeightConstraint: NSLayoutConstraint?
	@IBOutlet var scrollView: UIScrollView?
	@IBOutlet var saveButton: UIBarButtonItem?
	@IBOutlet var nameField: UITextField?
	var quest: QuestUserDefition?

	var includeFeatures: [(name: String, ident: String)] = []
	var excludeFeatures: [(name: String, ident: String)] = []

	public class func instantiateNew() -> UINavigationController {
		let sb = UIStoryboard(name: "QuestBuilder", bundle: nil)
		let vc = sb.instantiateViewController(withIdentifier: "QuestBuilderNavigation") as! UINavigationController
		return vc
	}

	public class func instantiateWith(quest: QuestUserDefition) -> UIViewController {
		let sb = UIStoryboard(name: "QuestBuilder", bundle: nil)
		let vc = sb.instantiateViewController(withIdentifier: "QuestBuilder") as! QuestBuilder
		vc.quest = quest
		return vc
	}

	@IBAction func onSave(_ sender: Any?) {
		do {
			let quest = QuestUserDefition(title: nameField!.text!,
			                              presetKey: presetField!.title(for: .normal)!,
			                              includeFeatures: includeFeatures.map { $0.ident },
			                              excludeFeatures: excludeFeatures.map { $0.ident })
			try QuestList.shared.addQuest(quest)
			onCancel(sender)
		} catch {
			let alertView = UIAlertController(title: NSLocalizedString("Quest Definition Error", comment: ""),
			                                  message: "",
			                                  preferredStyle: .actionSheet)
			alertView.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel))
			present(alertView, animated: true)
			return
		}
	}

	@IBAction func onCancel(_ sender: Any?) {
		if navigationController?.popViewController(animated: true) == nil {
			dismiss(animated: true)
		}
	}

	@objc func nameFieldDidChange(_ sender: Any?) {
		saveButton?.isEnabled = (nameField?.text?.count ?? 0) > 0
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		for featureView in [includeFeaturesView, excludeFeaturesView] {
			featureView?.layer.borderWidth = 1.0
			featureView?.layer.borderColor = UIColor.gray.cgColor
			featureView?.layer.cornerRadius = 5.0
		}

		// monitor changes to nameField
		nameField?.delegate = self
		nameField?.addTarget(self, action: #selector(nameFieldDidChange(_:)), for: .editingChanged)
		saveButton?.isEnabled = false

		// monitor when keyboard is visible
		registerKeyboardNotifications()

		if #available(iOS 13.0, *) {
			// prevent swiping down to dismiss
			self.isModalInPresentation = true
		}

		if let flowLayout = includeFeaturesView?.collectionViewLayout as? UICollectionViewFlowLayout {
			flowLayout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize
		}

		if #available(iOS 14.0, *) {
			// get all possible fields
			let keys: [String] = PresetsDatabase.shared.presetFields.values
				.compactMap({ field in
					guard
						let key = field.key,
						!key.hasSuffix(":"), // multiCombo isn't supported
						!allFeaturesWithKey(key).isEmpty
					else {
						return nil
					}
					return key
				})
			let handler: (_: Any?) -> Void = { _ in
				self.didAddAllInclude(nil)
				self.didRemoveAllExclude(nil)
			}
			let presetItems: [UIAction] = Array(Set(keys))
				.sorted()
				.map { UIAction(title: "\($0)", handler: handler) }
			presetField?.menu = UIMenu(title: NSLocalizedString("Tag Key", comment: ""),
			                           children: presetItems)
			presetField?.showsMenuAsPrimaryAction = true
		}

		// if we're editing an existing quest then fill in the fields
		if let quest = quest {
			let features = PresetsDatabase.shared.stdPresets
			includeFeatures = quest.includeFeatures.map { (features[$0]?.name ?? $0, $0) }
			excludeFeatures = quest.excludeFeatures.map { (features[$0]?.name ?? $0, $0) }
			nameField?.text = quest.title
			presetField?.setTitle(quest.presetKey, for: .normal)
			if #available(iOS 14.0, *) {
				// select the current presetKey
				if let item = presetField?.menu?.children.first(where: { $0.title == quest.presetKey }),
				   let action = item as? UIAction
				{
					action.state = .on
				}
			}
		}
	}

	@IBAction func didAddAllInclude(_ sender: Any?) {
		guard let key = presetField?.title(for: .normal) else { return }
		let features = allFeaturesWithKey(key)
		includeFeatures = features.map { ($0.name, $0.featureID) }.sorted(by: { a, b in a.name < b.name })
		includeFeaturesView?.reloadData()
	}

	@IBAction func didRemoveAllInclude(_ sender: Any?) {
		includeFeatures = []
		includeFeaturesView?.reloadData()
	}

	@IBAction func didAddAllExclude(_ sender: Any?) {
		guard let key = presetField?.title(for: .normal) else { return }
		let features = allFeaturesWithKey(key)
		excludeFeatures = features.map { ($0.name, $0.featureID) }.sorted(by: { a, b in a.name < b.name })
		excludeFeaturesView?.reloadData()
	}

	@IBAction func didRemoveAllExclude(_ sender: Any?) {
		excludeFeatures = []
		excludeFeaturesView?.reloadData()
	}

	func allFeaturesWithKey(_ key: String) -> [PresetFeature] {
		let presets = PresetsDatabase.shared.stdPresets.values.compactMap { feature in
			for fieldName in feature.fields ?? [] {
				guard let field = PresetsDatabase.shared.presetFields[fieldName] else { continue }
				if field.key == key {
					return feature
				}
			}
			return nil
		}
		return presets
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		let heightInclude = includeFeaturesView?.collectionViewLayout.collectionViewContentSize.height ?? 0.0
		includeFeaturesHeightConstraint?.constant = max(heightInclude, 25.0)

		let heightExclude = excludeFeaturesView?.collectionViewLayout.collectionViewContentSize.height ?? 0.0
		excludeFeaturesHeightConstraint?.constant = max(heightExclude, 25.0)

		view.layoutIfNeeded()
	}

	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		guard section == 0 else { return 0 }
		if collectionView === includeFeaturesView {
			return includeFeatures.count
		}
		if collectionView === excludeFeaturesView {
			return excludeFeatures.count
		}
		return 0
	}

	func collectionView(_ collectionView: UICollectionView,
	                    cellForItemAt indexPath: IndexPath) -> UICollectionViewCell
	{
		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "FeatureCell",
		                                              for: indexPath) as! QuestBuilderFeatureCell
		if collectionView === includeFeaturesView {
			cell.label?.text = includeFeatures[indexPath.row].name
		} else {
			cell.label?.text = excludeFeatures[indexPath.row].name
		}
		cell.onDelete = { cell in
			if let indexPath = collectionView.indexPath(for: cell) {
				if collectionView === self.includeFeaturesView {
					self.includeFeatures.remove(at: indexPath.row)
				} else {
					self.excludeFeatures.remove(at: indexPath.row)
				}
				collectionView.deleteItems(at: [indexPath])
				self.viewDidLayoutSubviews()
			}
		}
		return cell
	}

	// MARK: keyboard appeared

	func registerKeyboardNotifications() {
		NotificationCenter.default.addObserver(self,
		                                       selector: #selector(keyboardWillShow(notification:)),
		                                       name: UIResponder.keyboardWillShowNotification,
		                                       object: nil)
		NotificationCenter.default.addObserver(self,
		                                       selector: #selector(keyboardWillHide(notification:)),
		                                       name: UIResponder.keyboardWillHideNotification,
		                                       object: nil)
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		NotificationCenter.default.removeObserver(self)
	}

	@objc func keyboardWillShow(notification: NSNotification) {
		if let userInfo: NSDictionary = notification.userInfo as? NSDictionary,
		   let keyboardInfo = userInfo[UIResponder.keyboardFrameBeginUserInfoKey] as? NSValue
		{
			guard let scrollView = scrollView,
			      let nameField = nameField
			else { return }
			let keyboardSize = keyboardInfo.cgRectValue.size
			let contentInsets = UIEdgeInsets(top: 0, left: 0, bottom: keyboardSize.height, right: 0)
			scrollView.contentInset = contentInsets
			scrollView.scrollIndicatorInsets = contentInsets
			let rect = nameField.frame.offsetBy(dx: 0, dy: keyboardSize.height)
			scrollView.scrollRectToVisible(rect, animated: true)
		}
	}

	@objc func keyboardWillHide(notification: NSNotification) {
		scrollView?.contentInset = .zero
		scrollView?.scrollIndicatorInsets = .zero
	}
}
