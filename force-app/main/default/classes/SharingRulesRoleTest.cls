/* 
@auther: Emmanuel Jesse Madasu
@Date: 06-05-2026
@description:Test Class for SharingRulesRole 
@ref: https://1218globaluk.eu.teamwork.com/app/tasks/36058236
*/
@IsTest
private class SharingRulesRoleTest {

    @IsTest
    static void testGetRoles() {
        // Get any existing role
        UserRole role = [SELECT Id, Name FROM UserRole LIMIT 1];

        // Create user
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User'
                     LIMIT 1];

        User u = new User(FirstName = 'Test',LastName = 'User',
                          Alias = 'tuser',Email = 'testuser@example.com',
                          Username = 'testuser' + System.currentTimeMillis() + '@example.com',
                          TimeZoneSidKey = 'Asia/Kolkata', LocaleSidKey = 'en_US',
                          EmailEncodingKey = 'UTF-8',LanguageLocaleKey = 'en_US',
                          ProfileId = p.Id, UserRoleId = role.Id);
        insert u;

        // Create request
        SharingRulesRole.Request req = new SharingRulesRole.Request();
        req.userId = u.Id;

        List<SharingRulesRole.Request> requests =
            new List<SharingRulesRole.Request>{ req };

        Test.startTest();

        List<SharingRulesRole.Response> results =
            SharingRulesRole.getRoles(requests);

        Test.stopTest();

        // Verify response list returned
        System.assertEquals(1, results.size());

        
        // verify method executes successfully
        System.assertNotEquals(null, results[0]);
    }

    @IsTest
    static void testReturnsSearchPolicyApiName() {
        UserRole role = [SELECT Id, Name FROM UserRole WHERE DeveloperName = 'Prospero_Teaching' LIMIT 1];
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User u = new User(FirstName = 'Test',LastName = 'Teaching',
                          Alias = 'tteach',Email = 'testteaching@example.com',
                          Username = 'testteaching' + System.currentTimeMillis() + '@example.com',
                          TimeZoneSidKey = 'Asia/Kolkata', LocaleSidKey = 'en_US',
                          EmailEncodingKey = 'UTF-8',LanguageLocaleKey = 'en_US',
                          ProfileId = p.Id, UserRoleId = role.Id);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
        }

        insert new Textkernel1__SearchPolicy__c(Name = role.Name,
                                                Textkernel1__ApiName__c = 'ProsperoTeaching');

        SharingRulesRole.Request req = new SharingRulesRole.Request();
        req.userId = u.Id;

        Test.startTest();
        List<SharingRulesRole.Response> results =
            SharingRulesRole.getRoles(new List<SharingRulesRole.Request>{ req });
        Test.stopTest();

        // verify the Search Access Policy API value is returned, not the Role Name
        System.assertEquals('ProsperoTeaching', results[0].matchedRoleName);
    }
}