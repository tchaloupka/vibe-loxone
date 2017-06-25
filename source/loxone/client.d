module loxone.client;

import loxone.api;

import std.datetime;
import std.exception;
import std.format : format;
import std.string : startsWith;
import std.typecons : Nullable;
import vibe.core.core;
import vibe.core.log;
import vibe.data.json;
import vibe.http.websockets;
import vibe.inet.url : URL;

/// Loxone client implementatin
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
		LXResponse[string] m_results;
		ubyte[] m_binaryFile;
		string m_textFile;
		string m_awaitFile;
		ManualEvent m_await;
		Timer m_keepaliveTimer;
		Timer m_keepaliveResTimer;
	}

	this (string host, string username, string password)
	{
		this.m_host = host;
		this.m_username = username;
		this.m_password = password;
		this.m_await = createManualEvent();
	}

	void connect()
	in { assert (m_conn is null, "Already connected"); }
	body
	{
		m_conn = connectWebSocket(URL(format!"ws://%s/ws/rfc6455"(m_host)));
		m_reader = runTask(() => reader());
		m_keepaliveTimer = setTimer(4.minutes,
		()
		{
			if (m_conn.connected)
			{
				m_keepaliveResTimer = setTimer(1.seconds, ()
				{
					logWarn("Keepalive response timeout");
					this.close();
				});
				this.send("keepalive");
			}
		}, true);

		// get hash key
		auto key = query("jdev/sys/getkey");
		logDiagnostic("Key: %s", key);
		m_hash = createHash(m_username, m_password, key);

		// authenticate
		auto res = query("authenticate/" ~ m_hash);
	}

	void close()
	in { assert (m_conn !is null, "Not connected"); }
	body
	{
		logDiagnostic("Closing connection");
		m_reader.interrupt();
		m_keepaliveTimer.stop();
		if (m_keepaliveResTimer.pending) m_keepaliveResTimer.stop();
		m_conn.close();
	}

	void enableStatusUpdates()
	{
		query("jdev/sps/enablebinstatusupdate");
	}

	auto getStructureTimestamp()
	{
		auto res = query("jdev/sps/LoxAPPversion3");
		return DateTime(Date.fromISOExtString(res[0..10]), TimeOfDay.fromISOExtString(res[11..$]));
	}

	auto getStructure()
	{
		auto res = getFile!string("data/LoxAPP3.json");
		return res;
	}

	T getFile(T)(string fname)
	{
		Nullable!LXResponse res;
		auto data = download!T(fname, res);
		if (!res.isNull) throw new LoxoneException(format!"%s: %s"(res.code, res.value));
		return data;
	}

private:
	void send(string cmd)
	in { assert (m_conn !is null, "Not connected"); }
	body
	{
		logDiagnostic("Send cmd: %s", cmd);
		m_conn.send(cmd);
	}

	auto query(string cmd)
	in { assert (m_conn !is null, "Not connected"); }
	body
	{
		while (true)
		{
			auto pres = cmd in m_results;
			if (pres !is null)
			{
				// same command already in progress
				logDebug("Same command already in progress: %s", cmd);
				m_await.wait();
			}
			else break;
		}

		auto ecount = m_await.emitCount;
		send(cmd);

		if (cmd.startsWith("jdev")) cmd = cmd[1..$];

		while (true)
		{
			if (m_await.wait(1.seconds, ecount) == ecount)
			{
				this.close();
				throw new LoxoneException(format!"Command timeout: %s"(cmd));
			}

			auto pres = cmd in m_results;
			if (pres !is null)
			{
				auto cmdRes = (*pres);
				m_results.remove(cmd);
				if (cmdRes.code != "200")
				{
					this.close();
					throw new LoxoneException(cmdRes.value);
				}
				return cmdRes.value;
			}
			else ecount = m_await.emitCount;
		}
	}

	T download(T)(string fileName, out Nullable!LXResponse res)
		if (is(T == string) || is(T == ubyte[]))
	in { assert (m_conn !is null, "Not connected"); }
	body
	{
		while (true)
		{
			if (m_awaitFile.length)
			{
				// file download already in progress
				logDebug("File download already active: %s", m_awaitFile);
				m_await.wait();
			}
			else break;
		}

		auto ecount = m_await.emitCount;
		m_awaitFile = fileName;
		m_binaryFile.length = 0;
		send(fileName);

		while (true)
		{
			if (m_await.wait(1.seconds, ecount) == ecount)
			{
				this.close();
				throw new LoxoneException(format!"File download timeout: %s"(fileName));
			}

			if (m_binaryFile.length)
			{
				m_awaitFile = null;
				static if (is(T == string)) throw new LoxoneException("Expected text file, but received binary");
				else return m_binaryFile;
			}
			else if (m_textFile.length)
			{
				m_awaitFile = null;
				static if (!is(T == string)) throw new LoxoneException("Expected binary file, but received text");
				else return m_textFile;
			}
			else if (m_awaitFile in m_results)
			{
				res = m_results[m_awaitFile];
				m_results.remove(m_awaitFile);
				m_awaitFile = null;
				return null;
			}
			else ecount = m_await.emitCount;
		}
	}

	void reader()
	{
		import std.algorithm : map;
		import std.array : appender, array;
		import std.range : chunks;

		while (m_conn.waitForData)
		{
			auto hdata = m_conn.receiveBinary();
			auto header = MessageHeader(hdata);
			logDebug("Header: %s", header);
			if (header.estimatedLength) continue;
			final switch (header.cIdentifier)
			{
				case Identifier.text:
					auto txt = m_conn.receiveText();
					logDiagnostic("Text: %s", txt);
					auto res = txt.deserializeJson!(LXResponse);
					m_results[res.control.startsWith("jdev") ? res.control[1..$] : res.control] = res;
					m_await.emit();
					break;
				case Identifier.binary:
					string sdata;
					ubyte[] bdata;

					try sdata = m_conn.receiveText();
					catch (Exception) bdata = m_conn.receiveBinary();

					if (sdata.length)
					{
						logTrace("File: %s", sdata);
						m_textFile = sdata;
					}
					else
					{
						logTrace("File: %s", bdata);
						m_binaryFile = bdata;
					}
					m_await.emit();
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
					m_keepaliveResTimer.stop();
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