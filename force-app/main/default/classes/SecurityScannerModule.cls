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
        List<Map<String, Object>> profiles = extractRecords(
            toolingQuery(
                'SELECT Id, Name, PermissionsModifyAllData, PermissionsViewAllData ' +
                'FROM Profile ' +
                'WHERE (PermissionsModifyAllData = true OR PermissionsViewAllData = true) ' +
                'AND UserType = \'Standard\''
            )
        );

        for (Map<String, Object> p : profiles) {
            String name = str(p, 'Name');
            if ('System Administrator'.equalsIgnoreCase(name)) continue;

            Boolean modifyAll = (Boolean) p.get('PermissionsModifyAllData');
            String severity = modifyAll == true ? 'Critical' : 'High';
            String perm     = modifyAll == true ? 'Modify All Data' : 'View All Data';

            addFinding(
                severity,
                'Profile Permissions',
                'Non-admin profile has ' + perm,
                'Profile "' + name + '" has the ' + perm + ' permission, which bypasses all ' +
                'object-level and record-level security. Any user on this profile can ' +
                (modifyAll == true ? 'read and modify' : 'read') + ' every record in the org.',
                'Remove ' + perm + ' from "' + name + '". Grant specific object CRUD and field-level ' +
                'security instead. Where elevated access is needed for specific users, grant it via ' +
                'a Permission Set rather than embedding it in the profile.',
                name,
                'Profile'
            );
        }

        // Repeat for custom permission sets
        List<Map<String, Object>> permSets = extractRecords(
            toolingQuery(
                'SELECT Id, Label, PermissionsModifyAllData ' +
                'FROM PermissionSet ' +
                'WHERE PermissionsModifyAllData = true AND IsCustom = true'
            )
        );

        for (Map<String, Object> ps : permSets) {
            addFinding(
                'Critical',
                'Profile Permissions',
                'Custom Permission Set "' + str(ps, 'Label') + '" has Modify All Data',
                'Custom Permission Set "' + str(ps, 'Label') + '" grants Modify All Data. ' +
                'Any user assigned this permission set can read and overwrite every record in the org, ' +
                'bypassing sharing rules, field-level security, and validation rules.',
                'Remove Modify All Data from this Permission Set. If broad access is needed for an ' +
                'integration user or admin tool, scope it to specific objects via object CRUD permissions ' +
                'rather than a global bypass.',
                str(ps, 'Label'),
                'PermissionSet'
            );
        }
    }

    private void checkFLSGaps() {
        // Flag profiles/permission sets that have ViewAllRecords or ModifyAllRecords
        // on core CRM objects — these bypass sharing rules even when they're configured
        List<Map<String, Object>> rows = extractRecords(
            toolingQuery(
                'SELECT SobjectType, Parent.Name, PermissionsViewAllRecords, PermissionsModifyAllRecords ' +
                'FROM ObjectPermissions ' +
                'WHERE (PermissionsViewAllRecords = true OR PermissionsModifyAllRecords = true) ' +
                'AND SobjectType IN (\'Account\',\'Contact\',\'Lead\',\'Opportunity\',\'Case\')'
            )
        );

        if (rows.isEmpty()) return;

        Map<String, List<String>> byObject = new Map<String, List<String>>();
        for (Map<String, Object> row : rows) {
            String obj = str(row, 'SobjectType');
            Map<String, Object> parent = (Map<String, Object>) row.get('Parent');
            String profileName = parent != null ? str(parent, 'Name') : 'Unknown';
            if (!byObject.containsKey(obj)) byObject.put(obj, new List<String>());
            byObject.get(obj).add(profileName);
        }

        for (String obj : byObject.keySet()) {
            List<String> profiles = byObject.get(obj);
            // Only flag when many profiles bypass sharing — one or two admin profiles is expected
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
        List<User> guestUsers = [
            SELECT Id, Name, ProfileId, Profile.Name
            FROM User
            WHERE UserType = 'Guest' AND IsActive = true
        ];

        if (guestUsers.isEmpty()) return;

        for (User gu : guestUsers) {
            List<Map<String, Object>> objPerms = extractRecords(
                toolingQuery(
                    'SELECT SobjectType, PermissionsRead, PermissionsCreate, PermissionsEdit ' +
                    'FROM ObjectPermissions ' +
                    'WHERE ParentId = \'' + gu.ProfileId + '\' ' +
                    'AND PermissionsRead = true ' +
                    'AND SobjectType LIKE \'%__c\''
                )
            );

            if (objPerms.isEmpty()) continue;

            List<String> accessibleObjects = new List<String>();
            List<String> writableObjects   = new List<String>();
            for (Map<String, Object> perm : objPerms) {
                String sobj = str(perm, 'SobjectType');
                accessibleObjects.add(sobj);
                if ((Boolean) perm.get('PermissionsCreate') == true ||
                    (Boolean) perm.get('PermissionsEdit') == true) {
                    writableObjects.add(sobj);
                }
            }

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
        // If no Login IP Ranges exist on any profile, the org has no network-based access control
        List<Map<String, Object>> ipRanges = extractRecords(
            toolingQuery('SELECT Id FROM ProfileIpAddressRange LIMIT 1')
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
