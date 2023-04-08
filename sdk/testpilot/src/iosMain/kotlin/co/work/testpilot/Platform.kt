package co.work.testpilot

import platform.UIKit.UIDevice
import platform.Foundation.NSProcessInfo

class IOSPlatform: Platform {
    override val name: String = UIDevice.currentDevice.systemName() + " " + UIDevice.currentDevice.systemVersion
}

actual fun getPlatform(): Platform = IOSPlatform()

actual fun env(key: String): String? = NSProcessInfo.processInfo.environment[key] as? String

