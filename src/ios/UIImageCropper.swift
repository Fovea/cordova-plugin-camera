//
//  UIImageCropper.swift
//  UIImageCropper
//
//  Created by Jari Kalinainen jari@klubitii.com
//
//  Licensed under MIT License 2017
//

import UIKit

@objc public protocol UIImageCropperProtocol: class {
    /// Called when user presses crop button (or when there is unknown situation
    /// (one or both images will be nil)).
    /// - parameter originalImage
    ///   Orginal image from camera/gallery
    /// - parameter croppedImage
    ///   Cropped image in cropRatio aspect ratio
    func didCropImage(_ originalImage: UIImage?, croppedImage: UIImage?)
    /// (optional) Called when user cancels the picker.
    /// If method is not available picker is dismissed.
    @objc optional func didCancel()
}

@objc open class UIImageCropper: UIViewController,
                             UIImagePickerControllerDelegate,
                             UINavigationControllerDelegate {
    
    /// Aspect ratio of the cropped image (width / height)
    @objc open var cropRatio: CGFloat = 1

    /// delegate that implements UIImageCropperProtocol
    @objc open weak var delegate: UIImageCropperProtocol?

    /// UIImagePickerController picker
    @objc open weak var picker: UIImagePickerController? {
        didSet {
            picker?.delegate = self
            picker?.allowsEditing = false
        }
    }

    /// Crop button text
    @objc open var cropButtonText: String = "Crop"
    /// Retake/Cancel button text
    @objc open var cancelButtonText: String = "Retake"

    /// original image from camera or gallery
    @objc open var image: UIImage? {
        didSet {
            guard let image = self.image else {
                return
            }
            layoutDone = false
            imageRatio = image.size.height / image.size.width
            imageView.image = image
            self.view.layoutIfNeeded()
        }
    }
    /// cropped image
    @objc open var cropImage: UIImage? {
        return crop()
    }

    /// autoClosePicker: if true, picker is dismissed when when image is cropped
    /// When false parent needs to close picker.
    @objc open var autoClosePicker: Bool = true

    // topView is the root view containing imageView, cropView and fadeView
    fileprivate let topView = UIView()
    // fadeView is a translucent black view. It "fades" whatever is outside the
    // cropping rectangle.. func maskFadeView() is used to mask it.
    fileprivate let fadeView = UIView()
    // contains the image. pinch/pan events are attached to this view.
    // see pinch() and pan()
    fileprivate let imageView: UIImageView = UIImageView()
    // a square that shows the crop area
    fileprivate let cropView: UIView = UIView()

    // fileprivate var topConst: NSLayoutConstraint?
    // fileprivate var leadConst: NSLayoutConstraint?
    // fileprivate var imageHeightConst: NSLayoutConstraint?
    // fileprivate var imageWidthConst: NSLayoutConstraint?

    fileprivate var imageRatio: CGFloat = 1
    fileprivate var layoutDone: Bool = false
    
    fileprivate var initialState: CGRect = CGRect(x:0, y:0, width:0, height:0)
    // initialHeight: CGFloat = 0
    // fileprivate var initialWidth: CGFloat = 0
    // fileprivate var initialX: CGFloat = 0
    // fileprivate var initialY: CGFloat = 0
    fileprivate var pinchStart: CGPoint = .zero
    
    fileprivate let cropButton = UIButton(type: .custom)
    fileprivate let cancelButton = UIButton(type: .custom)

    //MARK: - overrides
    override open func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.backgroundColor = UIColor.black

        //main views
        topView.backgroundColor = UIColor.clear
        let bottomView = UIView()
        bottomView.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        self.view.addSubview(topView)
        self.view.addSubview(bottomView)
        topView.translatesAutoresizingMaskIntoConstraints = false
        bottomView.translatesAutoresizingMaskIntoConstraints = false
        let horizontalTopConst = NSLayoutConstraint.constraints(withVisualFormat: "H:|-(0)-[view]-(0)-|", options: NSLayoutFormatOptions(), metrics: nil, views: ["view": topView])
        let horizontalBottomConst = NSLayoutConstraint.constraints(withVisualFormat: "H:|-(0)-[view]-(0)-|", options: NSLayoutFormatOptions(), metrics: nil, views: ["view": bottomView])
        let verticalConst = NSLayoutConstraint.constraints(withVisualFormat: "V:|-(0)-[top]-(0)-[bottom(70)]-|", options: NSLayoutFormatOptions(), metrics: nil, views: ["bottom": bottomView, "top": topView])
        self.view.addConstraints(horizontalTopConst + horizontalBottomConst + verticalConst)

        // image view
        imageView.contentMode = .scaleAspectFit
        topView.addSubview(imageView)
        imageView.image = self.image

        // imageView gestures
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(pinch))
        imageView.addGestureRecognizer(pinchGesture)
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(pan))
        imageView.addGestureRecognizer(panGesture)
        imageView.isUserInteractionEnabled = true

        // fade overlay
        fadeView.translatesAutoresizingMaskIntoConstraints = false
        fadeView.isUserInteractionEnabled = false
        fadeView.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        topView.addSubview(fadeView)
        let horizontalFadeConst = NSLayoutConstraint.constraints(withVisualFormat: "H:|-(0)-[view]-(0)-|", options: NSLayoutFormatOptions(), metrics: nil, views: ["view": fadeView])
        let verticalFadeConst = NSLayoutConstraint.constraints(withVisualFormat: "V:|-(0)-[view]-(0)-|", options: NSLayoutFormatOptions(), metrics: nil, views: ["view": fadeView])
        topView.addConstraints(horizontalFadeConst + verticalFadeConst)

        // crop overlay
        cropView.translatesAutoresizingMaskIntoConstraints = false
        cropView.isUserInteractionEnabled = false
        topView.addSubview(cropView)
        // constraints:
        //  * cropView.centerX = topView.centerX
        //  * cropView.centerY = topView.centerY
        //  * cropView.width = topView.width * 0.9
        //  * cropView.height <= topView.height * 0.9
        //  * cropView.width = cropView.height * cropRatio
        let centerXConst = NSLayoutConstraint(item: cropView, attribute: .centerX, relatedBy: .equal, toItem: topView, attribute: .centerX, multiplier: 1, constant: 0)
        let centerYConst = NSLayoutConstraint(item: cropView, attribute: .centerY, relatedBy: .equal, toItem: topView, attribute: .centerY, multiplier: 1, constant: 0)
        let widthConst = NSLayoutConstraint(item: cropView, attribute: .width, relatedBy: .equal, toItem: topView, attribute: .width, multiplier: 0.9, constant: 0)
        widthConst.priority = UILayoutPriority.defaultHigh
        let heightConst = NSLayoutConstraint(item: cropView, attribute: .height, relatedBy: .lessThanOrEqual, toItem: topView, attribute: .height, multiplier: 0.9, constant: 0)
        let ratioConst = NSLayoutConstraint(item: cropView, attribute: .width, relatedBy: .equal, toItem: cropView, attribute: .height, multiplier: cropRatio, constant: 0)
        cropView.addConstraints([ratioConst])
        topView.addConstraints([widthConst, heightConst, centerXConst, centerYConst])
        cropView.layer.borderWidth = 1
        cropView.layer.borderColor = UIColor.white.cgColor
        cropView.backgroundColor = UIColor.clear

        // control buttons
        var cropCenterXMultiplier: CGFloat = 1.0
        if picker?.sourceType != .camera { //hide retake/cancel when using camera as camera has its own preview
            cancelButton.translatesAutoresizingMaskIntoConstraints = false
            cancelButton.setTitle(cancelButtonText, for: .normal)
            cancelButton.addTarget(self, action: #selector(cropCancel), for: .touchUpInside)
            bottomView.addSubview(cancelButton)
            let centerCancelXConst = NSLayoutConstraint(item: cancelButton, attribute: .centerX, relatedBy: .equal, toItem: bottomView, attribute: .centerX, multiplier: 0.5, constant: 0)
            let centerCancelYConst = NSLayoutConstraint(item: cancelButton, attribute: .centerY, relatedBy: .equal, toItem: bottomView, attribute: .centerY, multiplier: 1, constant: 0)
            bottomView.addConstraints([centerCancelXConst, centerCancelYConst])
            cropCenterXMultiplier = 1.5
        }
        cropButton.translatesAutoresizingMaskIntoConstraints = false
        cropButton.addTarget(self, action: #selector(cropDone), for: .touchUpInside)
        bottomView.addSubview(cropButton)
        let centerCropXConst = NSLayoutConstraint(item: cropButton, attribute: .centerX, relatedBy: .equal, toItem: bottomView, attribute: .centerX, multiplier: cropCenterXMultiplier, constant: 0)
        let centerCropYConst = NSLayoutConstraint(item: cropButton, attribute: .centerY, relatedBy: .equal, toItem: bottomView, attribute: .centerY, multiplier: 1, constant: 0)
        bottomView.addConstraints([centerCropXConst, centerCropYConst])
        
        self.view.bringSubview(toFront: bottomView)

        bottomView.layoutIfNeeded()
        topView.layoutIfNeeded()
    }
    
    override open func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.cancelButton.setTitle(cancelButtonText, for: .normal)
        self.cropButton.setTitle(cropButtonText, for: .normal)
        
        if image == nil {
            self.dismiss(animated: true, completion: nil)
        }
    }

    override open func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !layoutDone else {
            return
        }
        layoutDone = true

        var width: CGFloat
        var height: CGFloat
        if imageRatio < cropRatio {
            width = cropView.frame.height / imageRatio
            height = cropView.frame.height
        } else {
            width = cropView.frame.width
            height = cropView.frame.width * imageRatio
        }
        let x = cropView.frame.origin.x + cropView.frame.width * 0.5 - width * 0.5
        let y = cropView.frame.origin.y + cropView.frame.height * 0.5 - height * 0.5
        imageView.frame = CGRect(x:x, y:y, width:width, height:height)

        maskFadeView()
    }
    
    fileprivate func maskFadeView() {
        let path = UIBezierPath(rect: cropView.frame)
        path.append(UIBezierPath(rect: fadeView.frame))
        let mask = CAShapeLayer()
        mask.fillRule = kCAFillRuleEvenOdd
        mask.path = path.cgPath
        fadeView.layer.mask = mask
    }

    //MARK: - button actions
    @objc func cropDone() {
        presenting = false
        if picker == nil {
            self.dismiss(animated: false, completion: {
                if self.autoClosePicker {
                    self.picker?.dismiss(animated: true, completion: nil)
                }
                self.delegate?.didCropImage(self.image, croppedImage: self.cropImage)
            })
        } else {
            self.endAppearanceTransition()
            self.view.removeFromSuperview()
            self.removeFromParentViewController()
            if self.autoClosePicker {
                self.picker?.dismiss(animated: true, completion: nil)
            }
            self.delegate?.didCropImage(self.image, croppedImage: self.cropImage)
        }
    }
    
    @objc func cropCancel() {
        presenting = false
        if picker == nil {
            self.dismiss(animated: true, completion: nil)
        } else {
            self.endAppearanceTransition()
            self.view.removeFromSuperview()
            self.removeFromParentViewController()
        }
    }

    func setImageFrame(frame: CGRect) {
        var x = frame.origin.x
        var y = frame.origin.y
        let width = frame.size.width
        let height = frame.size.height
        if frame.minX > cropView.frame.minX {
            x += cropView.frame.minX - frame.minX
        }
        if frame.maxX < cropView.frame.maxX {
            x += cropView.frame.maxX - frame.maxX
        }
        if frame.minY > cropView.frame.minY {
            y += cropView.frame.minY - frame.minY
        }
        if frame.maxY < cropView.frame.maxY {
            y += cropView.frame.maxY - frame.maxY
        }
        imageView.frame = CGRect(x: x, y: y, width: width, height: height)
    }

    //MARK: - gesture handling
    @objc func pinch(_ pinch: UIPinchGestureRecognizer) {
        if pinch.state == .began {
            initialState = imageView.frame
            pinchStart = pinch.location(in: self.view)
        }
        var scale = pinch.scale
        if initialState.width * scale < cropView.frame.width {
            scale = cropView.frame.width / initialState.width
        }
        if initialState.height * scale < cropView.frame.height {
            scale = cropView.frame.height / initialState.height
        }
        if scale > 2 {
            scale = 2
        }
        let transform = CGAffineTransform(translationX: (1-scale) * pinchStart.x, y: (1-scale) * pinchStart.y)
            .scaledBy(x: scale, y: scale)
        setImageFrame(frame: initialState.applying(transform))
    }
    
    @objc func pan(_ pan: UIPanGestureRecognizer) {
        if pan.state == .began {
            initialState = imageView.frame
        }
        let trans = pan.translation(in: self.view)
        setImageFrame(frame: initialState.offsetBy(dx: trans.x, dy: trans.y))
    }

    //MARK: - cropping done here
    fileprivate func crop() -> UIImage? {
        guard let image = self.image else {
            return nil
        }
        let imageSize = image.size
        let width = cropView.frame.width / imageView.frame.width
        let height = cropView.frame.height / imageView.frame.height
        let x = (cropView.frame.origin.x - imageView.frame.origin.x) / imageView.frame.width
        let y = (cropView.frame.origin.y - imageView.frame.origin.y) / imageView.frame.height

        let cropFrame = CGRect(x: x * imageSize.width, y: y * imageSize.height, width: imageSize.width * width, height: imageSize.height * height)
        if let cropCGImage = image.cgImage?.cropping(to: cropFrame) {
            let cropImage = UIImage(cgImage: cropCGImage, scale: 1, orientation: .up)
            return cropImage
        }
        return nil
    }

    //MARK: - UIImagePickerControllerDelegates
    open func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        presenting = false
        if delegate?.didCancel?() == nil {
            picker.dismiss(animated: true, completion: nil)
        }
    }
    
    var presenting = false
    
    open func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        guard !presenting else {
            return
        }
        guard let image = info[UIImagePickerControllerOriginalImage] as? UIImage else {
            return
        }
        layoutDone = false
        presenting = true
        self.image = image.fixOrientation()
        self.picker?.view.addSubview(self.view)
        self.view.constraintToFill(superView: self.picker?.view)
        self.picker?.addChildViewController(self)
        self.willMove(toParentViewController: self.picker)
        self.beginAppearanceTransition(true, animated: false)
     }
    
}

extension UIView {
    func constraintToFill(superView view: UIView?) {
        guard let view = view else {
            assertionFailure("superview is nil")
            return
        }
        self.translatesAutoresizingMaskIntoConstraints = false
        self.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
        self.heightAnchor.constraint(equalTo: view.heightAnchor).isActive = true
        self.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        self.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
    }
}
