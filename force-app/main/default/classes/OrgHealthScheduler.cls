/**
 * Schedule with:
 *   System.schedule('Org Health Weekly Scan', '0 0 2 ? * SUN', new OrgHealthScheduler());
 */
public class OrgHealthScheduler implements Schedulable {
    public void execute(SchedulableContext ctx) {
        OrgHealthScanOrchestrator.startScheduledScan();
    }
}
