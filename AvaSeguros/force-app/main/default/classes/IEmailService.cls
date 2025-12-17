public interface IEmailService {
    void send(List<Messaging.SingleEmailMessage> emails);
}