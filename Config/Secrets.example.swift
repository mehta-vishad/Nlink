//
//  Secrets.example.swift
//  ENlink
//
//  TEMPLATE — safe to commit. Copy to BetterBlue/Utility/Secrets.swift
//  (gitignored) and fill in real values.
//
//  Only needed if Gate G1 took the fallback branch, i.e. the App Group
//  entitlement would not sign on the Personal Team and the widget has to
//  log in for itself instead of reading the app's shared container. If
//  App Groups signed, leave this alone and enter credentials in the app.
//
//  When you do create Secrets.swift, it has to compile into BOTH the
//  BetterBlue and WidgetExtension targets. `BetterBlue/` is a synchronized
//  group for the app target only, so add a membership exception for
//  WidgetExtension — the project already does this for other files under
//  BetterBlue/Utility.
//
//  Verify before your first push:
//      git check-ignore -v BetterBlue/Utility/Secrets.swift
//

import BetterBlueKit
import Foundation

enum Secrets {
    /// Bluelink account email.
    static let username = "you@example.com"

    /// Bluelink account password.
    static let password = "REPLACE_ME"

    /// Four-digit Bluelink PIN used to authorize remote commands.
    static let pin = "0000"

    /// VIN of the vehicle the widget drives.
    static let vin = "REPLACE_ME"

    static let region: Region = .usa
    static let brand: Brand = .hyundai
}
