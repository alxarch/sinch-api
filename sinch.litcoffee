SINCH PLATFORM API
==================

	module.exports = sinch = {}


	class SinchAPI
		constructor: (@key, @secret, @version="v1", @basic=no) ->

Authorization
-------------

Every request sent to the API must include the HTTP Authorization header.

The client must send a custom header x-timestamp (time) with each request
that is validated by the server. It is used to determine that the request
is not too old. The timestamp is also part of the signature.
The timestamp must be ISO 8061 formatted.

Access to public and protected resources is handled differently.

When accessing a protected resource,the Authorization header
should include both ApplicationKey and a signature of the request,
signed with the Application secret.

When accessing a public resource, the request Authorization header
should include only the ApplicationKey value.

		authorize: (msg, body, unsigned) ->
			msg.headers ?= {}
			msg.headers['x-timestamp'] ?= new Date().toISOString()
			if @basic
				msg.auth = "application\\#{@key}:#{@secret}"
			else if unsigned
				msg.headers["authorization"] = "Application #{@key}"
			else
				signature = @sign msg, body
				msg.headers["authorization"] = "Application #{@key}:#{signature}"
			msg

### Signature

Protected resources require a signed request.
The signature is used to validate the client and to check
whether the client is authorized to perform the operation.


Use the following steps to sign a request for the Sinch Platform.
The result should be included in the HTTP Authorization header sent with the
HTTP Request.

> <pre>
> Content-MD5 = Base64 ( MD5 ( UTF8 ( [BODY] ) ) )
>
> Signature = Base64 ( HMAC-SHA256 ( Secret, UTF8 ( StringToSign ) ) );
>
> StringToSign = HTTP-Verb + "\n" +
>    Content-MD5 + "\n" +
>    Content-Type + "\n" +
>    CanonicalizedHeaders + "\n" +
>    CanonicalizedResource
> </pre>


		sign: (req, body) ->
			req.headers ?= {}
			content_md5 = if body then md5sum body else ""
			content_type = req.headers["content-type"] or ""
			headers = do ->
				for own name, content of req.headers
					continue if name in ["content-type", "content-length"]
					"#{name}:#{content}"

			data = [
				req.method
				content_md5
				content_type
				headers.join "\n"
				req.path
			].join "\n"
			
			hmac data, @secret

REST APIs
---------

		request: (method, path, data, unsigned) ->
			host = @host
			headers = {}
			path = "#{@path or ''}/#{@version}#{path}"
			msg = {method, headers, path, host}
			if data
				body = new Buffer JSON.stringify data
				headers["content-type"] = "application/json"
				headers["content-length"] = body.length
			else
				body = null

			@authorize msg, body, unsigned

			new Promise (resolve, reject) ->
				req = request msg
				req.on "error", reject
				req.on "response", (res) ->
					res.on "readable", ->
						responseData = res.read()?.toString()
						json = 0 is res.headers['content-type']?.indexOf "application/json"
						if json
							responseData = JSON.parse responseData
						if res.statusCode is 200
							resolve responseData
						else
							reject new Error if json then responseData.message else responseData


				if body
					req.write body
				req.end()

MessagingAPI
------------

	class MessagingAPI extends SinchAPI

		host: "messagingapi.sinch.com"

		sendSms: (number, from, message) ->
			@request "POST", "/sms/#{number}", {from, message}

		sms: (message_id) ->
			@request "GET", "/sms/#{message_id}"

CallingAPI
-----------

	class CallingAPI extends SinchAPI
		host: "callingapi.sinch.com"

		callout: (callout, method="ttsCallout") ->
			data = {method}
			data[method] = callout
			@request "POST", "/callouts", data


		getCallResult: (call_id) ->
			@request "GET", "/calls/id/#{call_id}"

		manageCall: (call_id, svaml) ->
			@request "PATCH", "/calls/id/#{call_id}", svaml

		queryNumber: (type, endpoint) ->
			@request "GET", "/calling/query/#{type}/#{endpoint}"

ReportingAPI
------------

	class ReportingAPI extends SinchAPI
		host: "reportingapi.sinch.com"

		userCallReport: (user, start, stop, domain="data") ->
			date = (value) -> new Date(value).toISOString().substr 0, 10
			filters = {}
			filters._start = date start if start
			filters._stop = date stop if stop
			q = "?#{qs.stringify filters}"
			q = "" if q is "?"

			@request "GET", "/users/#{user.type}/#{user.endpoint}/calls/#{domain}#{q}"

		counter: (id) ->
			@request "GET", "/counters/#{id}", null, no

		servicestatus: (id) ->
			@request "GET", "/services/#{id}", null, no

VerificationAPI
---------------


> WARNING: The verification API changed on 2015-05-21.
> The legacy verification API is not supported.

	class VerificationAPI extends SinchAPI
		host: "api.sinch.com"
		path: "/verification"

		reportSms: (type, endpoint, code, cli) ->
			@request "PUT", "/verifications/#{type}/#{endpoint}",
				method: "sms"
				sms: {code, cli}

		reportFlashCall: (type, endpoint, cli) ->
			@request "PUT", "/verifications/#{type}/#{endpoint}",
				method: "flashCall"
				flashCall: {cli}

		requestSMS: (msisdn, options={}) ->
			@request "POST", "/verifications",
				identity:
					type: "number"
					endpoint: "#{msisdn}".replace /^\+?0*/, '+'
				method: "sms"
				reference: options.reference
				custom: options.custom

		requestFlashCall: (msisdn, options={}) ->
			@request "POST", "/verifications",
				identity:
					type: "number"
					endpoint: "#{msisdn}".replace /^\+?0*/, '+'
				method: "flashCall"
				options: _.pick options, "cli", "intercepted"
				reference: options.reference
				custom: options.custom

		find: (id) ->
			@request "GET", "/verifications/id/#{id}"

		findByReference: (ref) ->
			@request "GET", "/verifications/reference/#{id}"



Interface
---------

	sinch.client = (key, secret) ->
		secret = new Buffer secret, "base64"

		calling: new CallingAPI key, secret
		reporting: new ReportingAPI key, secret
		verification: new VerificationAPI key, secret
		messaging: new MessagingAPI key, secret

Helpers
-------


Generate an md5sum as a hex string

	md5sum = sinch.md5sum = (value) ->
		md5 = createHash "md5"
		md5.write value
		md5.end()
		md5.read().toString "base64"

Sign some data with hmac

	hmac = sinch.hmac = (value, secret, algorithm="sha256") ->
		hm = createHmac algorithm, secret
		hm.write value
		hm.end()
		hm.read().toString "base64"

	{createHash, createHmac} = require "crypto"
	_ = require "lodash"
	Promise = require "bluebird"
	qs = require "querystring"
	{request} = require "https"
