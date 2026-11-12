/++ SendGrid API for D
+ Authors: Andrea Fontana
+ License: MIT
+/
module sendgrid;

import std.datetime 	: SysTime;
import std.json 		: JSONValue, JSONType, parseJSON;
import std.base64 	: Base64;
import std.net.curl 	: HTTP, CurlException;
import core.time		: seconds;

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
		bool 			success() const { return _success; }

		/// HTTP status code, or -1 if the request could not be completed (network error, timeout, ...)
		@property
		int 			httpStatus() const { return _httpStatus; }

		/++ HTTP response. On errors SendGrid replies with a JSON object.
		+ If the request could not be completed, it is a string with the error message.
		+/
		@property
		JSONValue 	httpResponse() { return _httpResponse; }

		/// Convert to string
		string toString() => JSOB("success", _success, "httpStatus", _httpStatus, "httpResponse", _httpResponse).toPrettyString;

		private bool 		_success = false;
		private int 		_httpStatus;
		private JSONValue _httpResponse;
		alias success this;
	}

	/++ SendGrid servers. Use `eu` for accounts and subusers with EU data residency:
	+ their API keys only work on the EU servers.
	+/
	enum Region
	{
		global,	/// api.sendgrid.com (default)
		eu			/// api.eu.sendgrid.com
	}

	/// Constructor. It requires a valid API key
	this(string apiKey, Region region = Region.global)
	{
		import std.string : indexOfAny;

		if (apiKey.length == 0 || apiKey.indexOfAny("\r\n") >= 0)
			throw new Exception("Invalid API key");

		this.apiKey = apiKey;
		this._region = region;
	}

	/++ Send through the servers of a region
	+ ---
	+ auto result = new SendGrid("API_KEY")
	+ 	.region(SendGrid.Region.eu)
	+ 	.addPersonalization(new SendGridPersonalization("john@example.com", "John Doe"))
	+ 	.from("you@example.com", "Your Name")
	+ 	.subject("Hello World")
	+ 	.addContent("<html><body><h1>Hello World</h1></body></html>", "text/html")
	+ 	.send();
	+ ---
	+/
	SendGrid region(Region region)
	{
		_region = region;
		return this;
	}

	/++ Add a personalization to the message. At least one recipient is required.
	+ ---
	+ auto result = new SendGrid("API_KEY")
	+ 	.addPersonalization(new SendGridPersonalization("test@example.com", "Test").subject("Hello World"))
	+  .subject("This subject is overridden by personalization")
	+ 	.send();
	+ ---
	+/
	SendGrid addPersonalization(SendGridPersonalization personalization)
	{
		data.append("personalizations", personalization.data);
		return this;
	}

	/++ Add a CC recipient to every personalization of the message.
	+ SendGrid accepts CC recipients only inside personalizations: this is a shortcut.
	+ Addresses already present in a personalization are skipped.
	+/
	SendGrid addCC(string email, string name = "")
	{
		_cc ~= address(email, name);
		return this;
	}

	/++ Add a BCC recipient to every personalization of the message.
	+ SendGrid accepts BCC recipients only inside personalizations: this is a shortcut.
	+ Addresses already present in a personalization are skipped.
	+/
	SendGrid addBCC(string email, string name = "")
	{
		_bcc ~= address(email, name);
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

	/++ Add a content to the message. More than one content can be added.
	+ `text/plain` content is always sent first, then `text/html`, as required by SendGrid.
	+/
	SendGrid addContent(string value, string type = "text/html")
	{
		data.append("content", JSOB("type", type, "value", value));
		return this;
	}

	/++ Add an attachment to the message.
	+ If `type` is empty, the MIME type is guessed from the file extension.
	+/
	SendGrid addAttachment(const(ubyte)[] content, string filename, string type = "")
	{
		if (type.length == 0) type = mimeType(filename);
		data.append("attachments", JSOB("content", Base64.encode(content).idup, "filename", filename, "type", type));
		return this;
	}

	/++ Read a file from disk and add it as attachment to the message.
	+ If `type` is empty, the MIME type is guessed from the file extension.
	+ Warning: the file is read as is, never pass an unchecked path coming from user input.
	+/
	SendGrid addAttachment(string filename, string type = "")
	{
		import std.file : read;
		import std.path : baseName;

		return addAttachment(cast(const(ubyte)[])read(filename), baseName(filename), type);
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
		data.put("from", address(email, name));
		return this;
	}

	/// Set the reply-to address of the message
	SendGrid replyTo(string email, string name = "")
	{
		data.put("reply_to", address(email, name));
		return this;
	}

	/// Send the message
	SendResult send()
	{
		string msg = payload().toString;

		SendResult response;
		string content;

		HTTP http = HTTP((_region == Region.eu ? "https://api.eu.sendgrid.com" : "https://api.sendgrid.com") ~ "/v3/mail/send");
		http.connectTimeout = 10.seconds;
		http.operationTimeout = 60.seconds;
		http.method = HTTP.Method.post;
		http.addRequestHeader("Authorization", "Bearer " ~ apiKey);
		http.setPostData(msg, "application/json");
		http.onReceive = (ubyte[] chunk) { content ~= cast(const(char)[]) chunk; return chunk.length; };

		try
		{
			http.perform();
			response._httpStatus = http.statusLine.code;

			// on success (202) the body is empty; errors come as JSON
			try response._httpResponse = content.length ? content.parseJSON : JSONValue.init;
			catch (Exception) response._httpResponse = JSONValue(sanitized(content));
		}
		catch (CurlException e)
		{
			response._httpStatus = -1;
			response._httpResponse = JSONValue(e.msg);
		}

		response._success = (response._httpStatus == 202);

		return response;
	}

	@disable this();

	// Build the JSON sent to SendGrid. It does not modify the message, so send() can be called again.
	private JSONValue payload()
	{
		import std.algorithm : sort, SwapStrategy;
		import std.uni : toLower;

		if (!data.exists("personalizations/0/to/0/email"))
			throw new Exception("At least one recipient is required");

		if (!data.exists("from/email"))
			throw new Exception("Sender is required");

		if (!data.exists("content/0") && !data.exists("template_id"))
			throw new Exception("A content or a template id is required");

		// Deep copy: personalizations are shared with SendGridPersonalization objects
		JSONValue p = data.toString.parseJSON;

		if (_cc.length || _bcc.length)
		{
			foreach (ref pers; p["personalizations"].array)
			{
				bool[string] seen;
				foreach (field; ["to", "cc", "bcc"])
					if (field in pers)
						foreach (r; pers[field].array)
							seen[r["email"].str.toLower] = true;

				void add(string field, JSONValue[] list)
				{
					foreach (r; list)
					{
						auto email = r["email"].str.toLower;
						if (email in seen) continue;
						seen[email] = true;
						pers.append(field, r);
					}
				}

				add("cc", _cc);
				add("bcc", _bcc);
			}
		}

		if ("content" in p)
		{
			static int rank(JSONValue c)
			{
				auto t = c["type"].str.toLower;
				return t == "text/plain" ? 0 : t == "text/html" ? 1 : 2;
			}

			auto c = p["content"].array;
			c.sort!((a, b) => rank(a) < rank(b), SwapStrategy.stable);
			p["content"] = c;
		}

		return p;
	}

	private JSONValue 	data = "{}".parseJSON;
	private JSONValue[]	_cc;
	private JSONValue[]	_bcc;
	private string 		apiKey;
	private Region 		_region = Region.global;
}


/++ SendGrid personalization
+ ---
+ auto personalization = new SendGridPersonalization("john@example.com", "John Doe");
+ personalization.subject("Hello World");
+ personalization.addDynamicTemplateData("name", "John Doe");
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
	SendGridPersonalization addTo(string email, string name = "")
	{
		data.append("to", address(email, name));
		return this;
	}

	/// Add a CC recipient
	SendGridPersonalization addCC(string email, string name = "")
	{
		data.append("cc", address(email, name));
		return this;
	}

	/// Add a BCC recipient
	SendGridPersonalization addBCC(string email, string name = "")
	{
		data.append("bcc", address(email, name));
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

	/// Add a substitution (legacy templates): every `key` in the message is replaced with `value`
	SendGridPersonalization addSubstitution(string key, string value)
	{
		setField("substitutions", key, JSONValue(value));
		return this;
	}

	/++ Add a value for a dynamic template (see `SendGrid.templateId`)
	+ ---
	+ personalization
	+ 	.addDynamicTemplateData("name", "John Doe")
	+ 	.addDynamicTemplateData("items", ["one", "two"]);
	+ ---
	+/
	SendGridPersonalization addDynamicTemplateData(T)(string key, T value)
	{
		setField("dynamic_template_data", key, JSONValue(value));
		return this;
	}

	/// Set all the data for a dynamic template at once. It must be a JSON object.
	SendGridPersonalization dynamicTemplateData(JSONValue value)
	{
		if (value.type != JSONType.object)
			throw new Exception("Dynamic template data must be a JSON object");

		data["dynamic_template_data"] = value;
		return this;
	}

	// Set obj[key] = value, without interpreting `/` in key as a path
	private void setField(string obj, string key, JSONValue value)
	{
		JSONValue o = (obj in data) ? data[obj] : JSONValue(string[string].init);
		o[key] = value;
		data[obj] = o;
	}

	private JSONValue data = "{}".parseJSON;
	@disable this();
}

private JSONValue address(string email, string name)
{
	return name.length ? JSOB("email", email, "name", name) : JSOB("email", email);
}

private string sanitized(string s)
{
	import std.encoding : sanitize;
	return sanitize(s);
}

private string mimeType(string filename)
{
	import std.path : extension;
	import std.uni : toLower;

	switch (filename.extension.toLower)
	{
		case ".txt": 	return "text/plain";
		case ".htm":
		case ".html": 	return "text/html";
		case ".csv": 	return "text/csv";
		case ".ics": 	return "text/calendar";
		case ".xml": 	return "application/xml";
		case ".json": 	return "application/json";
		case ".pdf": 	return "application/pdf";
		case ".zip": 	return "application/zip";
		case ".doc": 	return "application/msword";
		case ".docx": 	return "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
		case ".xls": 	return "application/vnd.ms-excel";
		case ".xlsx": 	return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
		case ".png": 	return "image/png";
		case ".jpg":
		case ".jpeg": 	return "image/jpeg";
		case ".gif": 	return "image/gif";
		case ".webp": 	return "image/webp";
		case ".svg": 	return "image/svg+xml";
		default: 		return "application/octet-stream";
	}
}

unittest
{
	import std.exception : assertThrown;

	auto p1 = new SendGridPersonalization("john@example.com", "John")
		.addSubstitution("-name-", "John")
		.addSubstitution("a/b", "slash")
		.addDynamicTemplateData("count", 3);

	auto p2 = new SendGridPersonalization("jane@example.com")
		.addCC("boss@example.com");

	auto sg = new SendGrid("KEY")
		.addPersonalization(p1)
		.addPersonalization(p2)
		.from("me@example.com")
		.addCC("Boss@example.com", "Boss")
		.addBCC("archive@example.com")
		.addContent("<b>hi</b>")
		.addContent("hi", "text/plain")
		.addAttachment(cast(const(ubyte)[])"x", "report.PDF");

	auto p = sg.payload();

	// substitutions and dynamic template data are objects
	assert(p["personalizations"][0]["substitutions"]["-name-"].str == "John");
	assert(p["personalizations"][0]["substitutions"]["a/b"].str == "slash");
	assert(p["personalizations"][0]["dynamic_template_data"]["count"].integer == 3);

	// no cc/bcc at top level, they go to every personalization without duplicates
	assert("cc" !in p && "bcc" !in p);
	assert(p["personalizations"][0]["cc"].array.length == 1);
	assert(p["personalizations"][0]["cc"][0]["name"].str == "Boss");
	assert(p["personalizations"][0]["bcc"][0]["email"].str == "archive@example.com");
	assert(p["personalizations"][1]["cc"].array.length == 1);
	assert(p["personalizations"][1]["cc"][0]["email"].str == "boss@example.com");

	// empty names are omitted
	assert("name" !in p["from"]);
	assert("name" !in p["personalizations"][1]["to"][0]);

	// text/plain first
	assert(p["content"][0]["type"].str == "text/plain");
	assert(p["content"][1]["type"].str == "text/html");

	assert(p["attachments"][0]["type"].str == "application/pdf");
	assert(p["attachments"][0]["content"].str == "eA==");

	// payload() does not change the message or the personalizations
	assert(sg.payload() == p);
	assert("cc" !in p1.data);

	// validations
	assertThrown(new SendGrid("KEY").from("me@example.com").addContent("x").payload());
	assertThrown(new SendGrid("KEY").addPersonalization(p2).addContent("x").payload());
	assertThrown(new SendGrid("KEY").addPersonalization(p2).from("me@example.com").payload());
	new SendGrid("KEY").addPersonalization(p2).from("me@example.com").templateId("d-123").payload();

	assertThrown(new SendGrid("KEY\r\nX-Evil: 1"));
	assertThrown(new SendGrid(""));
	assertThrown(p1.dynamicTemplateData(JSONValue(1)));

	assert(mimeType("a.bin") == "application/octet-stream");
}
