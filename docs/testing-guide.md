# Org Health Check — Testing Guide

## Overview

This project includes comprehensive test coverage for the core framework and controllers. Tests are organized by class and follow Salesforce best practices.

## Test Classes Created

### Core Framework Tests

- **`OrgHealthTestFactory`** — Utility class for creating test data
  - `createScan()` — Create test HealthScan__c records
  - `createModuleScore()` — Create test HealthModuleScore__c records
  - `createFinding()` — Create test HealthFinding__c records
  - `createConfigOverride()` — Create test config overrides

- **`OrgHealthScanOrchestratorTest`** — Tests for scan orchestration (8 tests)
  - Scan initiation (manual, scheduled, API)
  - Score calculation and capping
  - Grade assignment
  - Error handling and finalization

- **`OrgHealthConstantsTest`** — Tests for config gateway (16 tests)
  - Config retrieval (modules, severities, checkpoints)
  - Override merging
  - Grade calculation (A–F thresholds)
  - Module chain validation

- **`OrgHealthModuleFactoryTest`** — Tests for module instantiation (8 tests)
  - Factory creation for all 6 modules
  - Exception handling for unknown modules
  - Module chain iteration

- **`OrgHealthConfigControllerTest`** — Tests for config management (10 tests)
  - Config retrieval with CMT + override merge
  - Saving new and updating existing overrides
  - Multiple change persistence
  - Error handling for null/empty changes

- **`OrgHealthDashboardControllerTest`** — Tests for dashboard endpoints (14 tests)
  - Latest scan retrieval
  - Score trend queries
  - Module score queries with filtering
  - Finding retrieval with severity filtering
  - Scan polling and progress tracking

- **`SecurityScannerModuleTest`** — Example module tests (8 tests)
  - Module initialization
  - Checkpoint gate logic
  - Finding and score creation
  - Checkpoint availability validation

## Running Tests

### From CLI

```bash
# Run all tests
sf apex run test -w 10

# Run a specific test class
sf apex run test --class OrgHealthScanOrchestratorTest -w 10

# Run with code coverage
sf apex run test --code-coverage -w 10
```

### From Salesforce UI

1. Navigate to Setup > Apex Test Execution
2. Select test classes
3. Click Run Tests
4. View results and code coverage

## Test Coverage Goals

| Component | Coverage | Status |
|-----------|----------|--------|
| OrgHealthScanOrchestrator | 95%+ | ✅ |
| OrgHealthConstants | 95%+ | ✅ |
| OrgHealthModuleFactory | 100% | ✅ |
| OrgHealthConfigController | 90%+ | ✅ |
| OrgHealthDashboardController | 90%+ | ✅ |
| Module Classes | 50%+ | 🔄 |

## Writing Module Tests

Module classes are challenging to test in isolation because they:
1. Execute as Queueable jobs
2. Call the Tooling API (requires mocking)
3. Perform DML in phases

### Strategy for Module Testing

#### Option 1: Integration Tests (Recommended)

```apex
@isTest
private class MyModuleTest {
    @isTest
    static void testModuleExecutesSuccessfully() {
        HealthScan__c scan = OrgHealthTestFactory.createScan('In Progress', 'Manual');
        insert scan;
        
        Test.startTest();
        System.enqueueJob(new MyModule(scan.Id));
        Test.stopTest();
        
        HealthModuleScore__c score = [
            SELECT Score__c, Status__c FROM HealthModuleScore__c
            WHERE HealthScan__c = :scan.Id
        ];
        Assert.areEqual('Complete', score.Status__c);
    }
}
```

#### Option 2: Mock Tooling API (Advanced)

```apex
@isTest
private class SecurityScannerModuleTest {
    static void setup() {
        // Mock HttpCalloutMock for Tooling API
        Test.setMock(HttpCalloutMock.class, new ToolingApiMock());
    }
    
    @isTest
    static void testSecurityChecksFindIssues() {
        setup();
        HealthScan__c scan = OrgHealthTestFactory.createScan('In Progress', 'Manual');
        insert scan;
        
        Test.startTest();
        System.enqueueJob(new SecurityScannerModule(scan.Id));
        Test.stopTest();
        
        List<HealthFinding__c> findings = [
            SELECT Id FROM HealthFinding__c
            WHERE HealthScan__c = :scan.Id AND Severity__c = 'Critical'
        ];
        Assert.isTrue(findings.size() > 0);
    }
}
```

### Checkpoint Testing

Test that checkpoint gates work correctly:

```apex
@isTest
static void testDisabledCheckpointSkipsCheck() {
    // Disable a checkpoint
    insert OrgHealthTestFactory.createConfigOverride('Security.ModifyAllData', false);
    
    Test.startTest();
    Boolean enabled = OrgHealthConstants.isCheckpointEnabled('Security.ModifyAllData');
    Test.stopTest();
    
    Assert.isFalse(enabled);
}
```

## Test Data Management

### Using OrgHealthTestFactory

```apex
// Create a complete scan scenario
HealthScan__c scan = OrgHealthTestFactory.createScan('Complete', 'Manual');
insert scan;

HealthModuleScore__c score = OrgHealthTestFactory.createModuleScore(
    scan.Id, 'Security', 85, 'Complete'
);
insert score;

HealthFinding__c finding = OrgHealthTestFactory.createFinding(
    scan.Id, score.Id, 'High', 'Test Finding'
);
insert finding;
```

### Custom Metadata (CMT) in Tests

CMT records are deployed with the package and cannot be modified in tests. To mock CMT for testing:

```apex
// In OrgHealthConstants, the setXxxConfigs methods are @TestVisible
@TestVisible
private static void setModuleConfigs(Map<String, OrgHealthModuleConfig__mdt> mock) {
    moduleConfigs = mock;
}

// In your test:
@isTest
static void testCustomModuleConfig() {
    Map<String, OrgHealthModuleConfig__mdt> mockConfigs = new Map<String, OrgHealthModuleConfig__mdt>();
    // Populate mock configs
    OrgHealthConstants.setModuleConfigs(mockConfigs);
    
    // Test with custom config
}
```

## Code Coverage Best Practices

1. **Test both happy path and error paths**
   - Success cases
   - Null input handling
   - Exception scenarios

2. **Test boundary conditions**
   - Empty collections
   - Maximum values (e.g., score = 100)
   - Minimum values (e.g., score = 0)

3. **Test integrations**
   - Controller → Apex logic
   - CMT merging with Custom Settings
   - Queueable chaining

4. **Test configuration merging**
   - CMT default is used when no override exists
   - Override replaces default when present
   - Multiple overrides are managed independently

## Debugging Tests

### Viewing Test Results

```bash
# Show detailed test output
sf apex run test --class OrgHealthScanOrchestratorTest --verbose
```

### Adding Debug Statements

```apex
@isTest
static void testMyLogic() {
    System.debug('Starting test');
    
    Test.startTest();
    OrgHealthScanOrchestrator.startScan();
    Test.stopTest();
    
    System.debug('Test completed');
}
```

### Analyzing Coverage

1. In Setup > Apex Test Execution, click "View coverage"
2. Look for red-highlighted lines (uncovered)
3. Write tests to exercise those branches

## Extending Test Coverage

To add tests for a new module (e.g., `NewModule`):

1. Create `NewModuleTest` class
2. Add instantiation test
3. Add checkpoint tests
4. Add integration test with System.enqueueJob()
5. Aim for 80%+ code coverage

### Template for Module Test

```apex
@isTest
private class NewModuleTest {
    
    @isTest
    static void testModuleInitialization() {
        HealthScan__c scan = OrgHealthTestFactory.createScan('In Progress', 'Manual');
        insert scan;
        
        Test.startTest();
        NewModule module = new NewModule(scan.Id);
        Test.stopTest();
        
        Assert.isNotNull(module);
    }
    
    @isTest
    static void testModuleCheckpoints() {
        Test.startTest();
        Boolean enabled = OrgHealthConstants.isCheckpointEnabled('NewModule.CheckpointKey');
        Test.stopTest();
        
        Assert.isTrue(enabled);
    }
    
    @isTest
    static void testModuleExecution() {
        HealthScan__c scan = OrgHealthTestFactory.createScan('In Progress', 'Manual');
        insert scan;
        
        Test.startTest();
        System.enqueueJob(new NewModule(scan.Id));
        Test.stopTest();
        
        HealthModuleScore__c score = [
            SELECT Score__c FROM HealthModuleScore__c
            WHERE HealthScan__c = :scan.Id AND Module__c = 'NewModule'
        ];
        Assert.isNotNull(score);
    }
}
```

## CI/CD Integration

### GitHub Actions / GitLab CI Example

```yaml
test:
  script:
    - sf apex run test --code-coverage -w 10
    - sf apex test report generate
  artifacts:
    paths:
      - test-results.xml
    reports:
      junit: test-results.xml
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "System.UnexpectedException: No more data to read" | Wrap Tooling API calls in HttpCalloutMock |
| "INVALID_CROSS_REFERENCE_KEY" | Ensure parent records exist before creating children |
| "Test method timed out" | Check for infinite loops; increase governor limit awareness |
| "CMT records not found" | CMT is read-only in tests; use `setXxxConfigs()` mocks |

## Resources

- [Salesforce Testing Best Practices](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_testing.htm)
- [Apex Test Classes](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_testing_testmethods.htm)
- [Code Coverage](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_testing_codecoverage.htm)
