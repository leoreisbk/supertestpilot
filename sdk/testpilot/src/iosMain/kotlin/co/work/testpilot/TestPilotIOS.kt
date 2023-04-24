package co.work.testpilot

import co.work.testpilot.runtime.Config
import co.work.testpilot.throwables.ConfigurationException
import co.work.testpilot.throwables.TestAutomationException
import kotlinx.coroutines.CancellationException
import platform.XCTest.*

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
