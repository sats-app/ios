// swiftlint:disable all
import Amplify
import Foundation

public enum MintQuoteState: String, EnumPersistable {
  case unpaid = "UNPAID"
  case paid = "PAID"
  case issued = "ISSUED"
}