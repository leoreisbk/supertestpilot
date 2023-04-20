package co.work.testpilot

import co.work.testpilot.extensions.simplifyUI

class AppUISnapshotIOS(val appDebugDescription: String?) : AppUISnapshot {
    override fun toPromptString(): String {
        return appDebugDescription?.simplifyUI() ?: ""
    }
}
