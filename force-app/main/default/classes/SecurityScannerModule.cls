public class SecurityScannerModule extends OrgHealthBaseModule {

    public SecurityScannerModule(Id scanId) {
        super(scanId, OrgHealthConstants.MODULE_SECURITY);
    }

    protected override void runChecks() {
        checkModifyAllDataProfiles();
        checkFLSGaps();
        checkGuestUserAccess();
        checkPasswordPolicy();
    }

    private void checkModifyAllDataProfiles() {
        if (!OrgHealthConstants.isCheckpointEnabled('Security.ModifyAllData')) return;
        for (Profile p : [
            SELECT Name, PermissionsModifyAllData, PermissionsViewAllData
            FROM Profile
            WHERE (PermissionsModifyAllData = true OR PermissionsViewAllData = true)
            AND UserType = 'Standard'
        ]) {
            if ('System Administrator'.equalsIgnoreCase(p.Name)) continue;

            Boolean modifyAll = p.PermissionsModifyAllData;
            String severity   = modifyAll ? 'Critical' : 'High';
            String perm       = modifyAll ? 'Modify All Data' : 'View All Data';

            addFinding(
                severity,
                'Profile Permissions',
                'Non-admin profile has ' + perm,
                'Profile "' + p.Name + '" has the ' + perm + ' permission, which bypasses all ' +
                'object-level and record-level security. Any user on this profile can ' +
                (modifyAll ? 'read and modify' : 'read') + ' every record in the org.',
                'Remove ' + perm + ' from "' + p.Name + '". Grant specific object CRUD and field-level ' +
                'security instead. Where elevated access is needed for specific users, grant it via ' +
                'a Permission Set rather than embedding it in the profile.',
                p.Name,
                'Profile'
            );
        }

        for (PermissionSet ps : [
            SELECT Label
            FROM PermissionSet
            WHERE PermissionsModifyAllData = true AND IsCustom = true
        ]) {
            addFinding(
                'Critical',
                'Profile Permissions',
                'Custom Permission Set "' + ps.Label + '" has Modify All Data',
                'Custom Permission Set "' + ps.Label + '" grants Modify All Data. ' +
                'Any user assigned this permission set can read and overwrite every record in the org, ' +
                'bypassing sharing rules, field-level security, and validation rules.',
                'Remove Modify All Data from this Permission Set. If broad access is needed for an ' +
                'integration user or admin tool, scope it to specific objects via object CRUD permissions ' +
                'rather than a global bypass.',
                ps.Label,
                'PermissionSet'
            );
        }
    }

    private void checkFLSGaps() {
        if (!OrgHealthConstants.isCheckpointEnabled('Security.FLSGaps')) return;
        List<ObjectPermissions> rows = [
            SELECT SobjectType, Parent.Name, PermissionsViewAllRecords, PermissionsModifyAllRecords
            FROM ObjectPermissions
            WHERE (PermissionsViewAllRecords = true OR PermissionsModifyAllRecords = true)
            AND SobjectType IN ('Account', 'Contact', 'Lead', 'Opportunity', 'Case')
        ];

        if (rows.isEmpty()) return;

        Map<String, List<String>> byObject = new Map<String, List<String>>();
        for (ObjectPermissions row : rows) {
            String obj         = row.SobjectType;
            String profileName = row.Parent?.Name ?? 'Unknown';
            if (!byObject.containsKey(obj)) byObject.put(obj, new List<String>());
            byObject.get(obj).add(profileName);
        }

        for (String obj : byObject.keySet()) {
            List<String> profiles = byObject.get(obj);
            if (profiles.size() > 3) {
                addFinding(
                    'High',
                    'FLS Gaps',
                    profiles.size() + ' profile(s) bypass sharing rules on ' + obj,
                    profiles.size() + ' profiles or permission sets have ViewAllRecords or ' +
                    'ModifyAllRecords on ' + obj + '. This circumvents the sharing rule and role ' +
                    'hierarchy configuration for these users. Profiles: ' +
                    String.join(profiles.size() <= 8 ? profiles : firstN(profiles, 8), ', ') +
                    (profiles.size() > 8 ? ' … and ' + (profiles.size() - 8) + ' more.' : '.'),
                    'Review whether each profile genuinely needs row-level bypass on ' + obj + '. ' +
                    'Restrict this to a minimum set of integration or admin profiles and remove it ' +
                    'from general user profiles.',
                    obj,
                    'Object'
                );
            }
        }
    }

    private void checkGuestUserAccess() {
        if (!OrgHealthConstants.isCheckpointEnabled('Security.GuestUserAccess')) return;
        List<User> guestUsers = [
            SELECT Id, Name, ProfileId, Profile.Name
            FROM User
            WHERE UserType = 'Guest' AND IsActive = true
        ];

        if (guestUsers.isEmpty()) return;

        for (User gu : guestUsers) {
            List<ObjectPermissions> objPerms = [
                SELECT SobjectType, PermissionsRead, PermissionsCreate, PermissionsEdit
                FROM ObjectPermissions
                WHERE ParentId = :gu.ProfileId
                AND PermissionsRead = true
            ];

            List<String> accessibleObjects = new List<String>();
            List<String> writableObjects   = new List<String>();
            for (ObjectPermissions perm : objPerms) {
                if (!perm.SobjectType.endsWith('__c')) continue;
                accessibleObjects.add(perm.SobjectType);
                if (perm.PermissionsCreate || perm.PermissionsEdit) {
                    writableObjects.add(perm.SobjectType);
                }
            }

            if (accessibleObjects.isEmpty()) continue;

            addFinding(
                'Critical',
                'Guest User Access',
                'Guest profile can access ' + accessibleObjects.size() + ' custom object(s)',
                'Guest user "' + gu.Name + '" (Profile: ' + gu.Profile.Name + ') has read access ' +
                'to ' + accessibleObjects.size() + ' custom object(s) without authentication: ' +
                String.join(accessibleObjects, ', ') + '.' +
                (writableObjects.isEmpty() ? '' : ' Write access on: ' + String.join(writableObjects, ', ') + '.'),
                'Remove unnecessary object permissions from the guest user profile. ' +
                'Expose only objects explicitly required for your Experience Cloud site or public-facing ' +
                'integration. Guest users represent the highest-risk access point in the org as they bypass authentication.',
                gu.Profile.Name,
                'Profile'
            );
        }
    }

    private void checkPasswordPolicy() {
        if (!OrgHealthConstants.isCheckpointEnabled('Security.PasswordPolicy')) return;
        List<Map<String, Object>> ipRanges = extractRecords(
            toolingQuery('SELECT Id FROM IpAddressRange LIMIT 1')
        );

        if (ipRanges.isEmpty()) {
            addFinding(
                'Medium',
                'Network Security',
                'No Login IP Range restrictions configured on any profile',
                'No profiles have Login IP Ranges set. Without IP restrictions, valid credentials ' +
                'can be used to authenticate from anywhere in the world.',
                'Configure Login IP Ranges on high-privilege profiles (System Administrator, ' +
                'Integration User) to restrict access to known corporate IP ranges. ' +
                'For users requiring global access, enforce MFA via a Verification Method policy ' +
                'as a compensating control.',
                'Org',
                'Org'
            );
        }
    }
}
