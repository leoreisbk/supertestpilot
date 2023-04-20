package co.work.testpilot

import co.work.testpilot.extensions.getElement
import co.work.testpilot.extensions.simplifyUI
import co.work.testpilot.extensions.waitForExistenceIfNecessary
import co.work.testpilot.throwables.ConfigurationException
import co.work.testpilot.throwables.TestAutomationException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import platform.XCTest.*
import kotlin.math.roundToLong

object TestPilotIOS {
    @Throws(
        TestAutomationException::class, 
        ConfigurationException::class, 
        CancellationException::class, 
        Exception::class,
    )
    suspend fun automate(
        test: XCTestCase, 
        config: Config, 
        objective: String, 
        bundleId: String? = null,
    ) {
        TestPilot.automate(
            app = TestableAppIOS(bundleId),
            actor = TestActorIOS(test),
            config = config,
            objective = objective,
        )
    }
}
