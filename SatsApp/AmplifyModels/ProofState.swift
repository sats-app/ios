// swiftlint:disable all
import Amplify
import Foundation

public enum ProofState: String, EnumPersistable {
  case spent = "SPENT"
  case unspent = "UNSPENT"
  case pending = "PENDING"
  case reserved = "RESERVED"
  case pendingSpent = "PENDING_SPENT"
}