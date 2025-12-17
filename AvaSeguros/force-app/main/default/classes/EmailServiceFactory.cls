public class EmailServiceFactory {

    @TestVisible
    private static IEmailService mock;

    public static void setMock(IEmailService m) {
        System.debug('mock: ' + m);
        mock = m;
    }

    public static IEmailService getInstance() {
        System.debug('mock: ' + mock);
        return mock != null ? mock : new EmailService();
    }
}
