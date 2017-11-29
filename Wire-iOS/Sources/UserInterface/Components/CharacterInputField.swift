//
// Wire
// Copyright (C) 2017 Wire Swiss GmbH
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see http://www.gnu.org/licenses/.
//

import Foundation
import Cartography

public protocol CharacterInputFieldDelegate: NSObjectProtocol {
    func shouldAcceptChanges(_ inputField: CharacterInputField) -> Bool
    func didChangeText(_ inputField: CharacterInputField, to: String)
    func didFillInput(inputField: CharacterInputField)
}

/// Custom input field implementation. Allows entering the characters from @c characterSet up to @c maxLength characters
/// Allows pasting the text.
public class CharacterInputField: UIControl, UITextInputTraits {
    fileprivate var storage = String() {
        didSet {
            if storage.characters.count > maxLength {
                storage = String(storage.prefix(maxLength))
            }
            
            self.updateCharacterViews(isFirstResponder: self.isFirstResponder)
            self.accessibilityValue = storage
        }
    }
    
    public let maxLength: Int
    public let characterSet: CharacterSet
    public weak var delegate: CharacterInputFieldDelegate? = .none
    private let characterViews: [CharacterView]
    private let stackView = UIStackView()
    
    fileprivate func prepare(string: String) -> String {
        var result = string.filter { element -> Bool in
            guard element.unicodeScalars.count == 1, let firstScalar = element.unicodeScalars.first else {
                return false
            }
            return characterSet.contains(firstScalar)
        }
        
        if result.count > maxLength {
            result = Array(result.prefix(maxLength))
        }
        
        return String(result)
    }
    
    private func updateCharacterViews(isFirstResponder: Bool) {
        for index in 0...(maxLength - 1) {
            let characterView = characterViews[index]
            
            if let character = storage.characters.count > index ? storage[storage.index(storage.startIndex, offsetBy: index)] : nil {
                characterView.character = .char(character)
            }
            else if storage.characters.count == index && isFirstResponder {
                characterView.character = .cursor
            }
            else {
                characterView.character = .none
            }
        }
    }
    
    fileprivate func notifyingDelegate(_ action: ()->()) {
        let wasFilled = self.isFilled
        let previousText = self.storage
        
        action()
        
        if previousText != storage {
            self.delegate?.didChangeText(self, to: storage)
        }
        
        if !wasFilled && self.isFilled {
            self.delegate?.didFillInput(inputField: self)
        }
    }
    
    fileprivate func showMenu() {
        let menuController = UIMenuController.shared
        menuController.setTargetRect(bounds, in: self)
        menuController.setMenuVisible(true, animated: true)
    }
    
    class CharacterView: UIView {
        private let label = UILabel()
        private let cursorView = UIView()
        
        enum CharacterInView {
            case char(Character)
            case cursor
            case none
        }
        
        var character: CharacterInView = .none {
            didSet {
                switch character {
                case .char(let character):
                    label.text = String(character)
                    label.isHidden = false
                    cursorView.isHidden = true
                case .cursor:
                    label.isHidden = true
                    cursorView.isHidden = false
                    self.startCursorAnimationIfNeeded()
                case .none:
                    label.isHidden = true
                    cursorView.isHidden = true
                }
            }
        }
        
        init() {
            super.init(frame: .zero)
            
            self.layer.cornerRadius = 4
            self.backgroundColor = .white
            
            label.font = UIFont.systemFont(ofSize: 32)
            self.addSubview(label)
            cursorView.backgroundColor = .accent()
            self.addSubview(cursorView)
            cursorView.isHidden = true
            
            constrain(self, label, cursorView) { selfView, label, cursorView in
                label.center == selfView.center
                cursorView.width == 2
                cursorView.height == 36
                cursorView.center == selfView.center
            }
            
            NotificationCenter.default.addObserver(self, selector: #selector(applicationDidBecomeActive), name: NSNotification.Name.UIApplicationDidBecomeActive, object: nil)
        }
        
        required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        override var intrinsicContentSize: CGSize {
            return CGSize(width: 50, height: 56)
        }
        
        override func didMoveToWindow() {
            super.didMoveToWindow()
            self.startCursorAnimationIfNeeded()
        }
        
        private func startCursorAnimationIfNeeded() {
            if !cursorView.isHidden && cursorView.layer.animation(forKey: "blinkAnimation") == nil {
                cursorView.layer.add(.cursorBlinkAnimation(), forKey: "blinkAnimation")
            }
        }
        
        @objc fileprivate func applicationDidBecomeActive(_ sender: Any?) {
            self.startCursorAnimationIfNeeded()
        }
    }
    
    // MARK: - Overrides
    
    init(maxLength: Int, characterSet: CharacterSet) {
        self.maxLength = maxLength
        self.characterSet = characterSet
        characterViews = (0..<maxLength).map { _ in CharacterView() }

        super.init(frame: .zero)
        
        self.isAccessibilityElement = true
        self.shouldGroupAccessibilityChildren = true
        
        stackView.spacing = 8
        stackView.axis = .horizontal
        
        characterViews.forEach(self.stackView.addArrangedSubview)
        
        self.addSubview(stackView)
        
        constrain(self, stackView) { selfView, stackView in
            stackView.edges == selfView.edges
        }
        
        let longPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(onLongPress(_:)))
        self.addGestureRecognizer(longPressGestureRecognizer)
        
        self.storage = String()
    }
    
    public required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override var canBecomeFirstResponder: Bool {
        return true
    }
    
    public override var canBecomeFocused: Bool {
        return true
    }
    
    @discardableResult public override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        updateCharacterViews(isFirstResponder: true)
        return result
    }
    
    @discardableResult public override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        updateCharacterViews(isFirstResponder: false)
        return result
    }
    
    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        self.becomeFirstResponder()
    }
    
    public override func accessibilityElementIsFocused() -> Bool {
        return self.becomeFirstResponder()
    }
    
    public override func accessibilityActivate() -> Bool {
        self.showMenu()
        
        return true
    }
    
    // MARK: - Paste support
    
    @objc fileprivate func onLongPress(_ sender: Any?) {
        self.showMenu()
    }
    
    public override func paste(_ sender: Any?) {
        guard let valueToPaste = UIPasteboard.general.string else {
            return
        }
        
        notifyingDelegate {
            self.text = valueToPaste
        }
    }
    
    public override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        switch action {
        case #selector(paste(_:)):
            return UIPasteboard.general.string != nil
        default:
            return false
        }
    }
    
    // MARK: - Public API
    
    public var isFilled: Bool {
        return storage.count >= maxLength
    }
    
    public var text: String {
        set {
            storage = prepare(string: newValue)
        }
        get {
            return storage
        }
    }
    
    // MARK: - UITextInputTraits
    public var keyboardType: UIKeyboardType = .default
}

extension CharacterInputField: UIKeyInput {
    public func insertText(_ text: String) {
        let shouldInsert = delegate?.shouldAcceptChanges(self) ?? true
        guard shouldInsert else { return }
        
        if let _ = text.rangeOfCharacter(from: CharacterSet.newlines) {
            self.resignFirstResponder()
            return
        }
        
        let allowedChars = prepare(string: text)
        guard !allowedChars.isEmpty else {
            return
        }
        
        notifyingDelegate {
            self.storage.append(String(allowedChars))
        }
    }
    
    public func deleteBackward() {
        guard !self.storage.isEmpty else {
            return
        }

        let shouldDelete = delegate?.shouldAcceptChanges(self) ?? true
        guard shouldDelete else { return }

        notifyingDelegate {
            self.storage.removeLast()
        }
    }
    
    public var hasText: Bool {
        return !storage.isEmpty
    }
}

