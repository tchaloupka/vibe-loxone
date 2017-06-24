module loxone.api;

import std.bitmanip;
import std.range;
import std.system;
import std.uuid;

import vibe.data.serialization;

@safe nothrow:

/**
 * The message header is used to distinguish what kind of data is going to be sent next and how
 * large the payload is going to be. In some cases, the Miniserver might not know yet how large the
 * payload is going to be. For these cases a flag indicates that the size is estimated (see Estimated).
 * The header is sent as a separate data packet before the actual payload is transmitted. This way the
 * clients know ahead how large the payload is going to be. Based on this info, clients know how long
 * it’s going to take and respond accordingly (UI or timeouts).
 *
 * The Message Header is an 8-byte binary message. It always starts with 0x03 as first byte, the
 * second one is the identifier byte, which gives info on what kind of data is received next. The third
 * byte is used for information flags and the fourth byte is reserved and not used right now. The last 4
 * bytes represent an unsigned integer that tells how large the payload is going to be.
 */
struct MessageHeader
{
	ubyte cBinType;		/// fix 0x03
	Identifier cIdentifier;	/// 8-Bit Unsigned Integer (little endian)
	Info cInfo;		/// Info
	ubyte cReserved;	/// reserved
	uint nLen;			/// 32-Bit Unsigned Integer (little endian)

	bool estimatedLength() pure const
	{
		return (cInfo & Info.estimatedLength) == Info.estimatedLength;
	}

	this (ubyte[] data) @nogc
	in { assert(data.length == 8); }
	body
	{
		this.cBinType = data[0];
		this.cIdentifier = cast(Identifier)data[1];
		this.cInfo = cast(Info)data[2];
		this.cReserved = data[3];
		this.nLen = data[4..$].peek!(uint, Endian.littleEndian);
	}
}

enum Identifier : ubyte
{
	text = 0,
	binary = 1,
	valueStates = 2,
	textStates = 3,
	daytimerStates = 4,
	outOfService = 5,
	keepAlive = 6,
	weatherStates = 7
}

enum Info
{
	none = 0,
	estimatedLength = 0x80
}

/**
 * Value-States are the simplest form of a state update, they consist of one UUID and one double
 * value each, so their size is always 24 Bytes.
 */
struct EvData
{
	UUID uuid;		/// 128-bit uuid
	double dVal;	/// 64-bit float value

	this (ubyte[] data) @nogc
	in { assert(data.length == 24); }
	body
	{
		this.uuid = readUUID(data);
		dVal = data.read!(double, Endian.littleEndian);
	}
}

struct EvDataText
{
	UUID uuid;
	UUID uuidIcon;
	string text;

	this (ref ubyte[] data)
	{
		this.uuid = readUUID(data);
		this.uuidIcon = readUUID(data);

		immutable len = data.read!(uint, Endian.littleEndian);

		this.text = (cast(char[])data[0..len]).idup;
		data = data[len..$];

		if (len % 4 != 0) data = data[4 - (len % 4)..$];
	}
}

struct EvDataDaytimer
{
	UUID uuid;
	double dDefValue;
	EvDataDaytimerEntry[] entries;

	this (ref ubyte[] data)
	{
		this.uuid = readUUID(data);
		this.dDefValue = data.read!(double, Endian.littleEndian);

		immutable num = data.read!(int, Endian.littleEndian);
		if (num > 0)
		{
			entries = new EvDataDaytimerEntry[num];
			foreach (i; 0..num) entries[i] = EvDataDaytimerEntry(data);
		}
	}
}

struct EvDataDaytimerEntry
{
	int nMode;
	int nFrom;
	int nTo;
	int bNeedActivate;
	double dValue;

	this (ref ubyte[] data) @nogc
	{
		this.nMode = data.read!(int, Endian.littleEndian);
		this.nFrom = data.read!(int, Endian.littleEndian);
		this.nTo = data.read!(int, Endian.littleEndian);
		this.bNeedActivate = data.read!(int, Endian.littleEndian);
		this.dValue = data.read!(double, Endian.littleEndian);
	}
}

struct EvDataWeather
{
	UUID uuid;
	uint lastUpdate;
	EvDataWeatherEntry[] entries;

	this (ref ubyte[] data)
	{
		this.uuid = readUUID(data);
		this.lastUpdate = data.read!(uint, Endian.littleEndian);

		immutable num = data.read!(int, Endian.littleEndian);
		if (num > 0)
		{
			entries = new EvDataWeatherEntry[num];
			foreach (i; 0..num) entries[i] = EvDataWeatherEntry(data);
		}
	}
}

struct EvDataWeatherEntry
{
	int timestamp;
	int weatherType;
	int windDirection;
	int solarRadiation;
	int relativeHumidity;
	double temperature;
	double perceivedTemperature;
	double dewPoint;
	double precipitation;
	double windSpeed;
	double barometricPressure;

	this (ref ubyte[] data) @nogc
	{
		this.timestamp = data.read!(int, Endian.littleEndian);
		this.weatherType = data.read!(int, Endian.littleEndian);
		this.windDirection = data.read!(int, Endian.littleEndian);
		this.solarRadiation = data.read!(int, Endian.littleEndian);
		this.relativeHumidity = data.read!(int, Endian.littleEndian);
		this.temperature = data.read!(double, Endian.littleEndian);
		this.perceivedTemperature = data.read!(double, Endian.littleEndian);
		this.dewPoint = data.read!(double, Endian.littleEndian);
		this.precipitation = data.read!(double, Endian.littleEndian);
		this.windSpeed = data.read!(double, Endian.littleEndian);
		this.barometricPressure = data.read!(double, Endian.littleEndian);
	}
}

struct LXResponse(T)
{
	struct Root
	{
		string control;
		T value;
		@name("Code") string code;
		@optional string lastEdit;
		@optional long unix;
	}

	@name("LL") Root root;

	alias root this;
}

/**
 * Helper to read UUID as Loxone is using little endian and D's UUID uses big endian internally
 */
private auto readUUID(ref ubyte[] data) pure @nogc
{
	import std.algorithm : reverse;
	auto d = data[0..16]; data = data[16..$];
	reverse(d[0..4]);
	reverse(d[4..6]);
	reverse(d[6..8]);

	return UUID(d[0..16]);
}

@safe unittest
{
	import vibe.data.json;

	auto msg = `{"LL": { "control": "jdev/sys/getkey", "value": "30303641374345423239383736344132413937384246453733433843303145443843313636384339", "Code": "200"}}`;
	auto res = deserializeJson!(LXResponse!string)(msg);
	assert (res.control == "jdev/sys/getkey");
	assert (res.value == "30303641374345423239383736344132413937384246453733433843303145443843313636384339");
}

@safe unittest
{
	import std.stdio;
	auto uuid = parseUUID("0feba4b8-03d3-0708-ffff2611f5ca7ad1");
	writeln(uuid);
}
