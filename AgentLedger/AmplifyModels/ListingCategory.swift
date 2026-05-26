// swiftlint:disable all
import Amplify
import Foundation

public enum ListingCategory: String, EnumPersistable {
  case forSale = "FOR_SALE"
  case housing = "HOUSING"
  case jobs = "JOBS"
  case services = "SERVICES"
  case community = "COMMUNITY"
  case gigs = "GIGS"
}