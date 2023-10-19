//
//  ViewController.swift
//  RAW Image Convert
//
//  Created by 骆荟州 on 2023/10/15.
//

import PhotosUI
import ImageIO
import CoreServices

class ViewController: UIViewController, PHPickerViewControllerDelegate {
    
    @IBOutlet weak var progressBar: UIProgressView!
    @IBOutlet weak var qualitySlider: UISlider!
    @IBOutlet weak var methodSwitch: UISwitch!
    @IBOutlet weak var imageIOhint: UILabel!
    
    let qualityValues = [0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0] as [Float]
    
    var selectedImageCount = 0
    var doneImageCount = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        progressBar.setProgress(0, animated: true)
        
        qualitySlider.value = 0
        qualitySlider.minimumValue = 0
        qualitySlider.maximumValue = Float(qualityValues.count - 1)
        
        imageIOhint.text = "Use ImageIO (quality: \(qualityValues[Int(qualitySlider.value)]))"
    }
    
    @IBAction func qualitySliderValueChanged(_ sender: Any) {
        let index = Int(qualitySlider.value + 0.5)
        qualitySlider.setValue(Float(index), animated: false)
        
        imageIOhint.text = "Use ImageIO (quality: \(qualityValues[Int(qualitySlider.value)]))"
    }
    
    @IBAction func openGalleryClick(_ sender: Any) {
        var config = PHPickerConfiguration(photoLibrary: PHPhotoLibrary.shared())
        config.selectionLimit = 0

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
        
        progressBar.setProgress(0, animated: true)
    }
    
    func doneWithImage() {
        print("done with an asset")
        DispatchQueue.main.async {
            self.doneImageCount += 1
            let progress = Float(self.doneImageCount) / Float(self.selectedImageCount)
            self.progressBar.setProgress(progress, animated: true)
        }
    }
    
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        
        let useImageIO = methodSwitch.isOn
        let quality = qualityValues[Int(qualitySlider.value)]
        
        let identifiers = results.compactMap(\.assetIdentifier)
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        
        selectedImageCount = fetchResult.count
        
        fetchResult.enumerateObjects { (asset, index, stop) in
            print("get an asset")
            let resources = PHAssetResource.assetResources(for: asset)
            
            var imageName: String?
            
            print("--------")
            for res in resources {
                print("  resource type: \(res.type.rawValue)")
                print("  resource uniform Type Identifier: \(res.uniformTypeIdentifier)")
                if res.type == .photo {
                    imageName = res.originalFilename
                }
            }
            print("--------")
            
            guard let imageName = imageName, imageName.lowercased().hasSuffix(".dng") else {
                print("image name not found, skip this photo")
                return
            }
            
            // check wheather it is a single DNG file
            if resources.count == 1 {
                
                let resource = resources[0];
                
                guard resource.type == .photo,
                      let resourceUTType = UTType(resource.uniformTypeIdentifier),
                      resourceUTType.conforms(to: UTType.rawImage),
                      resource.originalFilename.lowercased().hasSuffix(".dng")
                else {
                    // error hint
                    return
                }
                
                var dngData = Data()
                PHAssetResourceManager.default().requestData(for: resource, options: nil) { data in
                    dngData.append(data)
                } completionHandler: { err in
                    guard err == nil else { return } // error hint
                    
                    if useImageIO {
                        self.saveJPEGdataToGallery2(data: &dngData,
                                                    filename: String(resource.originalFilename.dropLast(4)) + ".jpg",
                                                    quality: quality)
                        self.doneWithImage()
                        return
                    }
                    
                    let dngDataPtr = dngData.withUnsafeBytes {
                        return $0.bindMemory(to: CChar.self).baseAddress
                    }
                    
                    guard checkEndian(dngDataPtr) == 1 else {
                        // error hint
                        return
                    }
                    
                    var jpegPtr: UnsafeMutablePointer<CChar>? = nil
                    var jpegLen: UInt64 = 0
                    
                    withUnsafeMutablePointer(to: &jpegLen) { lenPtr in
                        extractJPEGpreviewFromDNG(dngDataPtr, UInt64(dngData.count), &jpegPtr, lenPtr)
                    }
                    
                    if let jpegPtr = jpegPtr, jpegLen != 0 {
                        var jpegData = Data(bytes: jpegPtr, count: Int(jpegLen))
                        
                        let jpegFileName = String(resource.originalFilename.dropLast(4)) + ".jpg"
                        self.saveJPEGdataToGallery(data: &jpegData, filename: jpegFileName)
                        free(jpegPtr)
                        self.doneWithImage()
                    }
                    else {
                        // error hint
                    }
                }
            }
            else if (resources.count == 3) {
                // the ProRaw photo is edited and has a full-size JPEG preview image
                let targetTypeSet: Set<PHAssetResourceType> = Set([.photo, .fullSizePhoto, .adjustmentData])
                let extractedTypeSet = resources.map { $0.type }
                
                guard targetTypeSet.isSubset(of: extractedTypeSet) else {
                    // error hint
                    return
                }
                
                for resource in resources {
                    if resource.type == .fullSizePhoto,
                       let resourceUTType = UTType(resource.uniformTypeIdentifier),
                       resourceUTType.conforms(to: UTType.jpeg)
                    {
                        var imgData = Data()
                        
                        PHAssetResourceManager.default().requestData(for: resource, options: nil) { data in
                            imgData.append(data)
                        } completionHandler: { err in
                            guard err == nil else { return } // error hint
                            
                            self.saveJPEGdataToGallery(data: &imgData, filename: String(imageName.dropLast(4)) + ".jpg")
                            self.doneWithImage()
                        }
                    }
                }
            }
        }
    }
    
    func saveJPEGdataToGallery(data: inout Data, filename: String) {
        let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let outputPath = docDir.appendingPathComponent(filename)
        do {
            try data.write(to: outputPath)
        }
        catch {
            return
        }
        
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: outputPath)
        } completionHandler: { success, err in
            if success {
                do {
                    try FileManager.default.removeItem(at: outputPath)
                }
                catch {
                    print("delete image from document dir failed")
                }
            }
            else if let error = err {
                // error hint
                print(error.localizedDescription)
            }
        }
    }

    // In addition to extracting the preview JPEG directly from the DNG file,
    // we can also use ImageIO related api to convert DNG to jpg. The image
    // appearance is the same as the embedded JPEG preview. But here we need
    // to set the HDR gain map manually.
    func saveJPEGdataToGallery2(data: inout Data, filename: String, quality: Float) {
        let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let outputPath = docDir.appendingPathComponent(filename)

        guard let source = CGImageSourceCreateWithData(convertDataToCFData(data: data)!, nil),
              var properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return }

        guard let dest = CGImageDestinationCreateWithURL(outputPath as CFURL, kUTTypeJPEG, 1, nil)
        else { return }
        
        properties.removeValue(forKey: kCGImagePropertyDNGDictionary)
        properties[kCGImageDestinationLossyCompressionQuality] = quality

        CGImageDestinationAddImageFromSource(dest, source, 0, properties as CFDictionary)

        if let gainMapInfo = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeHDRGainMap) as Dictionary? {
            let infoDict = [
                kCGImageAuxiliaryDataInfoData: gainMapInfo[kCGImageAuxiliaryDataInfoData],
                kCGImageAuxiliaryDataInfoDataDescription: gainMapInfo[kCGImageAuxiliaryDataInfoDataDescription]
            ] as CFDictionary

            CGImageDestinationAddAuxiliaryDataInfo(dest, kCGImageAuxiliaryDataTypeHDRGainMap, infoDict)
        }

        if !CGImageDestinationFinalize(dest) {
            // error hint
            return
        }

        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: outputPath)
        } completionHandler: { success, err in
            if success {
                do {
                    try FileManager.default.removeItem(at: outputPath)
                }
                catch {
                    print("delete image from document dir failed")
                }
            }
            else if let error = err {
                // error hint
                print(error.localizedDescription)
            }
        }
    }

    func convertDataToCFData(data: Data) -> CFData? {
        return CFDataCreate(nil, data.withUnsafeBytes { $0.baseAddress }, data.count)
    }
    
    func readDNGProperties(data: Data) {
        guard let d = convertDataToCFData(data: data),
              let source = CGImageSourceCreateWithData(d, nil)
        else { return }
        
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
            print(properties)
//            if let dngProperties = properties[kCGImagePropertyDNGDictionary as String] as? [String: Any] {
//                print(dngProperties)
//            }
        }
    }
    
    
//    func extractEmbeddedPreview(fromDNG dngData: Data) -> CGImage? {
//        if let source = CGImageSourceCreateWithData(dngData as CFData, nil) {
//            return CGImageSourceCreateThumbnailAtIndex(source, 0, nil)
//        }
//        return nil
//    }
//
//    func saveCGImageAsJPEG(image: CGImage, atPath url: URL, compressionQuality: CGFloat = 1.0) {
//        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, kUTTypeJPEG, 1, nil) else {
//            return
//        }
//
//        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: compressionQuality]
//        CGImageDestinationAddImage(destination, image, options as CFDictionary)
//        let success = CGImageDestinationFinalize(destination)
//    }
//
}

