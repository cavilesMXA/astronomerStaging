public class AccountTriggerHandler {
    /*Let's say the you have sales reps A, B, C, and Z.  C reports to B, and B reports to A in the role hierarchy.  Z, is outside of the A-B-C hierarchy.
A can change account owners to any records A owns and any records B and C own but cannot change the owner of any records owned by Z. If A owns the accounts he can change the account ownership to any user.
B can change account owners to any records that B owns and any records that C owns.  But, B cannot change the ownership of records that A or Z owns. If B owns the accounts he can change the account ownership to any user.
C can change account owners to any records that C owns but cannot change owner of any records owned by B or A or Z. If C owns the accounts he can change the account ownership to any user. Write a trigger and helper class to govern the ownership changes as described above.*/
    
    
    
    // Cache the system admin profile id to avoid repeated SOQL.
    private static Id sysAdminProfileId;
    private static Apex_Custom_Settings__c settings ;

    
    /**
     * Validates that if a non-admin (and non‐admin_bypass) user is changing an Account’s Owner:
     *  1. The current (old) owner is either the current user or a subordinate.
     *  2. The new owner is “in the same branch” as the current owner (that is,
     *     either the new owner is above or equal to the old owner or vice‐versa).
     */
    public static void validateOwnerChange(List<Account> newAccounts, Map<Id, Account> oldAccountMap) {

        settings = Apex_Custom_Settings__c.getOrgDefaults();
        // Build a list of records whose owner is changed.
        List<Account> recordsToCheck = new List<Account>();
    
        for (Account acc : newAccounts) {
        /* Conditiions added to bypass the validation if the Account Owner is a Marketing Automation user or if the user is a Marketing Astronomer User.

        */
            Account oldAcc = oldAccountMap.get(acc.Id);
            String oldAccOwnerId = (String) oldAcc.OwnerId;
            Boolean isMarketingUserId =  String.isNotBlank(settings.Marketing_Automation_Id__c) ? oldAccOwnerId.contains(settings.Marketing_Automation_Id__c) : false ;
            Boolean IsMarketingAutomationUser = String.isNotBlank(settings.Marketing_Astronomer_User_Id__c) ? oldAccOwnerId == settings.Marketing_Astronomer_User_Id__c : false ;

          

            if (acc.OwnerId != oldAcc.OwnerId && !acc.Automation_Bypass__c && (
                ((isMarketingUserId  && !isBypassMarketing() ) )
                || 
                ((IsMarketingAutomationUser  && !isBypassMarketing() ) )
                || 
                (!IsMarketingAutomationUser && !isMarketingUserId)
                )
            ) {
                recordsToCheck.add(acc);
            }
        }
        
        
        if (recordsToCheck.isEmpty()) {
            return;
        }
        
        
        // Bypass all validations if the current user is a system admin or has the admin_bypass permission.
        if (isBypassUser()) {
            return;
        }
        // Bypass all validations if the current user has the Contact/Account Owner Change Bypass permission
        if(isContactOwnerBypass()){
             return;
        }
        
        
        // Collect all involved user Ids: the current user, each record’s old owner and new owner.
        Set<Id> userIds = new Set<Id>();
        Id currentUserId = UserInfo.getUserId();
        userIds.add(currentUserId);
        for (Account acc : recordsToCheck) {
            userIds.add(oldAccountMap.get(acc.Id).OwnerId);
            userIds.add(acc.OwnerId);
        }
        
        // Query Users (we only need the UserRoleId)
        Map<Id, User> userMap = new Map<Id, User>(
            [SELECT Id, UserRoleId FROM User WHERE Id IN :userIds]
        );
        
        // Collect the role ids we saw.
        Set<Id> roleIds = new Set<Id>();
        for (User u : userMap.values()) {
            if (u.UserRoleId != null) {
                roleIds.add(u.UserRoleId);
            }
        }
        
        // Query the UserRole objects to get each role’s ParentRoleId.
        Map<Id, UserRole> roleMap = new Map<Id, UserRole>();

        if (!roleIds.isEmpty()) {
            for (UserRole ur : [
                SELECT Id, ParentRoleId
                FROM UserRole
                
            ]) {
                
                roleMap.put(ur.Id, ur);
            }
        }
        
        // Loop through each record and enforce our two business rules.
        for (Account acc : recordsToCheck) {
            Account oldAcc = oldAccountMap.get(acc.Id);
            Id oldOwnerId = oldAcc.OwnerId;
            Id newOwnerId = acc.OwnerId;
            
            Boolean Rule1 = isUserAboveOrEqual(currentUserId, oldOwnerId, userMap, roleMap,false);
            Boolean Rule2a = isUserAboveOrEqual(newOwnerId, oldOwnerId, userMap, roleMap,false);
            Boolean Rule2b = isUserAboveOrEqual(oldOwnerId, newOwnerId, userMap, roleMap,true); 
            

            // Rule 2: The new owner must be in the same role hierarchy branch as the old owner.
            // That is, either the new owner is above or equal to the old owner, or vice‐versa.

            //If the current user role is above the old account owner role, then bypass the validation rule
            if (!( Rule2a || Rule2b ) && !(Rule1)) 
            {
                acc.addError('The new owner must be in the same role hierarchy branch as the current owner. Only the account owner has the ability to transfer ownership to any other user.');
                continue; // no need to run further checks on this record
            }
            // Rule 1: The logged‐in user must be the same as (or “above”) the current (old) owner.
            if (!Rule1) 
            {
                acc.addError('You do not have permission to change the owner for this account because you are not above the current owner in the role hierarchy.');
               
            }
           
            
            
        }
    }
    
    /**
     * Checks whether the current user should bypass the restrictions.
     * Returns true if the user is a system admin or if they have the custom permission admin_bypass.
     */
    public static Boolean isBypassUser() {
        // Cache the system admin profile id so we do not query it repeatedly.
        if (sysAdminProfileId == null) {
            sysAdminProfileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id;
        }
        if (UserInfo.getProfileId() == sysAdminProfileId) {
            return true;
        }
        // FeatureManagement.checkPermission() returns true if the current user has the custom permission.
        if (FeatureManagement.checkPermission('admin_bypass')) {
            return true;
        }
        return false;
    }

    public static Boolean isBypassMarketing() {

        // FeatureManagement.checkPermission() returns true if the current user has the custom permission.
        if (FeatureManagement.checkPermission('allow_marketing_owner_change')) {
            return true;
        }
        return false;
    }

    
    public static Boolean isContactOwnerBypass() {

        // FeatureManagement.checkPermission() returns true if the current user has the custom permission.
        if (FeatureManagement.checkPermission('Contact_Account_Owner_Change_Bypass')) {
            return true;
        }
        return false;
    }
    
    
    /**
     * Returns true if the user identified by potentialManagerId is either the same as or is “above”
     * the user identified by potentialSubordinateId in the role hierarchy.
     * 
     * The method uses the passed-in userMap (mapping user Id → User record, which includes the UserRoleId)
     * and roleMap (mapping a UserRole Id to its ParentRoleId) to traverse upward along the subordinate’s
     * role chain.
     */
    public static Boolean isUserAboveOrEqual(
        Id potentialManagerId,
        Id potentialSubordinateId,
        Map<Id, User> userMap,
        Map<Id, UserRole> roleMap ,
        Boolean isOldOwnerFirstParameter

    ) {
        // A user is always “above or equal to” itself.
        if (potentialManagerId == potentialSubordinateId) {
            return true;
        }
        
        User managerUser = userMap.get(potentialManagerId);
        User subordinateUser = userMap.get(potentialSubordinateId);
        
        // If we do not have the user or role information, conservatively return false.
        if (managerUser == null || subordinateUser == null) {
            return false;
        }
        if (subordinateUser.UserRoleId == null || managerUser.UserRoleId == null) {
            return false;
        }
        
        // Walk upward from the subordinate’s role. If we encounter the manager’s role, then the manager is "above."
        Id currentRoleId = subordinateUser.UserRoleId;
        while (currentRoleId != null) {
            if (currentRoleId == managerUser.UserRoleId) {
                return true;
            }
            UserRole currentRole = roleMap.get(currentRoleId);
            if (currentRole == null) {
                break;
            }
            currentRoleId = currentRole.ParentRoleId;

        }

        // 3/10/2025 added bypass to allow the Account Owner to change owner to any other user
        if(isOldOwnerFirstParameter){
            if(UserInfo.getUserId() == potentialManagerId){
                return true;
            }          
        }
        else if(!isOldOwnerFirstParameter){
            if(UserInfo.getUserId() == potentialSubordinateId){
                return true;
            }       
        }
       
        


        return false;
       
    }

/*

    public static Boolean isCurrentUserHighestForAccountChange(Id accountId, Id newOwnerId) {
      
        Boolean isCurrentUserHigherThanNewOwner = isHigherRole(currentUser.UserRoleId, newOwner.UserRoleId, roleMap);
        Boolean isCurrentUserHigherThanOldOwner = isHigherRole(currentUser.UserRoleId, oldOwner.UserRoleId, roleMap);
        Boolean isNewOwnerRelated = isDirectOrIndirectChild(currentUser.UserRoleId, newOwner.UserRoleId, roleMap);

        return isCurrentUserHigherThanNewOwner && isCurrentUserHigherThanOldOwner && isNewOwnerRelated;
    }

    private static Boolean isDirectOrIndirectChild(Id higherRoleId, Id childRoleId, Map<Id, UserRole> roleMap) {
        Id currentRoleId = childRoleId;
        while (currentRoleId != null) {
            UserRole role = roleMap.get(currentRoleId);
            if (role == null) break;
            if (role.ParentRoleId == higherRoleId) return true; 
            currentRoleId = role.ParentRoleId;
        }
        return false;
    }
*/


    
}