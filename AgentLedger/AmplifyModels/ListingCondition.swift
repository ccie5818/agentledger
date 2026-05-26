// swiftlint:disable all
import Amplify
import Foundation

public enum ListingCondition: String, EnumPersistable {
  case new = "NEW"
  case likeNew = "LIKE_NEW"
  case good = "GOOD"
  case fair = "FAIR"
  case salvage = "SALVAGE"
}