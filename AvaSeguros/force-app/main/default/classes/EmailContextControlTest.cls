@IsTest
public class EmailContextControlTest {

    @IsTest
    static void testSkipEmailsFlag() {
        EmailContextControl.skipEmails = true;
        System.assertEquals(true, EmailContextControl.skipEmails);
    }
}