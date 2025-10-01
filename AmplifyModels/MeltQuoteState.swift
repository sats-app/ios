// swiftlint:disable all
import Amplify
import Foundation

public enum MeltQuoteState: String, EnumPersistable {
  case unpaid = "UNPAID"
  case paid = "PAID"
  case pending = "PENDING"
  case `unknown` = "UNKNOWN"
  case failed = "FAILED"
}