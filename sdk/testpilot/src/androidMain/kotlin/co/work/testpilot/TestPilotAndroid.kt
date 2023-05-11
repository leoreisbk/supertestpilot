package co.work.testpilot

import android.content.Context
import co.work.testpilot.runtime.Config
import co.work.testpilot.throwables.ConfigurationException
import co.work.testpilot.throwables.TestAutomationException
import kotlin.coroutines.cancellation.CancellationException

object TestPilotAndroid {
    @Throws(TestAutomationException::class, ConfigurationException::class, CancellationException::class, Exception::class)
    suspend fun automate(
        context: Context,
        config: Config,
        objective: String,
    ) {
        TestPilot.automate(
            app = TestableAppAndroid(),
            actor = TestActorAndroid(),
            config = config,
            objective = objective,
            persistenceManager = PersistenceManagerAndroid(context, objective),
        )
    }
}
