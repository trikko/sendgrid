/++ SendGrid API for D
+ Authors: Andrea Fontana
+ License: MIT
+/
module sendgrid;

import std.datetime 	: SysTime;
import std.json 		: JSONValue, parseJSON;
import std.base64 	: Base64;
import std.net.curl 	: HTTP;
import std.string		: representation;
import std.typecons	: No;

import jsonwrap;

/++ Main class to send emails using SendGrid
+ ---
+ auto result = new SendGrid("API_KEY")
+ 	.addPersonalization(new SendGridPersonalization("john@example.com", "John Doe"))
+ 	.from("you@example.com", "Your Name")
+ 	.subject("Hello World")
+ 	.addContent("<html><body><h1>Hello World</h1></body></html>", "text/html")
+ 	.send();
+ ---
+/
class SendGrid
{
	/++ SendGrid response.
	+ ---
	+ if (result) // Same as if (result.success)
	+ 	writeln("Message sent successfully");
	+ ---
	+/
	struct SendResult
	{
		/// True if the message was sent successfully
		@property
		bool 			success() { return _success; }

		/// HTTP status code
		int 			httpStatus() { return _httpStatus; }

		/// HTTP response
		JSONValue 	httpResponse() { return _httpResponse; }

		/// Convert to string
		string toString() => JSOB("success", _success, "httpStatus", _httpStatus, "httpResponse", _httpResponse).toPrettyString;

		private bool 		_success = false;
		private int 		_httpStatus;
		private JSONValue _httpResponse;
		alias success this;
	}

	/// Constructor. It requires a valid API key
	this(string apiKey)
	{
		this.apiKey = apiKey;
	}

	/++ Add a personalization to the message. At least one recipient is required.
	+ ---
	+ auto result = new SendGrid("API_KEY")
	+ 	.addPersonalization(new SendGridPersonalization("test@example.com", "Test").subject("Hello World"))
	+  .subject("This subject is overridden by personalization")
	+ 	.send();
	+ ---
	+/
	SendGrid addPersonalization(SendGridPersonalization SendGridPersonalization)
	{
		data.append("personalizations", SendGridPersonalization.data);
		return this;
	}

	/// Add a CC recipient
	SendGrid addCC(string email, string name)
	{
		data.append("cc", JSOB("email", email, "name", name));
		return this;
	}

	/// Add a BCC recipient
	SendGrid addBCC(string email, string name)
	{
		data.append("bcc", JSOB("email", email, "name", name));
		return this;
	}

	/// Set the subject of the message
	SendGrid subject(string subject)
	{
		data.put("subject", subject);
		return this;
	}

	/++ Set the time at which the message should be sent
	+ ---
	+ // Your email will be sent in one hour
	+ email.sendAt(SysTime.currTime + 1.hours);
	+ ---
	+/
	SendGrid sendAt(SysTime time)
	{
		data.put("send_at", time.toUnixTime);
		return this;
	}

	/// Add a content to the message. More than one content can be added.
	SendGrid addContent(string value, string type = "text/html")
	{
		data.append("content", JSOB("type", type, "value", value));
		return this;
	}

	/// Add an attachment to the message
	SendGrid addAttachment(ubyte[] content, string filename, string type = "text/plain")
	{
		data.append("attachments", JSOB("content", Base64.encode(content), "filename", filename, "type", type));
		return this;
	}

	/// Add an attachment to the message
	SendGrid addAttachment(string filename, string type = "text/plain")
	{
		import std.file : read;
		import std.path : baseName;

		addAttachment(cast(ubyte[])read(filename), baseName(filename), type);
		return this;
	}

	/// Set the template id for the message
	SendGrid templateId(string templateId)
	{
		data.put("template_id", templateId);
		return this;
	}

	/// Set the sender of the message. Required.
	SendGrid from(string email, string name = "")
	{
		data.put("from", JSOB("email", email, "name", name));
		return this;
	}

	/// Set the reply-to addres of the message
	SendGrid replyTo(string email, string name = "")
	{
		data.put("reply_to", JSOB("email", email, "name", name));
		return this;
	}

	/// Send the message
	SendResult send()
	{
		// Some validations
		if (!data.exists("personalizations/0/to/0/email"))
			throw new Exception("At least one recipient is required");

		if (!data.exists("from/email"))
			throw new Exception("Sender is required");

		SendResult response;

		HTTP http = HTTP("https://api.sendgrid.com/v3/mail/send");
		http.method = HTTP.Method.post;
		http.addRequestHeader("Authorization", "Bearer " ~ apiKey);
		http.addRequestHeader("Content-Type", "application/json");

		string msg = data.toString;
		string content;

		http.onSend = (void[] data)
		{
			auto m = cast(void[]) msg;
			size_t len = m.length > data.length ? data.length : m.length;
			if (len == 0) return len;
			data[0 .. len] = m[0 .. len];
			msg = msg[len..$];
			return len;
		};

		http.onReceive = (ubyte[] data) { content ~= cast(char[]) data; return data.length; };

		auto ret = http.perform(No.throwOnError);

		if (ret != 0)
		{
			response._httpStatus = -1;
			response._httpResponse = "";
		}
		else
		{
			response._httpStatus = http.statusLine.code;
			response._httpResponse = content.parseJSON;
		}

		response._success = (response._httpStatus == 202);

		return response;
	}

	@disable this();

	private JSONValue data = "{}".parseJSON;
	private string 	apiKey;
}


/++ SendGrid personalization
+ ---
+ auto personalization = new SendGridPersonalization("john@example.com", "John Doe");
+ personalization.subject("Hello World");
+ personalization.addSubstitution("name", "John Doe");
+ ---
+/
class SendGridPersonalization
{
	/// Constructor. At least one recipient is required
	this(string toEmail, string toName = "")
	{
		addTo(toEmail, toName);
	}

	/// Add a recipient
	SendGridPersonalization addTo(string email, string name)
	{
		data.append("to", JSOB("email", email, "name", name));
		return this;
	}

	/// Add a CC recipient
	SendGridPersonalization addCC(string email, string name)
	{
		data.append("cc", JSOB("email", email, "name", name));
		return this;
	}

	/// Add a BCC recipient
	SendGridPersonalization addBCC(string email, string name)
	{
		data.append("bcc", JSOB("email", email, "name", name));
		return this;
	}

	/// Set the subject of the message
	SendGridPersonalization subject(string subject)
	{
		data.put("subject", subject);
		return this;
	}

	/// Set the time at which the message should be sent
	SendGridPersonalization sendAt(SysTime time)
	{
		data.put("send_at", time.toUnixTime);
		return this;
	}

	/// Add a substitution to the message
	SendGridPersonalization addSubstitution(string key, string value)
	{
		data.append("substitutions", JSOB("key", key, "value", value));
		return this;
	}

	private JSONValue data = "{}".parseJSON;
	@disable this();
}
