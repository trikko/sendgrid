# sendgrid
Unofficial sendgrid API for dlang. [docs](https://trikko.github.io/sendgrid)

# example
```d
auto sent = new SendGrid(YOUR_API_KEY)
  .addPersonalization(new SendGridPersonalization("john@example.com", "John Doe"))
  .from("me@example.com")
  .subject("hello world")
  .addContent("this is a test", "text/plain")
  .send();

if (sent) writeln("Message sent!");
```

# EU data residency
Accounts and subusers with EU data residency must use the EU servers (api.eu.sendgrid.com):
```d
auto sent = new SendGrid(YOUR_API_KEY, SendGrid.Region.eu)
  // or: new SendGrid(YOUR_API_KEY).region(SendGrid.Region.eu)
  .addPersonalization(new SendGridPersonalization("john@example.com", "John Doe"))
  .from("me@example.com")
  .subject("hello world")
  .addContent("this is a test", "text/plain")
  .send();
```
