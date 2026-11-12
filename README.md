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
else writeln(sent.httpStatus, " ", sent.httpResponse);
```

# dynamic templates
```d
auto sent = new SendGrid(YOUR_API_KEY)
  .addPersonalization(
    new SendGridPersonalization("john@example.com", "John Doe")
      .addDynamicTemplateData("name", "John")
  )
  .from("me@example.com")
  .templateId("d-1234567890abcdef")
  .send();
```

# cc, bcc and attachments
`SendGrid.addCC` and `SendGrid.addBCC` add the recipient to every personalization.
The MIME type of attachments is guessed from the file extension when not given.
```d
auto sent = new SendGrid(YOUR_API_KEY)
  .addPersonalization(new SendGridPersonalization("john@example.com", "John Doe"))
  .from("me@example.com")
  .addBCC("archive@example.com")
  .subject("your report")
  .addContent("see attachment", "text/plain")
  .addAttachment("report.pdf")
  .send();
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
