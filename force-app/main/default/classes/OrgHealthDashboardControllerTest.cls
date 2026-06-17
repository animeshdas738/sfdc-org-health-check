/**
 * Tests for OrgHealthDashboardController.
 * Covers dashboard data endpoints and scan polling.
 */
@isTest
private class OrgHealthDashboardControllerTest {

    @isTest
    static void testGetLatestScanReturnsNewestScan() {
        // Create two scans
        HealthScan__c scan1 = OrgHealthTestFactory.createScan('Complete', 'Manual');
        scan1.ScanStartTime__c = System.now().addHours(-2);
        HealthScan__c scan2 = OrgHealthTestFactory.createScan('Complete', 'Manual');
        scan2.ScanStartTime__c = System.now().addHours(-1);
        insert new List<HealthScan__c>{scan1, scan2};

        Test.startTest();
        HealthScan__c latest = OrgHealthDashboardController.getLatestScan();
        Test.stopTest();

        Assert.isNotNull(latest, 'Should return latest scan');
        Assert.areEqual(scan2.Id, latest.Id, 'Should return the most recent scan');
    }

    @isTest
    static void testGetLatestScanReturnsNullWhenNoScans() {
        Test.startTest();
        HealthScan__c latest = OrgHealthDashboardController.getLatestScan();
        Test.stopTest();

        Assert.isNull(latest, 'Should return null when no scans exist');
    }

    @isTest
    static void testGetScoreTrendReturnsCompletedScans() {
        // Create completed scans
        HealthScan__c complete1 = OrgHealthTestFactory.createScan('Complete', 'Manual');
        complete1.CompositeScore__c = 85;
        HealthScan__c complete2 = OrgHealthTestFactory.createScan('Complete', 'Manual');
        complete2.CompositeScore__c = 75;
        insert new List<HealthScan__c>{complete1, complete2};

        Test.startTest();
        List<HealthScan__c> trend = OrgHealthDashboardController.getScoreTrend(10);
        Test.stopTest();

        Assert.isTrue(trend.size() >= 1, 'Should return completed scans');
        // Verify that returned scans have composite scores
        for (HealthScan__c scan : trend) {
            Assert.isNotNull(scan.CompositeScore__c, 'Trend scans should have composite score');
        }
    }

    @isTest
    static void testGetScoreTrendRespectsLimit() {
        // Create multiple scans
        List<HealthScan__c> scans = new List<HealthScan__c>();
        for (Integer i = 0; i < 15; i++) {
            HealthScan__c scan = OrgHealthTestFactory.createScan('Complete', 'Manual');
            scan.ScanStartTime__c = System.now().addHours(-i);
            scans.add(scan);
        }
        insert scans;

        Test.startTest();
        List<HealthScan__c> trend = OrgHealthDashboardController.getScoreTrend(5);
        Test.stopTest();

        Assert.areEqual(5, trend.size(), 'Should return only requested number of scans');
    }

    @isTest
    static void testGetModuleScoresReturnsScoresForScan() {
        HealthScan__c scan = OrgHealthTestFactory.createScan('Complete', 'Manual');
        insert scan;

        HealthModuleScore__c ms1 = OrgHealthTestFactory.createModuleScore(scan.Id, 'Security', 85, 'Complete');
        HealthModuleScore__c ms2 = OrgHealthTestFactory.createModuleScore(scan.Id, 'CodeQuality', 75, 'Complete');
        insert new List<HealthModuleScore__c>{ms1, ms2};

        Test.startTest();
        List<HealthModuleScore__c> scores = OrgHealthDashboardController.getModuleScores(scan.Id);
        Test.stopTest();

        Assert.areEqual(2, scores.size(), 'Should return all module scores for scan');
    }

    @isTest
    static void testGetModuleScoresReturnsEmptyForNullScanId() {
        Test.startTest();
        List<HealthModuleScore__c> scores = OrgHealthDashboardController.getModuleScores(null);
        Test.stopTest();

        Assert.areEqual(0, scores.size(), 'Should return empty list for null scan ID');
    }

    @isTest
    static void testGetFindingsReturnsAllFindings() {
        HealthScan__c scan = OrgHealthTestFactory.createScan('Complete', 'Manual');
        insert scan;

        HealthModuleScore__c ms = OrgHealthTestFactory.createModuleScore(scan.Id, 'Security', 85, 'Complete');
        insert ms;

        HealthFinding__c f1 = OrgHealthTestFactory.createFinding(scan.Id, ms.Id, 'Critical', 'Test Finding 1');
        HealthFinding__c f2 = OrgHealthTestFactory.createFinding(scan.Id, ms.Id, 'High', 'Test Finding 2');
        insert new List<HealthFinding__c>{f1, f2};

        Test.startTest();
        List<HealthFinding__c> findings = OrgHealthDashboardController.getFindings(scan.Id, '');
        Test.stopTest();

        Assert.areEqual(2, findings.size(), 'Should return all findings');
    }

    @isTest
    static void testGetFindingsFiltersBySeverity() {
        HealthScan__c scan = OrgHealthTestFactory.createScan('Complete', 'Manual');
        insert scan;

        HealthModuleScore__c ms = OrgHealthTestFactory.createModuleScore(scan.Id, 'Security', 85, 'Complete');
        insert ms;

        HealthFinding__c f1 = OrgHealthTestFactory.createFinding(scan.Id, ms.Id, 'Critical', 'Test Finding 1');
        HealthFinding__c f2 = OrgHealthTestFactory.createFinding(scan.Id, ms.Id, 'High', 'Test Finding 2');
        insert new List<HealthFinding__c>{f1, f2};

        Test.startTest();
        List<HealthFinding__c> findings = OrgHealthDashboardController.getFindings(scan.Id, 'Critical');
        Test.stopTest();

        Assert.areEqual(1, findings.size(), 'Should return only Critical findings');
        Assert.areEqual('Critical', findings[0].Severity__c, 'Should be a Critical finding');
    }

    @isTest
    static void testTriggerScanInitiatesNewScan() {
        Id scanId;
        Test.startTest();
        scanId = OrgHealthDashboardController.triggerScan();
        Test.stopTest();

        Assert.isNotNull(scanId, 'Should return a scan ID');

        HealthScan__c scan = [SELECT Status__c, TriggerType__c, ScanStartTime__c FROM HealthScan__c WHERE Id = :scanId];
        Assert.areEqual('Manual', scan.TriggerType__c, 'Should be triggered manually');
        Assert.isNotNull(scan.Status__c, 'Scan should have a status');
        Assert.isNotNull(scan.ScanStartTime__c, 'Scan should have a start time');
    }

    @isTest
    static void testGetScanStatusReturnsScanData() {
        HealthScan__c scan = OrgHealthTestFactory.createScan('In Progress', 'Manual');
        insert scan;

        Test.startTest();
        HealthScan__c status = OrgHealthDashboardController.getScanStatus(scan.Id);
        Test.stopTest();

        Assert.isNotNull(status, 'Should return scan status');
        Assert.areEqual(scan.Id, status.Id, 'Should return requested scan');
        Assert.areEqual('In Progress', status.Status__c, 'Should have correct status');
    }

    @isTest
    static void testGetScanModuleProgressReturnsModuleScores() {
        HealthScan__c scan = OrgHealthTestFactory.createScan('In Progress', 'Manual');
        insert scan;

        // Use valid status values: Complete, Failed, Skipped
        HealthModuleScore__c ms1 = OrgHealthTestFactory.createModuleScore(scan.Id, 'Security', 85, 'Complete');
        HealthModuleScore__c ms2 = OrgHealthTestFactory.createModuleScore(scan.Id, 'CodeQuality', 75, 'Complete');
        insert new List<HealthModuleScore__c>{ms1, ms2};

        Test.startTest();
        List<HealthModuleScore__c> progress = OrgHealthDashboardController.getScanModuleProgress(scan.Id);
        Test.stopTest();

        Assert.areEqual(2, progress.size(), 'Should return all module progress');
        Assert.isNotNull(progress[0].Module__c, 'Module progress should have module name');
    }

    @isTest
    static void testGetScanModuleProgressReturnsEmptyForNullScanId() {
        Test.startTest();
        List<HealthModuleScore__c> progress = OrgHealthDashboardController.getScanModuleProgress(null);
        Test.stopTest();

        Assert.areEqual(0, progress.size(), 'Should return empty list for null scan ID');
    }
}
