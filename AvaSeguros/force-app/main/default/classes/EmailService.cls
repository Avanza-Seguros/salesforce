public with sharing class EmailService implements IEmailService{

    private static final Integer CHUNK_SIZE = 10;

    public static void send(List<Messaging.SingleEmailMessage> emails) {

        if (emails == null || emails.isEmpty()) return;

        Integer total = emails.size();

        for (Integer i = 0; i < total; i += CHUNK_SIZE) {

            List<Messaging.SingleEmailMessage> chunk =
                new List<Messaging.SingleEmailMessage>();

            Integer endTo = Math.min(i + CHUNK_SIZE, total);

            for (Integer j = i; j < endTo; j++) {
                chunk.add(emails[j]);
            }

            Messaging.sendEmail(chunk, false);
        }
    }
}
