module loxone.client;

import loxone.api;

import std.exception;
import std.format : format;
import vibe.core.core;
import vibe.core.log;
import vibe.data.json;
import vibe.http.websockets;
import vibe.inet.url : URL;

class Loxone
{
	private
	{
		string m_host;
		string m_username;
		string m_password;
		WebSocket m_conn;
		string m_hash;
		Task m_reader;
	}

	this (string host, string username, string password)
	{
		this.m_host = host;
		this.m_username = username;
		this.m_password = password;
	}

	void connect()
	in { assert (m_conn is null, "Already connected"); }
	body
	{
		m_conn = connectWebSocket(URL(format!"ws://%s/ws/rfc6455"(m_host)));

		// get hash key
		auto key = call!string("jdev/sys/getkey");
		logDiagnostic("Key: %s", key);
		m_hash = createHash(m_username, m_password, key);
		auto res = call!(LXResponse!string)("authenticate/" ~ m_hash);
		enforce (res.code == "200", res.value);
		m_reader = runTask(() => reader());
	}

	void enableStatusUpdates()
	{
		call!string("jdev/sps/enablebinstatusupdate");
	}

private:
	void send(string cmd)
	in { assert (m_conn !is null, "Not connected"); }
	body
	{
		logDiagnostic("Send cmd: %s", cmd);
		m_conn.send(cmd);
	}

	auto call(T)(string cmd)
	in { assert (m_conn !is null, "Not connected"); }
	body
	{
		send(cmd);
		auto hdr = m_conn.receiveBinary();
		logDiagnostic("Header: %s", MessageHeader(hdr));
		auto res = m_conn.receiveText();
		logDiagnostic("RAW Result: %s", res);

		static if (is(T == LXResponse!U, U))
		{
			auto cmdRes = res.deserializeJson!T;
			return cmdRes;
		}
		else
		{
			auto cmdRes = res.deserializeJson!(LXResponse!T);
			enforce(cmdRes.code == "200");
			return cmdRes.value;
		}
	}

	void reader()
	{
		import std.algorithm : map;
		import std.array : appender, array;
		import std.range : chunks;

		while (true)
		{
			auto hdata = m_conn.receiveBinary();
			auto header = MessageHeader(hdata);
			logDiagnostic("Header: %s", header);
			final switch (header.cIdentifier)
			{
				case Identifier.text:
					auto txt = m_conn.receiveText();
					logDiagnostic("Text: %s", txt);
					break;
				case Identifier.binary:
					auto data = m_conn.receiveBinary();
					break;
				case Identifier.valueStates:
					auto data = m_conn.receiveBinary();
					logTrace("ValueStates: %s", data);
					auto vs = data.chunks(24).map!(a => EvData(a)).array;
					logDiagnostic("ValueStates: %s", vs);
					break;
				case Identifier.textStates:
					auto data = m_conn.receiveBinary();
					logTrace("TextStates: %s", data);
					auto ts = appender!(EvDataText[]);
					while (data.length) ts ~= EvDataText(data);
					logDiagnostic("TextStates: %s", ts.data);
					assert (data.length == 0);
					break;
				case Identifier.daytimerStates:
					auto data = m_conn.receiveBinary();
					logTrace("DaytimerStates: %s", data);
					auto dts = appender!(EvDataDaytimer[]);
					while (data.length) dts ~= EvDataDaytimer(data);
					logDiagnostic("DaytimerStates: %s", dts.data);
					assert (data.length == 0);
					break;
				case Identifier.outOfService:
					//this.close();
					break;
				case Identifier.keepAlive:
					break;
				case Identifier.weatherStates:
					auto data = m_conn.receiveBinary();
					logTrace("WeatherStates: %s", data);
					auto ws = appender!(EvDataWeather[]);
					while (data.length) ws ~= EvDataWeather(data);
					logDiagnostic("WeatherStates: %s", ws.data);
					assert (data.length == 0);
					break;
			}
		}
	}
}

private static auto createHash(string username, string password, string key) pure
{
	import std.algorithm : map;
	import std.array : array;
	import std.conv : parse, text;
	import std.digest.digest : toHexString;
	import std.digest.hmac : hmac;
	import std.digest.sha : SHA1;
	import std.range : chain, chunks;
	import std.string : representation;

	// key is hex encoded
	ubyte[] bytes = (key.length % 2 ? "0" ~ key : key)
		.chunks(2)
		.map!(twoDigits => twoDigits.parse!ubyte(16))
		.array();

	return chain(username, ":", password)
		.text
		.representation
		.hmac!SHA1(bytes)
		.toHexString
		.text;

	// hash is hex encoded
}