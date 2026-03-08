# launcher_impeller_off_fixture.xml Metadata

## Date Node
- The node with resource-id `com.google.android.apps.nexuslauncher:id/date` (class `android.widget.TextView`) contains a hardcoded date string (`Fri, Mar 6`).
- Tests consuming this fixture should not assert the exact date value; prefer matching by resource-id/class.
- If a specific value is required, update the test to expect `Fri, Mar 6` for this fixture.
- Consider parameterizing the fixture for date stability if needed.
