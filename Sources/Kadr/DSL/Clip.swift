import Foundation
import CoreMedia

public protocol Clip: Sendable {
    var duration: CMTime { get }
}
