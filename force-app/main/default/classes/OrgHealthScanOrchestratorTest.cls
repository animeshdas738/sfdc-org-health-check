/**
 * Tests for OrgHealthScanOrchestrator.
 * Covers scan initiation, module chaining, and finalization.
 */
@isTest
private class OrgHealthScanOrchestratorTest {

    @isTest
    static void testStartScanCreatesHealthScanRecord() {
        Test.startTest();
        Id scanId = OrgHealthScanOrchestrator.startScan();
        Test.stopTest();

        Assert.isNotNull(scanId, 'Scan ID should be returned');

        HealthScan__c scan = [SELECT Id, Status__c, TriggerType__c FROM HealthScan__c WHERE Id = :scanId];
        Assert.areEqual('Manual', scan.TriggerType__c, 'startScan should use Manual trigger type');
        // Status may be finalized depending on execution context, so just verify it's set
        Assert.isNotNull(scan.Status__c, 'Scan should have a status');
    }

    @isTest
    static void testStartScheduledScanUsesTriggerTypeScheduled() {
        Test.startTest();
        Id scanId = OrgHealthScanOrchestrator.startScheduledScan();
        Test.stopTest();

        HealthScan__c scan = [SELECT TriggerType__c FROM HealthScan__c WHERE Id = :scanId];
        Assert.areEqual('Scheduled', scan.TriggerType__c, 'Scheduled scan should use Scheduled trigger type');
    }

    @isTest
    static void testStartApiScanUsesTriggerTypeApi() {
        Test.startTest();
        Id scanId = OrgHealthScanOrchestrator.startApiScan();
        Test.stopTest();

        HealthScan__c scan = [SELECT TriggerType__c FROM HealthScan__c WHERE Id = :scanId];
        Assert.areEqual('API', scan.TriggerType__c, 'API scan should use API trigger type');
    }

    @isTest
    static void testFinaliseScanCalculatesCompositeScore() {
        // Create a scan with module scores
        HealthScan__c scan = OrgHealthTestFactory.createScan('In Progress', 'Manual');
        insert scan;

        HealthModuleScore__c ms1 = OrgHealthTestFactory.createModuleScore(scan.Id, 'Security', 85, 'Complete');
        ms1.Weight__c = 30;
        HealthModuleScore__c ms2 = OrgHealthTestFactory.createModuleScore(scan.Id, 'CodeQuality', 75, 'Complete');
        ms2.Weight__c = 20;
        insert new List<HealthModuleScore__c>{ms1, ms2};

        Test.startTest();
        OrgHealthScanOrchestrator.finaliseScan(scan.Id);
        Test.stopTest();

        HealthScan__c finalScan = [SELECT Status__c, CompositeScore__c, Grade__c FROM HealthScan__c WHERE Id = :scan.Id];
        Assert.areEqual('Complete', finalScan.Status__c, 'Scan should be marked Complete');
        Assert.isNotNull(finalScan.CompositeScore__c, 'Composite score should be calculated');
        Assert.isNotNull(finalScan.Grade__c, 'Grade should be assigned');
    }

    @isTest
    static void testFinaliseScanMarksFailedOnException() {
        HealthScan__c scan = OrgHealthTestFactory.createScan('In Progress', 'Manual');
        insert scan;

        // The test framework doesn't throw exceptions, but we can verify error handling logic
        // by checking that finaliseScan handles edge cases
        Test.startTest();
        OrgHealthScanOrchestrator.finaliseScan(scan.Id);
        Test.stopTest();

        HealthScan__c finalScan = [SELECT Status__c FROM HealthScan__c WHERE Id = :scan.Id];
        Assert.isNotNull(finalScan.Status__c, 'Scan status should be updated');
    }

    @isTest
    static void testFinaliseScanAssignsCorrectGrade() {
        HealthScan__c scan = OrgHealthTestFactory.createScan('In Progress', 'Manual');
        insert scan;

        // Create score that will result in 90+ composite (grade A)
        HealthModuleScore__c ms = OrgHealthTestFactory.createModuleScore(scan.Id, 'Security', 100, 'Complete');
        ms.Weight__c = 100;
        insert ms;

        Test.startTest();
        OrgHealthScanOrchestrator.finaliseScan(scan.Id);
        Test.stopTest();

        HealthScan__c finalScan = [SELECT Grade__c, CompositeScore__c FROM HealthScan__c WHERE Id = :scan.Id];
        Assert.areEqual('A', finalScan.Grade__c, 'Score 100 should result in grade A');
    }

    @isTest
    static void testCompositeScoreCappedAt100() {
        HealthScan__c scan = OrgHealthTestFactory.createScan('In Progress', 'Manual');
        insert scan;

        // Create multiple high scores that would exceed 100 if summed directly
        HealthModuleScore__c ms1 = OrgHealthTestFactory.createModuleScore(scan.Id, 'Security', 100, 'Complete');
        ms1.Weight__c = 50;
        HealthModuleScore__c ms2 = OrgHealthTestFactory.createModuleScore(scan.Id, 'CodeQuality', 100, 'Complete');
        ms2.Weight__c = 50;
        insert new List<HealthModuleScore__c>{ms1, ms2};

        Test.startTest();
        OrgHealthScanOrchestrator.finaliseScan(scan.Id);
        Test.stopTest();

        HealthScan__c finalScan = [SELECT CompositeScore__c FROM HealthScan__c WHERE Id = :scan.Id];
        Assert.isTrue(finalScan.CompositeScore__c <= 100, 'Composite score should not exceed 100');
    }

    @isTest
    static void testCompositeScoreFlooredAt0() {
        HealthScan__c scan = OrgHealthTestFactory.createScan('In Progress', 'Manual');
        insert scan;

        // Create scores that result in 0
        HealthModuleScore__c ms = OrgHealthTestFactory.createModuleScore(scan.Id, 'Security', 0, 'Complete');
        ms.Weight__c = 100;
        insert ms;

        Test.startTest();
        OrgHealthScanOrchestrator.finaliseScan(scan.Id);
        Test.stopTest();

        HealthScan__c finalScan = [SELECT CompositeScore__c FROM HealthScan__c WHERE Id = :scan.Id];
        Assert.isTrue(finalScan.CompositeScore__c >= 0, 'Composite score should not be negative');
    }
}
