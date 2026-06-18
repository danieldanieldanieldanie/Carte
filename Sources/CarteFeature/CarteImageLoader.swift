import Foundation

#if canImport(UIKit)
import UIKit

public enum CarteImageLoader {
    public static func image(for assetID: String) -> UIImage? {
        guard let url = CarteAttachmentStore.existingPhotoURL(for: assetID) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}
#endif
